import os from "node:os";
import path from "node:path";
import { mkdir, writeFile } from "node:fs/promises";

/** Persistent upload dir — survives deploys (env UPLOAD_DIR or ~/hrms-uploads). */
export function uploadDir(): string {
  return process.env.UPLOAD_DIR ?? path.join(os.homedir(), "hrms-uploads");
}

export async function ensureUploadDir() {
  await mkdir(uploadDir(), { recursive: true });
}

export async function fsyncWrite(name: string, buf: Buffer) {
  await ensureUploadDir();
  await writeFile(path.join(uploadDir(), name), buf);
}

export function photoPath(employeeId: string, ext: string) {
  return path.join(uploadDir(), `${employeeId}.${ext}`);
}
