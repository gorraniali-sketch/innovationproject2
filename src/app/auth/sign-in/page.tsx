import AuthForm from "../auth-form";
import { signIn } from "../actions";

export default function SignInPage() {
  return (
    <AuthForm
      action={signIn}
      description="با ایمیل تأییدشده و رمز عبور حساب خود وارد شوید."
      fields={[
        {
          name: "email",
          label: "ایمیل",
          type: "email",
          autoComplete: "email",
          maxLength: 254,
        },
        {
          name: "password",
          label: "رمز عبور",
          type: "password",
          autoComplete: "current-password",
          maxLength: 128,
        },
      ]}
      links={[
        { href: "/auth/sign-up", label: "ساخت حساب جدید" },
        { href: "/auth/forgot-password", label: "رمز عبور را فراموش کرده‌اید؟" },
        {
          href: "/auth/resend-confirmation",
          label: "ارسال دوباره‌ی ایمیل تأیید",
        },
      ]}
      pendingLabel="در حال ورود…"
      submitLabel="ورود"
      title="ورود به جوانه"
    />
  );
}
