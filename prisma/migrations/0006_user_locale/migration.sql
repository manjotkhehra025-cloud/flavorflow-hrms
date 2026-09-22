-- Phase C4: per-user UI language (English / Punjabi)
ALTER TABLE "User" ADD COLUMN "locale" TEXT NOT NULL DEFAULT 'en';
