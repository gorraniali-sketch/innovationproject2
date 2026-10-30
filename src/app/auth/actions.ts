"use server";

import { revalidatePath } from "next/cache";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import {
  getSiteUrlOrNull,
  getSupabaseConfigOrNull,
  SupabaseConfigurationError,
} from "@/lib/supabase/env";
import {
  isValidEmail,
  isValidPassword,
  normalizeEmail,
  type AuthActionState,
} from "@/lib/supabase/auth-validation";

const unavailableState: AuthActionState = {
  status: "error",
  message:
    "سرویس احراز هویت برای این محیط آماده نیست. لطفاً بعداً دوباره تلاش کنید.",
};

const requestFailedState: AuthActionState = {
  status: "error",
  message: "در حال حاضر انجام درخواست ممکن نیست. کمی بعد دوباره تلاش کنید.",
};

const confirmationCooldownSeconds = 60;
const confirmationCooldownCookie = "javanah-confirmation-cooldown";

async function createConfiguredClient() {
  try {
    if (!getSupabaseConfigOrNull()) {
      return null;
    }

    return await createClient();
  } catch (error) {
    if (error instanceof SupabaseConfigurationError) {
      return null;
    }

    throw error;
  }
}

function readString(formData: FormData, name: string): string | null {
  const value = formData.get(name);
  return typeof value === "string" ? value : null;
}

function getEmail(formData: FormData): string | null {
  const value = readString(formData, "email");

  if (value === null) {
    return null;
  }

  const email = normalizeEmail(value);
  return isValidEmail(email) ? email : null;
}

function getCallbackUrl(path: string): string | null {
  try {
    const siteUrl = getSiteUrlOrNull();

    if (!siteUrl) {
      return null;
    }

    const callback = new URL("/auth/callback", siteUrl);
    callback.searchParams.set("next", path);
    return callback.toString();
  } catch (error) {
    if (error instanceof SupabaseConfigurationError) {
      return null;
    }

    throw error;
  }
}

export async function signUp(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const email = getEmail(formData);
  const password = readString(formData, "password");
  const confirmation = readString(formData, "confirmPassword");

  if (!email) {
    return { status: "error", message: "یک نشانی ایمیل معتبر وارد کنید." };
  }

  if (password === null || !isValidPassword(password)) {
    return {
      status: "error",
      message: "رمز عبور باید بین ۸ تا ۱۲۸ نویسه باشد.",
    };
  }

  if (password !== confirmation) {
    return {
      status: "error",
      message: "رمز عبور و تکرار آن یکسان نیستند.",
    };
  }

  const supabase = await createConfiguredClient();
  const emailRedirectTo = getCallbackUrl("/auth/confirmed");

  if (!supabase || !emailRedirectTo) {
    return unavailableState;
  }

  try {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: { emailRedirectTo },
    });

    if (error) {
      return requestFailedState;
    }

    if (data.session) {
      const { error: signOutError } = await supabase.auth.signOut({
        scope: "local",
      });

      if (signOutError) {
        return requestFailedState;
      }

      return {
        status: "error",
        message:
          "تأیید ایمیل در تنظیمات این پروژه فعال نیست. برای جلوگیری از ورود پیش از تأیید، ثبت‌نام تکمیل نشد.",
      };
    }
  } catch {
    return requestFailedState;
  }

  return {
    status: "success",
    message:
      "درخواست ثبت‌نام دریافت شد. اگر این نشانی آماده‌ی ثبت‌نام باشد، ایمیل تأیید برایتان فرستاده می‌شود؛ صندوق ورودی و پوشه‌ی هرزنامه را بررسی کنید.",
  };
}

export async function signIn(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const email = getEmail(formData);
  const password = readString(formData, "password");

  if (!email || !password || password.length > 128) {
    return {
      status: "error",
      message: "ایمیل و رمز عبور معتبر وارد کنید.",
    };
  }

  const supabase = await createConfiguredClient();

  if (!supabase) {
    return unavailableState;
  }

  try {
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      return {
        status: "error",
        message:
          "ورود انجام نشد. ایمیل و رمز عبور را بررسی کنید و اگر ایمیل را تأیید نکرده‌اید، ابتدا آن را تأیید کنید.",
      };
    }
  } catch {
    return requestFailedState;
  }

  revalidatePath("/", "layout");
  redirect("/ideas/new");
}

export async function requestPasswordReset(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const email = getEmail(formData);

  if (!email) {
    return { status: "error", message: "یک نشانی ایمیل معتبر وارد کنید." };
  }

  const supabase = await createConfiguredClient();
  const redirectTo = getCallbackUrl("/auth/update-password");

  if (!supabase || !redirectTo) {
    return unavailableState;
  }

  try {
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo,
    });

    if (error) {
      return requestFailedState;
    }
  } catch {
    return requestFailedState;
  }

  return {
    status: "success",
    message:
      "اگر حسابی با این نشانی وجود داشته باشد، دستورهای بازنشانی رمز عبور برای آن ارسال می‌شود.",
  };
}

export async function resendConfirmation(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const email = getEmail(formData);

  if (!email) {
    return { status: "error", message: "یک نشانی ایمیل معتبر وارد کنید." };
  }

  const cookieStore = await cookies();
  const cooldownUntil = Number(
    cookieStore.get(confirmationCooldownCookie)?.value ?? 0,
  );
  const now = Date.now();

  if (Number.isFinite(cooldownUntil) && cooldownUntil > now) {
    const seconds = Math.ceil((cooldownUntil - now) / 1000);
    return {
      status: "error",
      message: `برای درخواست دوباره، ${seconds} ثانیه صبر کنید.`,
    };
  }

  const supabase = await createConfiguredClient();
  const emailRedirectTo = getCallbackUrl("/auth/confirmed");

  if (!supabase || !emailRedirectTo) {
    return unavailableState;
  }

  cookieStore.set(
    confirmationCooldownCookie,
    String(now + confirmationCooldownSeconds * 1000),
    {
      httpOnly: true,
      maxAge: confirmationCooldownSeconds,
      path: "/auth/resend-confirmation",
      sameSite: "lax",
      secure: process.env.NODE_ENV === "production",
    },
  );

  try {
    const { error } = await supabase.auth.resend({
      type: "signup",
      email,
      options: { emailRedirectTo },
    });

    if (error) {
      return requestFailedState;
    }
  } catch {
    return requestFailedState;
  }

  return {
    status: "success",
    message:
      "اگر این نشانی به حسابی نیازمند تأیید متصل باشد، ایمیل تأیید ارسال می‌شود. در صورت نرسیدن ایمیل، پوشه‌ی هرزنامه را هم بررسی کنید.",
  };
}

export async function updatePassword(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const password = readString(formData, "password");
  const confirmation = readString(formData, "confirmPassword");

  if (password === null || !isValidPassword(password)) {
    return {
      status: "error",
      message: "رمز عبور باید بین ۸ تا ۱۲۸ نویسه باشد.",
    };
  }

  if (password !== confirmation) {
    return {
      status: "error",
      message: "رمز عبور و تکرار آن یکسان نیستند.",
    };
  }

  const supabase = await createConfiguredClient();

  if (!supabase) {
    return unavailableState;
  }

  try {
    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser();

    if (userError || !user) {
      return {
        status: "error",
        message:
          "پیوند بازنشانی معتبر نیست یا اعتبارش پایان یافته است. دوباره درخواست بازنشانی بدهید.",
      };
    }

    const { error } = await supabase.auth.updateUser({ password });

    if (error) {
      return requestFailedState;
    }
  } catch {
    return requestFailedState;
  }

  revalidatePath("/", "layout");
  return {
    status: "success",
    message: "رمز عبور با موفقیت تغییر کرد.",
  };
}

export async function signOut(
  previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  void previousState;
  void formData;

  const supabase = await createConfiguredClient();

  if (!supabase) {
    return unavailableState;
  }

  try {
    const { error } = await supabase.auth.signOut();

    if (error) {
      return requestFailedState;
    }
  } catch {
    return requestFailedState;
  }

  revalidatePath("/", "layout");
  redirect("/");
}
