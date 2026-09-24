CREATE TABLE IF NOT EXISTS "EmployeePermission" (
  "id" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "employeeId" TEXT NOT NULL,
  "canPunch" BOOLEAN NOT NULL DEFAULT true,
  "canApplyLeave" BOOLEAN NOT NULL DEFAULT true,
  "canGatePass" BOOLEAN NOT NULL DEFAULT true,
  "canSwapShift" BOOLEAN NOT NULL DEFAULT true,
  "canSocialPost" BOOLEAN NOT NULL DEFAULT true,
  "canViewPayslip" BOOLEAN NOT NULL DEFAULT true,
  CONSTRAINT "EmployeePermission_pkey" PRIMARY KEY ("id")
);
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'EmployeePermission_employeeId_key') THEN
    ALTER TABLE "EmployeePermission" ADD CONSTRAINT "EmployeePermission_employeeId_key" UNIQUE ("employeeId");
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'EmployeePermission_companyId_fkey') THEN
    ALTER TABLE "EmployeePermission" ADD CONSTRAINT "EmployeePermission_companyId_fkey"
      FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'EmployeePermission_employeeId_fkey') THEN
    ALTER TABLE "EmployeePermission" ADD CONSTRAINT "EmployeePermission_employeeId_fkey"
      FOREIGN KEY ("employeeId") REFERENCES "Employee"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS "EmployeePermission_companyId_idx" ON "EmployeePermission"("companyId");
