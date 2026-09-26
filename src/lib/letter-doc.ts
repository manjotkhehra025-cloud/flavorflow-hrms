import { t, type Lang } from "./i18n";
import { fmtDate } from "./utils";

/**
 * Single source of truth for the letter document (web letterhead sheet, the
 * public share page and the mobile API all render THIS — no copy drift).
 * Body paragraphs are segment lists: bold segments are dynamic data (names,
 * codes, dates — never translated), plain segments are fixed prose that goes
 * through the Punjabi dictionary exactly like <Pa> does on the web sheet.
 */

export type LetterSeg = { t: string; b?: boolean };

export const LETTER_TYPE_TITLES: Record<string, string> = {
  EXPERIENCE: "EXPERIENCE CERTIFICATE",
  JOINING: "JOINING / APPOINTMENT LETTER",
  KYC: "EMPLOYMENT VERIFICATION LETTER",
  DUTY: "DUTY & SHIFT PASS",
};

export const LETTER_TYPE_LABELS: Record<string, string> = {
  EXPERIENCE: "Experience Certificate",
  JOINING: "Joining / Appointment Letter",
  KYC: "KYC / Employment Verification",
  DUTY: "Duty & Shift Pass",
};

/** Letterhead address line (matches the printed company letterhead). */
export const LETTER_ADDRESS_LINE = "V.P.O. Khadur Sahib, Tarn Taran, Punjab – 143117, India";

/** Render-friendly ref: GDF/HR/2026/{empCode}-0007 (serial suffix stays global). */
export function displayRef(serial: string, empCode: string): string {
  const m = serial.match(/^(.*\/HR\/[0-9]{4})\/(\d+)$/);
  return m ? `${m[1]}/${empCode}-${m[2]}` : serial;
}

export type LetterDocEmployee = {
  firstName: string;
  lastName: string;
  code: string;
  joinDate: string | Date | null;
  category: string;
  address: string | null;
  department?: { name: string } | null;
  designation?: { title: string } | null;
};

export type LetterDocLetter = {
  serial: string;
  type: string;
  issuedTo: string | null;
  createdAt: string | Date;
  employee: LetterDocEmployee;
  company: { name: string };
};

const b = (t: string): LetterSeg => ({ t, b: true });

/** The four letter bodies, word-for-word identical to the approved letterhead. */
export function buildLetterBody(letter: LetterDocLetter, lang: Lang): LetterSeg[][] {
  const e = letter.employee;
  const name = `${e.firstName} ${e.lastName}`;
  const role = e.designation?.title ?? "employee";
  const dept = e.department?.name ?? "company";
  const company = letter.company.name;
  const joined = fmtDate(e.joinDate);

  if (letter.type === "EXPERIENCE") {
    return [
      [
        { t: "This is to certify that " },
        b(`Mr./Ms. ${name}`),
        { t: ", holding Employee ID" },
        b(e.code),
        { t: ", has been working with " },
        b(company),
        { t: "as" },
        b(role),
        { t: "in the" },
        b(dept),
        { t: " department since " },
        b(joined),
        { t: "." },
      ],
      [
        {
          t: "During the tenure, we have found him/her sincere, hardworking, and punctual in all duties assigned. The employee has maintained good conduct and discipline on the factory floor and has always complied with company policies.",
        },
      ],
      [{ t: "We wish " }, b(name), { t: " all the best in future endeavours." }],
    ];
  }

  if (letter.type === "JOINING") {
    return [
      [
        { t: "We are pleased to confirm the appointment of " },
        b(`Mr./Ms. ${name}`),
        { t: ", Employee ID" },
        b(e.code),
        { t: ", with " },
        b(company),
        { t: "as" },
        b(role),
        { t: "in the" },
        b(dept),
        { t: " department, effective " },
        b(joined),
        { t: "." },
      ],
      [
        {
          t: "The employment is subject to the company's standing orders, shift schedules, and factory rules as applicable. Weekly off and leave entitlement shall apply as per the staff category assigned (",
        },
        {
          t:
            e.category === "YELLOW_CARD"
              ? "Yellow Card Staff — 15 Earned Leaves per year"
              : "Official Staff — standard leave policy",
        },
        { t: ")." },
      ],
      [{ t: "We extend a warm welcome to the team." }],
    ];
  }

  if (letter.type === "DUTY") {
    return [
      [
        { t: "This is to certify that " },
        b(`Mr./Ms. ${name}`),
        { t: ", holding Employee ID" },
        b(e.code),
        { t: ", is a bonafide employee of " },
        b(company),
        { t: "in the" },
        b(dept),
        {
          t: " department. This pass authorizes him/her to report for official duty within the factory premises as per the shift roster assigned from time to time, including early-morning and night shifts.",
        },
      ],
      [
        {
          t: "The holder is requested to carry this pass along with the company ID card at all times. Traffic authorities and check-posts are requested to permit duty travel accordingly.",
        },
      ],
      [{ t: "This pass is valid for the period of active employment and must be surrendered on leaving service." }],
    ];
  }

  // KYC / employment verification
  const paras: LetterSeg[][] = [
    [
      { t: "This is to verify, at the request of " },
      letter.issuedTo ? b(letter.issuedTo) : { t: "the concerned authority" },
      { t: ", that " },
      b(`Mr./Ms. ${name}`),
      { t: ", holding Employee ID" },
      b(e.code),
      { t: ", is presently employed with " },
      b(company),
      { t: "as" },
      b(role),
      { t: "in the" },
      b(dept),
      { t: " department." },
    ],
  ];
  if (e.address) {
    paras.push([{ t: "As per our records, the employee's declared residential address is:" }, b(`${e.address}.`)]);
  }
  paras.push([
    { t: "The employee joined the company on " },
    b(joined),
    { t: " and is currently on active rolls with a standard shift roster. This letter is issued for " },
    { t: letter.issuedTo ? `${letter.issuedTo}'s` : "the applicant's" },
    { t: " KYC verification purpose only." },
  ]);
  return paras;
}

/** Everything a renderer (web sheet / mobile app) needs, pre-translated. */
export function buildLetterDoc(letter: LetterDocLetter, lang: Lang) {
  const e = letter.employee;
  return {
    serial: letter.serial,
    ref: displayRef(letter.serial, e.code),
    type: letter.type,
    title: LETTER_TYPE_TITLES[letter.type] ?? "LETTER",
    typeLabel: LETTER_TYPE_LABELS[letter.type] ?? letter.type,
    issuedTo: letter.issuedTo,
    addressee: letter.issuedTo ? `To,\n${letter.issuedTo}` : "To Whom It May Concern",
    dated: fmtDate(letter.createdAt),
    header: {
      company: letter.company.name.toUpperCase(),
      addressLine: LETTER_ADDRESS_LINE,
      monogram: "GD",
    },
    labels: {
      ref: t(lang, "Ref:"),
      dated: t(lang, "Dated:"),
      officialSeal: t(lang, "Official Seal"),
      signatory: t(lang, "Authorized Signatory (HR)"),
      forCompany: `${t(lang, "For")} ${letter.company.name}`,
      stampTop: letter.company.name.split(" ").slice(0, 2).join(" "),
      stampMid: t(lang, "Officially"),
      stampBottom: t(lang, "Verified"),
    },
    body: buildLetterBody(letter, lang).map((para) => para.map((s) => (s.b ? s : { t: t(lang, s.t) }))),
    footer: `${letter.company.name} · Ref ${letter.serial} · Generated via HRMate · ${fmtDate(letter.createdAt)}`,
  };
}

export type LetterDoc = ReturnType<typeof buildLetterDoc>;
