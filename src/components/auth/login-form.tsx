"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { signInAction } from "@/modules/auth/actions";
import { Button, Field, Input } from "@/components/ui/primitives";

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" className="w-full" disabled={pending}>
      {pending ? "جارٍ الدخول..." : "دخول"}
    </Button>
  );
}

export function LoginForm() {
  const [state, formAction] = useActionState(signInAction, { error: null as string | null });

  return (
    <form action={formAction} className="space-y-4">
      <Field label="البريد الإلكتروني">
        <Input name="email" type="email" required autoComplete="username" />
      </Field>
      <Field label="كلمة المرور">
        <Input name="password" type="password" required autoComplete="current-password" />
      </Field>
      {state.error ? <p className="text-sm text-danger">{state.error}</p> : null}
      <SubmitButton />
    </form>
  );
}
