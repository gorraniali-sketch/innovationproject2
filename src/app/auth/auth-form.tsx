"use client";

import Link from "next/link";
import { useActionState, useState, type FormEvent } from "react";
import {
  initialAuthActionState,
  type AuthAction,
} from "@/lib/supabase/auth-validation";

export type AuthFormField = {
  name: string;
  label: string;
  type: "email" | "password";
  autoComplete: string;
  minLength?: number;
  maxLength?: number;
};

type AuthFormProps = {
  action: AuthAction;
  title: string;
  description: string;
  fields: AuthFormField[];
  submitLabel: string;
  pendingLabel: string;
  links?: { href: string; label: string }[];
};

export default function AuthForm({
  action,
  title,
  description,
  fields,
  submitLabel,
  pendingLabel,
  links = [],
}: AuthFormProps) {
  const [state, formAction, isPending] = useActionState(
    action,
    initialAuthActionState,
  );
  const [clientError, setClientError] = useState("");

  function validatePasswords(event: FormEvent<HTMLFormElement>) {
    const formData = new FormData(event.currentTarget);
    const password = formData.get("password");
    const confirmation = formData.get("confirmPassword");

    if (
      typeof password === "string" &&
      typeof confirmation === "string" &&
      password !== confirmation
    ) {
      event.preventDefault();
      setClientError("رمز عبور و تکرار آن یکسان نیستند.");
      return;
    }

    setClientError("");
  }

  return (
    <section
      aria-labelledby="auth-form-title"
      className="rounded-2xl border border-[#e3e9e1] bg-white p-6 shadow-[0_16px_45px_-38px_rgba(24,58,43,0.35)] sm:p-8"
    >
      <h1
        className="text-2xl font-bold leading-snug text-[#173d32] sm:text-3xl"
        id="auth-form-title"
      >
        {title}
      </h1>
      <p className="mt-3 leading-7 text-[#647169]">{description}</p>

      <form
        action={formAction}
        className="mt-7 space-y-5"
        onChange={() => setClientError("")}
        onSubmit={validatePasswords}
      >
        {fields.map((field) => (
          <div key={field.name}>
            <label
              className="block text-sm font-semibold text-[#244c39]"
              htmlFor={field.name}
            >
              {field.label}
            </label>
            <input
              autoComplete={field.autoComplete}
              className="mt-2 min-h-12 w-full rounded-lg border border-[#dce4dc] bg-white px-4 text-left text-[#263d32] placeholder:text-[#9aa49d] focus:border-[#17634a] focus:outline-none"
              dir={field.type === "email" ? "ltr" : undefined}
              id={field.name}
              maxLength={field.maxLength}
              minLength={field.minLength}
              name={field.name}
              required
              type={field.type}
            />
          </div>
        ))}

        {(clientError || state.status !== "idle") && (
          <p
            aria-live="polite"
            className={`rounded-lg px-4 py-3 text-sm leading-6 ${
              !clientError && state.status === "success"
                ? "bg-[#edf4ed] text-[#24563d]"
                : "bg-[#fff1ee] text-[#8f3026]"
            }`}
            role={clientError || state.status === "error" ? "alert" : "status"}
          >
            {clientError || state.message}
          </p>
        )}

        <button
          className="inline-flex min-h-12 w-full items-center justify-center rounded-lg bg-[#17634a] px-5 font-semibold text-white transition-colors hover:bg-[#104d39] disabled:cursor-wait disabled:opacity-65"
          disabled={isPending || state.status === "success"}
          type="submit"
        >
          {isPending
            ? pendingLabel
            : state.status === "success"
              ? "درخواست ثبت شد"
              : submitLabel}
        </button>
      </form>

      {links.length > 0 && (
        <nav
          aria-label="پیوندهای بیشتر"
          className="mt-6 flex flex-wrap gap-x-5 gap-y-3 text-sm font-medium text-[#32634d]"
        >
          {links.map((link) => (
            <Link
              className="underline-offset-4 hover:underline"
              href={link.href}
              key={link.href}
            >
              {link.label}
            </Link>
          ))}
        </nav>
      )}
    </section>
  );
}
