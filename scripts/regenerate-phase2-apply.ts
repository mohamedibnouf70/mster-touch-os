#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const migrationsDir = path.join(root, "supabase", "migrations");
const files = [
  "015_engineering_disciplines.sql",
  "016_document_control.sql",
  "017_rfi.sql",
  "018_material_submittals.sql",
  "019_shop_drawings.sql",
  "020_method_statements.sql",
  "021_inspection_requests.sql",
  "022_ncr.sql",
  "023_reports_correspondence.sql",
  "024_contacts_transmittals.sql",
  "025_phase2_rbac.sql",
  "026_phase2_rls.sql",
  "027_phase2_rpc.sql",
  "028_phase2_indexes_workflows.sql",
  "029_document_version_lifecycle.sql",
];

const header = `-- Master Touch OS — Phase 2 apply (015–029)
-- Safe to re-run AFTER a partial apply when using fixed migration 028 (workflow UUID collision resolved).
-- For resume after failure at 028: run supabase/phase2_resume_028_029.sql instead.
-- Verify state first: supabase/phase2_verify.sql

`;

let body = header;
for (const file of files) {
  const sql = fs.readFileSync(path.join(migrationsDir, file), "utf8");
  body += `\n-- ===== ${file} =====\n\n${sql}\n`;
}

const outPath = path.join(root, "supabase", "phase2_apply_all.sql");
fs.writeFileSync(outPath, body, "utf8");

const resume = `-- Master Touch OS — resume Phase 2 from migration 028 (after 015–027 already applied)
-- Run phase2_verify.sql first.

${fs.readFileSync(path.join(migrationsDir, "028_phase2_indexes_workflows.sql"), "utf8")}

${fs.readFileSync(path.join(migrationsDir, "029_document_version_lifecycle.sql"), "utf8")}
`;

fs.writeFileSync(path.join(root, "supabase", "phase2_resume_028_029.sql"), resume, "utf8");
console.log(`Wrote ${outPath} (${body.length} bytes)`);
console.log(`Wrote supabase/phase2_resume_028_029.sql`);
