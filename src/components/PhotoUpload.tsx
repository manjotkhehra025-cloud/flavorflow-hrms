"use client";

import { useActionState, useRef, useState } from "react";
import { uploadEmployeePhotoAction, deleteEmployeePhotoAction } from "@/actions/photos";
import type { ActionState } from "@/actions/auth";
import { Icon } from "@/components/icons";

export function PhotoUpload({ employeeId, hasPhoto }: { employeeId: string; hasPhoto: boolean }) {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(uploadEmployeePhotoAction, {});
  const [delState, delAction, delPending] = useActionState<ActionState, FormData>(deleteEmployeePhotoAction, {});
  const inputRef = useRef<HTMLInputElement>(null);
  const [localMsg, setLocalMsg] = useState<string | null>(null);

  return (
    <div className="space-y-2">
      {state.error && <p className="rounded-lg bg-red-50 px-3 py-2 text-xs text-red-600">{state.error}</p>}
      {state.success && <p className="rounded-lg bg-emerald-50 px-3 py-2 text-xs text-emerald-700">{state.success}</p>}
      {localMsg && <p className="rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-700">{localMsg}</p>}
      <form action={formAction} className="flex flex-wrap items-center gap-2">
        <input type="hidden" name="employeeId" value={employeeId} />
        <input
          ref={inputRef}
          type="file"
          name="photo"
          accept="image/jpeg,image/png,image/webp"
          className="hidden"
          onChange={(e) => {
            const f = e.target.files?.[0];
            if (!f) return;
            if (f.size > 4 * 1024 * 1024) {
              setLocalMsg("Photo 4 MB se choti rakho 📦");
              e.target.value = "";
              return;
            }
            setLocalMsg(null);
            e.target.form?.requestSubmit();
          }}
        />
        <button
          type="button"
          disabled={pending}
          onClick={() => inputRef.current?.click()}
          className="flex items-center gap-1.5 rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs font-semibold text-slate-700 hover:bg-slate-50 active:scale-95 disabled:opacity-50"
        >
          <Icon name="badge" className="h-4 w-4" /> {pending ? "Uploading…" : hasPhoto ? "Change photo" : "Upload photo"}
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
