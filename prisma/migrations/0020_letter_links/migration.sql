-- CreateTable: public (token-gated) share links for letters (mirrors PayslipLink).
CREATE TABLE "LetterLink" (
    "id" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "letterId" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LetterLink_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "LetterLink_token_key" ON "LetterLink"("token");

-- CreateIndex
CREATE UNIQUE INDEX "LetterLink_letterId_key" ON "LetterLink"("letterId");

-- CreateIndex
CREATE INDEX "LetterLink_companyId_idx" ON "LetterLink"("companyId");

-- AddForeignKey
ALTER TABLE "LetterLink" ADD CONSTRAINT "LetterLink_letterId_fkey" FOREIGN KEY ("letterId") REFERENCES "Letter"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LetterLink" ADD CONSTRAINT "LetterLink_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
