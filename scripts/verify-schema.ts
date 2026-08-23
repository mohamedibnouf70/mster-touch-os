#!/usr/bin/env node
/**
 * Schema verification report for migrations 001–014.
 * Usage: npx tsx scripts/verify-schema.ts
 * Requires: NEXT_PUBLIC_SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in env
 */
import { createClient } from "@supabase/supabase-js";
import { EXPECTED_RPCS, verifySchema } from "../tests/live/helpers";

async function main() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    console.error("Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
    process.exit(1);
  }

  const admin = createClient(url, key, { auth: { persistSession: false } });
  const report = await verifySchema(admin);

  console.log("\n=== Master Touch OS — Schema Verification ===\n");
  console.log("Tables:");
  for (const t of report.tables) {
    console.log(`  ${t.ok ? "✓" : "✗"} ${t.name}${t.error ? ` — ${t.error}` : ""}`);
  }
  console.log("\nRPCs (expected):");
  for (const name of EXPECTED_RPCS) {
    console.log(`  • ${name}`);
  }
  console.log(`\nStorage bucket 'documents' private: ${report.bucketPrivate === true ? "yes" : report.bucketPrivate === false ? "NO — CRITICAL" : "unknown"}`);

  const failed = report.tables.filter((t) => !t.ok);
  process.exit(failed.length > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
