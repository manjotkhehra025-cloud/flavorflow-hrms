-- Phase B: employee photos + auto letters (GDF/HR/YYYY/NNNN serial)

-- AlterTable
ALTER TABLE "Employee" ADD COLUMN "photoUrl" TEXT;

-- AlterTable
ALTER TABLE "Company"
  ADD COLUMN "letterSeq" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "Letter" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "employeeId" TEXT NOT NULL,
    "serial" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "issuedTo" TEXT,
    "createdBy" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Letter_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Letter_companyId_employeeId_idx" ON "Letter"("companyId", "employeeId");

-- CreateIndex
CREATE UNIQUE INDEX "Letter_serial_key" ON "Letter"("serial");

-- AddForeignKey
ALTER TABLE "Letter" ADD CONSTRAINT "Letter_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Letter" ADD CONSTRAINT "Letter_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "Employee"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- photo extension tracking
ALTER TABLE "Employee" ADD COLUMN "photoExt" TEXT;
