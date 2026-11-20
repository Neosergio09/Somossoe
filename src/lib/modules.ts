// Módulos que aparecen en el menú y en Ctrl K según el rol (SRS §3.1).
// Solo ordena la interfaz: las páginas de consulta siguen abiertas porque la
// matriz §3.2 da lectura a casi todo, y la BD (RLS) es la que autoriza.
import type { AppRole } from './labels';

export type ModuleKey =
  | 'empresas'
  | 'oportunidades'
  | 'convenios'
  | 'jornadas'
  | 'ordenes'
  | 'produccion'
  | 'posventa'
  | 'facturas'
  | 'recaudo';

const ALL: ModuleKey[] = ['empresas', 'oportunidades', 'convenios', 'jornadas', 'ordenes', 'produccion', 'posventa', 'facturas', 'recaudo'];

export const ROLE_MODULES: Record<AppRole, ModuleKey[]> = {
  comercial: ['empresas', 'oportunidades', 'convenios', 'jornadas', 'ordenes'],
  operacion: ['jornadas', 'ordenes', 'produccion', 'posventa'],
  administracion_cartera: ['empresas', 'convenios', 'ordenes', 'facturas', 'recaudo'],
  direccion: ALL,
  socio: ALL,
  proveedor_lab: [],
};

export function canSeeModule(locals: App.Locals, key: ModuleKey): boolean {
  const role = locals.profile?.active ? locals.profile.role : null;
  return !!role && ROLE_MODULES[role].includes(key);
}
