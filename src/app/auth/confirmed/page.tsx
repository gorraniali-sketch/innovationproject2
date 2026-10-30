import { Suspense } from "react";
import { createClient } from "@/lib/supabase/server";
import { getSupabaseConfigOrNull } from "@/lib/supabase/env";
import AuthNotice from "../auth-notice";

function UnverifiedNotice() {
  return (
    <AuthNotice
      description="وضعیت تأیید این پیوند قابل بررسی نیست یا نشست معتبری پیدا نشد. می‌توانید وارد شوید یا برای دریافت پیوند تازه درخواست بدهید."
      links={[
        { href: "/auth/sign-in", label: "ورود به حساب" },
        { href: "/auth/resend-confirmation", label: "درخواست ایمیل تأیید تازه" },
      ]}
      title="تأیید ایمیل قابل تأیید نیست"
    />
  );
}

async function hasConfirmedEmail(): Promise<boolean> {
  try {
    if (!getSupabaseConfigOrNull()) {
      return false;
    }

    const supabase = await createClient();
    const {
      data: { user },
      error,
    } = await supabase.auth.getUser();

    return !error && Boolean(user?.email_confirmed_at);
  } catch {
    return false;
  }
}

async function ConfirmationStatus() {
  if (!(await hasConfirmedEmail())) {
    return <UnverifiedNotice />;
  }

  return (
    <AuthNotice
      description="ایمیل شما تأیید شد و ثبت‌نام کامل است. می‌توانید مسیر ایده‌یابی را ادامه دهید."
      links={[
        { href: "/ideas/new", label: "رفتن به ایده‌یابی" },
        { href: "/", label: "صفحه‌ی اصلی" },
      ]}
      title="تأیید ایمیل انجام شد"
    />
  );
}

export default function ConfirmedPage() {
  return (
    <Suspense
      fallback={
        <AuthNotice
          description="در حال بررسی وضعیت تأیید ایمیل…"
          links={[]}
          title="لطفاً کمی صبر کنید"
        />
      }
    >
      <ConfirmationStatus />
    </Suspense>
  );
}
