import type { Metadata } from "next";
import IdeaWizard from "./idea-wizard";

export const metadata: Metadata = {
  title: "شروع ایده‌یابی | جوانه",
  description:
    "مسئله‌ای اجتماعی را انتخاب کنید و با چند پرسش، ایده‌ی خود را در جوانه پرورش دهید.",
};

export default function NewIdeaPage() {
  return <IdeaWizard />;
}
