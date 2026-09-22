-- Phase D1: payroll base — salary fields on employees + advances
ALTER TABLE "Employee" ADD COLUMN "salaryType" TEXT NOT NULL DEFAULT 'MONTHLY';
ALTER TABLE "Employee" ADD COLUMN "baseSalary" INTEGER;
ALTER TABLE "Employee" ADD COLUMN "dailyRate" INTEGER;
ALTER TABLE "Employee" ADD COLUMN "otRate" INTEGER;
ALTER TABLE "Employee" ADD COLUMN "bankAccount" TEXT;
ALTER TABLE "Employee" ADD COLUMN "ifsc" TEXT;

CREATE TABLE "Advance" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "employeeId" TEXT NOT NULL,
    "amount" INTEGER NOT NULL,
    "repaid" INTEGER NOT NULL DEFAULT 0,
    "givenDate" TIMESTAMP(3) NOT NULL,
    "reason" TEXT,
    "createdById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Advance_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "Advance" ADD CONSTRAINT "Advance_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "Advance" ADD CONSTRAINT "Advance_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "Employee"("id") ON DELETE CASCADE ON UPDATE CASCADE;
CREATE INDEX "Advance_companyId_employeeId_idx" ON "Advance"("companyId", "employeeId");
