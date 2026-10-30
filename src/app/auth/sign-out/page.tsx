import SignOutForm from "./sign-out-form";

export default function SignOutPage() {
  return (
    <section
      aria-labelledby="sign-out-title"
      className="rounded-2xl border border-[#e3e9e1] bg-white p-6 shadow-[0_16px_45px_-38px_rgba(24,58,43,0.35)] sm:p-8"
    >
      <h1
        className="text-2xl font-bold leading-snug text-[#173d32] sm:text-3xl"
        id="sign-out-title"
      >
        خروج از حساب
      </h1>
      <p className="mt-4 mb-7 leading-7 text-[#647169]">
        با انتخاب دکمه‌ی زیر، نشست این مرورگر پاک می‌شود.
      </p>
      <SignOutForm />
    </section>
  );
}
