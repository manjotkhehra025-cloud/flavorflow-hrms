import { Pa } from "@/components/Pa";

import Link from "next/link";
import { notFound } from "next/navigation";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { btnGhost } from "@/components/ui";
import { monthName } from "@/lib/utils";
import { Icon } from "@/components/icons";
import { Payslip } from "@/components/Payslip";
import { buildPayslipData } from "@/lib/payslipData";
import { PrintButton } from "@/components/PrintButton";

export const dynamic = "force-dynamic";

export default async function PayslipPage({ params }: { params: Promise<{ id: string; rowId: string }> }) {
  const me = await requireStaff();
  const { id, rowId } = await params;

  const row = await db.payrollRow.findFirst({
    where: { id: rowId, runId: id },
    include: {
      run: true,
      employee: { include: { department: true, company: true } },
    },
  });
  if (!row || row.run.companyId !== me.companyId || row.run.status === "DRAFT") notFound();

  const data = buildPayslipData(row, "en");

  return (
    <div className="mx-auto max-w-2xl space-y-4 print:space-y-0">
      <div className="flex items-center justify-between print:hidden">
        <Link href={`/payroll/${id}`} className={btnGhost}><Icon name="chevron-down" className="h-3.5 w-3.5 rotate-90" /> <Pa>Back to run</Pa></Link>
        <PrintButton label={<Pa>🖨 Print / save PDF</Pa>} />
      </div>
      <div className="print-area">
        <Payslip d={data} />
      </div>
    </div>
  );
}
