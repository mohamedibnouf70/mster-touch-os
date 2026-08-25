#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const dir = path.join(root, "supabase", "migrations");
const files = [
  "031_suppliers.sql",
  "032_project_budget.sql",
  "033_purchase_requests.sql",
  "034_rfq.sql",
  "035_quotations.sql",
  "036_purchase_orders.sql",
  "037_goods_receipts.sql",
  "038_supplier_invoices_payments.sql",
  "039_project_contracts.sql",
  "040_client_valuations.sql",
  "041_variations.sql",
  "042_phase3_rbac.sql",
  "043_phase3_rls.sql",
  "044_phase3_rpc.sql",
  "045_phase3_indexes_cashflow.sql",
];

let body = `-- Master Touch OS — Phase 3 apply (031–045)
-- Apply in Supabase SQL Editor after Phase 2 (030) is applied.
-- Verify first: supabase/phase2_verify.sql (extend for Phase 3 tables)

`;
for (const f of files) {
  body += `\n-- ===== ${f} =====\n\n${fs.readFileSync(path.join(dir, f), "utf8")}\n`;
}
fs.writeFileSync(path.join(root, "supabase", "phase3_apply_all.sql"), body, "utf8");
console.log("Wrote supabase/phase3_apply_all.sql");
