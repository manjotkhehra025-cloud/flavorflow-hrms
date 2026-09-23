import { Pa } from "@/components/Pa";

import Link from "next/link";
import { notFound } from "next/navigation";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { btnGhost } from "@/components/ui";
import { monthName, monthNamePa } from "@/lib/utils";
import { getRequestLang } from "@/lib/i18n";
import { Icon } from "@/components/icons";
import { Payslip } from "@/components/Payslip";
import { buildPayslipData } from "@/lib/payslipData";
import { PrintButton } from "@/components/PrintButton";
import { PayslipShareButtons } from "@/components/PayslipShareButtons";

export const dynamic = "force-dynamic";

/** Employee's own payslip (own-only; staff should use the payroll run view instead). */
export default async function MyPayslipPage({ params }: { params: Promise<{ rowId: string }> }) {
  const me = await requireUser();
  const { rowId } = await params;
  const lang = await getRequestLang();

  const row = await db.payrollRow.findFirst({
    where: { id: rowId, run: { companyId: me.companyId, status: "LOCKED" } },
    include: { run: true, employee: { include: { department: true, company: true } } },
  });
  if (!row || row.employeeId !== me.employeeId) notFound();

  const data = buildPayslipData(row, lang === "pa" ? "pa" : "en");

  return (
    <div className="mx-auto max-w-2xl space-y-4 print:space-y-0">
      <div className="flex items-center justify-between print:hidden">
        <Link href="/payslips" className={btnGhost}><Icon name="chevron-down" className="h-3.5 w-3.5 rotate-90" /> <Pa>All payslips</Pa></Link>
        <span className="inline-flex items-center gap-1.5">
          <PayslipShareButtons rowId={row.id} />
          <PrintButton label={<Pa>Print / save PDF</Pa>} />
        </span>
      </div>
      <Payslip d={data} />
    </div>
  );
}
