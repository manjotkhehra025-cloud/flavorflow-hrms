"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { useLang } from "./LangCtx";
import { setLanguageAction } from "@/actions/lang";

/** 🌐 language pill — tap to flip English ⇄ Punjabi. Must sit inside LangProvider. */
export function LangToggle({ dark = false, className = "" }: { dark?: boolean; className?: string }) {
  const lang = useLang();
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  return (
    <button
      type="button"
      disabled={pending}
      onClick={() =>
        startTransition(async () => {
          await setLanguageAction(lang === "en" ? "pa" : "en");
          router.refresh();
        })
      }
      className={`inline-flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1.5 text-[11px] font-bold transition-all active:scale-95 disabled:opacity-50 ${
        dark
          ? "bg-white/10 text-white ring-1 ring-white/25 hover:bg-white/20"
          : "bg-emerald-50 text-emerald-700 ring-1 ring-emerald-200 hover:bg-emerald-100"
      } ${className}`}
    >
      <span aria-hidden>🌐</span>
      {pending ? "…" : lang === "en" ? "ਪੰਜਾਬੀ" : "English"}
    </button>
  );
}
