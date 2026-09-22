-- Phase E9: optional selfie-on-punch
ALTER TABLE "Company" ADD COLUMN "punchSelfieRequired" BOOLEAN NOT NULL DEFAULT false;
