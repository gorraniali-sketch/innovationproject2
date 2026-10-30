import AuthForm from "../auth-form";
import { signUp } from "../actions";

export default function SignUpPage() {
  return (
    <AuthForm
      action={signUp}
      description="برای ساخت حساب جوانه، ایمیل و رمز عبور خود را وارد کنید. ورود پس از تأیید ایمیل امکان‌پذیر است."
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
          label: "رمز عبور (۸ تا ۱۲۸ نویسه)",
          type: "password",
          autoComplete: "new-password",
          minLength: 8,
          maxLength: 128,
        },
        {
          name: "confirmPassword",
          label: "تکرار رمز عبور",
          type: "password",
          autoComplete: "new-password",
          minLength: 8,
          maxLength: 128,
        },
      ]}
      links={[
        { href: "/auth/sign-in", label: "از قبل حساب دارید؟ وارد شوید" },
        {
          href: "/auth/resend-confirmation",
          label: "ارسال دوباره‌ی ایمیل تأیید",
        },
      ]}
      pendingLabel="در حال ثبت‌نام…"
      submitLabel="ساخت حساب"
      title="ثبت‌نام در جوانه"
    />
  );
}
