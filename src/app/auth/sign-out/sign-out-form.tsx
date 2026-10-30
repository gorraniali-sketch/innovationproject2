"use client";

import { useActionState } from "react";
import { signOut } from "../actions";
import { initialAuthActionState } from "@/lib/supabase/auth-validation";

export default function SignOutForm() {
  const [state, formAction, isPending] = useActionState(
    signOut,
    initialAuthActionState,
  );

  return (
    <form action={formAction}>
      {state.status === "error" && (
        <p
          aria-live="polite"
          className="mb-5 rounded-lg bg-[#fff1ee] px-4 py-3 text-sm leading-6 text-[#8f3026]"
          role="alert"
        >
          {state.message}
        </p>
      )}
      <button
        className="inline-flex min-h-12 w-full items-center justify-center rounded-lg bg-[#17634a] px-5 font-semibold text-white transition-colors hover:bg-[#104d39] disabled:cursor-wait disabled:opacity-65"
        disabled={isPending}
        type="submit"
      >
        {isPending ? "در حال خروج…" : "خروج از حساب"}
      </button>
    </form>
  );
}
