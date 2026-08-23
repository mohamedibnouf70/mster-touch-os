import "server-only";

import { createServerSupabaseClient } from "@/lib/supabase/server";
import { isPermissionKey, type PermissionKey } from "@/lib/permissions/catalog";
import { listGrantedPermissions, type RoleGrant, type RoleScopeType } from "@/lib/permissions/evaluate";
import type { AuthContext, Employee, Organization, Profile } from "@/types/models";
import type { MembershipStatus } from "@/types/enums";

type RoleRow = {
  organization_id: string;
  scope_type: RoleScopeType;
  scope_id: string | null;
  roles: {
    code: string;
    is_external: boolean;
    role_permissions: Array<{ permission_key: string }>;
  } | null;
};

export async function getAuthContext(): Promise<AuthContext | null> {
  const supabase = await createServerSupabaseClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return null;
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", user.id)
    .maybeSingle<Profile>();

  if (!profile) {
    return null;
  }

  const { data: membership } = await supabase
    .from("organization_members")
    .select("organization_id, status, organizations(*)")
    .eq("profile_id", user.id)
    .eq("status", "active")
    .order("joined_at", { ascending: true })
    .limit(1)
    .maybeSingle<{
      organization_id: string;
      status: MembershipStatus;
      organizations: Organization | Organization[] | null;
    }>();

  const organization = Array.isArray(membership?.organizations)
    ? membership.organizations[0]
    : membership?.organizations;

  if (!membership || !organization) {
    return null;
  }

  const { data: employee } = await supabase
    .from("employees")
    .select("*")
    .eq("organization_id", organization.id)
    .eq("profile_id", user.id)
    .maybeSingle<Employee>();

  const { data: roleRows } = await supabase
    .from("user_roles")
    .select("organization_id, scope_type, scope_id, roles(code, is_external, role_permissions(permission_key))")
    .eq("profile_id", user.id)
    .eq("organization_id", organization.id);

  const grants: RoleGrant[] = (roleRows ?? []).flatMap((raw) => {
    const row = raw as unknown as RoleRow & {
      roles: RoleRow["roles"] | Array<NonNullable<RoleRow["roles"]>>;
    };
    const role = Array.isArray(row.roles) ? row.roles[0] : row.roles;
    if (!role) {
      return [];
    }
    return [
      {
        roleCode: role.code,
        isExternal: role.is_external,
        organizationId: row.organization_id,
        scopeType: row.scope_type,
        scopeId: row.scope_id,
        permissions: role.role_permissions
          .map((item) => item.permission_key)
          .filter(isPermissionKey),
      },
    ];
  });

  if (profile.is_platform_admin) {
    const { ALL_INTERNAL_PERMISSIONS } = await import("@/lib/permissions/catalog");
    grants.unshift({
      roleCode: "super_admin",
      isExternal: false,
      organizationId: organization.id,
      scopeType: "organization",
      scopeId: null,
      permissions: ALL_INTERNAL_PERMISSIONS,
    });
  }

  const permissions = listGrantedPermissions(grants, {
    organizationId: organization.id,
  }) as PermissionKey[];

  return {
    userId: user.id,
    profile,
    organization,
    employee,
    membershipStatus: membership.status,
    grants,
    permissions,
  };
}
