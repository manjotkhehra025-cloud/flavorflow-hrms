-- Phase C1: KRA (quarterly, weightage + targets, auto-score)

CREATE TYPE "KraStatus" AS ENUM ('DRAFT', 'OPEN', 'SCORING', 'CLOSED');

CREATE TABLE "KraCycle" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "year" INTEGER NOT NULL,
    "quarter" INTEGER NOT NULL,
    "status" "KraStatus" NOT NULL DEFAULT 'DRAFT',
    "closedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "KraCycle_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "KraGoal" (
    "id" TEXT NOT NULL,
    "cycleId" TEXT NOT NULL,
    "employeeId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "weight" INTEGER NOT NULL,
    "target" DOUBLE PRECISION NOT NULL,
    "achieved" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "unit" TEXT,
    "hrNote" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "KraGoal_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "KraCycle_companyId_year_quarter_key" ON "KraCycle"("companyId", "year", "quarter");
CREATE INDEX "KraGoal_cycleId_idx" ON "KraGoal"("cycleId");
CREATE INDEX "KraGoal_employeeId_idx" ON "KraGoal"("employeeId");

ALTER TABLE "KraCycle" ADD CONSTRAINT "KraCycle_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "KraGoal" ADD CONSTRAINT "KraGoal_cycleId_fkey" FOREIGN KEY ("cycleId") REFERENCES "KraCycle"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "KraGoal" ADD CONSTRAINT "KraGoal_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "Employee"("id") ON DELETE CASCADE ON UPDATE CASCADE;
