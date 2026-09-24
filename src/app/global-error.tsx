"use client";
import { useEffect } from "react";
import { Tt } from "@/components/LangCtx";
import { LangProvider } from "@/components/LangCtx";

/** Root-level crash (e.g. stale JS chunk right after a deploy) — branded retry instead of the white Next.js error. */
export default function GlobalError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  // Chunk-load / RSC-mismatch errors are always cured by a full reload.
  useEffect(() => {
    if (/ChunkLoadError|Loading chunk|Hydration|dynamic rendering/i.test(String(error?.message || ""))) {
      const last = Number(sessionStorage.getItem("ff_autoreload") || 0);
      if (Date.now() - last > 15000) {
        sessionStorage.setItem("ff_autoreload", String(Date.now()));
        window.location.reload();
      }
    }
  }, [error]);

  return (
    <html lang="en">
      <body style={{ margin: 0, fontFamily: "system-ui, sans-serif", background: "#f8fafc" }}>
        <LangProvider lang="en">
          <div style={{ minHeight: "100dvh", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", padding: 24, textAlign: "center" }}>
            <div style={{ width: 40, height: 40, borderRadius: 12, background: "#0a1628", display: "flex", alignItems: "center", justifyContent: "center", color: "#34d399", fontWeight: 900, fontSize: 18 }}>H</div>
            <h2 style={{ marginTop: 16, fontSize: 17, fontWeight: 800, color: "#0f172a" }}>
              <Tt>App was just updated — one reload fixes it.</Tt>
            </h2>
            <p style={{ marginTop: 6, fontSize: 13, color: "#64748b", maxWidth: 320 }}>
              <Tt>A new version shipped while this page was open. Tap below once and everything works again.</Tt>
            </p>
            {error.digest && <p style={{ marginTop: 4, fontSize: 10, fontFamily: "monospace", color: "#94a3b8" }}>Error ID: {error.digest}</p>}
            <div style={{ marginTop: 18, display: "flex", gap: 8 }}>
              <button
                onClick={() => window.location.reload()}
                style={{ borderRadius: 12, background: "#0a1628", padding: "10px 22px", fontSize: 13, fontWeight: 800, color: "#34d399", border: "none" }}
              >
                <Tt>Reload now</Tt>
              </button>
              <button
                onClick={reset}
                style={{ borderRadius: 12, background: "#e2e8f0", padding: "10px 18px", fontSize: 13, fontWeight: 700, color: "#475569", border: "none" }}
              >
                <Tt>Retry view</Tt>
              </button>
            </div>
          </div>
        </LangProvider>
      </body>
    </html>
  );
}
