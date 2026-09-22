-- Phase E: salary revisions (E2), shift roster (E7), payslip share links (E11), selfie (E12), contractor (E8)
ALTER TABLE "Employee" ADD COLUMN "contractor" TEXT;
ALTER TABLE "Attendance" ADD COLUMN "selfiePath" TEXT;

CREATE TABLE "SalaryRevision" (
    "id" TEXT NOT NULL,
    "employeeId" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "effectiveDate" TIMESTAMP(3) NOT NULL,
    "changeType" TEXT NOT NULL,
    "oldSalaryType" TEXT,
    "newSalaryType" TEXT,
    "oldSalary" INTEGER,
    "newSalary" INTEGER,
    "note" TEXT,
    "createdById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SalaryRevision_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ShiftAssignment" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "employeeId" TEXT NOT NULL,
    "date" TIMESTAMP(3) NOT NULL,
    "shiftId" TEXT,
    "isOff" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "ShiftAssignment_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "PayslipLink" (
    "id" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "rowId" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PayslipLink_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "SalaryRevision" ADD CONSTRAINT "SalaryRevision_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "Employee"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ShiftAssignment" ADD CONSTRAINT "ShiftAssignment_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ShiftAssignment" ADD CONSTRAINT "ShiftAssignment_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "Employee"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ShiftAssignment" ADD CONSTRAINT "ShiftAssignment_shiftId_fkey" FOREIGN KEY ("shiftId") REFERENCES "Shift"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "PayslipLink" ADD CONSTRAINT "PayslipLink_rowId_fkey" FOREIGN KEY ("rowId") REFERENCES "PayrollRow"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE INDEX "SalaryRevision_companyId_employeeId_idx" ON "SalaryRevision"("companyId", "employeeId");
CREATE UNIQUE INDEX "ShiftAssignment_employeeId_date_key" ON "ShiftAssignment"("employeeId", "date");
CREATE INDEX "ShiftAssignment_companyId_date_idx" ON "ShiftAssignment"("companyId", "date");
CREATE UNIQUE INDEX "PayslipLink_rowId_key" ON "PayslipLink"("rowId");
CREATE UNIQUE INDEX "PayslipLink_token_key" ON "PayslipLink"("token");
CREATE INDEX "PayslipLink_companyId_idx" ON "PayslipLink"("companyId");
