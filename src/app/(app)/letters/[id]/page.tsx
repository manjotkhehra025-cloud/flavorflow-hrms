import { notFound } from "next/navigation";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { PrintButton } from "@/components/PrintButton";
import { LetterSheet } from "@/components/LetterSheet";
import { LetterShareButtons } from "@/components/LetterShareButtons";
import { displayRef, LETTER_TYPE_TITLES } from "@/lib/letter-doc";

export const dynamic = "force-dynamic";

export default async function LetterPage({ params }: { params: Promise<{ id: string }> }) {
  const me = await requireUser();
  const { id } = await params;

  const letter = await db.letter.findFirst({
    where: { id, companyId: me.companyId },
    include: {
      employee: { include: { department: true, designation: true } },
      company: true,
    },
  });
  if (!letter) notFound();
  // Owner employee can view own letters, staff can view all
  if (me.role === "EMPLOYEE" && letter.employeeId !== me.employeeId) notFound();

  const title = LETTER_TYPE_TITLES[letter.type] ?? "LETTER";

  return (
    <div className="print-area mx-auto max-w-3xl">
      <div className="mb-4 flex items-center justify-between print:hidden">
        <div className="text-sm font-semibold text-slate-600">
          Ref: <span className="font-black text-emerald-700">{displayRef(letter.serial, letter.employee.code)}</span>
          <span className="ml-2 text-xs text-slate-400">({title.toLowerCase()})</span>
        </div>
        <div className="flex items-center gap-2">
          <LetterShareButtons letterId={letter.id} />
          <PrintButton />
        </div>
      </div>

      {/* Letterhead sheet */}
      <LetterSheet letter={letter} />
    </div>
  );
}
