import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from './database.types';
import type { AppRole } from './labels';

type Client = SupabaseClient<Database>;

export async function activeUsers(supabase: Client, roles: AppRole[]) {
  const { data } = await supabase
    .from('users_profiles')
    .select('id, full_name, role')
    .eq('active', true)
    .in('role', roles)
    .order('full_name');
  return data ?? [];
}

export async function operationalCities(supabase: Client) {
  const { data } = await supabase
    .from('cities')
    .select('id, name')
    .eq('active', true)
    .eq('is_operational', true)
    .order('name');
  return data ?? [];
}

export async function allActiveCities(supabase: Client) {
  const { data } = await supabase
    .from('cities')
    .select('id, name, is_operational')
    .eq('active', true)
    .order('name');
  return data ?? [];
}

// N26-05: orden acordado (Referido, Outbound, Evento, Inbound, Otro)
const ORIGIN_ORDER = ['referido', 'llamada_saliente', 'evento', 'inbound_web', 'otro'];

/** Orígenes activos; `keep` conserva el origen actual de una oportunidad aunque esté retirado. */
export async function activeOrigins(supabase: Client, keep?: string | null) {
  const { data } = await supabase.from('deal_origins').select('code, label, active').order('label');
  const rank = (code: string) => (ORIGIN_ORDER.indexOf(code) + 1 || 99);
  return (data ?? [])
    .filter((o) => o.active || o.code === keep)
    .sort((a, b) => rank(a.code) - rank(b.code))
    .map(({ code, label, active }) => ({ code, label: active ? label : `${label} (retirado)` }));
}

/** Nombres activos de un catálogo buscable (sectores, tipos de lente). */
export async function catalogNames(supabase: Client, kind: 'sector' | 'tipo_lente') {
  const { data } = await supabase.from('catalog_items').select('name').eq('kind', kind).eq('active', true).order('name');
  return (data ?? []).map((r) => r.name);
}

/** Quita caracteres que rompen los filtros `or()` de PostgREST. */
export function safeSearch(value: string | null): string {
  return (value ?? '').replace(/[,()*%\\]/g, ' ').trim().slice(0, 80);
}
