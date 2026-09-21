"use client";

import { Icon } from "@/components/icons";

export function PrintButton() {
  return (
    <button onClick={() => window.print()} className="btn-ghost !text-xs">
      <Icon name="printer" className="h-4 w-4" /> Print / Save PDF
    </button>
  );
}
