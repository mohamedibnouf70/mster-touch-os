import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);

/** Project root (parent of /tests). */
export const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/** Load Next.js env files (.env.local, .env, …) into process.env. */
export function loadTestEnv(): void {
  const { loadEnvConfig } = require("@next/env") as typeof import("@next/env");
  const env = process.env as Record<string, string | undefined>;
  const priorNodeEnv = env.NODE_ENV;
  // Vitest sets NODE_ENV=test, which prevents @next/env from loading .env.local.
  env.NODE_ENV = "development";
  loadEnvConfig(projectRoot);
  env.NODE_ENV = priorNodeEnv ?? "test";
}

// Runs when Vitest loads this file as a setupFile in test workers.
loadTestEnv();
