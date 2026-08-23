import { EXTERNAL_ROLES, type PermissionKey, type SystemRoleCode } from "./catalog";

export type RoleScopeType = "organization" | "department" | "project";

export type RoleGrant = {
  roleCode: string;
  isExternal: boolean;
  organizationId: string;
  scopeType: RoleScopeType;
  scopeId: string | null;
  permissions: readonly PermissionKey[];
};

export type PermissionContext = {
  organizationId: string;
  departmentId?: string | null;
  projectId?: string | null;
};

function matchesScope(grant: RoleGrant, context: PermissionContext): boolean {
  if (grant.organizationId !== context.organizationId) {
    return false;
  }

  if (grant.scopeType === "organization") {
    return true;
  }

  if (grant.scopeType === "project") {
    return Boolean(context.projectId && grant.scopeId === context.projectId);
  }

  if (grant.scopeType === "department") {
    return Boolean(context.departmentId && grant.scopeId === context.departmentId);
  }

  return false;
}

export function evaluatePermission(
  grants: readonly RoleGrant[],
  permission: PermissionKey,
  context: PermissionContext,
): boolean {
  return grants.some((grant) => {
    if (grant.isExternal || EXTERNAL_ROLES.includes(grant.roleCode as SystemRoleCode)) {
      return false;
    }
    if (!matchesScope(grant, context)) {
      return false;
    }
    return grant.permissions.includes(permission);
  });
}

export function can(
  grants: readonly RoleGrant[],
  permission: PermissionKey,
  context: PermissionContext,
): boolean {
  return evaluatePermission(grants, permission, context);
}

export function listGrantedPermissions(
  grants: readonly RoleGrant[],
  context: PermissionContext,
): PermissionKey[] {
  const keys = new Set<PermissionKey>();
  for (const grant of grants) {
    if (grant.isExternal || !matchesScope(grant, context)) {
      continue;
    }
    for (const permission of grant.permissions) {
      keys.add(permission as PermissionKey);
    }
  }
  return [...keys];
}
