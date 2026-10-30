import Link from "next/link";

type AuthNoticeProps = {
  title: string;
  description: string;
  links: { href: string; label: string }[];
};

export default function AuthNotice({
  title,
  description,
  links,
}: AuthNoticeProps) {
  return (
    <section
      aria-labelledby="auth-notice-title"
      className="rounded-2xl border border-[#e3e9e1] bg-white p-6 shadow-[0_16px_45px_-38px_rgba(24,58,43,0.35)] sm:p-8"
    >
      <h1
        className="text-2xl font-bold leading-snug text-[#173d32] sm:text-3xl"
        id="auth-notice-title"
      >
        {title}
      </h1>
      <p className="mt-4 leading-7 text-[#647169]">{description}</p>
      <nav
        aria-label="گام بعدی"
        className="mt-7 flex flex-wrap gap-x-5 gap-y-3 text-sm font-semibold text-[#32634d]"
      >
        {links.map((link) => (
          <Link
            className="underline-offset-4 hover:underline"
            href={link.href}
            key={link.href}
          >
            {link.label}
          </Link>
        ))}
      </nav>
    </section>
  );
}
