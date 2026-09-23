"use client";
import { Tt } from "@/components/LangCtx";

import { useEffect, useRef, useState } from "react";
import { checkInGeoAction, checkOutGeoAction } from "@/actions/attendance";
import { Icon } from "@/components/icons";

const btnCls = "flex w-full items-center justify-center gap-3 rounded-2xl bg-gradient-to-r from-emerald-500 to-emerald-600 py-4 text-base font-bold text-white shadow-[0_10px_30px_-6px_rgb(16_185_129_/_60%)] transition hover:from-emerald-400 hover:to-emerald-500 active:scale-[0.98] disabled:opacity-60";

type Mode = "in" | "out";

type Geo = { lat: number; lng: number; radius: number };

export function PunchWithSelfie({ mode, selfieRequired, geofence }: { mode: Mode; selfieRequired: boolean; geofence?: Geo | null }) {
  const [stage, setStage] = useState<"idle" | "locating" | "camera" | "working" | "error">("idle");
  const [coords, setCoords] = useState<{ lat: number; lng: number; dist: number } | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);

  useEffect(() => () => stopCamera(), []);

  function stopCamera() {
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
  }

  function locate() {
    setErr(null); setStage("locating");
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const R = 6371000, r = (d: number) => (d * Math.PI) / 180;
        const a = Math.sin(r(pos.coords.latitude - geofence!.lat) / 2) ** 2 + Math.cos(r(geofence!.lat)) * Math.cos(r(pos.coords.latitude)) * Math.sin(r(pos.coords.longitude - geofence!.lng) / 2) ** 2;
        const dist = 2 * R * Math.asin(Math.sqrt(a));
        if (dist > geofence!.radius) {
          setCoords(null);
          setErr(`You are ${(dist / 1000).toFixed(2)} km from factory — punch is allowed only from factory premises (${geofence!.radius}m radius).`);
          setStage("error");
          return;
        }
        const c = { lat: pos.coords.latitude, lng: pos.coords.longitude, dist };
        if (selfieRequired) { setStage("idle"); startCamera(); } else { punch(mode, c); }
      },
      () => { setErr("Location blocked — allow GPS access and retry."); setStage("error"); },
      { enableHighAccuracy: true, timeout: 15000 },
    );
  }

  async function start() {
    if (geofence && !coords) { locate(); return; }
    if (!selfieRequired) { punch(mode, null); return; }
    setErr(null);
    startCamera();
  }

  async function startCamera() {
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
    await punch(mode, coords ? { ...coords, selfiePath: path } : path);
  }

  async function punch(m: Mode, inp: { lat: number; lng: number; dist: number } | string | null) {
    setStage("working");
    const args = typeof inp === "string" ? { selfiePath: inp } : (inp ?? {});
    const res = await (m === "in" ? checkInGeoAction(args) : checkOutGeoAction(args));
    if (res?.error) { setErr(String(res.error)); setStage("error"); return; }
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
        <button type="button" onClick={start} disabled={stage === "working" || stage === "locating"} className={btnCls}>
          <Icon name="fingerprint" className="h-6 w-6" /> {stage === "working" ? "…" : stage === "locating" ? <Tt>📡 Locating…</Tt> : mode === "in" ? <Tt>Punch In</Tt> : <Tt>Punch Out</Tt>}
          {selfieRequired && stage === "idle" && <span className="text-xs opacity-80">📸</span>}
          {geofence && stage === "idle" && <span className="text-xs opacity-80">📍</span>}
        </button>
      )}
      {stage === "error" && err && <p className="mt-2 text-center text-[11px] text-amber-300">{err}</p>}
    </div>
  );
}
