"use client";
import { Tt } from "@/components/LangCtx";

import { useEffect, useState } from "react";

function pad(n: number) {
  return String(n).padStart(2, "0");
}

/**
 * Live ring around the punch button.
 * While the shift runs      → big ticking elapsed-work timer (device clock, 1s sync).
 * Once the shift is complete → ring stays full and the centre flips to LIVE device time.
 */
export function LiveTimer({ checkInIso, shiftHours, checkedOut = false }: {
  checkInIso: string;
  shiftHours: number;
  checkedOut?: boolean;
}) {
  const [now, setNow] = useState<number | null>(null); // null until mounted → zero server/client mismatch

  useEffect(() => {
    setNow(Date.now());
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);
  // While SSR/before mount, hold a stable visual shell (no ticking text to mismatch).

  const start = new Date(checkInIso).getTime();
  const elapsed = now === null ? 0 : Math.max(0, now - start);
  const h = Math.floor(elapsed / 3600000);
  const m = Math.floor((elapsed % 3600000) / 60000);
  const s = Math.floor((elapsed % 60000) / 1000);
  const shiftDone = elapsed >= shiftHours * 3600000 || checkedOut;
  const progress = now === null ? 0 : (shiftDone ? 1 : Math.min(elapsed / (shiftHours * 3600000), 1));

  // Live device clock for post-shift display (12h, device timezone)
  const d = new Date(now ?? 0);
  let hour = d.getHours();
  const ampm = hour >= 12 ? "PM" : "AM";
  hour = hour % 12 || 12;
  const clock = `${pad(hour)}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;

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
          stroke={shiftDone ? "url(#ringDone)" : "url(#ringGrad)"}
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
          <linearGradient id="ringDone" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="#10b981" />
            <stop offset="100%" stopColor="#34d399" />
          </linearGradient>
        </defs>
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        {shiftDone ? (
          <>
            <div className="flex items-center gap-1 text-[11px] font-semibold text-emerald-300/90">
              <span className="relative flex h-1.5 w-1.5">
                <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-75" />
                <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-emerald-400" />
              </span>
              <Tt>Shift complete · Live time</Tt>
            </div>
            <div className="mt-0.5 text-2xl font-black tabular-nums tracking-tight text-white">
              {clock}
            </div>
            <div className="text-[10px] font-bold tracking-wider text-emerald-300/70">{ampm}</div>
          </>
        ) : (
          <>
            <div className="text-[11px] font-semibold text-emerald-300/80">
              {pad(Math.floor(h))}h {pad(m)}m / {pad(Math.floor(shiftHours))}h {pad(Math.round((shiftHours % 1) * 60))}m
            </div>
            <div className="text-3xl font-black tabular-nums tracking-tight text-white">
              {pad(h)}:{pad(m)}:{pad(s)}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
