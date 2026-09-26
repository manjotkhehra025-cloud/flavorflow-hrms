import { getRequestLang } from "@/lib/i18n";
import { buildLetterDoc, type LetterDocLetter } from "@/lib/letter-doc";

/**
 * The company letterhead sheet — ONE implementation rendered by the signed-in
 * letter page, the public share page and (from the same document JSON) the
 * mobile app. Body copy lives in lib/letter-doc.ts so nothing can drift.
 */
export async function LetterSheet({ letter }: { letter: LetterDocLetter }) {
  const lang = await getRequestLang();
  const doc = buildLetterDoc(letter, lang);

  return (
    <div className="rounded-xl bg-white p-8 shadow-pop ring-1 ring-slate-200/70 md:p-12 print:rounded-none print:p-0 print:shadow-none print:ring-0">
      <div className="border-b-4 border-emerald-500 pb-5">
        <div className="flex items-start justify-between">
          <div>
            <div className="text-2xl font-black tracking-tight text-[#0a1628]">{doc.header.company}</div>
            <div className="mt-1 text-xs text-slate-500">{doc.header.addressLine}</div>
          </div>
          <div className="flex h-14 w-14 items-center justify-center rounded-xl bg-[#0a1628] text-lg font-black text-emerald-400">
            {doc.header.monogram}
          </div>
        </div>
      </div>

      <div className="mt-6 flex items-center justify-between text-sm text-slate-700">
        <div>
          {doc.labels.ref}
          <b>{doc.ref}</b>
        </div>
        <div>
          {doc.labels.dated}
          <b>{doc.dated}</b>
        </div>
      </div>

      <div className="mt-6 whitespace-pre-line text-sm leading-relaxed text-slate-700">{doc.addressee},</div>

      <h1 className="mt-8 text-center text-lg font-black tracking-[0.25em] text-[#0a1628] underline decoration-emerald-500 decoration-2 underline-offset-8">
        {doc.title}
      </h1>

      <div className="mt-8 space-y-4 text-justify text-[15px] leading-[1.9] text-slate-800">
        {doc.body.map((para, i) => (
          <p key={i}>
            {para.map((seg, j) =>
              seg.b ? (
                <b key={j}>{seg.t}</b>
              ) : (
                <span key={j}>{seg.t}</span>
              )
            )}
          </p>
        ))}
      </div>

      <div className="mt-12 flex items-end justify-between">
        <div className="text-xs text-slate-400">
          <div className="relative flex h-20 w-20 -rotate-12 items-center justify-center rounded-full border-[3px] border-emerald-600/70">
            <div className="absolute inset-1 rounded-full border border-emerald-600/50" />
            <div className="text-center text-[7px] font-black uppercase leading-tight tracking-wider text-emerald-700">
              {doc.labels.stampTop}
              <br />
              {doc.labels.stampMid}
              <br />
              {doc.labels.stampBottom}
            </div>
          </div>
          <div className="mt-1 text-center text-[10px]">{doc.labels.officialSeal}</div>
        </div>
        <div className="text-right">
          <div className="text-sm font-bold text-slate-700">{doc.labels.forCompany}</div>
          <div className="mt-10 border-t border-slate-300 pt-1 text-xs font-semibold text-slate-500">
            {doc.labels.signatory}
          </div>
        </div>
      </div>

      <div className="mt-8 border-t border-slate-100 pt-3 text-center text-[10px] text-slate-400">{doc.footer}</div>
    </div>
  );
}
