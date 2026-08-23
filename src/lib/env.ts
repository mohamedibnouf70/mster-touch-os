import { z } from "zod";

const publicSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.string().url(),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(20),
  NEXT_PUBLIC_APP_URL: z.string().url().optional(),
});

const serverSchema = publicSchema.extend({
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(20).optional(),
  BOOTSTRAP_ADMIN_EMAIL: z.string().email().optional(),
  LIVE_TEST_ENABLED: z
    .enum(["true", "false", "1", "0"])
    .optional()
    .transform((v) => v === "true" || v === "1"),
  LIVE_TEST_PASSWORD_PREFIX: z.string().min(8).optional(),
  DATABASE_URL: z.string().url().optional(),
});

export type PublicEnv = z.infer<typeof publicSchema>;
export type ServerEnv = z.infer<typeof serverSchema>;

function isBuildTime(): boolean {
  return process.env.NEXT_PHASE === "phase-production-build";
}

function readPublicEnv(): PublicEnv {
  const parsed = publicSchema.safeParse({
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    NEXT_PUBLIC_APP_URL: process.env.NEXT_PUBLIC_APP_URL,
  });

  if (!parsed.success) {
    if (isBuildTime()) {
      return {
        NEXT_PUBLIC_SUPABASE_URL: "https://build.placeholder.supabase.co",
        NEXT_PUBLIC_SUPABASE_ANON_KEY: "sb_publishable_build_placeholder_key_value",
      };
    }
    throw new Error(
      "Missing or invalid public environment variables. Copy .env.example to .env.local.",
    );
  }

  return parsed.data;
}

let cachedPublic: PublicEnv | undefined;

export function getPublicEnv(): PublicEnv {
  if (!cachedPublic) {
    cachedPublic = readPublicEnv();
  }
  return cachedPublic;
}

export function getServerEnv(): ServerEnv {
  const parsed = serverSchema.safeParse({
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    NEXT_PUBLIC_APP_URL: process.env.NEXT_PUBLIC_APP_URL,
    SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
    BOOTSTRAP_ADMIN_EMAIL: process.env.BOOTSTRAP_ADMIN_EMAIL,
  });

  if (!parsed.success) {
    throw new Error(
      "Missing or invalid server environment variables. Copy .env.example to .env.local.",
    );
  }

  return parsed.data;
}

export function getServiceRoleKey(): string {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY is not configured.");
  }
  return key;
}

export function hasSupabaseConfig(): boolean {
  return Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  );
}

export type EnvClassification = {
  name: string;
  scope: "public" | "server" | "optional" | "dev-only";
  required: boolean;
  description: string;
};

/** Documented environment variable contract for operators and CI. */
export const ENV_CATALOG: readonly EnvClassification[] = [
  {
    name: "NEXT_PUBLIC_SUPABASE_URL",
    scope: "public",
    required: true,
    description: "Supabase project URL",
  },
  {
    name: "NEXT_PUBLIC_SUPABASE_ANON_KEY",
    scope: "public",
    required: true,
    description: "Supabase anon/publishable key",
  },
  {
    name: "NEXT_PUBLIC_APP_URL",
    scope: "public",
    required: false,
    description: "Canonical app URL for redirects",
  },
  {
    name: "SUPABASE_SERVICE_ROLE_KEY",
    scope: "server",
    required: false,
    description: "Service role — admin user bootstrap and user creation only",
  },
  {
    name: "BOOTSTRAP_ADMIN_EMAIL",
    scope: "server",
    required: false,
    description: "First-login platform admin email (normalized lowercase)",
  },
  {
    name: "LIVE_TEST_ENABLED",
    scope: "dev-only",
    required: false,
    description: "Enable live Supabase integration tests",
  },
  {
    name: "LIVE_TEST_PASSWORD_PREFIX",
    scope: "dev-only",
    required: false,
    description: "Prefix for ephemeral test-user passwords",
  },
  {
    name: "DATABASE_URL",
    scope: "dev-only",
    required: false,
    description: "Direct Postgres URL for migration scripts",
  },
] as const;

export function isLiveTestEnabled(): boolean {
  const v = process.env.LIVE_TEST_ENABLED;
  return v === "true" || v === "1";
}

export function getLiveTestPassword(role: string): string {
  const prefix = process.env.LIVE_TEST_PASSWORD_PREFIX ?? "MtTest1!";
  return `${prefix}${role}`;
}
