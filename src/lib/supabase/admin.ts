import "server-only";

import { createClient } from "@supabase/supabase-js";
import { getServerEnv, getServiceRoleKey } from "@/lib/env";

export function createAdminSupabaseClient() {
  const env = getServerEnv();
  return createClient(env.NEXT_PUBLIC_SUPABASE_URL, getServiceRoleKey(), {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });
}
