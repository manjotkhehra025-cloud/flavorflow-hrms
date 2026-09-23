import { Pa } from "@/components/Pa";
import { fmtINR } from "@/lib/utils";

export type PayslipData = {
  month: string; // YYYY-MM
  monthLabel: string;
  companyName: string;
  code: string;
  name: string;
  dept: string;
  salaryType: string;
  // money
  fullBase: number; // monthly: base+LOP; daily: baseAmount
  baseHint: string; // e.g. "₹ 11,000 / 30 days" or "20 days × ₹450"
  otHours: number; otRate: number; otAmount: number;
  offWorkDays: number; offWorkPay: number;
  otherEarning: number; otherEarningNote: string | null;
  lopDays: number; lopPerDay: number; lopAmount: number;
  pfEmployee: number; pfEmployer: number;
  esiEmployee: number; esiEmployer: number;
  advanceRecover: number;
  otherDeduction: number; otherDeductionNote: string | null;
  netPay: number;
  paymentMode: string; bank: string | null;
  presentDays: number; leaveDays: number; offDays: number; absentDays: number;
};

const cell: React.CSSProperties = { padding: "10px 14px" };

export function Payslip({ d }: { d: PayslipData }) {
  return (
    <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white print:border-slate-300">
      {/* header strip */}
      <div style={{ background: "linear-gradient(90deg,#0a1628,#123043)", color: "white", padding: "16px 18px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div>
            <div style={{ fontSize: 13, fontWeight: 900, letterSpacing: 1 }}>{d.companyName.toUpperCase()}</div>
            <div style={{ fontSize: 10, color: "rgba(148,163,184,1)" }}>HRMate · <Pa>Salary slip</Pa> — {d.monthLabel}</div>
          </div>
          <div style={{ textAlign: "right" }}>
            <div style={{ fontSize: 15, fontWeight: 800 }}>{d.name}</div>
            <div style={{ fontSize: 10, color: "rgba(148,163,184,1)" }}>{d.code} · {d.dept}</div>
          </div>
        </div>
      </div>

      <div style={{ padding: 14 }}>
        {/* days summary */}
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 10 }}>
          {([
            [<Pa>Present</Pa>, d.presentDays], [<Pa>Leave</Pa>, d.leaveDays], [<Pa>Weekly-off/holiday</Pa>, d.offDays], [<Pa>Absent</Pa>, d.absentDays],
          ] as [React.ReactNode, number][]).map(([k, v], i) => (
            <div key={i} style={{ flex: 1, minWidth: 70, border: "1px solid #e2e8f0", borderRadius: 10, padding: "6px 10px", textAlign: "center" }}>
              <div style={{ fontSize: 9.5, color: "#64748b", fontWeight: 700 }}>{k}</div>
              <div style={{ fontSize: 15, fontWeight: 800, color: i === 3 && v > 0 ? "#dc2626" : "#0f172a" }}>{v}</div>
            </div>
          ))}
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "1fr", gap: 10 }} className="sm:grid-cols-2">
          {/* EARNINGS */}
          <div style={{ border: "1px solid #d1fae5", background: "#f6fef9", borderRadius: 12, overflow: "hidden" }}>
            <div style={{ background: "#10b981", color: "white", ...cell, fontSize: 10.5, fontWeight: 900, letterSpacing: 1 }}>
              <Pa>EARNINGS</Pa>
            </div>
            <div style={cell}>
              <Row k={<Pa>Base pay</Pa>} h={d.baseHint} v={fmtINR(d.fullBase)} />
              {d.otAmount > 0 && (
                <Row k={<Pa>Overtime</Pa>} h={`${d.otHours}h × ₹${d.otRate}`} v={"+" + fmtINR(d.otAmount)} good />
              )}
              {d.offWorkPay > 0 && (
                <Row k={<Pa>Weekly-off duty pay</Pa>} h={`${d.offWorkDays} off-day(s) worked`} v={"+" + fmtINR(d.offWorkPay)} good />
              )}
              {d.otherEarning > 0 && (
                <Row k={<Pa>Reward / bonus</Pa>} h={d.otherEarningNote ?? undefined} v={"+" + fmtINR(d.otherEarning)} good />
              )}
            </div>
          </div>

          {/* DEDUCTIONS */}
          <div style={{ border: "1px solid #fecaca", background: "#fef7f7", borderRadius: 12, overflow: "hidden" }}>
            <div style={{ background: "#dc2626", color: "white", ...cell, fontSize: 10.5, fontWeight: 900, letterSpacing: 1 }}>
              <Pa>DEDUCTIONS</Pa>
            </div>
            <div style={cell}>
              {d.lopAmount > 0 ? (
                <Row k={<Pa>Absent (LOP)</Pa>} h={`${d.lopDays} days × ₹${d.lopPerDay}`} v={"−" + fmtINR(d.lopAmount)} bad />
              ) : (
                <div style={{ fontSize: 11, color: "#64748b", padding: "4px 0" }}><Pa>No absent deduction 🎉</Pa></div>
              )}
              {d.pfEmployee > 0 && (
                <Row k={<Pa>Provident Fund (12%)</Pa>} v={"−" + fmtINR(d.pfEmployee)} bad />
              )}
              {d.esiEmployee > 0 && (
                <Row k={<Pa>ESI (0.75%)</Pa>} v={"−" + fmtINR(d.esiEmployee)} bad />
              )}
              {d.advanceRecover > 0 && (
                <Row k={<Pa>Advance recovery</Pa>} v={"−" + fmtINR(d.advanceRecover)} bad />
              )}
              {d.otherDeduction > 0 && (
                <Row k={<Pa>Other deduction</Pa>} h={d.otherDeductionNote ?? undefined} v={"−" + fmtINR(d.otherDeduction)} bad />
              )}
            </div>
          </div>
        </div>

        {/* NET */}
        <div style={{ marginTop: 10, background: "#0a1628", color: "white", borderRadius: 12, padding: "14px 16px", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div>
            <div style={{ fontSize: 10, color: "#94a3b8", fontWeight: 800, letterSpacing: 1 }}><Pa>NET PAY</Pa> · {d.month}</div>
            <div style={{ fontSize: 10.5, color: "#94a3b8" }}><Pa>paid via</Pa> {d.paymentMode}{d.bank ? " · " + d.bank : ""}</div>
          </div>
          <div style={{ fontSize: 24, fontWeight: 900, color: "#6ee7b7" }}>{fmtINR(d.netPay)}</div>
        </div>

        <div style={{ marginTop: 10, fontSize: 9.5, color: "#94a3b8", lineHeight: 1.5 }}>
          {(d.pfEmployer > 0 || d.esiEmployer > 0) && (
            <div style={{ marginBottom: 4 }}>
              <Pa>Employer's PF / ESI contribution</Pa> ({d.pfEmployer > 0 ? `PF ${fmtINR(d.pfEmployer)}` : ""}{d.pfEmployer > 0 && d.esiEmployer > 0 ? " + " : ""}{d.esiEmployer > 0 ? `ESI ${fmtINR(d.esiEmployer)}` : ""}) <Pa>is paid by the company on top of your salary — it does NOT reduce your net pay.</Pa>
            </div>
          )}
          <Pa>This is a system-generated salary slip and does not require a signature.</Pa>
        </div>
      </div>
    </div>
  );
}

function Row({ k, h, v, good = false, bad = false }: { k: React.ReactNode; h?: string; v: string; good?: boolean; bad?: boolean }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", padding: "4px 0" }}>
      <div style={{ fontSize: 11.5, color: "#334155" }}>{k}{h && <div style={{ fontSize: 9.5, color: "#94a3b8" }}>{h}</div>}</div>
      <div style={{ fontSize: 12.5, fontWeight: 800, color: good ? "#059669" : bad ? "#dc2626" : "#0f172a" }}>{v}</div>
    </div>
  );
}
