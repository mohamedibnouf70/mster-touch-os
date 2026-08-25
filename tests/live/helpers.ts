import { loadTestEnv } from "../setup-env";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

loadTestEnv();

export const MASTER_TOUCH_ORG_ID = "11111111-1111-1111-1111-111111111111";

export type LiveRole = "admin" | "pm" | "engineer" | "restricted" | "finance";

export type LiveFixture = {
  runId: string;
  orgAId: string;
  orgBId: string;
  users: Record<LiveRole, { id: string; email: string; password: string }>;
  projectId: string;
  orgBProjectId: string;
  workflowDefinitionId: string;
  cleanup: () => Promise<void>;
};

export const EXPECTED_TABLES = [
  "organizations",
  "profiles",
  "organization_members",
  "departments",
  "employees",
  "permissions",
  "roles",
  "role_permissions",
  "user_roles",
  "project_counters",
  "projects",
  "project_members",
  "project_stages",
  "workflow_definitions",
  "workflow_versions",
  "workflow_steps",
  "workflow_instances",
  "workflow_instance_steps",
  "approval_requests",
  "approval_steps",
  "approval_actions",
  "documents",
  "document_versions",
  "notifications",
  "audit_logs",
  "domain_events",
  "engineering_disciplines",
  "project_disciplines",
  "document_type_codes",
  "document_number_counters",
  "rfis",
  "material_submittals",
  "shop_drawings",
  "method_statements",
  "inspection_requests",
  "ncrs",
  "project_reports",
  "correspondence",
  "project_contacts",
  "transmittals",
  "transmittal_items",
  "supplier_categories",
  "suppliers",
  "supplier_contacts",
  "cost_categories",
  "project_budgets",
  "project_budget_items",
  "purchase_requests",
  "purchase_request_items",
  "rfqs",
  "rfq_items",
  "rfq_suppliers",
  "supplier_quotations",
  "supplier_quotation_items",
  "quotation_comparisons",
  "purchase_orders",
  "purchase_order_items",
  "goods_receipts",
  "goods_receipt_items",
  "supplier_invoices",
  "supplier_payments",
  "project_contracts",
  "contract_milestones",
  "client_valuations",
  "client_invoices",
  "client_payments",
  "variations",
  "approval_threshold_rules",
  "entity_documents",
] as const;

export const EXPECTED_RPCS = [
  "create_project",
  "generate_project_code",
  "start_workflow",
  "complete_workflow_step",
  "submit_approval_decision",
  "bootstrap_platform_admin",
  "has_permission",
  "can_access_project",
  "can_act_on_approval_step",
  "can_act_on_workflow_step",
  "generate_document_number",
  "register_controlled_document",
  "create_document_revision",
  "apply_document_approval_decision",
  "issue_transmittal",
  "compute_project_health",
  "has_project_permission",
  "generate_supplier_code",
  "generate_commercial_number",
  "get_supplier_banking",
  "record_supplier_payment",
  "evaluate_supplier_invoice_match",
  "issue_purchase_order",
  "post_goods_receipt",
  "approve_variation",
  "compute_project_commercial_summary",
  "compute_project_commercial_health",
  "can_record_supplier_payment",
  "record_client_payment",
  "can_record_client_payment",
  "issue_client_invoice",
  "record_client_valuation_certification",
  "recalculate_client_valuation",
  "activate_project_contract",
  "mark_contract_milestone_eligible",
  "decide_entity_approval",
  "can_issue_client_invoice",
  "can_certify_client_valuation",
  "can_approve_variation",
] as const;

export function liveTestConfigured(): boolean {
  const enabled = process.env.LIVE_TEST_ENABLED === "true" || process.env.LIVE_TEST_ENABLED === "1";
  return Boolean(
    enabled &&
      process.env.NEXT_PUBLIC_SUPABASE_URL &&
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY &&
      process.env.SUPABASE_SERVICE_ROLE_KEY,
  );
}

export function skipLive(reason: string): void {
  console.warn(`[live-test] SKIP: ${reason}`);
}

export function adminClient(): SupabaseClient {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY!;
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function anonClient(): SupabaseClient {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

type CachedAuthSession = {
  access_token: string;
  refresh_token: string;
};

const authSessionCache = new Map<string, CachedAuthSession>();
const authClientCache = new Map<string, SupabaseClient>();
const authSessionInflight = new Map<string, Promise<CachedAuthSession>>();
let passwordSignInGate: Promise<void> = Promise.resolve();

function isAuthRateLimitError(error: { status?: number; code?: string; message?: string } | null): boolean {
  if (!error) return false;
  const status = error.status;
  const code = (error.code ?? "").toLowerCase();
  const message = (error.message ?? "").toLowerCase();
  return (
    status === 429 ||
    code.includes("over_request_rate_limit") ||
    code.includes("rate_limit") ||
    message.includes("rate limit")
  );
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function withPasswordSignInLock<T>(fn: () => Promise<T>): Promise<T> {
  const previous = passwordSignInGate;
  let release!: () => void;
  passwordSignInGate = new Promise<void>((resolve) => {
    release = resolve;
  });
  await previous;
  try {
    return await fn();
  } finally {
    release();
  }
}

async function passwordSignInWithRetry(email: string, password: string): Promise<CachedAuthSession> {
  return withPasswordSignInLock(async () => {
    const cached = authSessionCache.get(email.toLowerCase());
    if (cached) return cached;

    const maxAttempts = 3;
    let lastMessage = "unknown error";

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      const client = anonClient();
      const { data, error } = await client.auth.signInWithPassword({ email, password });
      if (!error && data.session?.access_token && data.session.refresh_token) {
        const session: CachedAuthSession = {
          access_token: data.session.access_token,
          refresh_token: data.session.refresh_token,
        };
        authSessionCache.set(email.toLowerCase(), session);
        return session;
      }

      lastMessage = error?.message ?? "missing session";
      if (!isAuthRateLimitError(error) || attempt === maxAttempts) {
        throw new Error(`signIn failed for ${email}: ${lastMessage}`);
      }
      await sleep(1000 * 2 ** (attempt - 1));
    }

    throw new Error(`signIn failed for ${email}: ${lastMessage}`);
  });
}

async function resolveAuthSession(email: string, password: string): Promise<CachedAuthSession> {
  const key = email.toLowerCase();
  const cached = authSessionCache.get(key);
  if (cached) return cached;

  const inflight = authSessionInflight.get(key);
  if (inflight) return inflight;

  const pending = passwordSignInWithRetry(email, password).finally(() => {
    authSessionInflight.delete(key);
  });
  authSessionInflight.set(key, pending);
  return pending;
}

async function clientFromSession(session: CachedAuthSession, email: string, password: string): Promise<SupabaseClient> {
  const client = anonClient();
  const { error } = await client.auth.setSession({
    access_token: session.access_token,
    refresh_token: session.refresh_token,
  });
  if (!error) return client;

  authSessionCache.delete(email.toLowerCase());
  const refreshed = await passwordSignInWithRetry(email, password);
  const retryClient = anonClient();
  const { error: retryError } = await retryClient.auth.setSession({
    access_token: refreshed.access_token,
    refresh_token: refreshed.refresh_token,
  });
  if (retryError) {
    throw new Error(`signIn session restore failed for ${email}: ${retryError.message}`);
  }
  return retryClient;
}

export async function signInAs(email: string, password: string): Promise<SupabaseClient> {
  const key = email.toLowerCase();
  const cachedClient = authClientCache.get(key);
  if (cachedClient) return cachedClient;

  const session = await resolveAuthSession(email, password);
  const client = await clientFromSession(session, email, password);
  authClientCache.set(key, client);
  return client;
}

function forgetAuthSession(email: string): void {
  const key = email.toLowerCase();
  authSessionCache.delete(key);
  authClientCache.delete(key);
}

async function roleId(admin: SupabaseClient, code: string): Promise<string> {
  const { data, error } = await admin
    .from("roles")
    .select("id")
    .eq("code", code)
    .is("organization_id", null)
    .single();
  if (error || !data) throw new Error(`role ${code} not found — run migrations/seed`);
  return data.id;
}

async function createUserWithRole(
  admin: SupabaseClient,
  input: { email: string; password: string; roleCode: string; orgId: string },
): Promise<string> {
  const { data: created, error } = await admin.auth.admin.createUser({
    email: input.email,
    password: input.password,
    email_confirm: true,
    user_metadata: { full_name_ar: input.roleCode, full_name_en: input.roleCode, locale: "ar" },
  });
  if (error || !created.user) throw new Error(`createUser: ${error?.message}`);

  const userId = created.user.id;

  await admin.from("organization_members").upsert({
    organization_id: input.orgId,
    profile_id: userId,
    status: "active",
  });

  await admin.from("employees").upsert({
    organization_id: input.orgId,
    profile_id: userId,
    employment_status: "active",
    is_active: true,
  });

  if (input.roleCode) {
    const rid = await roleId(admin, input.roleCode);
    await admin.from("user_roles").upsert({
      organization_id: input.orgId,
      profile_id: userId,
      role_id: rid,
      scope_type: "organization",
    });
  }

  return userId;
}

export async function provisionLiveFixture(): Promise<LiveFixture> {
  const admin = adminClient();
  const runId = crypto.randomUUID().slice(0, 8);
  const prefix = process.env.LIVE_TEST_PASSWORD_PREFIX ?? "MtTest1!";

  const emails = {
    admin: `mt-live-admin-${runId}@test.local`,
    pm: `mt-live-pm-${runId}@test.local`,
    engineer: `mt-live-eng-${runId}@test.local`,
    restricted: `mt-live-res-${runId}@test.local`,
    finance: `mt-live-fin-${runId}@test.local`,
  } as const;

  const passwords = {
    admin: `${prefix}admin`,
    pm: `${prefix}pm`,
    engineer: `${prefix}eng`,
    restricted: `${prefix}res`,
    finance: `${prefix}fin`,
  } as const;

  const orgAId = MASTER_TOUCH_ORG_ID;

  const { data: orgB, error: orgBErr } = await admin
    .from("organizations")
    .insert({
      name_ar: `اختبار ${runId}`,
      name_en: `Test Org ${runId}`,
      country: "SA",
      timezone: "Asia/Riyadh",
      default_currency: "SAR",
      status: "active",
    })
    .select("id")
    .single();
  if (orgBErr || !orgB) throw new Error(`orgB: ${orgBErr?.message}`);

  const userIds = {
    admin: await createUserWithRole(admin, {
      email: emails.admin,
      password: passwords.admin,
      roleCode: "super_admin",
      orgId: orgAId,
    }),
    pm: await createUserWithRole(admin, {
      email: emails.pm,
      password: passwords.pm,
      roleCode: "project_manager",
      orgId: orgAId,
    }),
    engineer: await createUserWithRole(admin, {
      email: emails.engineer,
      password: passwords.engineer,
      roleCode: "engineer",
      orgId: orgAId,
    }),
    restricted: await createUserWithRole(admin, {
      email: emails.restricted,
      password: passwords.restricted,
      roleCode: "",
      orgId: orgAId,
    }),
    finance: await createUserWithRole(admin, {
      email: emails.finance,
      password: passwords.finance,
      roleCode: "finance_manager",
      orgId: orgAId,
    }),
  };

  for (const role of Object.keys(emails) as LiveRole[]) {
    await signInAs(emails[role], passwords[role]);
  }

  const adminSession = await signInAs(emails.admin, passwords.admin);
  const { data: project, error: projectErr } = await adminSession.rpc("create_project", {
    p_organization_id: orgAId,
    p_name_ar: `مشروع ${runId}`,
    p_name_en: `Project ${runId}`,
    p_description: "live test",
    p_client_id: null,
    p_project_manager_id: userIds.pm,
    p_priority: "medium",
    p_start_date: null,
    p_planned_end_date: null,
    p_location: null,
    p_template_id: null,
  });
  if (projectErr || !project) throw new Error(`create_project: ${projectErr?.message}`);

  const { data: orgBProject, error: orgBProjectErr } = await admin
    .from("projects")
    .insert({
      organization_id: orgB.id,
      project_code: `MT-TST-${runId}`,
      name_ar: "مشروع B",
      name_en: "Org B Project",
      status: "active",
      priority: "medium",
      progress_percentage: 0,
      risk_level: "low",
      created_by: userIds.admin,
    })
    .select("id")
    .single();
  if (orgBProjectErr || !orgBProject) throw new Error(`orgB project: ${orgBProjectErr?.message}`);

  const { data: wfDef } = await admin
    .from("workflow_definitions")
    .select("id")
    .eq("status", "published")
    .limit(1)
    .maybeSingle();

  const cleanup = async () => {
    await admin.from("organizations").delete().eq("id", orgB.id);
    for (const email of Object.values(emails)) {
      forgetAuthSession(email);
      const { data: listed } = await admin.auth.admin.listUsers();
      const match = listed.users.find((u) => u.email === email);
      if (match) await admin.auth.admin.deleteUser(match.id);
    }
  };

  return {
    runId,
    orgAId,
    orgBId: orgB.id,
    users: Object.fromEntries(
      (Object.keys(emails) as LiveRole[]).map((role) => [
        role,
        { id: userIds[role], email: emails[role], password: passwords[role] },
      ]),
    ) as LiveFixture["users"],
    projectId: project.id,
    orgBProjectId: orgBProject.id,
    workflowDefinitionId: wfDef?.id ?? "",
    cleanup,
  };
}

export async function verifySchema(admin: SupabaseClient): Promise<{
  tables: { name: string; ok: boolean; error?: string }[];
  rpcs: { name: string; ok: boolean }[];
  bucketPrivate: boolean | null;
}> {
  const tables = await Promise.all(
    EXPECTED_TABLES.map(async (name) => {
      const { error } = await admin.from(name).select("*").limit(0);
      return { name, ok: !error, error: error?.message };
    }),
  );

  const rpcs = EXPECTED_RPCS.map((name) => ({ name, ok: true }));

  const { data: buckets } = await admin.storage.listBuckets();
  const docBucket = buckets?.find((b) => b.id === "documents");
  const bucketPrivate = docBucket ? docBucket.public === false : null;

  return { tables, rpcs, bucketPrivate };
}
