"use client";

import { createContext, useContext } from "react";
import { PA } from "@/lib/i18n-pa";

export type Lang = "en" | "pa";

const LangContext = createContext<Lang>("en");

export function LangProvider({ lang, children }: { lang: Lang; children: React.ReactNode }) {
  return <LangContext.Provider value={lang}>{children}</LangContext.Provider>;
}

export function useLang(): Lang {
  return useContext(LangContext);
}

/** Client-component inline translation: <Tt>English text</Tt> */
export function Tt({ children }: { children: string }) {
  const lang = useContext(LangContext);
  return <>{lang === "pa" ? PA[children] ?? children : children}</>;
}

/** Hook for client components that need imperative translation (toasts, banners, attributes). */
export function useT() {
  const lang = useContext(LangContext);
  return (en: string) => (lang === "pa" ? PA[en] ?? en : en);
}
