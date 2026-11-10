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

export async function activeOrigins(supabase: Client) {
  const { data } = await supabase.from('deal_origins').select('code, label').eq('active', true).order('label');
  return data ?? [];
}

/** Quita caracteres que rompen los filtros `or()` de PostgREST. */
export function safeSearch(value: string | null): string {
  return (value ?? '').replace(/[,()*%\\]/g, ' ').trim().slice(0, 80);
}
