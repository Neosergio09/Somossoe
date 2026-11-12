/** Soportes documentales en Supabase Storage (bucket privado "soportes"). */
export const SUPPORT_BUCKET = 'soportes';
export const SUPPORT_MAX_BYTES = 10 * 1024 * 1024;
export const SUPPORT_TYPES: Record<string, string> = {
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};
export const SUPPORT_KINDS = ['convenios', 'compradores', 'ordenes', 'entregas', 'garantias', 'pagos', 'retenciones'] as const;
export type SupportKind = (typeof SUPPORT_KINDS)[number];

/** Ruta válida de un soporte: {tipo}/{uuid usuario}/{uuid}.{ext} */
const PATH_RE = /^(convenios|compradores|ordenes|entregas|garantias|pagos|retenciones)\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(pdf|jpg|png|webp)$/;

export function isSupportPath(value: string | null | undefined, kind?: SupportKind): value is string {
  return !!value && PATH_RE.test(value) && (!kind || value.startsWith(`${kind}/`));
}

/** Enlace para abrir un soporte (genera un enlace firmado temporal). */
export function supportHref(path: string): string {
  return `/api/soportes/abrir?ruta=${encodeURIComponent(path)}`;
}

/** ¿Los soportes exigen archivo? (parámetro require_document_files) */
export async function filesRequired(supabase: App.Locals['supabase']): Promise<boolean> {
  const { data } = await supabase.from('system_settings').select('value').eq('key', 'require_document_files').maybeSingle();
  return Number(data?.value ?? 0) === 1;
}

/** Valor de un campo de ruta del formulario: válido para el tipo, o null. */
export function supportPathFrom(form: FormData, field: string, kind: SupportKind): string | null {
  const value = String(form.get(field) ?? '').trim();
  return isSupportPath(value, kind) ? value : null;
}
