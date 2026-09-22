import ExcelJS from "exceljs";

const NAVY = "FF0A1628";
const EMERALD = "FF059669";

export type XlsxCol = { header: string; width: number; key?: string };

/**
 * Brand-styled worksheet: navy title band, dark header row, zebra rows.
 * Returns Buffer ready for a download response.
 */
export async function makeXlsx(opts: {
  title: string;           // big title row, merged across all cols
  subtitle?: string;       // second merged row
  sheetName: string;
  columns: XlsxCol[];
  rows: (string | number | null | undefined)[][];
  headerFill?: string;     // hex ARGB, default navy
  zebra?: boolean;
}): Promise<Buffer> {
  const wb = new ExcelJS.Workbook();
  wb.creator = "HRMate";
  const ws = wb.addWorksheet(opts.sheetName, {
    views: [{ state: "frozen", ySplit: opts.subtitle ? 3 : 2 }],
  });

  const nCols = opts.columns.length;
  ws.columns = opts.columns.map((c) => ({ width: c.width }));

  // Title band
  const titleRow = ws.addRow([opts.title]);
  ws.mergeCells(1, 1, 1, nCols);
  titleRow.height = 26;
  titleRow.font = { size: 14, bold: true, color: { argb: "FFFFFFFF" } };
  titleRow.alignment = { vertical: "middle", horizontal: "left", indent: 1 };
  titleRow.fill = { type: "pattern", pattern: "solid", fgColor: { argb: NAVY } };

  let headerAt = 2;
  if (opts.subtitle) {
    const sr = ws.addRow([opts.subtitle]);
    ws.mergeCells(2, 1, 2, nCols);
    sr.height = 18;
    sr.font = { size: 10, color: { argb: "FF475569" }, italic: true };
    sr.alignment = { vertical: "middle", horizontal: "left", indent: 1 };
    headerAt = 3;
  }

  // Header row
  const hr = ws.addRow(opts.columns.map((c) => c.header));
  hr.height = 20;
  hr.font = { size: 10, bold: true, color: { argb: "FFFFFFFF" } };
  hr.fill = { type: "pattern", pattern: "solid", fgColor: { argb: opts.headerFill ?? EMERALD } };
  hr.alignment = { vertical: "middle", horizontal: "center" };
  hr.border = { bottom: { style: "thin", color: { argb: "FFCBD5E1" } } };

  // Data rows
  opts.rows.forEach((r, i) => {
    const row = ws.addRow(r.map((v) => (v === undefined ? null : v)));
    row.font = { size: 10, color: { argb: "FF1E293B" } };
    if (opts.zebra !== false && i % 2 === 1) {
      row.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF1F5F9" } };
    }
  });

  return Buffer.from(await wb.xlsx.writeBuffer());
}

/** Status-code fill colors for the register grid sheet (ARGB). */
export const CELL_FILLS: Record<string, string> = {
  P: "FFD1FAE5", // emerald-100
  A: "FFFEE2E2", // red-100
  L: "FFFEF3C7", // amber-100
  W: "FFDBEAFE", // blue-100
  H: "FFEDE9FE", // violet-100
};
export const CELL_FONTS: Record<string, string> = {
  P: "FF047857",
  A: "FFB91C1C",
  L: "FFB45309",
  W: "FF1D4ED8",
  H: "FF6D28D9",
};
