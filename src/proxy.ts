import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import {
  getSupabaseConfigOrNull,
  SupabaseAuthError,
} from "@/lib/supabase/env";

export async function proxy(request: NextRequest) {
  if (
    process.env.NODE_ENV === "development" &&
    request.method === "POST" &&
    request.nextUrl.pathname === "/auth/sign-up"
  ) {
    console.info("[server-action-host-debug]", {
      origin: request.headers.get("origin"),
      host: request.headers.get("host"),
      "x-forwarded-host": request.headers.get("x-forwarded-host"),
    });
  }

  const config = getSupabaseConfigOrNull();

  if (!config) {
    return NextResponse.next({ request });
  }

  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    config.url,
    config.publishableKey,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet, headers) {
          cookiesToSet.forEach(({ name, value }) => {
            request.cookies.set(name, value);
          });

          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) => {
            response.cookies.set(name, value, options);
          });
          Object.entries(headers).forEach(([name, value]) => {
            response.headers.set(name, value);
          });
        },
      },
    },
  );

  const { error } = await supabase.auth.getClaims();

  if (error && error.name !== "AuthSessionMissingError") {
    throw new SupabaseAuthError();
  }

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
