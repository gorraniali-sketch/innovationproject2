const processSteps = [
  {
    number: "۰۱",
    title: "تعریف مسئله",
    description:
      "از یک نیاز یا مسئله‌ی واقعی در جامعه شروع کنید و روشن کنید چه چیزی نیاز به تغییر دارد.",
  },
  {
    number: "۰۲",
    title: "گفت‌وگوی راهنما",
    description:
      "با پرسش‌های هدفمند، ابعاد مسئله، افراد درگیر و فرصت‌های پیش رو را بهتر بشناسید.",
  },
  {
    number: "۰۳",
    title: "تدوین ایده",
    description:
      "بینش‌های خود را به ایده‌ای روشن، قابل توضیح و آماده‌ی بررسی و توسعه تبدیل کنید.",
  },
];

const eventThemes = [
  "کیفیت زندگی شهری",
  "آموزش و فرصت برابر",
  "سلامت و رفاه اجتماعی",
  "محیط زیست و پایداری",
];

const persianNumber = new Intl.NumberFormat("fa-IR", {
  minimumIntegerDigits: 2,
  useGrouping: false,
});

export default function Home() {
  return (
    <div className="overflow-hidden">
      <header className="border-b border-[#e6e9e2] bg-[#fbfcf9]">
        <div className="mx-auto flex min-h-[76px] max-w-7xl items-center justify-between gap-6 px-5 sm:px-8 lg:px-12">
          <a
            aria-label="جوانه، رفتن به ابتدای صفحه"
            className="flex shrink-0 items-center gap-3 text-[#174a3a]"
            href="#top"
          >
            <span className="flex size-10 items-center justify-center rounded-xl bg-[#e6f0e7]">
              <svg
                aria-hidden="true"
                className="size-6"
                fill="none"
                viewBox="0 0 24 24"
              >
                <path
                  d="M12 20v-8m0 3c-4.5 0-7-2.5-7-7 4.5 0 7 2.5 7 7Zm0-3c0-4.5 2.5-7 7-7 0 4.5-2.5 7-7 7Z"
                  stroke="currentColor"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="1.7"
                />
              </svg>
            </span>
            <span className="text-xl font-bold tracking-tight">جوانه</span>
          </a>

          <nav
            aria-label="ناوبری اصلی"
            className="hidden items-center gap-8 text-sm font-medium text-[#53635b] md:flex"
          >
            <a className="transition-colors hover:text-[#174a3a]" href="#intro">
              معرفی سامانه
            </a>
            <a
              className="transition-colors hover:text-[#174a3a]"
              href="#event-themes"
            >
              محورهای رویداد
            </a>
            <a
              className="transition-colors hover:text-[#174a3a]"
              href="#how-it-works"
            >
              راهنما
            </a>
          </nav>

          <div className="flex items-center gap-3">
            <a
              className="text-xs font-semibold text-[#32634d] transition-colors hover:text-[#174a3a] sm:text-sm"
              href="/auth/sign-in"
            >
              ورود
            </a>
            <a
              className="text-xs font-semibold text-[#32634d] transition-colors hover:text-[#174a3a] sm:text-sm"
              href="/auth/sign-up"
            >
              ثبت‌نام
            </a>
            <a
              className="inline-flex min-h-11 items-center justify-center rounded-lg bg-[#17634a] px-4 text-sm font-semibold text-white transition-colors hover:bg-[#104d39] sm:px-5"
              href="/ideas/new"
            >
              شروع ایده‌یابی
            </a>
          </div>
        </div>
      </header>

      <main id="top">
        <section
          aria-labelledby="hero-title"
          className="bg-[#f3f7f1]"
          id="intro"
        >
          <div className="mx-auto grid max-w-7xl items-center gap-14 px-5 py-16 sm:px-8 sm:py-20 lg:grid-cols-[1.05fr_0.95fr] lg:gap-20 lg:px-12 lg:py-24">
            <div>
              <p className="mb-6 inline-flex items-center gap-2 rounded-full border border-[#dbe7dc] bg-white/70 px-3.5 py-2 text-sm font-medium text-[#32634d]">
                <span aria-hidden="true" className="size-2 rounded-full bg-[#da8a45]" />
                ایده‌های کوچک، تغییرهای ماندگار
              </p>
              <h1
                className="max-w-2xl text-4xl leading-[1.45] font-bold tracking-tight text-[#173d32] sm:text-5xl sm:leading-[1.4] lg:text-[3.5rem]"
                id="hero-title"
              >
                مسئله‌های اجتماعی را به ایده‌های قابل اجرا تبدیل کنیم
              </h1>
              <p className="mt-6 max-w-xl text-base leading-8 text-[#58675f] sm:text-lg">
                جوانه فضایی برای دیدن دقیق‌تر چالش‌های پیرامون ما و پرورش راه‌حل‌هایی
                است که از دل تجربه و گفت‌وگو شکل می‌گیرند.
              </p>
              <div className="mt-9 flex flex-col gap-3 sm:flex-row sm:items-center">
                <a
                  className="inline-flex min-h-12 items-center justify-center rounded-lg bg-[#17634a] px-6 font-semibold text-white transition-colors hover:bg-[#104d39]"
                  href="/ideas/new"
                >
                  ایده‌ام را پرورش می‌دهم
                </a>
                <a
                  className="inline-flex min-h-12 items-center justify-center rounded-lg border border-[#cad8cc] bg-white/70 px-6 font-semibold text-[#285942] transition-colors hover:bg-white"
                  href="#event-themes"
                >
                  آشنایی با محورهای رویداد
                </a>
              </div>
            </div>

            <div
              aria-label="نمایی نمونه از مسیر شکل‌گیری یک ایده"
              className="relative mx-auto w-full max-w-lg"
              role="img"
            >
              <div className="absolute -inset-4 rounded-[2rem] bg-[#e4eee2]" />
              <div className="relative rounded-2xl border border-[#e1e8df] bg-white p-6 shadow-[0_18px_50px_-32px_rgba(24,58,43,0.35)] sm:p-8">
                <div className="flex items-center justify-between gap-4 border-b border-[#edf0eb] pb-5">
                  <div>
                    <p className="text-sm font-semibold text-[#244c39]">
                      از پرسش تا امکان
                    </p>
                    <p className="mt-1 text-xs text-[#7a877f]">
                      نمونه‌ای از مسیر پرورش ایده
                    </p>
                  </div>
                  <span className="rounded-md bg-[#f7f0e7] px-3 py-1.5 text-xs font-medium text-[#966332]">
                    سه گام
                  </span>
                </div>
                <div className="mt-6 space-y-4">
                  <div className="flex items-start gap-4 rounded-xl bg-[#f7f9f6] p-4">
                    <span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-[#e5eee5] text-sm font-bold text-[#32634d]">
                      ۱
                    </span>
                    <div>
                      <p className="font-semibold text-[#273f34]">چه چیزی نیاز به تغییر دارد؟</p>
                      <p className="mt-1 text-sm leading-6 text-[#718078]">
                        مسئله را از نگاه افراد درگیر ببینیم.
                      </p>
                    </div>
                  </div>
                  <div className="flex items-start gap-4 rounded-xl border border-[#e8ece6] p-4">
                    <span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-[#f8eee3] text-sm font-bold text-[#a66a32]">
                      ۲
                    </span>
                    <div>
                      <p className="font-semibold text-[#273f34]">چه امکان‌هایی داریم؟</p>
                      <p className="mt-1 text-sm leading-6 text-[#718078]">
                        با پرسش و گفت‌وگو، راه‌های تازه را پیدا کنیم.
                      </p>
                    </div>
                  </div>
                  <div className="flex items-start gap-4 rounded-xl bg-[#174a3a] p-4 text-white">
                    <span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-white/15 text-sm font-bold">
                      ۳
                    </span>
                    <div>
                      <p className="font-semibold">ایده را شکل بدهیم</p>
                      <p className="mt-1 text-sm leading-6 text-white/75">
                        راه‌حلی روشن برای قدم بعدی بسازیم.
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section
          aria-labelledby="process-title"
          className="bg-white py-20 sm:py-24"
          id="how-it-works"
        >
          <div className="mx-auto max-w-7xl px-5 sm:px-8 lg:px-12">
            <div className="max-w-2xl">
              <p className="text-sm font-bold text-[#a66a32]">مسیر ایده‌پردازی</p>
              <h2
                className="mt-3 text-3xl leading-snug font-bold tracking-tight text-[#173d32] sm:text-4xl"
                id="process-title"
              >
                از مشاهده تا ساختن راه‌حل
              </h2>
              <p className="mt-4 text-base leading-8 text-[#647169]">
                ایده‌پردازی با یک پاسخ قطعی شروع نمی‌شود؛ با شناخت مسئله و چند پرسش
                خوب، مسیر روشن‌تری پیدا می‌کند.
              </p>
            </div>

            <ol className="mt-10 grid gap-5 md:grid-cols-3">
              {processSteps.map((step) => (
                <li
                  className="rounded-xl border border-[#e6ebe5] bg-[#fbfcfa] p-6 sm:p-7"
                  key={step.number}
                >
                  <span className="text-sm font-bold tracking-wide text-[#b47740]">
                    گام {step.number}
                  </span>
                  <h3 className="mt-5 text-xl font-bold text-[#214535]">
                    {step.title}
                  </h3>
                  <p className="mt-3 leading-7 text-[#637168]">
                    {step.description}
                  </p>
                </li>
              ))}
            </ol>
          </div>
        </section>

        <section
          aria-labelledby="themes-title"
          className="bg-[#f6f8f4] py-20 sm:py-24"
          id="event-themes"
        >
          <div className="mx-auto grid max-w-7xl gap-10 px-5 sm:px-8 lg:grid-cols-[0.85fr_1.15fr] lg:items-start lg:gap-16 lg:px-12">
            <div>
              <p className="text-sm font-bold text-[#a66a32]">نگاه به پیرامون</p>
              <h2
                className="mt-3 text-3xl leading-snug font-bold tracking-tight text-[#173d32] sm:text-4xl"
                id="themes-title"
              >
                محورهایی برای شروع فکر
              </h2>
              <p className="mt-4 leading-8 text-[#647169]">
                این عنوان‌ها نمونه‌های عمومی و قابل‌ویرایش‌اند؛ محورهای نهایی رویداد
                پس از تأیید، جداگانه اعلام می‌شوند.
              </p>
            </div>
            <ul className="grid gap-3 sm:grid-cols-2">
              {eventThemes.map((theme, index) => (
                <li
                  className="flex min-h-24 items-center gap-4 rounded-xl border border-[#e3e9e1] bg-white p-5"
                  key={theme}
                >
                  <span className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-[#eaf1e8] text-sm font-bold text-[#32634d]">
                    {persianNumber.format(index + 1)}
                  </span>
                  <span className="font-semibold text-[#294536]">{theme}</span>
                </li>
              ))}
            </ul>
          </div>
        </section>

        <section
          aria-labelledby="closing-title"
          className="bg-[#174a3a] py-16 text-white sm:py-20"
          id="start"
        >
          <div className="mx-auto flex max-w-7xl flex-col gap-7 px-5 sm:px-8 md:flex-row md:items-center md:justify-between lg:px-12">
            <div className="max-w-2xl">
              <h2
                className="text-3xl leading-snug font-bold tracking-tight sm:text-4xl"
                id="closing-title"
              >
                هر ایده‌ی اثرگذار، از دیدن یک مسئله آغاز می‌شود.
              </h2>
              <p className="mt-4 leading-7 text-white/75">
                برای آشنایی با قدم‌های پرورش ایده، مسیر سه‌مرحله‌ای را ببینید.
              </p>
            </div>
            <a
              className="inline-flex min-h-12 shrink-0 items-center justify-center rounded-lg bg-white px-6 font-semibold text-[#174a3a] transition-colors hover:bg-[#edf3ed]"
              href="/ideas/new"
            >
              شروع ایده‌یابی
            </a>
          </div>
        </section>
      </main>

      <footer className="bg-[#11392e] py-6 text-sm text-white/70">
        <div className="mx-auto flex max-w-7xl flex-col gap-2 px-5 sm:px-8 md:flex-row md:items-center md:justify-between lg:px-12">
          <p className="font-semibold text-white">جوانه؛ جایی برای رشد ایده‌ها</p>
          <p>با هم، برای مسئله‌هایی که به راه‌حل نیاز دارند.</p>
        </div>
      </footer>
    </div>
  );
}
