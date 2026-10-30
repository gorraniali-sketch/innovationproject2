import Link from "next/link";

export default function AuthLayout({
  children,
}: LayoutProps<"/auth">) {
  return (
    <div className="min-h-screen bg-[#f6f8f4]" dir="rtl">
      <header className="border-b border-[#e6e9e2] bg-[#fbfcf9]">
        <div className="mx-auto flex min-h-[72px] max-w-5xl items-center justify-between gap-4 px-5 sm:px-8">
          <Link
            aria-label="جوانه، بازگشت به صفحه‌ی اصلی"
            className="text-lg font-bold text-[#174a3a]"
            href="/"
          >
            جوانه
          </Link>
          <Link
            className="text-sm font-medium text-[#53635b] transition-colors hover:text-[#174a3a]"
            href="/"
          >
            بازگشت به صفحه‌ی اصلی
          </Link>
        </div>
      </header>
      <main className="mx-auto max-w-xl px-5 py-10 sm:px-8 sm:py-14">
        {children}
      </main>
    </div>
  );
}
