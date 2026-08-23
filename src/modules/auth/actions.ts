"use server";

import { redirect } from "next/navigation";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { ValidationError } from "@/lib/errors";
import { getServerEnv } from "@/lib/env";
import { bootstrapAdminIfNeeded } from "@/server/use-cases/platform";

export async function signInAction(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const password = String(formData.get("password") ?? "");
  if (!email || !password) {
    throw new ValidationError("أدخل البريد وكلمة المرور.", "Enter email and password.");
  }

  const supabase = await createServerSupabaseClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) {
    throw new ValidationError("بيانات الدخول غير صحيحة.", "Invalid sign-in details.");
  }

  const env = getServerEnv();
  if (env.BOOTSTRAP_ADMIN_EMAIL && env.BOOTSTRAP_ADMIN_EMAIL.toLowerCase() === email) {
    await bootstrapAdminIfNeeded(email);
  }

  redirect("/");
}

export async function signOutAction() {
  const supabase = await createServerSupabaseClient();
  await supabase.auth.signOut();
  redirect("/login");
}
