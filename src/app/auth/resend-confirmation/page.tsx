import AuthForm from "../auth-form";
import { resendConfirmation } from "../actions";

export default function ResendConfirmationPage() {
  return (
    <AuthForm
      action={resendConfirmation}
      description="ایمیل حساب خود را وارد کنید. برای جلوگیری از ارسال پی‌درپی، پس از هر درخواست باید ۶۰ ثانیه صبر کنید."
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
      submitLabel="ارسال ایمیل تأیید"
      title="ارسال دوباره‌ی ایمیل تأیید"
    />
  );
}
