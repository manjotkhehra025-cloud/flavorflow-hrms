import { notFound } from "next/navigation";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { fmtDate } from "@/lib/utils";
import { PrintButton } from "@/components/PrintButton";

export const dynamic = "force-dynamic";

const TYPE_TITLES: Record<string, string> = {
  EXPERIENCE: "EXPERIENCE CERTIFICATE",
  JOINING: "JOINING / APPOINTMENT LETTER",
  KYC: "EMPLOYMENT VERIFICATION LETTER",
};

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

  const e = letter.employee;
  const name = `${e.firstName} ${e.lastName}`;
  const role = e.designation?.title ?? "employee";
  const dept = e.department?.name ?? "company";
  const title = TYPE_TITLES[letter.type] ?? "LETTER";
  const addressee = letter.issuedTo ? `To,\n${letter.issuedTo}` : "To Whom It May Concern";

  return (
    <div className="print-area mx-auto max-w-3xl">
      <div className="mb-4 flex items-center justify-between print:hidden">
        <div className="text-sm font-semibold text-slate-600">
          Ref: <span className="font-black text-emerald-700">{letter.serial}</span>
          <span className="ml-2 text-xs text-slate-400">({title.toLowerCase()})</span>
        </div>
        <PrintButton />
      </div>

      {/* Letterhead sheet */}
      <div className="rounded-xl bg-white p-8 shadow-pop ring-1 ring-slate-200/70 md:p-12 print:rounded-none print:p-0 print:shadow-none print:ring-0">
        <div className="border-b-4 border-emerald-500 pb-5">
          <div className="flex items-start justify-between">
            <div>
              <div className="text-2xl font-black tracking-tight text-[#0a1628]">{letter.company.name.toUpperCase()}</div>
              <div className="mt-1 text-xs text-slate-500">
                V.P.O. Khadur Sahib, Tarn Taran, Punjab – 143117, India
              </div>
            </div>
            <div className="flex h-14 w-14 items-center justify-center rounded-xl bg-[#0a1628] text-lg font-black text-emerald-400">
              GD
            </div>
          </div>
        </div>

        <div className="mt-6 flex items-center justify-between text-sm text-slate-700">
          <div>Ref: <b>{letter.serial}</b></div>
          <div>Dated: <b>{fmtDate(letter.createdAt)}</b></div>
        </div>

        <div className="mt-6 whitespace-pre-line text-sm leading-relaxed text-slate-700">{addressee},</div>

        <h1 className="mt-8 text-center text-lg font-black tracking-[0.25em] text-[#0a1628] underline decoration-emerald-500 decoration-2 underline-offset-8">
          {title}
        </h1>

        <div className="mt-8 space-y-4 text-justify text-[15px] leading-[1.9] text-slate-800">
          {letter.type === "EXPERIENCE" && (
            <>
              <p>
                This is to certify that <b>Mr./Ms. {name}</b>, holding Employee ID <b>{e.code}</b>, has been working
                with <b>{letter.company.name}</b> as <b>{role}</b> in the <b>{dept}</b> department since{" "}
                <b>{fmtDate(e.joinDate)}</b>.
              </p>
              <p>
                During the tenure, we have found {name.split(" ")[0].toLowerCase().startsWith("s") ? "him/her" : "him/her"} sincere,
                hardworking, and punctual in all duties assigned. The employee has maintained good conduct
                and discipline on the factory floor and has always complied with company policies.
              </p>
              <p>
                We wish <b>{name}</b> all the best in future endeavours.
              </p>
            </>
          )}
          {letter.type === "JOINING" && (
            <>
              <p>
                We are pleased to confirm the appointment of <b>Mr./Ms. {name}</b>, Employee ID <b>{e.code}</b>,
                with <b>{letter.company.name}</b> as <b>{role}</b> in the <b>{dept}</b> department, effective{" "}
                <b>{fmtDate(e.joinDate)}</b>.
              </p>
              <p>
                The employment is subject to the company's standing orders, shift schedules, and factory rules as
                applicable. Weekly off and leave entitlement shall apply as per the staff category assigned
                ({e.category === "YELLOW_CARD" ? "Yellow Card Staff — 15 Earned Leaves per year" : "Official Staff — standard leave policy"}).
              </p>
              <p>
                We extend a warm welcome to the team.
              </p>
            </>
          )}
          {letter.type === "KYC" && (
            <>
              <p>
                This is to verify, at the request of {letter.issuedTo ? <b>{letter.issuedTo}</b> : "the concerned authority"},
                that <b>Mr./Ms. {name}</b>, holding Employee ID <b>{e.code}</b>, is presently employed
                with <b>{letter.company.name}</b> as <b>{role}</b> in the <b>{dept}</b> department.
              </p>
              <p>
                {e.address && <>As per our records, the employee's declared residential address is: <b>{e.address}.</b></>}
              </p>
              <p>
                The employee joined the company on <b>{fmtDate(e.joinDate)}</b> and is currently on active rolls
                with a standard shift roster. This letter is issued for {letter.issuedTo ? `${letter.issuedTo}'s` : "the applicant's"} KYC
                verification purpose only.
              </p>
            </>
          )}
        </div>

        <div className="mt-12 flex items-end justify-between">
          <div className="text-xs text-slate-400">
            <div className="h-16 w-16 rounded-full border-2 border-dashed border-slate-300 flex items-center justify-center text-slate-300">
              SEAL
            </div>
            <div className="mt-1 text-center text-[10px]">Company Seal</div>
          </div>
          <div className="text-right">
            <div className="text-sm font-bold text-slate-700">For {letter.company.name}</div>
            <div className="mt-10 border-t border-slate-300 pt-1 text-xs font-semibold text-slate-500">Authorized Signatory (HR)</div>
          </div>
        </div>

        <div className="mt-8 border-t border-slate-100 pt-3 text-center text-[10px] text-slate-400">
          {letter.company.name} · Ref {letter.serial} · Generated via HRMate · {fmtDate(letter.createdAt)}
        </div>
      </div>
    </div>
  );
}
