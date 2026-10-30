import "server-only";

import { createClient } from "./server";
import { SupabaseAuthError } from "./env";

export type CurrentUser = {
  id: string;
  email: string | null;
};

export async function getCurrentUser(): Promise<CurrentUser | null> {
  const supabase = await createClient();
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error?.name === "AuthSessionMissingError") {
    return null;
  }

  if (error) {
    throw new SupabaseAuthError();
  }

  if (!user) {
    return null;
  }

  return { id: user.id, email: user.email ?? null };
}
