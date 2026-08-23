import { describe, expect, it } from "vitest";
import { can, evaluatePermission, type RoleGrant } from "@/lib/permissions/evaluate";
import type { PermissionKey } from "@/lib/permissions/catalog";

const orgA = "11111111-1111-1111-1111-111111111111";
const orgB = "22222222-2222-2222-2222-222222222222";
const projectA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";

function grant(partial: Partial<RoleGrant> & Pick<RoleGrant, "permissions">): RoleGrant {
  return {
    roleCode: partial.roleCode ?? "engineer",
    isExternal: partial.isExternal ?? false,
    organizationId: partial.organizationId ?? orgA,
    scopeType: partial.scopeType ?? "organization",
    scopeId: partial.scopeId ?? null,
    permissions: partial.permissions,
  };
}

describe("RBAC evaluatePermission", () => {
  it("denies when user has no matching permission", () => {
    const grants = [grant({ permissions: ["project.read"] })];
    expect(can(grants, "approval.approve", { organizationId: orgA })).toBe(false);
  });

  it("allows when role includes the permission", () => {
    const grants = [grant({ roleCode: "project_manager", permissions: ["approval.approve", "project.read"] })];
    expect(can(grants, "approval.approve", { organizationId: orgA })).toBe(true);
  });

  it("never grants internal access to external roles", () => {
    const grants = [
      grant({
        roleCode: "client",
        isExternal: true,
        permissions: ["project.read", "approval.approve"] as PermissionKey[],
      }),
    ];
    expect(evaluatePermission(grants, "project.read", { organizationId: orgA })).toBe(false);
  });

  it("isolates tenants by organization id", () => {
    const grants = [grant({ organizationId: orgA, permissions: ["project.read"] })];
    expect(can(grants, "project.read", { organizationId: orgB })).toBe(false);
    expect(can(grants, "project.read", { organizationId: orgA })).toBe(true);
  });

  it("respects project-scoped grants", () => {
    const grants = [
      grant({
        scopeType: "project",
        scopeId: projectA,
        permissions: ["project.update"],
      }),
    ];
    expect(can(grants, "project.update", { organizationId: orgA, projectId: projectA })).toBe(true);
    expect(
      can(grants, "project.update", {
        organizationId: orgA,
        projectId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
      }),
    ).toBe(false);
  });
});
