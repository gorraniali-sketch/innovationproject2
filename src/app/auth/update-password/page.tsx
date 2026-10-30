import AuthForm from "../auth-form";
import { updatePassword } from "../actions";

export default function UpdatePasswordPage() {
  return (
    <AuthForm
      action={updatePassword}
      description="رمز عبور تازه‌ای انتخاب کنید. این فرم فقط با نشست معتبر ایجادشده از پیوند بازنشانی کار می‌کند."
      fields={[
        {
          name: "password",
          label: "رمز عبور جدید (۸ تا ۱۲۸ نویسه)",
          type: "password",
          autoComplete: "new-password",
          minLength: 8,
          maxLength: 128,
        },
        {
          name: "confirmPassword",
          label: "تکرار رمز عبور جدید",
          type: "password",
          autoComplete: "new-password",
          minLength: 8,
          maxLength: 128,
        },
      ]}
      links={[
        { href: "/auth/forgot-password", label: "درخواست پیوند تازه" },
      ]}
      pendingLabel="در حال ذخیره…"
      submitLabel="تغییر رمز عبور"
      title="انتخاب رمز عبور جدید"
    />
  );
}
