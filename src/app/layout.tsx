import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "جوانه | سامانه ایده‌یابی و پرورش ایده",
  description:
    "در جوانه، مسئله‌های اجتماعی را بهتر بشناسید و ایده‌هایی برای ساختن راه‌حل‌های قابل اجرا پرورش دهید.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="fa" dir="rtl" className="h-full antialiased">
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
