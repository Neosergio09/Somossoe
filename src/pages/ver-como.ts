import type { APIRoute } from 'astro';
import { isViewAsRole, safeBackPath, VIEW_AS_COOKIE } from '../lib/viewAs';

/** Activa o quita la vista "Ver como" (solo Dirección). */
export const POST: APIRoute = async ({ locals, request, cookies, redirect }) => {
  const realRole = locals.realRole ?? locals.profile?.role;
  if (!locals.profile?.active || realRole !== 'direccion') {
    return new Response('No autorizado', { status: 403 });
  }

  const form = await request.formData();
  const role = form.get('role');
  if (isViewAsRole(role)) {
    cookies.set(VIEW_AS_COOKIE, role, { path: '/', httpOnly: true, sameSite: 'lax', secure: import.meta.env.PROD });
  } else {
    cookies.delete(VIEW_AS_COOKIE, { path: '/' });
  }
  return redirect(safeBackPath(form.get('back')), 303);
};
