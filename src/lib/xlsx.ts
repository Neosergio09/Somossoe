// Lector mínimo de .xlsx (solo lectura): hojas, celdas y valores en caché
// de las fórmulas. Sin dependencias pesadas; no evalúa fórmulas ni macros.
import { unzipSync, strFromU8 } from 'fflate';

export type CellValue = string | number | boolean | Date;
export type Cell = { value: CellValue; formula?: string };
/** Fila → columna (0 = A) → celda */
export type SheetCells = Map<number, Map<number, Cell>>;
export type WorkbookSheet = { name: string; index: number; cells: SheetCells };

const ENTITIES: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
const decode = (s: string) =>
  s.replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (m, e: string) =>
    e[0] === '#' ? String.fromCodePoint(e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : Number(e.slice(1))) : (ENTITIES[e] ?? m),
  );

/** Texto de un nodo con o sin prefijo de espacio de nombres (x:t, t…). */
const texts = (xml: string, tag: string) =>
  [...xml.matchAll(new RegExp(`<(?:\\w+:)?${tag}(?:\\s[^>]*)?>([\\s\\S]*?)</(?:\\w+:)?${tag}>`, 'g'))].map((m) => decode(m[1]!));

export function columnIndex(ref: string): number {
  let n = 0;
  for (const ch of ref.replace(/\d+/g, '')) n = n * 26 + (ch.charCodeAt(0) - 64);
  return n - 1;
}

// Formatos de fecha integrados de Excel
const BUILTIN_DATE_FORMATS = new Set([14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47]);

/** Serial de Excel (sistema 1900) → fecha UTC */
export function excelSerialToDate(serial: number): Date {
  return new Date(Math.round((serial - 25569) * 86400 * 1000));
}

function dateStyles(files: Record<string, Uint8Array>): Set<number> {
  const xml = files['xl/styles.xml'] ? strFromU8(files['xl/styles.xml']) : '';
  const custom = new Map<number, string>();
  for (const m of xml.matchAll(/<(?:\w+:)?numFmt\s[^>]*numFmtId="(\d+)"[^>]*formatCode="([^"]*)"/g)) custom.set(Number(m[1]), decode(m[2]!));
  const cellXfs = /<(?:\w+:)?cellXfs[^>]*>([\s\S]*?)<\/(?:\w+:)?cellXfs>/.exec(xml)?.[1] ?? '';
  const result = new Set<number>();
  [...cellXfs.matchAll(/<(?:\w+:)?xf\s([^>]*)/g)].forEach((m, i) => {
    const id = Number(/numFmtId="(\d+)"/.exec(m[1]!)?.[1] ?? 0);
    const code = (custom.get(id) ?? '').replace(/"[^"]*"|\[[^\]]*\]|\\./g, '');
    if (BUILTIN_DATE_FORMATS.has(id) || (custom.has(id) && /[dy]/i.test(code))) result.add(i);
  });
  return result;
}

export function readWorkbook(data: Uint8Array): WorkbookSheet[] {
  let files: Record<string, Uint8Array>;
  try {
    files = unzipSync(data, { filter: (f) => (f.name.startsWith('xl/') && f.name.endsWith('.xml')) || f.name.endsWith('.rels') });
  } catch {
    throw new Error('El archivo no es un Excel (.xlsx) válido.');
  }
  const workbook = files['xl/workbook.xml'];
  if (!workbook) throw new Error('El archivo no es un Excel (.xlsx) válido.');

  const shared = files['xl/sharedStrings.xml']
    ? [...strFromU8(files['xl/sharedStrings.xml']).matchAll(/<(?:\w+:)?si>([\s\S]*?)<\/(?:\w+:)?si>/g)].map((m) => texts(m[1]!, 't').join(''))
    : [];
  const dates = dateStyles(files);

  // Hoja → archivo según las relaciones del libro
  const rels = new Map<string, string>();
  const relsXml = files['xl/_rels/workbook.xml.rels'] ? strFromU8(files['xl/_rels/workbook.xml.rels']) : '';
  for (const m of relsXml.matchAll(/<(?:\w+:)?Relationship\s([^>]*)/g)) {
    const id = /Id="([^"]+)"/.exec(m[1]!)?.[1];
    const target = /Target="([^"]+)"/.exec(m[1]!)?.[1];
    if (id && target) rels.set(id, target.replace(/^\/?(xl\/)?/, 'xl/'));
  }

  const sheets: WorkbookSheet[] = [];
  const wbXml = strFromU8(workbook);
  [...wbXml.matchAll(/<(?:\w+:)?sheet\s([^>]*)\/?>/g)].forEach((m, i) => {
    const attrs = m[1]!;
    const name = decode(/name="([^"]*)"/.exec(attrs)?.[1] ?? `Hoja ${i + 1}`);
    const rid = /r:id="([^"]+)"|\bid="([^"]+)"/.exec(attrs);
    const path = rels.get(rid?.[1] ?? rid?.[2] ?? '') ?? `xl/worksheets/sheet${i + 1}.xml`;
    const xml = files[path] ? strFromU8(files[path]) : '';
    sheets.push({ name, index: i + 1, cells: parseSheet(xml, shared, dates) });
  });
  return sheets;
}

function parseSheet(xml: string, shared: string[], dateStyleIdx: Set<number>): SheetCells {
  const cells: SheetCells = new Map();
  const re = /<(?:\w+:)?c\s([^>]*?)(?:\/>|>([\s\S]*?)<\/(?:\w+:)?c>)/g;
  for (const m of xml.matchAll(re)) {
    const attrs = m[1]!;
    const inner = m[2] ?? '';
    const ref = /\br="([A-Z]+)(\d+)"/.exec(attrs);
    if (!ref) continue;
    const type = /\bt="([^"]+)"/.exec(attrs)?.[1] ?? 'n';
    const style = Number(/\bs="(\d+)"/.exec(attrs)?.[1] ?? -1);
    const formula = texts(inner, 'f')[0];
    const raw = texts(inner, 'v')[0];
    let value: CellValue | undefined;
    if (type === 's') value = raw != null ? shared[Number(raw)] : undefined;
    else if (type === 'inlineStr') value = texts(inner, 't').join('');
    else if (type === 'str') value = raw;
    else if (type === 'b') value = raw === '1';
    else if (type === 'e') value = undefined;
    else if (type === 'd') value = raw ? new Date(raw) : undefined;
    else if (raw != null && raw !== '') {
      const n = Number(raw);
      value = Number.isFinite(n) ? (dateStyleIdx.has(style) ? excelSerialToDate(n) : n) : raw;
    }
    if (value === undefined || value === '') continue;
    const row = Number(ref[2]);
    const col = columnIndex(ref[1]!);
    if (!cells.has(row)) cells.set(row, new Map());
    cells.get(row)!.set(col, formula ? { value, formula } : { value });
  }
  return cells;
}
