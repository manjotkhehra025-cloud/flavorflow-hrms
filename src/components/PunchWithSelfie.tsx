"use client";
import { Tt } from "@/components/LangCtx";

import { useEffect, useRef, useState } from "react";
import { checkInAction, checkOutAction } from "@/actions/attendance";
import { Icon } from "@/components/icons";

const btnCls = "flex w-full items-center justify-center gap-3 rounded-2xl bg-gradient-to-r from-emerald-500 to-emerald-600 py-4 text-base font-bold text-white shadow-[0_10px_30px_-6px_rgb(16_185_129_/_60%)] transition hover:from-emerald-400 hover:to-emerald-500 active:scale-[0.98] disabled:opacity-60";

type Mode = "in" | "out";

export function PunchWithSelfie({ mode, selfieRequired }: { mode: Mode; selfieRequired: boolean }) {
  const [stage, setStage] = useState<"idle" | "camera" | "working" | "error">("idle");
  const [err, setErr] = useState<string | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);

  useEffect(() => () => stopCamera(), []);

  function stopCamera() {
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
  }

  async function start() {
    if (!selfieRequired) { punch(mode, null); return; }
    setErr(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "user", width: { ideal: 480 } }, audio: false });
      streamRef.current = stream;
      setStage("camera");
      requestAnimationFrame(() => { if (videoRef.current) { videoRef.current.srcObject = stream; videoRef.current.play().catch(() => {}); } });
    } catch (e) {
      setErr("Camera blocked — allow camera access and retry.");
      setStage("error");
    }
  }

  async function capture() {
    const v = videoRef.current;
    if (!v || !v.videoWidth) { setErr("Camera not ready — wait a sec."); return; }
    const c = document.createElement("canvas");
    c.width = Math.min(480, v.videoWidth);
    c.height = Math.round((v.videoHeight / v.videoWidth) * c.width);
    c.getContext("2d")!.drawImage(v, 0, 0, c.width, c.height);
    const dataUrl = c.toDataURL("image/jpeg", 0.65);
    stopCamera();
    setStage("working");
    const up = await fetch("/api/attendance/selfie", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ dataUrl }) });
    if (!up.ok) { setErr("Selfie save failed — retry."); setStage("camera"); return; }
    const { path } = await up.json();
    punch(mode, path);
  }

  async function punch(m: Mode, path: string | null) {
    setStage("working");
    if (m === "in") await checkInAction(path ?? undefined);
    else await checkOutAction(path ?? undefined);
    location.reload();
  }

  return (
    <div className="mx-auto mt-6 max-w-xs">
      {stage === "camera" ? (
        <div className="overflow-hidden rounded-2xl bg-[#0a1628] p-3 ring-1 ring-white/10">
          <video ref={videoRef} playsInline muted className="w-full rounded-xl" />
          <button type="button" onClick={capture} className={btnCls + " mt-3"}>
            <Icon name="fingerprint" className="h-6 w-6" /> <Tt>Capture & Punch</Tt> {mode === "in" ? <Tt>In</Tt> : <Tt>Out</Tt>}
          </button>
          <button type="button" onClick={() => { stopCamera(); setStage("idle"); }} className="mt-2 w-full text-center text-[11px] font-semibold text-slate-400">
            <Tt>Cancel</Tt>
          </button>
          {err && <p className="mt-2 text-center text-[11px] text-amber-300">{err}</p>}
        </div>
      ) : (
        <button type="button" onClick={start} disabled={stage === "working"} className={btnCls}>
          <Icon name="fingerprint" className="h-6 w-6" /> {stage === "working" ? "…" : mode === "in" ? <Tt>Punch In</Tt> : <Tt>Punch Out</Tt>}
          {selfieRequired && stage === "idle" && <span className="text-xs opacity-80">📸</span>}
        </button>
      )}
      {stage === "error" && err && <p className="mt-2 text-center text-[11px] text-amber-300">{err}</p>}
    </div>
  );
}
