// "Ver como": Dirección puede previsualizar el CRM con los menús, botones y
// pantallas de otro rol. Solo cambia la interfaz: la sesión, la RLS y los
// datos siguen siendo los de Dirección, y mientras está activo no se guarda nada.
import type { AppRole } from './labels';

export const VIEW_AS_COOKIE = 'view_as';

/** Roles que se pueden previsualizar (Laboratorio no tiene pantallas propias). */
export const VIEW_AS_ROLES: AppRole[] = ['comercial', 'operacion', 'administracion_cartera', 'costos', 'socio'];

export function isViewAsRole(value: unknown): value is AppRole {
  return typeof value === 'string' && (VIEW_AS_ROLES as string[]).includes(value);
}

/** Ruta interna segura para volver tras cambiar de vista. */
export function safeBackPath(value: unknown): string {
  return typeof value === 'string' && value.startsWith('/') && !value.startsWith('//') ? value : '/';
}
