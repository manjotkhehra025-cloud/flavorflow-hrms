"use client";
import { Tt } from "@/components/LangCtx";

import { useEffect, useRef, useState } from "react";
import { checkInGeoAction, checkOutGeoAction } from "@/actions/attendance";
import { Icon } from "@/components/icons";

const btnCls = "flex w-full items-center justify-center gap-3 rounded-2xl bg-gradient-to-r from-emerald-500 to-emerald-600 py-4 text-base font-bold text-white shadow-[0_10px_30px_-6px_rgb(16_185_129_/_60%)] transition hover:from-emerald-400 hover:to-emerald-500 active:scale-[0.98] disabled:opacity-60";

type Mode = "in" | "out";

type Geo = { lat: number; lng: number; radius: number };

/**
 * Fixes coarser than this are meaningless for a factory fence (a ±1.5 km
 * Wi-Fi/IP fix at the gate reads "1.36 km away" and wrongly kills the
 * button). Such fixes are ignored — the UI asks for open sky instead.
 */
const MAX_GPS_ACC = 150; // metres

export function PunchWithSelfie({ mode, selfieRequired, geofence }: { mode: Mode; selfieRequired: boolean; geofence?: Geo | null }) {
  const [stage, setStage] = useState<"idle" | "locating" | "camera" | "working" | "error">("idle");
  const [coords, setCoords] = useState<{ lat: number; lng: number; dist: number; acc: number } | null>(null);
  const [geoBlocked, setGeoBlocked] = useState<boolean>(false); // outside fence → button dead
  const [geoWeak, setGeoWeak] = useState<boolean>(false); // fix too coarse to judge → ask for open sky
  const [geoInfo, setGeoInfo] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);

  useEffect(() => () => stopCamera(), []);

  // Live geo-watch: while a fence exists, continuously measure distance and
  // hard-disable the button when the device is outside the allowed radius.
  useEffect(() => {
    if (!geofence || !navigator.geolocation) return;
    const R = 6371000, r = (d: number) => (d * Math.PI) / 180;
    const watchId = navigator.geolocation.watchPosition(
      (pos) => {
        const acc = pos.coords.accuracy;
        if (acc == null || acc > MAX_GPS_ACC) {
          setCoords(null);
          setGeoBlocked(false);
          setGeoWeak(true);
          setGeoInfo(`\u00b1${Math.round(acc ?? 0)}m`);
          return;
        }
        setGeoWeak(false);
        const a =
          Math.sin(r(pos.coords.latitude - geofence.lat) / 2) ** 2 +
          Math.cos(r(geofence.lat)) * Math.cos(r(pos.coords.latitude)) * Math.sin(r(pos.coords.longitude - geofence.lng) / 2) ** 2;
        const dist = 2 * R * Math.asin(Math.sqrt(a));
        setCoords({ lat: pos.coords.latitude, lng: pos.coords.longitude, dist, acc });
        if (dist > geofence.radius) {
          setGeoBlocked(true);
          setGeoInfo((dist / 1000).toFixed(2) + " km");
        } else {
          setGeoBlocked(false);
          setGeoInfo(Math.round(dist) + " m");
        }
      },
      () => { /* silent — one-shot locate() handles errors on tap */ },
      { enableHighAccuracy: true, maximumAge: 2000 },
    );
    return () => navigator.geolocation.clearWatch(watchId);
  }, [geofence]);

  function stopCamera() {
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
  }

  function locate() {
    setErr(null); setStage("locating");
    if (coords && coords.dist <= geofence!.radius) {
      const c = coords;
      if (selfieRequired) { setStage("idle"); startCamera(); } else { punch(mode, c); }
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const acc = pos.coords.accuracy;
        if (acc == null || acc > MAX_GPS_ACC) {
          setCoords(null);
          setErr(`GPS too weak (\u00b1${Math.round(acc ?? 0)}m) \u2014 stand in the open and retry.`);
          setStage("error");
          return;
        }
        const R = 6371000, r = (d: number) => (d * Math.PI) / 180;
        const a = Math.sin(r(pos.coords.latitude - geofence!.lat) / 2) ** 2 + Math.cos(r(geofence!.lat)) * Math.cos(r(pos.coords.latitude)) * Math.sin(r(pos.coords.longitude - geofence!.lng) / 2) ** 2;
        const dist = 2 * R * Math.asin(Math.sqrt(a));
        if (dist > geofence!.radius) {
          setCoords(null);
          setErr(`You are ${(dist / 1000).toFixed(2)} km from factory — punch is allowed only from factory premises (${geofence!.radius}m radius).`);
          setStage("error");
          return;
        }
        const c = { lat: pos.coords.latitude, lng: pos.coords.longitude, dist, acc: pos.coords.accuracy };
        if (selfieRequired) { setStage("idle"); startCamera(); } else { punch(mode, c); }
      },
      () => { setErr("Location blocked — allow GPS access and retry."); setStage("error"); },
      { enableHighAccuracy: true, timeout: 15000 },
    );
  }

  async function start() {
    if (geoBlocked) return; // hard block — touch does nothing outside the fence
    if (geofence) {
      if (!coords) { locate(); return; }
      if (coords.dist > geofence.radius) { setGeoBlocked(true); return; }
      if (selfieRequired) { setErr(null); startCamera(); } else { punch(mode, coords); }
      return;
    }
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

  async function punch(m: Mode, inp: { lat: number; lng: number; dist: number; acc?: number } | string | null) {
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
        <>
        <button
          type="button"
          onClick={start}
          disabled={stage === "working" || stage === "locating" || geoBlocked}
          className={geoBlocked ? btnCls.replace(/bg-[^ ]+/g, "") + " cursor-not-allowed bg-slate-300 text-slate-500" : btnCls}
          aria-disabled={geoBlocked}
        >
          <Icon name="fingerprint" className="h-6 w-6" /> {stage === "working" ? "…" : stage === "locating" ? <Tt>Locating…</Tt> : mode === "in" ? <Tt>Punch In</Tt> : <Tt>Punch Out</Tt>}
        </button>
        {geofence && (
          <p className={`mt-2 text-center text-[11px] font-bold ${geoBlocked ? "text-red-300" : geoWeak ? "text-amber-300" : geoInfo ? "text-emerald-300" : "text-slate-400"}`}>
            {geoBlocked
              ? <Tt>{`Outside factory — come within ${geofence.radius} m of the gate to punch (${geoInfo} away)`}</Tt>
              : geoWeak
                ? <Tt>{`Weak GPS (${geoInfo}) — stand in the open for a better fix…`}</Tt>
                : geoInfo
                ? <Tt>{`Inside factory zone · ${geoInfo} from gate ✔`}</Tt>
                : <Tt>Checking your location…</Tt>}
          </p>
        )}
        </>
      )}
      {stage === "error" && err && <p className="mt-2 text-center text-[11px] text-amber-300">{err}</p>}
    </div>
  );
}
