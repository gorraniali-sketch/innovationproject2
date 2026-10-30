import AuthForm from "../auth-form";
import { requestPasswordReset } from "../actions";

export default function ForgotPasswordPage() {
  return (
    <AuthForm
      action={requestPasswordReset}
      description="ایمیل حساب خود را وارد کنید. اگر حسابی با این نشانی وجود داشته باشد، پیوند بازنشانی برایتان فرستاده می‌شود."
      fields={[
        {
          name: "email",
          label: "ایمیل",
          type: "email",
          autoComplete: "email",
          maxLength: 254,
        },
      ]}
      links={[{ href: "/auth/sign-in", label: "بازگشت به ورود" }]}
      pendingLabel="در حال ارسال…"
      submitLabel="درخواست بازنشانی"
      title="بازیابی رمز عبور"
    />
  );
}
