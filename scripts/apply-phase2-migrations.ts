#!/usr/bin/env node
/**
 * Apply pending SQL migrations 015–029 against DATABASE_URL (direct Postgres).
 * Usage: set DATABASE_URL then: npx tsx scripts/apply-phase2-migrations.ts
 */
import fs from "node:fs";
import path from "node:path";
import { loadEnvConfig } from "@next/env";
import pg from "pg";

loadEnvConfig(process.cwd());

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

async function main() {
  const url = process.env.DATABASE_URL;
  if (!url) {
    console.error("DATABASE_URL is required (Postgres connection string from Supabase).");
    process.exit(1);
  }

  const client = new pg.Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
  await client.connect();

  await client.query(`
    create table if not exists public.schema_migrations (
      filename text primary key,
      applied_at timestamptz not null default timezone('utc', now())
    );
  `);

  const dir = path.join(process.cwd(), "supabase", "migrations");
  for (const file of files) {
    const { rows } = await client.query(
      "select 1 from public.schema_migrations where filename = $1",
      [file],
    );
    if (rows.length) {
      console.log(`skip ${file}`);
      continue;
    }
    const sql = fs.readFileSync(path.join(dir, file), "utf8");
    console.log(`apply ${file}...`);
    try {
      await client.query("begin");
      await client.query(sql);
      await client.query("insert into public.schema_migrations (filename) values ($1)", [file]);
      await client.query("commit");
      console.log(`  ok ${file}`);
    } catch (err) {
      await client.query("rollback");
      console.error(`  FAIL ${file}`, err);
      await client.end();
      process.exit(1);
    }
  }

  await client.end();
  console.log("Phase 2 migrations applied.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
