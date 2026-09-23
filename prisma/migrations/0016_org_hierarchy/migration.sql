-- Sub-departments + designation categorisation (universal org structure)
DO $$ BEGIN
  CREATE TYPE "DesignationCategory" AS ENUM ('OFFICIAL', 'YELLOW_CARD', 'BOTH');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "Department" ADD COLUMN IF NOT EXISTS "parentId" TEXT;
ALTER TABLE "Designation" ADD COLUMN IF NOT EXISTS "category" "DesignationCategory" NOT NULL DEFAULT 'BOTH';
ALTER TABLE "Designation" ADD COLUMN IF NOT EXISTS "departmentId" TEXT;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'Department_parentId_fkey') THEN
    ALTER TABLE "Department" ADD CONSTRAINT "Department_parentId_fkey"
      FOREIGN KEY ("parentId") REFERENCES "Department"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'Designation_departmentId_fkey') THEN
    ALTER TABLE "Designation" ADD CONSTRAINT "Designation_departmentId_fkey"
      FOREIGN KEY ("departmentId") REFERENCES "Department"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;
