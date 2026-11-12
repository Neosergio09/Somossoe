import type { APIRoute } from 'astro';
import { isSupportPath, SUPPORT_BUCKET } from '../../../lib/supports';

/**
 * Abre un soporte con un enlace firmado de 5 minutos. Storage solo lo
 * firma si el usuario puede ver el registro que lo referencia (RLS), y la
 * consulta queda registrada (RNF-05).
 */
export const GET: APIRoute = async ({ url, locals, redirect }) => {
  if (!locals.profile?.active) return new Response('Sesión no válida.', { status: 401 });
  const path = url.searchParams.get('ruta');
  if (!isSupportPath(path)) return new Response('Soporte no válido.', { status: 400 });

  const { data, error } = await locals.supabase.storage.from(SUPPORT_BUCKET).createSignedUrl(path, 300);
  if (error || !data) return new Response('No tiene acceso a este soporte o ya no existe.', { status: 403 });

  const { error: logError } = await locals.supabase.rpc('log_support_access', { p_path: path });
  if (logError) return new Response('No tiene acceso a este soporte.', { status: 403 });

  return redirect(data.signedUrl, 302);
};
