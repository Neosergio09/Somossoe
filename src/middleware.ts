import { defineMiddleware } from 'astro:middleware';
import { createSupabaseServerClient } from './lib/supabase';

const PUBLIC_PATHS = new Set(['/login']);
const INACTIVE_ALLOWED = new Set(['/pendiente', '/logout']);

function redirect(location: string) {
  return new Response(null, { status: 303, headers: { Location: location } });
}

export const onRequest = defineMiddleware(async (context, next) => {
  const pendingHeaders = new Headers();
  const supabase = createSupabaseServerClient(context.request, context.cookies, pendingHeaders);
  context.locals.supabase = supabase;
  context.locals.userId = null;
  context.locals.profile = null;

  const path = context.url.pathname;
  const isAsset = path.startsWith('/_astro') || path.startsWith('/favicon');

  if (isAsset) {
    return next();
  }

  const { data } = await supabase.auth.getClaims();
  const userId = data?.claims?.sub ?? null;

  if (userId) {
    context.locals.userId = userId;
    const { data: profile } = await supabase
      .from('users_profiles')
      .select('id, full_name, email, role, active')
      .eq('id', userId)
      .maybeSingle();
    context.locals.profile = profile;
  }

  let response: Response;
  if (!userId && !PUBLIC_PATHS.has(path)) {
    response = redirect('/login');
  } else if (userId && !context.locals.profile?.active && !INACTIVE_ALLOWED.has(path)) {
    response = redirect('/pendiente');
  } else if (userId && context.locals.profile?.active && path === '/login') {
    response = redirect('/');
  } else {
    response = await next();
  }

  // Páginas con datos de sesión: nunca en caché compartida
  response.headers.set('Cache-Control', 'private, no-store');
  pendingHeaders.forEach((value, key) => response.headers.set(key, value));
  return response;
});
