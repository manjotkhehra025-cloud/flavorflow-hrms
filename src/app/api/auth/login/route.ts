import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import bcrypt from "bcryptjs";
import { db } from "@/lib/db";
import { signSession, setSessionCookie } from "@/lib/auth";

const schema = z.object({ email: z.string().email().toLowerCase(), password: z.string().min(1) });

export async function POST(req: NextRequest) {
  const parsed = schema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: "Invalid payload" }, { status: 400 });
  }

  const user = await db.user.findUnique({
    where: { email: parsed.data.email },
    include: { company: true },
  });
  if (!user || !user.isActive || !(await bcrypt.compare(parsed.data.password, user.passwordHash))) {
    return NextResponse.json({ error: "Invalid credentials" }, { status: 401 });
  }

  const token = await signSession({
    id: user.id,
    companyId: user.companyId,
    companyName: user.company.name,
    email: user.email,
    name: user.name,
    role: user.role,
    employeeId: user.employeeId,
  });
  await setSessionCookie(token);

  // The token is returned so mobile apps (future Android app) can store it
  // and send it as "Authorization: Bearer <token>".
  return NextResponse.json({
    token,
    user: {
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role,
      company: user.company.name,
      employeeId: user.employeeId,
    },
  });
}
