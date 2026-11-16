import { FormError, int, text, z } from './forms';
import { ITEM_TYPE_LABELS } from './labels';

export const ITEM_TYPES = Object.keys(ITEM_TYPE_LABELS) as [keyof typeof ITEM_TYPE_LABELS, ...(keyof typeof ITEM_TYPE_LABELS)[]];

/** Valor en pesos: admite "350.000" o "350000". */
export const money = () =>
  z.preprocess(
    (v) => (typeof v === 'string' ? v.replace(/[.\s$]/g, '') : v),
    z.coerce.number({ error: 'Valor inválido' }).int({ error: 'Valor sin decimales' }).min(0),
  );

export const itemSchema = z
  .object({
    item_type: z.enum(ITEM_TYPES),
    frame_description: text(200).optional(),
    lens_type: text(200).optional(),
    lens_filter: text(200).optional(),
    description: text(300).optional(),
    quantity: int().min(1),
    unit_price: money(),
    discount_amount: money().optional().default(0),
    discount_reason: text(500).optional(),
  })
  // Neto de la línea = cantidad × valor unitario − descuento (doc de Jornadas §4.3)
  .superRefine((item, ctx) => {
    if (item.discount_amount > item.quantity * item.unit_price) {
      ctx.addIssue({ code: 'custom', path: ['discount_amount'], message: 'no puede superar cantidad × valor unitario' });
    }
    if (item.discount_amount > 0 && !item.discount_reason?.trim()) {
      ctx.addIssue({ code: 'custom', path: ['discount_reason'], message: 'indique por qué se descuenta' });
    }
  })
  .transform((item) => ({
    ...item,
    discount_reason: item.discount_amount > 0 ? item.discount_reason!.trim() : undefined,
  }));

export type ItemInput = z.infer<typeof itemSchema>;

const ITEM_FIELD_LABELS: Record<string, string> = {
  item_type: 'Tipo',
  frame_description: 'Montura',
  lens_type: 'Tipo de lente',
  lens_filter: 'Filtro',
  description: 'Descripción',
  quantity: 'Cantidad',
  unit_price: 'Valor unitario',
  discount_amount: 'Descuento',
  discount_reason: 'Motivo del descuento',
};

const ITEM_FIELDS = ['item_type', 'frame_description', 'lens_type', 'lens_filter', 'description', 'quantity', 'unit_price', 'discount_amount', 'discount_reason'] as const;

/** Base de la línea antes del descuento. */
export const lineBase = (item: { quantity: number; unit_price: number }) => item.quantity * item.unit_price;

/** Filas `items[i][campo]` del formulario, en orden y sin las filas vacías. */
export function itemRows(values: Record<string, string>): Record<string, string>[] {
  const rows = new Map<number, Record<string, string>>();
  for (const [key, value] of Object.entries(values)) {
    const m = /^items\[(\d+)\]\[(\w+)\]$/.exec(key);
    if (!m) continue;
    const index = Number(m[1]);
    rows.set(index, { ...rows.get(index), [m[2]!]: value });
  }
  return [...rows.entries()]
    .sort(([a], [b]) => a - b)
    .map(([, row]) => row)
    .filter((row) => ITEM_FIELDS.some((f) => f !== 'item_type' && f !== 'quantity' && (row[f] ?? '') !== ''));
}

/** Valida los ítems del formulario de nueva orden. */
export function parseItems(values: Record<string, string>): ItemInput[] {
  const rows = itemRows(values);
  if (!rows.length) throw new FormError('Agregue al menos un ítem a la orden.');
  return rows.map((row, i) => {
    const raw = Object.fromEntries(Object.entries(row).map(([k, v]) => [k, v === '' ? undefined : v]));
    const result = itemSchema.safeParse(raw);
    if (!result.success) {
      const issue = result.error.issues[0];
      const field = ITEM_FIELD_LABELS[String(issue?.path?.[0] ?? '')];
      throw new FormError(`Ítem ${i + 1}: ${field ? `${field}: ` : ''}${issue?.message ?? 'datos inválidos'}`);
    }
    const item = result.data;
    if (!item.frame_description && !item.lens_type && !item.description) {
      throw new FormError(`Ítem ${i + 1}: describa la montura, el tipo de lente o el producto.`);
    }
    return item;
  });
}

/** Requisitos que revisa Administración, según modalidad (RF-M04-03). */
export function requirementChecklist(order: {
  payment_modality: string;
  hr_approval_required: boolean | null;
  missing_requirements: string[] | null;
}) {
  const all = ['Al menos un ítem con valor', 'Autorización de tratamiento de datos del comprador'];
  if (order.payment_modality === 'nomina_empresa') {
    all.push('Convenio de nómina aprobado', 'Autorización de descuento firmada por el empleado');
    if (order.hr_approval_required !== false) all.push('Aval de RRHH');
  }
  const missing = new Set(order.missing_requirements ?? []);
  return all.map((label) => ({ label, ok: !missing.has(label) }));
}

export function orderNumber(n: number | null | undefined): string {
  return n == null ? '—' : `#${String(n).padStart(5, '0')}`;
}
