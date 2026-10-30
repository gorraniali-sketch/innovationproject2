"use client";

import Link from "next/link";
import { useState } from "react";

const socialThemes = [
  "کیفیت زندگی شهری",
  "آموزش و فرصت برابر",
  "سلامت و رفاه اجتماعی",
  "محیط زیست و پایداری",
  "مشارکت و همبستگی اجتماعی",
  "موضوعی دیگر",
];

type IdeaDraft = {
  theme: string;
  problem: string;
  affectedPeople: string;
  possibleCauses: string;
  proposedSolution: string;
  beneficiaryGroup: string;
  expectedOutcome: string;
  implementationBarriers: string;
};

type Step = 1 | 2 | 3;

const emptyDraft: IdeaDraft = {
  theme: "",
  problem: "",
  affectedPeople: "",
  possibleCauses: "",
  proposedSolution: "",
  beneficiaryGroup: "",
  expectedOutcome: "",
  implementationBarriers: "",
};

function WizardHeader() {
  return (
    <header className="border-b border-[#e6e9e2] bg-[#fbfcf9]">
      <div className="mx-auto flex min-h-[72px] max-w-5xl items-center justify-between gap-4 px-5 sm:px-8">
        <Link
          className="text-lg font-bold text-[#174a3a]"
          href="/"
          aria-label="جوانه، بازگشت به صفحه اصلی"
        >
          جوانه
        </Link>
        <Link
          className="text-sm font-medium text-[#53635b] transition-colors hover:text-[#174a3a]"
          href="/"
        >
          بازگشت به صفحه اصلی
        </Link>
        <Link
          className="text-sm font-medium text-[#53635b] transition-colors hover:text-[#174a3a]"
          href="/auth/sign-out"
        >
          خروج از حساب
        </Link>
      </div>
    </header>
  );
}

function StepProgress({
  activeStep,
  canContinue,
  canAdvanceToStep3,
  onStepChange,
}: {
  activeStep: Step;
  canContinue: boolean;
  canAdvanceToStep3: boolean;
  onStepChange: (step: Step) => void;
}) {
  const steps: { number: Step; title: string }[] = [
    { number: 1, title: "تعریف مسئله" },
    { number: 2, title: "شناخت افراد و علت‌ها" },
    { number: 3, title: "پرورش ایده" },
  ];

  return (
    <nav aria-label="مراحل ایده‌یابی">
      <ol className="grid grid-cols-3 gap-2 sm:gap-3">
        {steps.map((step) => {
          const isActive = activeStep === step.number;
          const isDisabled =
            (step.number === 2 && !canContinue) ||
            (step.number === 3 && !canAdvanceToStep3);

          return (
            <li key={step.number}>
              <button
                aria-current={isActive ? "step" : undefined}
                className={`flex min-h-[68px] w-full items-center gap-2 rounded-lg border px-2 text-right transition-colors sm:gap-3 sm:px-4 ${
                  isActive
                    ? "border-[#17634a] bg-[#edf4ed] text-[#174a3a]"
                    : "border-[#e5eae4] bg-white text-[#758078]"
                } disabled:cursor-not-allowed disabled:opacity-60`}
                disabled={isDisabled}
                onClick={() => onStepChange(step.number)}
                type="button"
              >
                <span
                  className={`flex size-9 shrink-0 items-center justify-center rounded-full text-sm font-bold ${
                    isActive
                      ? "bg-[#17634a] text-white"
                      : "bg-[#f0f2ef] text-[#718078]"
                  }`}
                >
                  {step.number === 1 ? "۱" : step.number === 2 ? "۲" : "۳"}
                </span>
                <span>
                  <span className="block text-xs text-[#77837b]">
                    مرحله {step.number === 1 ? "اول" : step.number === 2 ? "دوم" : "سوم"}
                  </span>
                  <span className="mt-1 block text-xs font-semibold leading-5 sm:text-sm">
                    {step.title}
                  </span>
                </span>
              </button>
            </li>
          );
        })}
      </ol>
    </nav>
  );
}

function TextQuestion({
  id,
  label,
  hint,
  value,
  onChange,
  placeholder,
}: {
  id: string;
  label: string;
  hint: string;
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
}) {
  return (
    <div>
      <label className="block text-base font-semibold text-[#244c39]" htmlFor={id}>
        {label}
      </label>
      <p className="mt-2 text-sm leading-6 text-[#718078]" id={`${id}-hint`}>
        {hint}
      </p>
      <textarea
        className="mt-3 min-h-32 w-full resize-y rounded-lg border border-[#dce4dc] bg-white px-4 py-3 leading-7 text-[#263d32] placeholder:text-[#9aa49d] focus:border-[#17634a] focus:outline-none"
        id={id}
        onChange={(event) => onChange(event.target.value)}
        placeholder={placeholder}
        value={value}
        aria-describedby={`${id}-hint`}
      />
    </div>
  );
}

function ProblemStep({
  draft,
  canContinue,
  onDraftChange,
  onContinue,
}: {
  draft: IdeaDraft;
  canContinue: boolean;
  onDraftChange: (field: keyof IdeaDraft, value: string) => void;
  onContinue: () => void;
}) {
  return (
    <section aria-labelledby="problem-title">
      <p className="text-sm font-bold text-[#a66a32]">مرحله اول از سه</p>
      <h1
        className="mt-2 text-2xl leading-snug font-bold text-[#173d32] sm:text-3xl"
        id="problem-title"
      >
        چه مسئله‌ای را می‌خواهید حل کنید؟
      </h1>
      <p className="mt-3 leading-7 text-[#647169]">
        یک محور نزدیک به موضوع خود انتخاب کنید و مسئله را با زبان خودتان توضیح دهید.
      </p>

      <fieldset className="mt-8">
        <legend className="text-base font-semibold text-[#244c39]">
          محور اجتماعی
        </legend>
        <p className="mt-2 text-sm text-[#718078]">
          نزدیک‌ترین گزینه را انتخاب کنید؛ این انتخاب در همین صفحه قابل تغییر است.
        </p>
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          {socialThemes.map((theme) => (
            <label
              className={`flex min-h-14 cursor-pointer items-center gap-3 rounded-lg border px-4 py-3 text-sm font-medium transition-colors ${
                draft.theme === theme
                  ? "border-[#17634a] bg-[#edf4ed] text-[#174a3a]"
                  : "border-[#e2e8e1] bg-white text-[#45594d] hover:border-[#b7cbb9]"
              }`}
              key={theme}
            >
              <input
                checked={draft.theme === theme}
                className="size-4 accent-[#17634a]"
                name="social-theme"
                onChange={() => onDraftChange("theme", theme)}
                type="radio"
                value={theme}
              />
              {theme}
            </label>
          ))}
        </div>
      </fieldset>

      <div className="mt-8">
        <TextQuestion
          hint="چه اتفاقی می‌افتد، کجا رخ می‌دهد و چرا برای شما اهمیت دارد؟"
          id="problem-description"
          label="توضیح مسئله"
          onChange={(value) => onDraftChange("problem", value)}
          placeholder="مسئله‌ای را که مشاهده کرده‌اید، با چند جمله شرح دهید..."
          value={draft.problem}
        />
      </div>

      <div className="mt-8 flex flex-col-reverse gap-3 border-t border-[#edf0eb] pt-6 sm:flex-row sm:items-center sm:justify-between">
        <p className="text-xs leading-5 text-[#78847c]" id="continue-hint">
          برای ادامه، انتخاب محور و توضیح مسئله لازم است.
        </p>
        <button
          className="inline-flex min-h-12 items-center justify-center rounded-lg bg-[#17634a] px-6 font-semibold text-white transition-colors hover:bg-[#104d39] disabled:cursor-not-allowed disabled:bg-[#aebbb1]"
          disabled={!canContinue}
          onClick={onContinue}
          type="button"
          aria-describedby="continue-hint"
        >
          ادامه
          <span aria-hidden="true" className="mr-2">
            ←
          </span>
        </button>
      </div>
    </section>
  );
}

function ImpactStep({
  draft,
  canFinish,
  onDraftChange,
  onBack,
  onContinue,
}: {
  draft: IdeaDraft;
  canFinish: boolean;
  onDraftChange: (field: keyof IdeaDraft, value: string) => void;
  onBack: () => void;
  onContinue: () => void;
}) {
  return (
    <section aria-labelledby="impact-title">
      <p className="text-sm font-bold text-[#a66a32]">مرحله دوم از سه</p>
      <h1
        className="mt-2 text-2xl leading-snug font-bold text-[#173d32] sm:text-3xl"
        id="impact-title"
      >
        چه کسانی و چرا تحت تأثیرند؟
      </h1>
      <p className="mt-3 leading-7 text-[#647169]">
        کمی دقیق‌تر به تجربه‌ی افراد درگیر و علت‌های احتمالی مسئله فکر کنید.
      </p>

      <div className="mt-8 space-y-8">
        <TextQuestion
          hint="به گروه‌هایی فکر کنید که این مسئله را تجربه می‌کنند یا از پیامدهای آن اثر می‌پذیرند."
          id="affected-people"
          label="چه افرادی از این مسئله تأثیر می‌پذیرند؟"
          onChange={(value) => onDraftChange("affectedPeople", value)}
          placeholder="برای مثال: چه کسانی، در چه شرایطی با این مسئله روبه‌رو هستند؟"
          value={draft.affectedPeople}
        />
        <TextQuestion
          hint="این‌ها فرضیه‌های اولیه‌اند و لازم نیست پاسخ قطعی داشته باشید."
          id="possible-causes"
          label="علت‌های احتمالی مسئله چیست؟"
          onChange={(value) => onDraftChange("possibleCauses", value)}
          placeholder="چه شرایطی ممکن است به شکل‌گیری یا ادامه‌ی مسئله کمک کند؟"
          value={draft.possibleCauses}
        />
      </div>

      <div className="mt-8 flex flex-col gap-3 border-t border-[#edf0eb] pt-6 sm:flex-row sm:items-center sm:justify-between">
        <button
          className="inline-flex min-h-12 items-center justify-center rounded-lg border border-[#cad8cc] bg-white px-5 font-semibold text-[#285942] transition-colors hover:bg-[#f7f9f6]"
          onClick={onBack}
          type="button"
        >
          <span aria-hidden="true" className="ml-2">
            →
          </span>
          بازگشت به تعریف مسئله
        </button>
        <button
          className="inline-flex min-h-12 items-center justify-center rounded-lg bg-[#17634a] px-6 font-semibold text-white transition-colors hover:bg-[#104d39] disabled:cursor-not-allowed disabled:bg-[#aebbb1]"
          disabled={!canFinish}
          onClick={onContinue}
          type="button"
          aria-describedby="finish-hint"
        >
          ادامه به پرورش ایده
          <span aria-hidden="true" className="mr-2">
            ←
          </span>
        </button>
      </div>
      <p className="mt-3 text-xs leading-5 text-[#78847c]" id="finish-hint">
        برای ادامه، هر دو پرسش این مرحله را تکمیل کنید.
      </p>
    </section>
  );
}

function IdeaDevelopmentStep({
  draft,
  canFinish,
  onDraftChange,
  onBack,
  onFinish,
}: {
  draft: IdeaDraft;
  canFinish: boolean;
  onDraftChange: (field: keyof IdeaDraft, value: string) => void;
  onBack: () => void;
  onFinish: () => void;
}) {
  return (
    <section aria-labelledby="idea-development-title">
      <p className="text-sm font-bold text-[#a66a32]">مرحله سوم از سه</p>
      <h1
        className="mt-2 text-2xl leading-snug font-bold text-[#173d32] sm:text-3xl"
        id="idea-development-title"
      >
        ایده‌ی خود را پرورش دهید
      </h1>
      <p className="mt-3 leading-7 text-[#647169]">
        فعلاً به یک راه‌حل اولیه فکر کنید؛ لازم نیست همه‌ی جزئیات از همین حالا مشخص باشند.
      </p>

      <div className="mt-8 space-y-8">
        <TextQuestion
          hint="چه کاری می‌تواند به کاهش یا حل مسئله کمک کند؟"
          id="proposed-solution"
          label="راه‌حل اولیه‌ی پیشنهادی"
          onChange={(value) => onDraftChange("proposedSolution", value)}
          placeholder="راه‌حل خود را در چند جمله توضیح دهید..."
          value={draft.proposedSolution}
        />
        <TextQuestion
          hint="مشخص کنید این راه‌حل برای چه کسانی طراحی شده است."
          id="beneficiary-group"
          label="گروه یا افراد بهره‌مند از راه‌حل"
          onChange={(value) => onDraftChange("beneficiaryGroup", value)}
          placeholder="چه افرادی یا گروه‌هایی از این راه‌حل بهره می‌برند؟"
          value={draft.beneficiaryGroup}
        />
        <TextQuestion
          hint="چه تغییری برای افراد یا جامعه انتظار دارید؟"
          id="expected-outcome"
          label="نتیجه‌ی مورد انتظار"
          onChange={(value) => onDraftChange("expectedOutcome", value)}
          placeholder="اگر راه‌حل اجرا شود، چه نتیجه‌ای امیدوارید ببینید؟"
          value={draft.expectedOutcome}
        />
        <TextQuestion
          hint="به منابع، همکاری‌ها یا شرایطی فکر کنید که ممکن است اجرای ایده را دشوار کند."
          id="implementation-barriers"
          label="موانع احتمالی اجرا"
          onChange={(value) => onDraftChange("implementationBarriers", value)}
          placeholder="چه چیزهایی ممکن است اجرای این راه‌حل را دشوار کند؟"
          value={draft.implementationBarriers}
        />
      </div>

      <div className="mt-8 flex flex-col gap-3 border-t border-[#edf0eb] pt-6 sm:flex-row sm:items-center sm:justify-between">
        <button
          className="inline-flex min-h-12 items-center justify-center rounded-lg border border-[#cad8cc] bg-white px-5 font-semibold text-[#285942] transition-colors hover:bg-[#f7f9f6]"
          onClick={onBack}
          type="button"
        >
          <span aria-hidden="true" className="ml-2">
            →
          </span>
          بازگشت به مرحله قبل
        </button>
        <button
          className="inline-flex min-h-12 items-center justify-center rounded-lg bg-[#17634a] px-6 font-semibold text-white transition-colors hover:bg-[#104d39] disabled:cursor-not-allowed disabled:bg-[#aebbb1]"
          disabled={!canFinish}
          onClick={onFinish}
          type="button"
          aria-describedby="complete-hint"
        >
          نمایش خلاصه‌ی ایده
        </button>
      </div>
      <p className="mt-3 text-xs leading-5 text-[#78847c]" id="complete-hint">
        برای نمایش خلاصه، هر چهار بخش این مرحله را تکمیل کنید.
      </p>
    </section>
  );
}

function CompletionSummary({
  draft,
  onEditStep,
  onRestart,
}: {
  draft: IdeaDraft;
  onEditStep: (step: Step) => void;
  onRestart: () => void;
}) {
  const summaryItems = [
    { label: "محور اجتماعی", value: draft.theme },
    { label: "مسئله", value: draft.problem },
    { label: "افراد تأثیرپذیرفته", value: draft.affectedPeople },
    { label: "علت‌های احتمالی", value: draft.possibleCauses },
    { label: "راه‌حل اولیه‌ی پیشنهادی", value: draft.proposedSolution },
    { label: "گروه یا افراد بهره‌مند", value: draft.beneficiaryGroup },
    { label: "نتیجه‌ی مورد انتظار", value: draft.expectedOutcome },
    { label: "موانع احتمالی اجرا", value: draft.implementationBarriers },
  ];

  return (
    <section aria-labelledby="complete-title">
      <p className="text-sm font-bold text-[#a66a32]">پایان نسخه‌ی آزمایشی</p>
      <h1
        className="mt-2 text-2xl leading-snug font-bold text-[#173d32] sm:text-3xl"
        id="complete-title"
      >
        خلاصه‌ی ایده‌ی شما
      </h1>
      <p className="mt-3 leading-7 text-[#647169]">
        این جمع‌بندی فقط بر اساس پاسخ‌های شما ساخته شده است. اطلاعات به جایی ارسال
        یا به‌صورت دائمی ذخیره نشده‌اند.
      </p>

      <dl className="mt-8 grid gap-4 sm:grid-cols-2">
        {summaryItems.map((item) => (
          <div
            className="min-w-0 rounded-lg border border-[#e5eae4] bg-[#fbfcfa] p-5"
            key={item.label}
          >
            <dt className="text-sm font-semibold text-[#32634d]">{item.label}</dt>
            <dd className="mt-2 whitespace-pre-wrap break-words leading-7 text-[#2f4739]">
              {item.value}
            </dd>
          </div>
        ))}
      </dl>

      <div className="mt-8 flex flex-col gap-3 border-t border-[#edf0eb] pt-6 sm:flex-row">
        <button
          className="inline-flex min-h-12 items-center justify-center rounded-lg bg-[#17634a] px-6 font-semibold text-white transition-colors hover:bg-[#104d39]"
          onClick={() => onEditStep(1)}
          type="button"
        >
          ویرایش مسئله
        </button>
        <button
          className="inline-flex min-h-12 items-center justify-center rounded-lg border border-[#cad8cc] bg-white px-6 font-semibold text-[#285942] transition-colors hover:bg-[#f7f9f6]"
          onClick={() => onEditStep(2)}
          type="button"
        >
          ویرایش افراد و علت‌ها
        </button>
        <button
          className="inline-flex min-h-12 items-center justify-center rounded-lg border border-[#cad8cc] bg-white px-6 font-semibold text-[#285942] transition-colors hover:bg-[#f7f9f6]"
          onClick={() => onEditStep(3)}
          type="button"
        >
          ویرایش پرورش ایده
        </button>
        <button
          className="inline-flex min-h-12 items-center justify-center rounded-lg border border-[#cad8cc] bg-white px-6 font-semibold text-[#285942] transition-colors hover:bg-[#f7f9f6]"
          onClick={onRestart}
          type="button"
        >
          شروع دوباره
        </button>
      </div>
    </section>
  );
}

export default function IdeaWizard() {
  const [draft, setDraft] = useState<IdeaDraft>(emptyDraft);
  const [activeStep, setActiveStep] = useState<Step>(1);
  const [isComplete, setIsComplete] = useState(false);

  const canContinue = draft.theme.trim().length > 0 && draft.problem.trim().length > 0;
  const canAdvanceToStep3 =
    draft.affectedPeople.trim().length > 0 &&
    draft.possibleCauses.trim().length > 0;
  const canFinish =
    canAdvanceToStep3 &&
    draft.proposedSolution.trim().length > 0 &&
    draft.beneficiaryGroup.trim().length > 0 &&
    draft.expectedOutcome.trim().length > 0 &&
    draft.implementationBarriers.trim().length > 0;

  function updateDraft(field: keyof IdeaDraft, value: string) {
    setDraft((currentDraft) => ({ ...currentDraft, [field]: value }));
  }

  function restart() {
    setDraft(emptyDraft);
    setActiveStep(1);
    setIsComplete(false);
  }

  function navigateToStep(step: Step) {
    setActiveStep(step);
    setIsComplete(false);
  }

  return (
    <div className="min-h-screen bg-[#f6f8f4]" dir="rtl">
      <WizardHeader />
      <main className="mx-auto max-w-5xl px-5 py-8 sm:px-8 sm:py-12">
        <div className="mx-auto max-w-3xl">
          <div className="mb-7 flex flex-col gap-2 sm:mb-8 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p className="text-sm font-semibold text-[#32634d]">
                فضای امن برای فکر کردن و شروع کردن
              </p>
              <h2 className="mt-2 text-xl font-bold text-[#173d32] sm:text-2xl">
                پرورش یک ایده‌ی اجتماعی
              </h2>
            </div>
            <p className="text-xs text-[#77837b]">
              نسخه‌ی آزمایشی · اطلاعات فقط در حافظه‌ی همین صفحه
            </p>
          </div>

          <div className="mb-6">
            <StepProgress
              activeStep={activeStep}
              canAdvanceToStep3={canContinue && canAdvanceToStep3}
              canContinue={canContinue}
              onStepChange={navigateToStep}
            />
          </div>

          <div className="rounded-xl border border-[#e3e9e1] bg-white p-5 shadow-[0_16px_45px_-38px_rgba(24,58,43,0.35)] sm:p-8 md:p-10">
            {isComplete ? (
              <CompletionSummary
                draft={draft}
                onEditStep={navigateToStep}
                onRestart={restart}
              />
            ) : activeStep === 1 ? (
              <ProblemStep
                canContinue={canContinue}
                draft={draft}
                onContinue={() => setActiveStep(2)}
                onDraftChange={updateDraft}
              />
            ) : activeStep === 2 ? (
              <ImpactStep
                canFinish={canAdvanceToStep3}
                draft={draft}
                onBack={() => setActiveStep(1)}
                onDraftChange={updateDraft}
                onContinue={() => setActiveStep(3)}
              />
            ) : (
              <IdeaDevelopmentStep
                canFinish={canFinish}
                draft={draft}
                onBack={() => setActiveStep(2)}
                onDraftChange={updateDraft}
                onFinish={() => setIsComplete(true)}
              />
            )}
          </div>

          {!isComplete && (
            <p className="mt-5 text-center text-xs leading-6 text-[#77837b]">
              در این نسخه، با بستن یا تازه‌سازی صفحه، پاسخ‌ها پاک می‌شوند.
            </p>
          )}
        </div>
      </main>
    </div>
  );
}
