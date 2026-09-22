import { cache } from "react";
import { db } from "./db";
import { getSessionUser } from "./auth";
import { PA } from "./i18n-pa";

export type Lang = "en" | "pa";

export function t(lang: Lang, en: string): string {
  if (lang !== "pa") return en;
  return PA[en] ?? en;
}

/** Server-only: translate a literal for attributes (placeholder/title) inside an RSC. */
export async function pht(en: string): Promise<string> {
  return t(await getRequestLang(), en);
}

/** Server-only: translate an action banner (error/success) for the requesting user. */
export async function bt(en: string): Promise<string> {
  return t(await getRequestLang(), en);
}

/** Template-style: "{} in {}", t(l, "……{}……", a, b) — replaces {} slots left-to-right. */
export function tt(lang: Lang, en: string, ...vals: (string | number)[]): string {
  const text = t(lang, en);
  let i = 0;
  return text.replace(/\{\}/g, () => String(vals[i++] ?? ""));
}

/**
 * Current request's UI language — React `cache` dedupes this to at most one
 * DB roundtrip per server render, no matter how many <Pa> nodes call it.
 */
export const getRequestLang = cache(async (): Promise<Lang> => {
  try {
    const me = await getSessionUser();
    if (!me) return "en";
    const u = await db.user.findUnique({ where: { id: me.id }, select: { locale: true } });
    return u?.locale === "pa" ? "pa" : "en";
  } catch {
    return "en";
  }
});
