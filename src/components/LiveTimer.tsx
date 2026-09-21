"use client";

import { useEffect, useState } from "react";

function pad(n: number) {
  return String(n).padStart(2, "0");
}

/** Live ticking elapsed-time ring: progress = elapsed / shift hours. */
export function LiveTimer({ checkInIso, shiftHours }: { checkInIso: string; shiftHours: number }) {
  const [now, setNow] = useState<number>(Date.now());

  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  const start = new Date(checkInIso).getTime();
  const elapsed = Math.max(0, now - start);
  const h = Math.floor(elapsed / 3600000);
  const m = Math.floor((elapsed % 3600000) / 60000);
  const s = Math.floor((elapsed % 60000) / 1000);
  const progress = Math.min(elapsed / (shiftHours * 3600000), 1);

  const r = 60;
  const circ = 2 * Math.PI * r;

  return (
    <div className="relative mx-auto h-40 w-40">
      <svg viewBox="0 0 140 140" className="h-full w-full -rotate-90">
        <circle cx="70" cy="70" r={r} fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth="9" />
        <circle
          cx="70"
          cy="70"
          r={r}
          fill="none"
          stroke="url(#ringGrad)"
          strokeWidth="9"
          strokeLinecap="round"
          strokeDasharray={circ}
          strokeDashoffset={circ * (1 - progress)}
          style={{ filter: "drop-shadow(0 0 8px rgb(16 185 129 / 0.6))", transition: "stroke-dashoffset 1s linear" }}
        />
        <defs>
          <linearGradient id="ringGrad" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="#34d399" />
            <stop offset="100%" stopColor="#059669" />
          </linearGradient>
        </defs>
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <div className="text-[11px] font-semibold text-emerald-300/80">
          {pad(Math.floor(h))}h {pad(m)}m / {pad(Math.floor(shiftHours))}h {pad(Math.round((shiftHours % 1) * 60))}m
        </div>
        <div className="text-3xl font-black tabular-nums tracking-tight text-white">
          {pad(h)}:{pad(m)}:{pad(s)}
        </div>
      </div>
    </div>
  );
}
