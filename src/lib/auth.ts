import type { AppRole } from './labels';

/** Para mostrar u ocultar controles; la autorización real la hace la BD (RLS). */
export function hasRole(locals: App.Locals, ...roles: AppRole[]): boolean {
  const role = locals.profile?.role;
  return !!role && !!locals.profile?.active && roles.includes(role);
}
