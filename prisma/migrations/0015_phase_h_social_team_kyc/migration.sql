ALTER TABLE "Employee"
  ADD COLUMN IF NOT EXISTS "bloodGroup" TEXT,
  ADD COLUMN IF NOT EXISTS "emergencyName" TEXT,
  ADD COLUMN IF NOT EXISTS "emergencyPhone" TEXT;

ALTER TABLE "Company"
  ADD COLUMN IF NOT EXISTS "geoFacility" TEXT,
  ADD COLUMN IF NOT EXISTS "geoAddress" TEXT;

CREATE TABLE "SocialPost" (
  "id" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "authorId" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SocialPost_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "SocialPost_companyId_createdAt_idx" ON "SocialPost"("companyId", "createdAt");
ALTER TABLE "SocialPost" ADD CONSTRAINT "SocialPost_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SocialPost" ADD CONSTRAINT "SocialPost_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "PostLike" (
  "id" TEXT NOT NULL,
  "postId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  CONSTRAINT "PostLike_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "PostLike_postId_userId_key" ON "PostLike"("postId", "userId");
CREATE INDEX "PostLike_postId_idx" ON "PostLike"("postId");
ALTER TABLE "PostLike" ADD CONSTRAINT "PostLike_postId_fkey" FOREIGN KEY ("postId") REFERENCES "SocialPost"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PostLike" ADD CONSTRAINT "PostLike_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "PostComment" (
  "id" TEXT NOT NULL,
  "postId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PostComment_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "PostComment_postId_idx" ON "PostComment"("postId");
ALTER TABLE "PostComment" ADD CONSTRAINT "PostComment_postId_fkey" FOREIGN KEY ("postId") REFERENCES "SocialPost"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PostComment" ADD CONSTRAINT "PostComment_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "ShiftSwapRequest" (
  "id" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "requesterId" TEXT NOT NULL,
  "peerId" TEXT NOT NULL,
  "date" DATE NOT NULL,
  "note" TEXT,
  "status" "RequestStatus" NOT NULL DEFAULT 'PENDING',
  "approverId" TEXT,
  "decidedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ShiftSwapRequest_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "ShiftSwapRequest_companyId_status_idx" ON "ShiftSwapRequest"("companyId", "status");
ALTER TABLE "ShiftSwapRequest" ADD CONSTRAINT "ShiftSwapRequest_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ShiftSwapRequest" ADD CONSTRAINT "ShiftSwapRequest_requesterId_fkey" FOREIGN KEY ("requesterId") REFERENCES "Employee"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ShiftSwapRequest" ADD CONSTRAINT "ShiftSwapRequest_peerId_fkey" FOREIGN KEY ("peerId") REFERENCES "Employee"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "KycDoc" (
  "id" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "employeeId" TEXT NOT NULL,
  "docType" TEXT NOT NULL,
  "refNumber" TEXT NOT NULL,
  "filePath" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "KycDoc_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "KycDoc_companyId_employeeId_idx" ON "KycDoc"("companyId", "employeeId");
ALTER TABLE "KycDoc" ADD CONSTRAINT "KycDoc_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "KycDoc" ADD CONSTRAINT "KycDoc_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "Employee"("id") ON DELETE CASCADE ON UPDATE CASCADE;
