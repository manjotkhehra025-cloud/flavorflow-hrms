"use client";

import { Icon } from "@/components/icons";

export function PrintButton({ label = "Print / Save PDF" }: { label?: string }) {
  return (
    <button onClick={() => window.print()} className="btn-dark !text-xs print:hidden">
      <Icon name="printer" className="h-4 w-4" /> {label}
    </button>
  );
}
