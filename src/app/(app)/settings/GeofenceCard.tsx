"use client";
import { Tt } from "@/components/LangCtx";

import { useActionState, useState } from "react";
import { saveGeofenceAction } from "@/actions/config";
import type { ActionState } from "@/actions/auth";
import { Card } from "@/components/ui";

export function GeofenceCard({ initial }: { initial: { enabled: boolean; lat: number | null; lng: number | null; radius: number } }) {
  const [eda, formAction, pending] = useActionState<ActionState, FormData>(saveGeofenceAction, {});
  const [enabled, setEnabled] = useState(initial.enabled);
  const [lat, setLat] = useState(initial.lat?.toFixed(6) ?? "");
  const [lng, setLng] = useState(initial.lng?.toFixed(6) ?? "");
  const [locating, setLocating] = useState(false);
  const [note, setNote] = useState<string | null>(null);

  function useMyLocation() {
    setLocating(true); setNote(null);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLat(pos.coords.latitude.toFixed(6));
        setLng(pos.coords.longitude.toFixed(6));
        setNote(`✓ ±${Math.round(pos.coords.accuracy)}m`);
        setLocating(false);
      },
      () => { setNote("Location blocked — allow GPS and retry."); setLocating(false); },
      { enableHighAccuracy: true, timeout: 12000 },
    );
  }

  return (
    <Card className="mb-6 p-5 border-l-4 border-l-sky-500">
      <div className="mb-3 flex items-start justify-between gap-3">
        <div>
          <h3 className="text-sm font-bold text-slate-900"><Tt>Factory geofence 📍</Tt></h3>
          <p className="mt-0.5 text-[11px] text-slate-500"><Tt>Punch sirf factory ke andar — GPS check every punch.</Tt></p>
        </div>
        <label className="flex items-center gap-2 text-xs font-bold text-slate-700">
          <input type="checkbox" name="geofenceEnabled" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />
          <Tt>ON</Tt>
        </label>
      </div>
      <form action={formAction} className="flex flex-wrap items-end gap-2.5">
        <input type="hidden" name="geofenceEnabled" value={enabled ? "on" : "off"} readOnly={false} />
        <label>
          <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Tt>Latitude</Tt></span>
          <input name="geoLat" value={lat} onChange={(e) => setLat(e.target.value)} placeholder="30.346912" className="input w-32 font-mono text-xs" inputMode="decimal" />
        </label>
        <label>
          <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Tt>Longitude</Tt></span>
          <input name="geoLng" value={lng} onChange={(e) => setLng(e.target.value)} placeholder="76.372902" className="input w-32 font-mono text-xs" inputMode="decimal" />
        </label>
        <label>
          <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Tt>Radius (metres)</Tt></span>
          <input type="number" name="geoRadius" defaultValue={initial.radius} min={25} max={5000} className="input w-24" />
        </label>
        <button type="button" onClick={useMyLocation} className="btn-ghost" disabled={locating}>
          {locating ? "📡…" : "📍"} <Tt>Use my location (stand at factory gate)</Tt>
        </button>
        <button type="submit" className="btn-brand" disabled={pending}>{pending ? "…" : "💾"} <Tt>Save geofence</Tt></button>
        {note && <span className="text-[11px] text-emerald-700">{note}</span>}
        {eda?.error && <span className="w-full rounded-lg bg-red-50 px-3 py-2 text-xs text-red-600">{eda.error}</span>}
        {eda?.success && <span className="w-full rounded-lg bg-emerald-100 px-3 py-2 text-xs text-emerald-800">{eda.success}</span>}
      </form>
    </Card>
  );
}
