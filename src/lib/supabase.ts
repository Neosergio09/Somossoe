import { createServerClient, parseCookieHeader } from '@supabase/ssr';
import { createClient } from '@supabase/supabase-js';
import type { AstroCookies, AstroCookieSetOptions } from 'astro';
import { PUBLIC_SUPABASE_PUBLISHABLE_KEY, PUBLIC_SUPABASE_URL } from 'astro:env/client';
import { SUPABASE_SECRET_KEY } from 'astro:env/server';
import type { Database } from './database.types';

/**
 * Cliente por petición con la sesión del usuario (cookies).
 * Las cabeceras de caché que pide @supabase/ssr se acumulan en
 * `responseHeaders` y el middleware las aplica a la respuesta.
 */
export function createSupabaseServerClient(
  request: Request,
  cookies: AstroCookies,
  responseHeaders: Headers,
) {
  return createServerClient<Database>(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_PUBLISHABLE_KEY, {
    cookies: {
      getAll() {
        return parseCookieHeader(request.headers.get('Cookie') ?? '').map((c) => ({
          name: c.name,
          value: c.value ?? '',
        }));
      },
      setAll(cookiesToSet, headers) {
        for (const { name, value, options } of cookiesToSet) {
          cookies.set(name, value, options as AstroCookieSetOptions);
        }
        for (const [key, value] of Object.entries(headers ?? {})) {
          responseHeaders.set(key, value);
        }
      },
    },
  });
}

/**
 * Cliente con la clave secreta: solo en servidor y solo después de
 * comprobar que quien llama es Dirección (alta de usuarios).
 */
export function createSupabaseAdminClient() {
  return createClient<Database>(PUBLIC_SUPABASE_URL, SUPABASE_SECRET_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
