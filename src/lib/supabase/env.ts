export type SupabaseConfig = {
  url: string;
  publishableKey: string;
};

export class SupabaseConfigurationError extends Error {
  constructor() {
    super(
      "Supabase is not configured. Set NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, and NEXT_PUBLIC_SITE_URL.",
    );
    this.name = "SupabaseConfigurationError";
  }
}

export class SupabaseAuthError extends Error {
  constructor() {
    super("Supabase authentication could not be completed.");
    this.name = "SupabaseAuthError";
  }
}

export function getSupabaseConfigOrNull(): SupabaseConfig | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!url || !publishableKey) {
    return null;
  }

  let parsedUrl: URL;

  try {
    parsedUrl = new URL(url);
  } catch {
    throw new SupabaseConfigurationError();
  }

  const isLocalHttp =
    parsedUrl.protocol === "http:" &&
    ["localhost", "127.0.0.1", "::1"].includes(parsedUrl.hostname);

  if (parsedUrl.protocol !== "https:" && !isLocalHttp) {
    throw new SupabaseConfigurationError();
  }

  return { url, publishableKey };
}

export function getSupabaseConfig(): SupabaseConfig {
  const config = getSupabaseConfigOrNull();

  if (!config) {
    throw new SupabaseConfigurationError();
  }

  return config;
}

export function getSiteUrlOrNull(): URL | null {
  const value = process.env.NEXT_PUBLIC_SITE_URL;

  if (!value) {
    return null;
  }

  let siteUrl: URL;

  try {
    siteUrl = new URL(value);
  } catch {
    throw new SupabaseConfigurationError();
  }

  const isLocalHttp =
    siteUrl.protocol === "http:" &&
    ["localhost", "127.0.0.1", "::1"].includes(siteUrl.hostname);

  if (
    (siteUrl.protocol !== "https:" && !isLocalHttp) ||
    siteUrl.username ||
    siteUrl.password ||
    siteUrl.pathname !== "/" ||
    siteUrl.search ||
    siteUrl.hash
  ) {
    throw new SupabaseConfigurationError();
  }

  return siteUrl;
}
