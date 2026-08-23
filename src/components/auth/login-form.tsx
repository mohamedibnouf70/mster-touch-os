"use client";

import { useState, useTransition } from "react";
import { signInAction } from "@/modules/auth/actions";
import { Button, Field, Input } from "@/components/ui/primitives";
import { isAppError, toAppError } from "@/lib/errors";

export function LoginForm() {
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  return (
    <form
      action={(formData) => {
        setError(null);
        startTransition(async () => {
          try {
            await signInAction(formData);
          } catch (caught) {
            if (isRedirect(caught)) {
              throw caught;
            }
            const appError = isAppError(caught) ? caught : toAppError(caught);
            setError(appError.userMessageAr);
          }
        });
      }}
      className="space-y-4"
    >
      <Field label="البريد الإلكتروني">
        <Input name="email" type="email" required autoComplete="username" />
      </Field>
      <Field label="كلمة المرور">
        <Input name="password" type="password" required autoComplete="current-password" />
      </Field>
      {error ? <p className="text-sm text-danger">{error}</p> : null}
      <Button type="submit" className="w-full" disabled={pending}>
        {pending ? "جارٍ الدخول..." : "دخول"}
      </Button>
    </form>
  );
}

function isRedirect(error: unknown): boolean {
  return Boolean(error && typeof error === "object" && "digest" in error && String((error as { digest?: string }).digest).startsWith("NEXT_REDIRECT"));
}
