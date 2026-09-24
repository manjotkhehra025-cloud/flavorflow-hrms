import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";
const db=new PrismaClient();
(async()=>{
  const comp=await db.company.findFirstOrThrow();
  const hash=await bcrypt.hash("Test@1234",10);
  const mk=async(code:string,fn:string,ln:string,email:string)=>{
    const emp=await db.employee.upsert({where:{companyId_code:{companyId:comp.id,code}},update:{},create:{companyId:comp.id,code,firstName:fn,lastName:ln,joinDate:new Date("2024-01-01"),category:"OFFICIAL"}});
    await db.user.upsert({where:{email},update:{employeeId:emp.id},create:{companyId:comp.id,employeeId:emp.id,name:fn+" "+ln,email,passwordHash:hash,role:"EMPLOYEE"}});
  };
  await mk("OP10","Harbhajan","Singh","op10@test.in");
  console.log("fixture ok");
  await db.$disconnect();
})();
