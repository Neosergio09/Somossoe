import type { AstroGlobal } from 'astro';
import { setFlash } from './flash';
import { ROLE_LABELS, type AppRole } from './labels';

/** Super administrador: pasa todas las guardas de rol y de propiedad (igual que en la BD). */
export function isSuperadmin(locals: App.Locals): boolean {
  return !!locals.profile?.active && locals.profile.role === 'superadmin';
}

/** Roles que pueden usar "Ver como" (previsualizar la interfaz de otro rol). */
export function canUseViewAs(role: AppRole | null | undefined): boolean {
  return role === 'direccion' || role === 'superadmin';
}

/** Para mostrar u ocultar controles; la autorización real la hace la BD (RLS). */
export function hasRole(locals: App.Locals, ...roles: AppRole[]): boolean {
  const role = locals.profile?.role;
  if (!role || !locals.profile?.active) return false;
  return role === 'superadmin' || roles.includes(role);
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
  if (isSuperadmin(locals)) return true;
  if (assignedUserId == null) return allowUnassigned;
  return assignedUserId === locals.userId;
}

/**
 * Guarda de pantallas de creación: si el rol no corresponde, vuelve a `back`
 * con un aviso. Solo es interfaz; la BD (RLS) sigue siendo la que autoriza.
 */
export function denyUnless(Astro: AstroGlobal, back: string, ...roles: AppRole[]): Response | null {
  if (hasRole(Astro.locals, ...roles)) return null;
  const who = roles.map((r) => ROLE_LABELS[r]).join(' o ');
  setFlash(Astro.cookies, { type: 'error', message: `Esta acción le corresponde a ${who}.` });
  return Astro.redirect(back);
}
