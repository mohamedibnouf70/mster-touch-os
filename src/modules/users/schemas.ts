import { z } from "zod";

export const createUserSchema = z.object({
  email: z.string().email(),
  full_name_ar: z.string().trim().min(2).max(200),
  full_name_en: z.string().trim().min(2).max(200),
  job_title_ar: z.string().trim().max(160).optional(),
  job_title_en: z.string().trim().max(160).optional(),
  department_id: z.string().uuid().optional().or(z.literal("")),
  role_id: z.string().uuid().optional().or(z.literal("")),
});

export const assignRoleSchema = z.object({
  profileId: z.string().uuid(),
  roleId: z.string().uuid(),
});

export const assignDepartmentSchema = z.object({
  employeeId: z.string().uuid(),
  departmentId: z.string().uuid(),
});

export const setUserActiveSchema = z.object({
  profileId: z.string().uuid(),
  isActive: z.boolean(),
});
