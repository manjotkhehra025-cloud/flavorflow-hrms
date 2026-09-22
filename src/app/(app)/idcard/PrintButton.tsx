"use client";
import { Tt } from "@/components/LangCtx";

import { Icon } from "@/components/icons";

export function PrintButton() {
  return (
    <button onClick={() => window.print()} className="btn-ghost !text-xs">
      <Icon name="printer" className="h-4 w-4" /> <Tt>Print / Save PDF</Tt>
    </button>
  );
}
