import { redirect } from "next/navigation";
import { Badge, Button, Card, EmptyState, Field, Input, PageHeader, Select } from "@/components/ui/primitives";
import { getAuthContext } from "@/server/context";
import { hasPermission } from "@/server/policies/authorize";
import { CoreRepository } from "@/server/repositories/core.repository";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import {
  assignDepartmentAction,
  assignRoleAction,
  createUserAction,
  setUserActiveAction,
} from "@/server/use-cases/platform";

type RoleRow = { id: string; name_ar: string; is_external?: boolean };

export default async function EmployeesPage() {
  const ctx = await getAuthContext();
  if (!ctx || !hasPermission(ctx, "employee.read")) redirect("/login");

  const supabase = await createServerSupabaseClient();
  const repo = new CoreRepository(supabase);
  const [employees, departments, roles, users] = await Promise.all([
    repo.listEmployees(ctx.organization.id),
    repo.listDepartments(ctx.organization.id),
    repo.listRoles(),
    repo.listUsers(ctx.organization.id),
  ]);

  const roleRows = roles as RoleRow[];
  const canManage = hasPermission(ctx, "employee.manage") || hasPermission(ctx, "user.create");
  const canAssignRole = hasPermission(ctx, "role.assign");
  const canDisable = hasPermission(ctx, "user.disable");

  return (
    <div>
      <PageHeader title="الموظفون" description="إدارة الهوية الوظيفية والأدوار والإدارات دون حذف السجل التاريخي" />

      {canManage ? (
        <Card className="mb-6">
          <h2 className="mb-4 text-base font-semibold text-navy">إنشاء مستخدم / موظف</h2>
          <form action={createUserAction} className="grid gap-3 md:grid-cols-2">
            <Field label="البريد">
              <Input name="email" type="email" required />
            </Field>
            <Field label="الاسم بالعربية">
              <Input name="full_name_ar" required />
            </Field>
            <Field label="الاسم بالإنجليزية">
              <Input name="full_name_en" required />
            </Field>
            <Field label="المسمى الوظيفي">
              <Input name="job_title_ar" />
            </Field>
            <Field label="الإدارة">
              <Select name="department_id" defaultValue="">
                <option value="">بدون</option>
                {departments.map((department) => (
                  <option key={department.id} value={department.id}>
                    {department.name_ar}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="الدور">
              <Select name="role_id" defaultValue="">
                <option value="">بدون</option>
                {roleRows
                  .filter((role) => !role.is_external)
                  .map((role) => (
                    <option key={role.id} value={role.id}>
                      {role.name_ar}
                    </option>
                  ))}
              </Select>
            </Field>
            <div className="md:col-span-2">
              <Button type="submit">إنشاء</Button>
            </div>
          </form>
        </Card>
      ) : null}

      {employees.length === 0 ? (
        <EmptyState title="لا يوجد موظفون بعد." />
      ) : (
        <div className="space-y-4">
          {employees.map((employee) => {
            const profile = employee.profiles;
            const member = users.find((row) => {
              const typed = row as { profile_id?: string; profiles?: { id?: string } };
              return typed.profile_id === employee.profile_id || typed.profiles?.id === employee.profile_id;
            }) as { profiles?: { is_active?: boolean } } | undefined;
            const active = member?.profiles?.is_active ?? profile?.is_active ?? employee.is_active;

            return (
              <Card key={employee.id}>
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <h2 className="text-base font-semibold text-navy">
                      {profile?.full_name_ar || "بدون اسم"}
                    </h2>
                    <p className="text-sm text-muted">
                      {employee.job_title_ar || "بدون مسمى"} · {employee.employment_status}
                    </p>
                  </div>
                  <Badge tone={active ? "success" : "danger"}>{active ? "نشط" : "موقوف"}</Badge>
                </div>

                <div className="mt-4 grid gap-3 border-t border-line pt-4 md:grid-cols-3">
                  {hasPermission(ctx, "employee.manage") ? (
                    <form action={assignDepartmentAction} className="space-y-2">
                      <input type="hidden" name="employeeId" value={employee.id} />
                      <Field label="تعيين إدارة">
                        <Select name="departmentId" required defaultValue="">
                          <option value="" disabled>
                            اختر
                          </option>
                          {departments.map((department) => (
                            <option key={department.id} value={department.id}>
                              {department.name_ar}
                            </option>
                          ))}
                        </Select>
                      </Field>
                      <Button type="submit" variant="secondary">
                        حفظ الإدارة
                      </Button>
                    </form>
                  ) : null}

                  {canAssignRole ? (
                    <form action={assignRoleAction} className="space-y-2">
                      <input type="hidden" name="profileId" value={employee.profile_id} />
                      <Field label="تعيين دور">
                        <Select name="roleId" required defaultValue="">
                          <option value="" disabled>
                            اختر
                          </option>
                          {roleRows
                            .filter((role) => !role.is_external)
                            .map((role) => (
                              <option key={role.id} value={role.id}>
                                {role.name_ar}
                              </option>
                            ))}
                        </Select>
                      </Field>
                      <Button type="submit" variant="secondary">
                        حفظ الدور
                      </Button>
                    </form>
                  ) : null}

                  {canDisable ? (
                    <form action={setUserActiveAction} className="space-y-2">
                      <input type="hidden" name="profileId" value={employee.profile_id} />
                      <input type="hidden" name="isActive" value={active ? "false" : "true"} />
                      <p className="text-sm text-muted">إيقاف الوصول يحافظ على السجل التاريخي.</p>
                      <Button type="submit" variant={active ? "danger" : "primary"}>
                        {active ? "إيقاف الوصول" : "إعادة التفعيل"}
                      </Button>
                    </form>
                  ) : null}
                </div>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
