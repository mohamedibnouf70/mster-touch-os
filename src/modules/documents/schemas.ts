import { z } from "zod";

export const uploadDocumentSchema = z.object({
  title: z.string().trim().min(2).max(240),
  category: z.string().min(2).max(60),
  projectId: z.string().uuid().optional().or(z.literal("")),
  documentId: z.string().uuid().optional().or(z.literal("")),
  confidentiality: z.enum(["internal", "confidential", "restricted"]).default("internal"),
});
