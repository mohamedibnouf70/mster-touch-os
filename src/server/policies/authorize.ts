import "server-only";

import { ForbiddenError, UnauthorizedError } from "@/lib/errors";
import { type PermissionKey } from "@/lib/permissions/catalog";
import { can, type PermissionContext } from "@/lib/permissions/evaluate";
import type { AuthContext } from "@/types/models";

export function requireUser(ctx: AuthContext | null): AuthContext {
  if (!ctx) {
    throw new UnauthorizedError();
  }
  if (!ctx.profile.is_active || ctx.membershipStatus !== "active") {
    throw new ForbiddenError({ reason: "inactive" });
  }
  return ctx;
}

export function authorize(
  ctx: AuthContext | null,
  permission: PermissionKey,
  context?: Partial<PermissionContext>,
): AuthContext {
  const user = requireUser(ctx);
  const fullContext: PermissionContext = {
    organizationId: context?.organizationId ?? user.organization.id,
    departmentId: context?.departmentId,
    projectId: context?.projectId,
  };

  if (!can(user.grants, permission, fullContext)) {
    throw new ForbiddenError({ permission });
  }

  return user;
}

export function hasPermission(
  ctx: AuthContext | null,
  permission: PermissionKey,
  context?: Partial<PermissionContext>,
): boolean {
  if (!ctx || !ctx.profile.is_active || ctx.membershipStatus !== "active") {
    return false;
  }
  return can(ctx.grants, permission, {
    organizationId: context?.organizationId ?? ctx.organization.id,
    departmentId: context?.departmentId,
    projectId: context?.projectId,
  });
}
