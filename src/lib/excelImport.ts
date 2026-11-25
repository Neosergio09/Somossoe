// Interpretación del Excel histórico «INFORME JORNADAS SOE» (doc de Jornadas
// §3). Las columnas se reconocen por su encabezado, no por la letra, porque
// cambian de posición entre hojas (mapas L1–L10).
//
// Exclusión clínica (doc §8): RX, ADD y cualquier encabezado de fórmula o
// graduación no se leen; las columnas sin encabezado reconocido tampoco,
// salvo marcas cortas conocidas (FACTURADO, X, ENTREGADA).
//
// Plantilla 2026 (L11, «SOE - JORNADAS (nuevo)»): título en la fila 1,
// «Fecha jornada» en la fila 2, encabezados en la fila 4, estado del lente
// calculado y hojas de consulta (INICIO, BASE, BUSCAR…) que no se importan.
// En MAGNETRON las filas van en secciones: las de «pendientes por llamar» y
// «desistieron» no son ventas, pasan a Seguimiento de la jornada.
import type { Cell, CellValue, WorkbookSheet } from './xlsx';

export type ImportRow = {
  row_number: number;
  block_number: number;
  fingerprint: string;
  event_date: string | null;
  company_name: string | null;
  full_name: string | null;
  document_id: string | null;
  phone: string | null;
  sale_value: number | null;
  installments: number | null;
  lab_reference: string | null;
  lab_name: string | null;
  frame: string | null;
  lens_type: string | null;
  cost_lens: number | null;
  cost_frame: number | null;
  cost_kit: number | null;
  paid_declared: number | null;
  lens_status: LensStatus | null;
  row_kind: RowKind;
  section_label: string | null;
  legacy_marks: Record<string, string>;
};

export type LensStatus = 'por_pedir' | 'en_laboratorio' | 'por_entregar' | 'entregado';
/** venta = se carga como orden; los demás no compraron y van a Seguimiento */
export type RowKind = 'venta' | 'pendiente_cierre' | 'desistio';

export type ImportSheet = {
  sheet_name: string;
  sheet_index: number;
  map_code: string | null;
  detected_columns: string[];
  skip_reason: string | null;
  rows: ImportRow[];
};

type Field = Exclude<keyof ImportRow, 'row_number' | 'block_number' | 'fingerprint' | 'legacy_marks' | 'row_kind' | 'section_label'>;

/** Mayúsculas, sin tildes ni signos, espacios simples. */
export const norm = (s: string) =>
  s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toUpperCase()
    .replace(/[^A-Z0-9 ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

// Hojas conocidas → mapa de origen (doc §3.1)
const SHEET_MAPS: [string, string][] = [
  ['FACIL CREDITOS PEREIRA', 'L1'],
  ['FACIL CREDITOS DORADA', 'L2'], ['FACIL CREDITOS NEIVA', 'L2'], ['PINTURAS NOVA', 'L2'],
  ['PARTICULAR AGOSTO', 'L2'], ['PARTICULARES OCTUBRE', 'L2'],
  ['PARTICULAR SEPTIEMBRE', 'L3'], ['FACIL CREDITOS SEPTIEMBRE', 'L3'], ['GASTRONOMIA 33', 'L3'], ['TRAYECTUARQ', 'L3'],
  ['SALSAMENTARIA HR', 'L3'], ['TRANSPORTES CHICUE', 'L3'], ['THIS FRUTA', 'L3'], ['ENERGIA DESCUENTO NOMINA', 'L3'],
  ['TRANSPORTE GRANADA', 'L3'], ['COPIA DE HOJA 25 1', 'L3'], ['COPIA DE HOJA 25', 'L3'],
  ['TRANSPORTES DM', 'L4'], ['FUNDACION CLUB CAMPESTRE', 'L5'], ['ENERGIA DE PEREIRA', 'L6'],
  ['ENEREGIA PARTICULAR', 'L7'], ['PARTICULAR NOVIEMBRE', 'L8'], ['NOVIEMBRE EMPRESAS CLIENTES', 'L9'],
  ['GARANTIAS', 'L10'],
];

const GARANTIAS_REASON = 'Hoja de garantías: no se importa por columnas. Las garantías se registran en Posventa sobre la orden ya cargada.';
const HIDDEN_REASON = 'Hoja oculta del Excel (cálculos internos): no se importa.';
const CONTROL_REASON = 'Hoja de consulta del Excel: se calcula a partir de las hojas de ventas, no se importa.';
// Hojas de consulta de la plantilla 2026 (repiten datos de las hojas de ventas)
const CONTROL_SHEETS = new Set(['INICIO', 'LABORATORIOS', 'POR ENTREGAR', 'BUSCAR', 'BUSCAR PACIENTE', 'BASE', 'CONFIG']);

// Encabezados clínicos: nunca se leen
const CLINICAL = /^(RX|ADD|AD|FORMULA|GRADUACION|DIAGNOSTICO|ESFERA|CILINDRO|EJE|DP|AV)( |$)/;

// Encabezado → campo
const HEADER_FIELDS: [RegExp, Field][] = [
  [/^FECHA/, 'event_date'],
  [/^EMPRESA/, 'company_name'],
  [/^NOMBRE/, 'full_name'],
  [/^(CEDULA|DOCUMENTO|CC|IDENTIFICACION)/, 'document_id'],
  [/^(TELEFONO|CELULAR)/, 'phone'],
  [/^TIPO DE LENTE/, 'lens_type'],
  [/^CUOTAS?$/, 'installments'],
  // ORDEN, N.º ORDEN («N ORDEN» normalizado), NO. ORDEN, NÚMERO DE ORDEN
  [/^((N|NO|NRO|NUM|NUMERO)( DE)? )?ORDEN\b/, 'lab_reference'],
  [/^LABORATORIO/, 'lab_name'],
  [/^MONTURA/, 'frame'],
  [/^COSTO MONTURA/, 'cost_frame'],
  [/^COSTO KIT/, 'cost_kit'],
  [/^ABONO/, 'paid_declared'],
  [/^ESTADO( DEL)? LENTE/, 'lens_status'],
];
// Marcas legadas con encabezado: se guardan solo en la revisión
const LEGACY_HEADERS = /^(PENDIENTE|FACTURADO|X|ENTREGADAS?|OBSERVACION(ES)?|MEDIO DE PAGO)$/;
// Marcas cortas en columnas sin encabezado (p. ej. FACTURADO en L1:N)
const LEGACY_TOKENS = /^(FACTURADO|FACTURADA|X|ENTREGADO|ENTREGADA|ENTREGADAS|PENDIENTE)$/;

type ColumnMap = { fields: Map<number, Field>; legacy: Map<number, string>; dateInFirstColumn: boolean; detected: string[] };

function isHeaderRow(row: Map<number, Cell>): boolean {
  const values = [...row.values()].map((c) => (typeof c.value === 'string' ? norm(c.value) : ''));
  return values.some((v) => v.startsWith('NOMBRE')) && values.some((v) => /^(CEDULA|DOCUMENTO)/.test(v));
}

function buildColumnMap(header: Map<number, Cell>): ColumnMap {
  const fields = new Map<number, Field>();
  const legacy = new Map<number, string>();
  const detected: string[] = [];
  const entries = [...header.entries()]
    .filter(([, c]) => typeof c.value === 'string')
    .map(([col, c]) => [col, norm(String(c.value))] as const)
    .sort(([a], [b]) => a - b);

  // VALOR: la primera es la venta; las siguientes (junto a montura) se ignoran
  let saleTaken = false;
  // COSTO LENTE: el del bloque económico es el más cercano a la izquierda de COSTO MONTURA
  const costFrameCol = entries.find(([, h]) => /^COSTO MONTURA/.test(h))?.[0];
  const lensCostCols = entries.filter(([, h]) => /^COSTO LENTE/.test(h)).map(([c]) => c);
  const lensCostCol = costFrameCol != null
    ? lensCostCols.filter((c) => c < costFrameCol).at(-1)
    : lensCostCols.at(-1);

  for (const [col, h] of entries) {
    if (!h || CLINICAL.test(h)) continue;
    if (/^VALOR( VENTA| DE VENTA)?$/.test(h)) {
      if (!saleTaken) {
        fields.set(col, 'sale_value');
        detected.push(h);
        saleTaken = true;
      }
      continue;
    }
    if (/^COSTO LENTE/.test(h)) {
      if (col === lensCostCol) {
        fields.set(col, 'cost_lens');
        detected.push(h);
      }
      continue;
    }
    if (LEGACY_HEADERS.test(h)) {
      legacy.set(col, h);
      detected.push(h);
      continue;
    }
    const match = HEADER_FIELDS.find(([re]) => re.test(h));
    if (match && ![...fields.values()].includes(match[1])) {
      fields.set(col, match[1]);
      detected.push(h);
    }
  }
  // L3–L8: la columna A sin encabezado trae la fecha de atención
  const dateInFirstColumn = !fields.has(0) && ![...fields.values()].includes('event_date');
  return { fields, legacy, dateInFirstColumn, detected };
}

/**
 * L5: el encabezado NOMBRE de la columna A trae fechas. Si las primeras filas
 * de esa columna son fechas y la siguiente trae texto, la columna es la fecha
 * de atención y el nombre está a su derecha.
 */
function fixDateUnderNameHeader(columns: ColumnMap, sheet: WorkbookSheet, headerRow: number) {
  const nameCol = [...columns.fields].find(([, f]) => f === 'full_name')?.[0];
  if (nameCol == null) return;
  const sample = [...sheet.cells.keys()].filter((r) => r > headerRow).sort((a, b) => a - b).slice(0, 5);
  const looksLikeDate = (c?: Cell) => !!c && (c.value instanceof Date || toDate(c.value) != null);
  const dated = sample.filter((r) => looksLikeDate(sheet.cells.get(r)?.get(nameCol))).length;
  const nextIsText = sample.some((r) => typeof sheet.cells.get(r)?.get(nameCol + 1)?.value === 'string');
  if (sample.length && dated >= Math.ceil(sample.length / 2) && nextIsText && !columns.fields.has(nameCol + 1)) {
    columns.fields.delete(nameCol);
    if (![...columns.fields.values()].includes('event_date')) columns.fields.set(nameCol, 'event_date');
    columns.fields.set(nameCol + 1, 'full_name');
    columns.dateInFirstColumn = false;
  }
}

const text = (v: CellValue | undefined): string | null => {
  if (v == null) return null;
  const s = (v instanceof Date ? v.toISOString().slice(0, 10) : String(v)).trim();
  return s ? s.slice(0, 200) : null;
};

/** Pesos: admite números y textos como "$ 350.000". */
export const money = (v: CellValue | undefined): number | null => {
  if (typeof v === 'number') return Number.isFinite(v) ? Math.round(v) : null;
  if (typeof v !== 'string') return null;
  const digits = v.replace(/[^\d,-]/g, '').replace(/,\d{1,2}$/, '').replace(/,/g, '');
  return /^\d+$/.test(digits) ? Number(digits) : null;
};

const integer = (v: CellValue | undefined): number | null => {
  const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v.replace(/[^\d]/g, '')) : NaN;
  return Number.isFinite(n) && n > 0 && n < 1000 ? Math.round(n) : null;
};

/** Fecha: Date, serial de Excel o texto dd/mm/aaaa. */
export const toDate = (v: CellValue | undefined): string | null => {
  if (v instanceof Date && !Number.isNaN(v.getTime())) return v.toISOString().slice(0, 10);
  if (typeof v === 'number' && v > 30000 && v < 80000) return new Date(Math.round((v - 25569) * 86400000)).toISOString().slice(0, 10);
  if (typeof v === 'string') {
    const m = /^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$/.exec(v.trim());
    if (m) {
      const year = m[3]!.length === 2 ? 2000 + Number(m[3]) : Number(m[3]);
      const d = new Date(Date.UTC(year, Number(m[2]) - 1, Number(m[1])));
      if (!Number.isNaN(d.getTime())) return d.toISOString().slice(0, 10);
    }
    const iso = /^(\d{4}-\d{2}-\d{2})/.exec(v.trim());
    if (iso) return iso[1]!;
  }
  return null;
};

const isTotalRow = (row: Map<number, Cell>) =>
  [...row.values()].some((c) => typeof c.value === 'string' && /^TOTAL/.test(norm(c.value)));

async function sha256(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Huella de la venta: con documento y referencia del laboratorio basta (la
 * misma orden repetida en otra pestaña coincide); si no, documento, nombre,
 * valor, fecha y hoja.
 */
export async function rowFingerprint(row: Omit<ImportRow, 'fingerprint'>, sheetName: string): Promise<string> {
  const doc = (row.document_id ?? '').replace(/[^0-9A-Za-z]/g, '').toUpperCase();
  const key = doc && row.lab_reference
    ? ['ref', doc, norm(row.lab_reference), row.sale_value ?? '']
    : ['fila', doc, norm(row.full_name ?? ''), row.sale_value ?? '', row.event_date ?? '', norm(sheetName)];
  return sha256(JSON.stringify(key));
}

/** Estado del lente calculado en la plantilla 2026 */
export const lensStatus = (v: CellValue | undefined): LensStatus | null => {
  if (typeof v !== 'string') return null;
  const s = norm(v);
  if (/^ENTREGAD/.test(s)) return 'entregado';
  if (/^LLEGO/.test(s) || /POR ENTREGAR/.test(s)) return 'por_entregar';
  if (/LABORATORIO/.test(s)) return 'en_laboratorio';
  if (/^POR PEDIR/.test(s)) return 'por_pedir';
  return null;
};

/**
 * Fila de sección (solo texto, sin persona ni valor), p. ej. en MAGNETRON:
 * «COMPRARON…», «PENDIENTES POR LLAMAR…», «DESISTIERON». Devuelve el tipo de
 * las filas que siguen, o null si el texto no es una sección conocida.
 */
export const sectionKind = (label: string): RowKind | null => {
  const s = norm(label);
  if (/DESISTI/.test(s)) return 'desistio';
  if (/PENDIENTE|LLAMAR|NO CONTESTA|NO HAN ABONADO|QUEDARON DE ABONAR/.test(s)) return 'pendiente_cierre';
  if (/^COMPRARON|^COMPRO|^VENTAS?\b/.test(s)) return 'venta';
  return null;
};

/** «Fecha jornada:» y su valor a la derecha, antes de los encabezados */
function sheetEventDate(sheet: WorkbookSheet, headerRow: number): string | null {
  for (const [rowNumber, cells] of sheet.cells) {
    if (rowNumber >= headerRow) continue;
    for (const [col, cell] of cells) {
      if (typeof cell.value === 'string' && /^FECHA (DE )?(LA )?JORNADA/.test(norm(cell.value))) {
        const date = toDate(cells.get(col + 1)?.value);
        if (date) return date;
      }
    }
  }
  return null;
}

export async function interpretSheet(sheet: WorkbookSheet): Promise<ImportSheet> {
  const normalized = norm(sheet.name);
  const nameMap = SHEET_MAPS.find(([name]) => name === normalized)?.[1] ?? null;
  const base = { sheet_name: sheet.name, sheet_index: sheet.index, map_code: nameMap };
  const skipped = (map_code: string | null, reason: string) => ({ ...base, map_code, detected_columns: [], skip_reason: reason, rows: [] });
  if (nameMap === 'L10' || /\bGARANTIA/.test(normalized)) return skipped('L10', GARANTIAS_REASON);
  if (sheet.hidden) return skipped(null, HIDDEN_REASON);
  if (CONTROL_SHEETS.has(normalized)) return skipped(null, CONTROL_REASON);

  const rows: ImportRow[] = [];
  const detected = new Set<string>();
  let columns: ColumnMap | null = null;
  let block = 0;
  let template2026 = false;
  let defaultDate: string | null = null;
  let kind: RowKind = 'venta';
  let section: string | null = null;
  let groupCompany: string | null = null;

  for (const rowNumber of [...sheet.cells.keys()].sort((a, b) => a - b)) {
    const cells = sheet.cells.get(rowNumber)!;
    if (isHeaderRow(cells)) {
      columns = buildColumnMap(cells);
      fixDateUnderNameHeader(columns, sheet, rowNumber);
      columns.detected.forEach((h) => detected.add(h));
      if ([...columns.fields.values()].includes('lens_status') || columns.detected.includes('MEDIO DE PAGO')) template2026 = true;
      defaultDate = sheetEventDate(sheet, rowNumber) ?? defaultDate;
      block += 1;
      kind = 'venta';
      section = null;
      groupCompany = null;
      continue;
    }
    if (!columns || isTotalRow(cells)) continue;

    const get = (field: Field) => {
      for (const [col, f] of columns!.fields) if (f === field) return cells.get(col);
      return undefined;
    };
    // Subtotal por fórmula (=SUM…) en la columna de venta
    const sale = get('sale_value');
    if (sale?.formula && /SUM|SUMA/i.test(sale.formula)) continue;

    const fullName = text(get('full_name')?.value);
    const documentId = text(get('document_id')?.value);
    const saleValue = money(sale?.value);

    // Fila de solo texto: sección (MAGNETRON) o, en la plantilla 2026 sin
    // columna EMPRESA, el nombre de la empresa del grupo (hoja de empresas
    // clientes, donde cada empresa va como fila separadora)
    if (!fullName && !documentId && saleValue == null) {
      const labels = [...cells.values()].filter((c) => typeof c.value === 'string' && !c.formula).map((c) => String(c.value).trim());
      if (labels.length === 1 && labels[0]) {
        const k = sectionKind(labels[0]);
        if (k) {
          kind = k;
          section = labels[0].slice(0, 200);
        } else if (template2026 && ![...columns.fields.values()].includes('company_name') && toDate(labels[0]) == null) {
          groupCompany = labels[0].slice(0, 200);
        }
      }
      continue;
    }

    const row: Omit<ImportRow, 'fingerprint'> = {
      row_number: rowNumber,
      block_number: block,
      event_date: toDate(get('event_date')?.value ?? (columns.dateInFirstColumn ? cells.get(0)?.value : undefined)) ?? defaultDate,
      company_name: text(get('company_name')?.value) ?? groupCompany,
      full_name: fullName,
      document_id: documentId,
      phone: text(get('phone')?.value),
      sale_value: saleValue,
      installments: integer(get('installments')?.value),
      lab_reference: text(get('lab_reference')?.value)?.slice(0, 60) ?? null,
      lab_name: text(get('lab_name')?.value),
      frame: text(get('frame')?.value),
      lens_type: text(get('lens_type')?.value),
      cost_lens: money(get('cost_lens')?.value),
      cost_frame: money(get('cost_frame')?.value),
      cost_kit: money(get('cost_kit')?.value),
      paid_declared: money(get('paid_declared')?.value),
      lens_status: lensStatus(get('lens_status')?.value),
      row_kind: kind,
      section_label: section,
      legacy_marks: {},
    };

    for (const [col, header] of columns.legacy) {
      const v = text(cells.get(col)?.value);
      if (v) row.legacy_marks[header] = v;
    }
    for (const [col, cell] of cells) {
      if (columns.fields.has(col) || columns.legacy.has(col) || (col === 0 && columns.dateInFirstColumn)) continue;
      const v = typeof cell.value === 'string' ? norm(cell.value) : '';
      if (LEGACY_TOKENS.test(v)) row.legacy_marks['MARCA SIN ENCABEZADO'] = v;
    }

    rows.push({ ...row, fingerprint: await rowFingerprint(row, sheet.name) });
  }

  return {
    ...base,
    map_code: template2026 ? 'L11' : nameMap,
    detected_columns: [...detected],
    skip_reason: block === 0 ? 'No se encontró una fila de encabezados con NOMBRE y CÉDULA/DOCUMENTO.' : null,
    rows,
  };
}

export async function interpretWorkbook(sheets: WorkbookSheet[]): Promise<ImportSheet[]> {
  return Promise.all(sheets.map(interpretSheet));
}
