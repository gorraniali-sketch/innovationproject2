import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getSupabaseConfigOrNull } from "@/lib/supabase/env";
import { getAuthRedirectPath } from "@/lib/supabase/auth-validation";

function redirectTo(request: NextRequest, path: string) {
  const response = NextResponse.redirect(new URL(path, request.url));
  response.headers.set("Referrer-Policy", "no-referrer");
  return response;
}

export async function GET(request: NextRequest) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const destination = getAuthRedirectPath(url.searchParams.get("next"));

  if (!code) {
    return redirectTo(request, "/auth/link-error");
  }

  try {
    if (!getSupabaseConfigOrNull()) {
      return redirectTo(request, "/auth/link-error");
    }

    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);

    if (error) {
      return redirectTo(request, "/auth/link-error");
    }
  } catch {
    return redirectTo(request, "/auth/link-error");
  }

  return redirectTo(request, destination);
}
