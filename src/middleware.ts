import { defineMiddleware } from 'astro:middleware';
import { createSupabaseServerClient } from './lib/supabase';
import { canUseViewAs } from './lib/auth';
import { isViewAsRole, VIEW_AS_COOKIE } from './lib/viewAs';

const PUBLIC_PATHS = new Set(['/login']);
const INACTIVE_ALLOWED = new Set(['/pendiente', '/logout']);
const VIEW_AS_WRITE_ALLOWED = new Set(['/ver-como', '/logout']);
const VIEW_AS_BLOCKED = 'Estás en modo «Ver como»: es solo una vista previa. Vuelve a Dirección para guardar cambios.';

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
  const isAsset = path.startsWith('/_astro') || path.startsWith('/favicon') || path.startsWith('/brand/') || path === '/apple-touch-icon.png';

  if (isAsset) {
    return next();
  }

  const { data } = await supabase.auth.getClaims();
  const userId = data?.claims?.sub ?? null;

  if (userId) {
    context.locals.userId = userId;
    const { data: profile } = await supabase
      .from('users_profiles')
      .select('id, full_name, email, role, extra_roles, active')
      .eq('id', userId)
      .maybeSingle();
    context.locals.profile = profile;

    // "Ver como": Dirección (o el superadmin) ve la interfaz de otro rol (la RLS no cambia)
    const viewAs = context.cookies.get(VIEW_AS_COOKIE)?.value;
    if (profile?.active && canUseViewAs(profile.role) && isViewAsRole(viewAs)) {
      context.locals.realRole = profile.role;
      context.locals.viewAs = viewAs;
      context.locals.profile = { ...profile, role: viewAs, extra_roles: [] };
    }
  }

  const isWrite = !['GET', 'HEAD', 'OPTIONS'].includes(context.request.method);
  let response: Response;
  let blockedFlash = false;
  if (context.locals.viewAs && isWrite && !VIEW_AS_WRITE_ALLOWED.has(path)) {
    // Vista previa: no se guarda nada mientras está activa
    if (path.startsWith('/api/')) {
      response = Response.json({ error: VIEW_AS_BLOCKED }, { status: 403 });
    } else {
      response = redirect(path + context.url.search);
      blockedFlash = true;
    }
  } else if (!userId && !PUBLIC_PATHS.has(path)) {
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
  if (blockedFlash) {
    const flash = encodeURIComponent(JSON.stringify({ type: 'error', message: VIEW_AS_BLOCKED }));
    response.headers.append('Set-Cookie', `flash=${flash}; Path=/; Max-Age=60; HttpOnly; SameSite=Lax`);
  }
  return response;
});
