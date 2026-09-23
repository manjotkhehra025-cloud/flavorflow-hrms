"use client";

/** Segment error boundary — a page-level crash shows a friendly retry instead of the generic white error. */
export default function AppSegmentError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div className="mx-auto flex max-w-md flex-col items-center justify-center px-6 py-24 text-center">
      <div className="flex h-16 w-16 items-center justify-center rounded-3xl bg-slate-100 text-3xl">🤕</div>
      <h2 className="mt-4 text-lg font-extrabold text-slate-800">Oye! Something tripped here.</h2>
      <p className="mt-1.5 text-sm text-slate-500">
        Bas ik retry te sahi ho jaanda — pehla &quot;Try again&quot; dabao. Je fer vi same error aawe, page nu hard-refresh karo
        (tab band karke /settings fer kholho).
      </p>
      {error.digest && (
        <p className="mt-2 text-[11px] font-mono text-slate-400">Error ID: {error.digest}</p>
      )}
      <div className="mt-5 flex gap-2">
        <button
          onClick={reset}
          className="rounded-xl bg-[#0a1628] px-5 py-2.5 text-sm font-extrabold text-emerald-300 shadow transition hover:brightness-110 active:scale-95"
        >
          🔁 Try again
        </button>
        <a
          href="/dashboard"
          className="rounded-xl bg-slate-100 px-5 py-2.5 text-sm font-bold text-slate-600 transition hover:bg-slate-200 active:scale-95"
        >
          🏠 Home
        </a>
      </div>
    </div>
  );
}
