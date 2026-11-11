/**
 * Integración con Alegra (RF-M06-01 F2): consulta de solo lectura de una
 * factura para traer su total y estado y señalar diferencias.
 *
 * Queda desactivada mientras no existan ALEGRA_API_USER y ALEGRA_API_TOKEN.
 * Al activar la cuenta, validar contra la documentación vigente de la API
 * de Alegra: autenticación Basic (correo:token), ruta GET /invoices/{id} y
 * los nombres de campos que se leen en `toSnapshot`.
 */
import { ALEGRA_API_TOKEN, ALEGRA_API_URL, ALEGRA_API_USER } from 'astro:env/server';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from './database.types';
import { createSupabaseAdminClient } from './supabase';

export class AlegraError extends Error {}

export type AlegraInvoiceSnapshot = {
  externalId: string;
  number: string | null;
  date: string | null;
  total: number | null;
  status: string | null;
};

export function alegraEnabled(): boolean {
  return !!ALEGRA_API_USER && !!ALEGRA_API_TOKEN;
}

function authHeader(): string {
  const raw = new TextEncoder().encode(`${ALEGRA_API_USER}:${ALEGRA_API_TOKEN}`);
  return `Basic ${btoa(String.fromCharCode(...raw))}`;
}

function toSnapshot(externalId: string, json: Record<string, unknown>): AlegraInvoiceSnapshot {
  const template = json.numberTemplate as { fullNumber?: unknown } | undefined;
  const total = json.total == null ? null : Number(json.total);
  return {
    externalId,
    number: typeof template?.fullNumber === 'string' ? template.fullNumber : null,
    date: typeof json.date === 'string' ? json.date : null,
    total: total == null || Number.isNaN(total) ? null : Math.round(total),
    status: typeof json.status === 'string' ? json.status : null,
  };
}

/** Consulta una factura en Alegra por su ID interno. */
export async function fetchAlegraInvoice(externalId: string): Promise<AlegraInvoiceSnapshot> {
  if (!alegraEnabled()) throw new AlegraError('La integración con Alegra no está configurada.');
  let response: Response;
  try {
    response = await fetch(`${ALEGRA_API_URL.replace(/\/$/, '')}/invoices/${encodeURIComponent(externalId)}`, {
      headers: { Authorization: authHeader(), Accept: 'application/json' },
      signal: AbortSignal.timeout(10_000),
    });
  } catch {
    throw new AlegraError('No se pudo conectar con Alegra.');
  }
  if (response.status === 401 || response.status === 403) throw new AlegraError('Alegra rechazó las credenciales.');
  if (response.status === 404) throw new AlegraError('La factura no existe en Alegra con ese ID.');
  if (!response.ok) throw new AlegraError(`Alegra respondió con error ${response.status}.`);
  return toSnapshot(externalId, (await response.json()) as Record<string, unknown>);
}

/**
 * Sincroniza una factura: la lee con la sesión del usuario (RLS), consulta
 * Alegra y guarda el resultado con la clave secreta (los campos de
 * sincronización no son editables desde la app).
 */
export async function syncInvoiceWithAlegra(
  supabase: SupabaseClient<Database>,
  invoiceId: string,
  userId: string,
): Promise<{ ok: boolean; message: string }> {
  const { data: invoice } = await supabase
    .from('alegra_invoices')
    .select('id, alegra_external_id, invoiced_amount')
    .eq('id', invoiceId)
    .maybeSingle();
  if (!invoice) throw new AlegraError('Factura no encontrada.');
  if (!invoice.alegra_external_id) throw new AlegraError('Registre el ID de la factura en Alegra para consultarla.');

  const admin = createSupabaseAdminClient();
  try {
    const snapshot = await fetchAlegraInvoice(invoice.alegra_external_id);
    await admin
      .from('alegra_invoices')
      .update({
        alegra_status: snapshot.status,
        alegra_total: snapshot.total,
        alegra_synced_at: new Date().toISOString(),
        alegra_sync_error: null,
      })
      .eq('id', invoiceId);
    const differs = snapshot.total != null && snapshot.total !== Number(invoice.invoiced_amount);
    const message = differs
      ? `Alegra reporta un total de ${snapshot.total} distinto del registrado.`
      : 'Factura consultada en Alegra sin diferencias.';
    await admin.from('alegra_sync_events').insert({
      invoice_id: invoiceId,
      ok: true,
      alegra_status: snapshot.status,
      alegra_total: snapshot.total,
      message,
      requested_by: userId,
    });
    return { ok: !differs, message };
  } catch (error) {
    const message = error instanceof AlegraError ? error.message : 'Error inesperado al consultar Alegra.';
    if (!(error instanceof AlegraError)) console.error(error);
    await admin.from('alegra_invoices').update({ alegra_sync_error: message }).eq('id', invoiceId);
    await admin.from('alegra_sync_events').insert({ invoice_id: invoiceId, ok: false, message, requested_by: userId });
    throw new AlegraError(message);
  }
}
