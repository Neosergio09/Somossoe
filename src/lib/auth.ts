import type { AstroGlobal } from 'astro';
import { setFlash } from './flash';
import type { AppRole } from './labels';

/**
 * Acceso total (27-nov-2026): Super administrador o cualquier usuario con el
 * rol Comercial. Pasa todas las guardas de rol y de propiedad (igual que
 * private.has_full_access en la BD), salvo la gestión de usuarios.
 */
export function hasFullAccess(locals: App.Locals): boolean {
  const p = locals.profile;
  if (!p?.active || !p.role) return false;
  return p.role === 'superadmin' || [p.role, ...(p.extra_roles ?? [])].includes('comercial');
}

/** Gestión de usuarios: solo Super administrador y Dirección (private.can_manage_users). */
export function canManageUsers(locals: App.Locals): boolean {
  const p = locals.profile;
  return !!p?.active && (p.role === 'superadmin' || p.role === 'direccion');
}

/** «Ver como» está oculto para todos (27-nov-2026). */
export function canUseViewAs(_role: AppRole | null | undefined): boolean {
  return false;
}

/** Rol principal más roles adicionales del usuario activo (SRS 1.6 §3.3). */
export function userRoles(locals: App.Locals): AppRole[] {
  const p = locals.profile;
  if (!p?.active || !p.role) return [];
  return [p.role, ...(p.extra_roles ?? [])];
}

/**
 * Para mostrar u ocultar controles: verdadero si alguno de los roles del
 * usuario coincide (igual que private.has_role). La autorización real la hace la BD (RLS).
 */
export function hasRole(locals: App.Locals, ...roles: AppRole[]): boolean {
  const mine = userRoles(locals);
  return hasFullAccess(locals) || mine.some((r) => roles.includes(r));
}

/**
 * Comercial dueño del registro: es el ejecutivo asignado o (si se permite)
 * el registro no tiene ejecutivo. La regla real la aplica la BD (RLS).
 */
export function isOwnerComercial(
  locals: App.Locals,
  assignedUserId: string | null | undefined,
  { allowUnassigned = false } = {},
): boolean {
  if (!hasRole(locals, 'comercial')) return false;
  if (hasFullAccess(locals)) return true;
  if (assignedUserId == null) return allowUnassigned;
  return assignedUserId === locals.userId;
}

/**
 * Guarda de pantallas de creación: si el rol no corresponde, vuelve a `back`
 * con un aviso. Solo es interfaz; la BD (RLS) sigue siendo la que autoriza.
 */
export function denyUnless(Astro: AstroGlobal, back: string, ...roles: AppRole[]): Response | null {
  if (hasRole(Astro.locals, ...roles)) return null;
  // Sin nombres de roles: los roles están ocultos para todos (27-nov-2026)
  setFlash(Astro.cookies, { type: 'error', message: 'Su usuario no tiene permiso para esta acción.' });
  return Astro.redirect(back);
}
