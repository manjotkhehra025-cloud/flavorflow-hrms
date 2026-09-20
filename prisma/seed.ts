/**
 * OPTIONAL demo data — run locally with: npm run db:seed
 * Production uses /setup instead (creates company + admin once, no demo data).
 */
import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";

const db = new PrismaClient();

async function main() {
  const company = await db.company.upsert({
    where: { code: "FF" },
    update: {},
    create: { name: "FlavorFlow Foods Pvt. Ltd.", code: "FF" },
  });

  const hash = await bcrypt.hash("Admin@123", 10);
  await db.user.upsert({
    where: { email: "admin@flavorflow.co.in" },
    update: {},
    create: {
      companyId: company.id,
      name: "Admin",
      email: "admin@flavorflow.co.in",
      passwordHash: hash,
      role: "ADMIN",
    },
  });

  console.log("Seeded. Login: admin@flavorflow.co.in / Admin@123  (change immediately)");
}

main().finally(() => db.$disconnect());
