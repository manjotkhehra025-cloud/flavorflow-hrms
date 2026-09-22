import { getRequestLang, t } from "@/lib/i18n";

/** Server-component inline translation: <Pa>English text</Pa> → Punjabi when the viewer has it enabled. */
export async function Pa({ children }: { children: string }) {
  const lang = await getRequestLang();
  return <>{t(lang, children)}</>;
}
