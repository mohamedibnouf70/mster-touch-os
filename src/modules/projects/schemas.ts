import { z } from "zod";

export const createProjectSchema = z.object({
  name_ar: z.string().trim().min(2).max(200),
  name_en: z.string().trim().min(2).max(200),
  description: z.string().trim().max(4000).optional(),
  project_manager_id: z.string().uuid().optional().or(z.literal("")),
  priority: z.enum(["low", "medium", "high", "critical"]).default("medium"),
  start_date: z.string().optional(),
  planned_end_date: z.string().optional(),
  location: z.string().trim().max(300).optional(),
});

export const assignProjectMemberSchema = z.object({
  projectId: z.string().uuid(),
  profileId: z.string().uuid(),
  roleLabel: z.string().trim().max(80).optional(),
});

export const updateStageSchema = z.object({
  stageId: z.string().uuid(),
  status: z.enum(["not_started", "in_progress", "blocked", "completed", "skipped", "cancelled"]),
});

export type CreateProjectInput = z.infer<typeof createProjectSchema>;
