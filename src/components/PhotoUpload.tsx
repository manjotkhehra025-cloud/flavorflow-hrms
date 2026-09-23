"use client";

import { useActionState, useRef, useState } from "react";
import { uploadEmployeePhotoAction, deleteEmployeePhotoAction } from "@/actions/photos";
import type { ActionState } from "@/actions/auth";
import { Icon } from "@/components/icons";

/** Phone photos come in at 2–6 MB — shrink to ≤1600px JPEG (~400–800 KB) before upload. */
async function compressImage(file: File): Promise<File> {
  try {
    const MAX_DIM = 1600;
    const bmp = await createImageBitmap(file);
    const scale = Math.min(1, MAX_DIM / Math.max(bmp.width, bmp.height));
    const w = Math.round(bmp.width * scale);
    const h = Math.round(bmp.height * scale);
    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d");
    if (!ctx) return file;
    ctx.drawImage(bmp, 0, 0, w, h);
    bmp.close();
    const blob = await new Promise<Blob | null>((res) => canvas.toBlob(res, "image/jpeg", 0.86));
    if (!blob || blob.size >= file.size) return file;
    return new File([blob], file.name.replace(/\.[^.]+$/, "") + ".jpg", { type: "image/jpeg" });
  } catch {
    return file; // compression optional — agar fail, original bhejo
  }
}

export function PhotoUpload({ employeeId, hasPhoto }: { employeeId: string; hasPhoto: boolean }) {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(uploadEmployeePhotoAction, {});
  const [delState, delAction, delPending] = useActionState<ActionState, FormData>(deleteEmployeePhotoAction, {});
  const inputRef = useRef<HTMLInputElement>(null);
  const [localMsg, setLocalMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  return (
    <div className="space-y-2">
      {state.error && <p className="rounded-lg bg-red-50 px-3 py-2 text-xs text-red-600">{state.error}</p>}
      {state.success && <p className="rounded-lg bg-emerald-50 px-3 py-2 text-xs text-emerald-700">{state.success}</p>}
      {delState.error && <p className="rounded-lg bg-red-50 px-3 py-2 text-xs text-red-600">{delState.error}</p>}
      {localMsg && <p className="rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-700">{localMsg}</p>}
      <form action={formAction} className="flex flex-wrap items-center gap-2">
        <input type="hidden" name="employeeId" value={employeeId} />
        <input
          ref={inputRef}
          type="file"
          name="photo"
          accept="image/jpeg,image/png,image/webp"
          className="hidden"
          onChange={async (e) => {
            const input = e.target;
            const f = input.files?.[0];
            if (!f) return;
            setBusy(true);
            setLocalMsg(f.size > 1024 * 1024 ? "Compressing photo…" : null);
            try {
              const small = await compressImage(f);
              if (small.size > 4 * 1024 * 1024) {
                setLocalMsg("Even after compressing this photo is over 4 MB — try another one 📦");
                input.value = "";
                return;
              }
              const dt = new DataTransfer();
              dt.items.add(small);
              input.files = dt.files;
              setLocalMsg(null);
              input.form?.requestSubmit();
            } finally {
              setBusy(false);
            }
          }}
        />
        <button
          type="button"
          disabled={pending || busy}
          onClick={() => inputRef.current?.click()}
          className="flex items-center gap-1.5 rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs font-semibold text-slate-700 hover:bg-slate-50 active:scale-95 disabled:opacity-50"
        >
          <Icon name="badge" className="h-4 w-4" />
          {busy ? "Compressing…" : pending ? "Uploading…" : hasPhoto ? "Change photo" : "Upload photo"}
        </button>
        {hasPhoto && (
          <form action={delAction}>
            <input type="hidden" name="employeeId" value={employeeId} />
            <button disabled={delPending} className="px-2 py-2 text-xs font-semibold text-red-500 hover:underline disabled:opacity-50">
              {delPending ? "…" : "Remove"}
            </button>
          </form>
        )}
      </form>
    </div>
  );
}
