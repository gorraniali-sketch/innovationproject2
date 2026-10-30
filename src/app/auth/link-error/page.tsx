import AuthNotice from "../auth-notice";

export default function AuthLinkErrorPage() {
  return (
    <AuthNotice
      description="پیوند تأیید یا بازنشانی معتبر نیست، قبلاً استفاده شده یا اعتبارش پایان یافته است. برای دریافت پیوند تازه درخواست جدیدی ثبت کنید."
      links={[
        { href: "/auth/sign-up", label: "تلاش دوباره برای ثبت‌نام" },
        { href: "/auth/resend-confirmation", label: "درخواست ایمیل تأیید" },
        { href: "/auth/forgot-password", label: "درخواست بازنشانی رمز عبور" },
      ]}
      title="پیوند قابل استفاده نیست"
    />
  );
}
