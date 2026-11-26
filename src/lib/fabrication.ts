// Ficha de fabricación (SRS 1.6 · RF-M04-07). Los rangos y pasos los
// valida la BD (CHECK); aquí solo se arman los formularios y se formatea.
import type { Database } from './database.types';

export type FabricationStatus = Database['public']['Functions']['fabrication_spec_status']['Returns'][number];

export type FabricationSpec = {
  spec_id: string;
  version: number;
  od_sphere: number | null;
  od_cylinder: number | null;
  od_axis: number | null;
  od_add: number | null;
  od_pd_mm: number | null;
  od_height_mm: number | null;
  os_sphere: number | null;
  os_cylinder: number | null;
  os_axis: number | null;
  os_add: number | null;
  os_pd_mm: number | null;
  os_height_mm: number | null;
  pd_total_mm: number | null;
  technical_notes: string | null;
  prescription_date: string | null;
  source: string;
  validated_at: string | null;
  change_reason: string | null;
};

export type FabricationPurpose = 'captura' | 'validacion' | 'envio_laboratorio' | 'correccion';
export const FABRICATION_PURPOSES: FabricationPurpose[] = ['captura', 'validacion', 'envio_laboratorio', 'correccion'];

export const FABRICATION_SOURCE_LABELS: Record<string, string> = {
  formula_optometra_jornada: 'Fórmula de la optómetra (jornada)',
  formula_externa: 'Fórmula externa',
};

type FieldKind = 'diopter' | 'axis' | 'mm';
export const EYE_FIELDS: { key: string; label: string; kind: FieldKind; step: string; min: string; max: string; required?: boolean }[] = [
  { key: 'sphere', label: 'Esfera', kind: 'diopter', step: '0.25', min: '-30', max: '30', required: true },
  { key: 'cylinder', label: 'Cilindro', kind: 'diopter', step: '0.25', min: '-10', max: '10' },
  { key: 'axis', label: 'Eje', kind: 'axis', step: '1', min: '0', max: '180' },
  { key: 'add', label: 'ADD', kind: 'diopter', step: '0.25', min: '0.5', max: '4' },
  { key: 'pd_mm', label: 'DP mono', kind: 'mm', step: '0.5', min: '20', max: '40' },
  { key: 'height_mm', label: 'Altura', kind: 'mm', step: '0.5', min: '10', max: '40' },
];

/** +1.25 / −0.50 / 90° / 31.5 mm */
export function fmtRx(value: unknown, kind: FieldKind): string {
  if (value === null || value === undefined || value === '') return '—';
  const n = Number(value);
  if (kind === 'diopter') return `${n > 0 ? '+' : n < 0 ? '−' : ''}${Math.abs(n).toFixed(2)}`;
  if (kind === 'axis') return `${n}°`;
  return `${n} mm`;
}

const NUMERIC = ['pd_total_mm', ...['od', 'os'].flatMap((eye) => EYE_FIELDS.map((f) => `${eye}_${f.key}`))];

/** Valores del formulario → JSON para public.save_fabrication_spec (vacío = null). */
export function fabricationValues(form: FormData): Record<string, number | string | null> {
  const out: Record<string, number | string | null> = {};
  for (const key of NUMERIC) {
    const raw = String(form.get(key) ?? '').trim().replace(',', '.');
    if (raw === '') {
      out[key] = null;
      continue;
    }
    const n = Number(raw);
    if (!Number.isFinite(n)) throw new Error(key);
    out[key] = n;
  }
  for (const key of ['technical_notes', 'prescription_date', 'source']) {
    const raw = String(form.get(key) ?? '').trim();
    out[key] = raw === '' ? null : raw;
  }
  return out;
}
