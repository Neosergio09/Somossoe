import type { AstroGlobal } from 'astro';
import { z } from 'astro/zod';
import type { PostgrestError } from '@supabase/supabase-js';
import { setFlash } from './flash';
import {
  AGREEMENT_STATUS_LABELS,
  CAMPAIGN_STATUS_LABELS,
  DOC_STATUS_LABELS,
  OPS_STATUS_LABELS,
  PAYMENT_MODALITY_LABELS,
  STAGE_LABELS,
} from './labels';

z.config(z.locales.es());

export { z };

/** Error de negocio que se muestra al usuario tal cual. */
export class FormError extends Error {}

export type ActionResult = { message?: string; redirect?: string } | void;
export type ActionHandler = (form: FormData) => Promise<ActionResult>;

export type PostOutcome =
  | { kind: 'redirect'; response: Response }
  | { kind: 'error'; error: string; values: Record<string, string>; action: string };

/**
 * Procesa un POST despachando por el campo oculto `_action`.
 * Éxito: guarda mensaje flash y redirige (PRG). Error de negocio: devuelve
 * el mensaje y los valores enviados para volver a pintar el formulario.
 */
export async function runActions(
  Astro: AstroGlobal,
  handlers: Record<string, ActionHandler>,
): Promise<PostOutcome | null> {
  if (Astro.request.method !== 'POST') return null;

  const form = await Astro.request.formData();
  const action = String(form.get('_action') ?? '');
  const values = formValues(form);
  const handler = handlers[action];

  try {
    if (!handler) throw new FormError('Acción no reconocida.');
    const result = await handler(form);
    if (result?.message) setFlash(Astro.cookies, { type: 'ok', message: result.message });
    const target = result?.redirect ?? Astro.url.pathname + Astro.url.search;
    return { kind: 'redirect', response: Astro.redirect(target, 303) };
  } catch (error) {
    if (error instanceof FormError) {
      Astro.response.status = 422;
      return { kind: 'error', error: error.message, values, action };
    }
    console.error(error);
    Astro.response.status = 500;
    return { kind: 'error', error: 'Ocurrió un error inesperado. Intente de nuevo.', values, action };
  }
}

/** Valores de texto del formulario, sin espacios sobrantes. */
export function formValues(form: FormData): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of form.entries()) {
    if (typeof value === 'string') out[key] = value.trim();
  }
  return out;
}

/** Valida el formulario con Zod; los campos vacíos llegan como undefined. */
export function parseForm<S extends z.ZodType>(schema: S, form: FormData): z.infer<S> {
  const raw: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(formValues(form))) {
    raw[key] = value === '' ? undefined : value;
  }
  const result = schema.safeParse(raw);
  if (!result.success) {
    const issue = result.error.issues[0];
    const field = issue?.path?.[0];
    const label = typeof field === 'string' ? FIELD_LABELS[field] : undefined;
    throw new FormError(label ? `${label}: ${issue?.message}` : (issue?.message ?? 'Datos inválidos.'));
  }
  return result.data;
}

type Nullified<T> = { [K in keyof T]-?: undefined extends T[K] ? Exclude<T[K], undefined> | null : T[K] };

/** Convierte los campos opcionales vacíos en null para poder limpiarlos en un UPDATE. */
export function nullify<T extends Record<string, unknown>>(obj: T): Nullified<T> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(obj)) out[key] = value === undefined ? null : value;
  return out as Nullified<T>;
}

/**
 * Lanza FormError con un mensaje en español si la consulta falló.
 * Con `.single()` el dato siempre existe cuando no hay error.
 */
export function ensure<R extends { data: unknown; error: PostgrestError | null }>(result: R): NonNullable<R['data']> {
  if (result.error) throw new FormError(dbErrorMessage(result.error));
  return result.data as NonNullable<R['data']>;
}

// ---------------------------------------------------------------------
// Esquemas reutilizables
// ---------------------------------------------------------------------
export const text = (max = 500) => z.string().max(max);
export const uuid = () => z.guid({ error: 'Seleccione una opción válida' });
export const date = () => z.iso.date({ error: 'Fecha inválida' });
export const time = () => z.iso.time({ error: 'Hora inválida' });
export const int = () => z.coerce.number().int({ error: 'Debe ser un número entero' });
export const checkbox = () =>
  z.preprocess((v) => v === 'on' || v === 'true' || v === true, z.boolean());

// ---------------------------------------------------------------------
// Errores de base de datos → mensajes para el usuario
// ---------------------------------------------------------------------
const FIELD_LABELS: Record<string, string> = {
  name: 'Nombre',
  nit: 'NIT',
  nit_dv: 'DV',
  sector: 'Sector',
  total_employees: 'Total de empleados',
  website: 'Sitio web',
  email: 'Correo',
  password: 'Contraseña',
  full_name: 'Nombre completo',
  role_title: 'Cargo',
  phone_whatsapp: 'Teléfono / WhatsApp',
  deal_name_branch: 'Nombre del negocio',
  target_employees_n: 'Empleados a atender (N)',
  next_action: 'Siguiente acción',
  next_action_due_date: 'Fecha de la siguiente acción',
  interaction_note: 'Detalle de la interacción',
  max_installments: 'Máximo de cuotas',
  document_name: 'Nombre del documento',
  document_id: 'Documento de identidad',
  session_date: 'Fecha de la sesión',
  start_time: 'Hora de inicio',
  end_time: 'Hora de fin',
  cancel_reason: 'Motivo',
  value: 'Valor',
  document_type: 'Tipo de documento',
  phone: 'Teléfono',
  installments_count: 'Número de cuotas',
  first_due_date: 'Fecha de la primera cuota',
  item_type: 'Tipo de ítem',
  frame_description: 'Montura',
  lens_type: 'Tipo de lente',
  lens_filter: 'Filtro',
  description: 'Descripción',
  quantity: 'Cantidad',
  unit_price: 'Valor unitario',
  prepayment_exception_reason: 'Motivo de la excepción',
  notes: 'Notas',
  lab_provider_id: 'Laboratorio',
  sent_to_lab_at: 'Fecha de envío',
  promised_date: 'Fecha prometida',
  ready_at: 'Fecha real de listo',
  receiver_name: 'Quién recibe',
  delivered_at: 'Fecha de entrega',
  resolution: 'Solución aplicada',
  responsible_user_id: 'Responsable',
  alegra_invoice_number: 'Número de factura',
  invoice_date: 'Fecha de la factura',
  invoiced_amount: 'Monto facturado',
  amount_assigned: 'Monto asignado',
  alegra_external_id: 'ID en Alegra',
  payment_date: 'Fecha del pago',
  total_received_bank: 'Valor recibido en bancos',
  bank_reference: 'Referencia bancaria',
  amount_applied: 'Dinero recibido',
  withholding_applied: 'Retención',
};

const UNIQUE_MESSAGES: Record<string, string> = {
  companies_name_normalized_key: 'Ya existe una empresa con esa razón social.',
  companies_nit_key: 'Ya existe una empresa con ese NIT.',
  company_branches_name_key: 'La empresa ya tiene una sede con ese nombre.',
  company_branches_one_main_key: 'La empresa ya tiene una sede principal.',
  campaign_attendance_unique_person: 'Esa persona ya está registrada en esta sesión.',
  cities_name_key: 'Ya existe una ciudad con ese nombre.',
  lab_providers_name_key: 'Ya existe un laboratorio con ese nombre.',
  deal_origins_pkey: 'Ya existe un origen con ese código.',
  users_profiles_email_key: 'Ya existe un usuario con ese correo.',
  buyers_document_key: 'Ya existe un comprador con ese documento.',
  order_productions_one_active_key: 'La orden ya está liberada a producción.',
  order_productions_one_active_warranty_key: 'La garantía ya tiene una reposición en curso.',
  order_delivery_items_unique_item: 'Un ítem aparece dos veces en la misma entrega.',
  alegra_invoices_number_key: 'Ya existe una factura con ese número.',
  alegra_invoice_orders_unique: 'Esa orden ya está vinculada a esta factura; corrija su monto.',
  collections_payments_bank_movement_key: 'Ya está registrado un pago con esa referencia, fecha y valor.',
};

const CHECK_MESSAGES: Record<string, string> = {
  companies_nit_check: 'El NIT debe tener entre 5 y 10 dígitos, sin puntos ni dígito de verificación.',
  companies_nit_dv_valid: 'El dígito de verificación no corresponde al NIT.',
  companies_firm_nit_complete: 'Para confirmar el NIT se requieren el NIT y su dígito de verificación.',
  companies_total_employees_check: 'El total de empleados debe ser mayor que cero.',
  company_branches_one_city: 'Elija una ciudad del catálogo o escriba otra ciudad (solo una de las dos).',
  contacts_has_channel: 'El contacto necesita teléfono/WhatsApp o correo.',
  contacts_email_check: 'El correo no es válido.',
  contacts_phone_whatsapp_check: 'El teléfono no es válido.',
  deals_next_action_required: 'Defina la siguiente acción con fecha y responsable.',
  deals_proposal_data: 'Desde Propuesta Enviada se requieren N y la fecha estimada de cierre.',
  deals_campaign_date: 'Defina la fecha tentativa de jornada.',
  deals_lost_substatus: 'Seleccione el sub-estado del cierre perdido (Nurturing o No Contactar).',
  deals_opportunities_target_employees_n_check: 'N debe ser mayor que cero.',
  agreements_validity: 'La fecha final de vigencia debe ser posterior a la inicial.',
  campaign_sessions_time: 'La hora de fin debe ser posterior a la de inicio.',
  campaigns_cancel_reason: 'Indique el motivo de la cancelación.',
  campaign_attendance_document_id_check: 'El documento debe tener entre 4 y 15 letras o números, sin puntos.',
  users_profiles_active_requires_role: 'Asigne un rol antes de activar al usuario.',
  users_profiles_provider_requires_lab: 'Un usuario de laboratorio necesita un laboratorio asignado.',
  users_profiles_lab_only_for_provider: 'Solo los usuarios de laboratorio tienen laboratorio asignado.',
  buyers_document_id_check: 'El documento debe tener entre 4 y 15 letras o números.',
  buyers_phone_check: 'El teléfono no es válido.',
  buyers_email_check: 'El correo no es válido.',
  orders_payroll_plan: 'El descuento de nómina requiere empresa con convenio, número de cuotas y fecha de la primera cuota.',
  orders_installments_count_check: 'El número de cuotas no es válido.',
  orders_prepayment_exception_cash: 'La excepción de anticipo solo aplica a órdenes de contado.',
  orders_cancel_reason: 'Indique el motivo de la anulación.',
  order_items_described: 'Describa cada ítem: montura, tipo de lente o descripción.',
  order_items_quantity_check: 'La cantidad debe ser mayor que cero.',
  order_items_unit_price_check: 'El valor unitario no puede ser negativo.',
  order_productions_promised: 'La fecha prometida no puede ser anterior a la fecha de envío.',
  order_productions_ready_after_sent: 'La fecha real de listo no puede ser anterior a la fecha de envío.',
  order_productions_cancel_reason: 'Indique el motivo de la cancelación.',
  post_sale_warranties_closed: 'Para cerrar la garantía registre la solución aplicada.',
  post_sale_warranties_description_check: 'Describa el caso.',
  order_delivery_items_quantity_check: 'La cantidad entregada debe ser mayor que cero.',
  alegra_invoices_subject: 'La factura se emite a una empresa o a un comprador (uno de los dos).',
  alegra_invoices_void_reason: 'Indique el motivo de la anulación.',
  alegra_invoices_invoiced_amount_check: 'El monto facturado debe ser mayor que cero.',
  alegra_invoices_alegra_external_id_check: 'El ID de Alegra solo admite letras, números y guiones.',
  alegra_invoice_orders_amount_assigned_check: 'El monto asignado debe ser mayor que cero.',
  collections_payments_payer: 'El pago es de una empresa o de un comprador (uno de los dos).',
  collections_payments_void_reason: 'Indique el motivo de la anulación.',
  collections_payments_total_received_bank_check: 'El valor recibido debe ser mayor que cero.',
  payment_allocations_positive: 'Indique dinero recibido o retención mayor que cero.',
  payment_allocations_void_reason: 'Indique el motivo de la anulación.',
};

/** Reemplaza códigos internos (etapas, estados) por su etiqueta. */
function humanizeCodes(message: string): string {
  const labels: Record<string, string> = {
    ...Object.fromEntries(Object.entries(STAGE_LABELS).map(([k, v]) => [k, v.replace(/^\d\.\s*/, '')])),
    ...AGREEMENT_STATUS_LABELS,
    ...CAMPAIGN_STATUS_LABELS,
    ...PAYMENT_MODALITY_LABELS,
    ...DOC_STATUS_LABELS,
    ...OPS_STATUS_LABELS,
    mensual: 'mensual',
    quincenal: 'quincenal',
  };
  return message.replace(/\b[a-z]+(?:_[a-z]+)+\b|\b(?:borrador|aprobado|cancelado|programada|cerrada|cancelada|prospecto|negociacion)\b/g, (code) =>
    labels[code] ?? code,
  );
}

export function dbErrorMessage(error: Pick<PostgrestError, 'code' | 'message'>): string {
  const constraint = /constraint "([^"]+)"/.exec(error.message)?.[1] ?? '';
  switch (error.code) {
    case 'P0001':
      return humanizeCodes(error.message);
    case '42501':
      return /permission denied|row-level security/i.test(error.message)
        ? 'No tiene permiso para realizar esta acción.'
        : error.message;
    case '23505':
      return UNIQUE_MESSAGES[constraint] ?? 'Ya existe un registro con esos datos.';
    case '23514':
      if (constraint.startsWith('system_settings_')) return 'El valor está fuera del rango permitido.';
      return CHECK_MESSAGES[constraint] ?? 'Algún dato no cumple las reglas del sistema.';
    case '23503':
      return 'Hay una referencia inválida (por ejemplo, una sede o un contacto de otra empresa).';
    case '23502':
      return 'Falta un dato obligatorio.';
    case '22P02':
    case '22007':
    case '22008':
      return 'Hay un dato con formato inválido.';
    case 'PGRST116':
      return 'No se encontró el registro o no tiene permiso para modificarlo.';
    default:
      return 'No se pudo guardar. Revise los datos e intente de nuevo.';
  }
}
