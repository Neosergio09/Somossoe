// Perfiles visibles (SRS 1.6 §3.3). Un perfil es solo una plantilla de
// roles: los permisos los decide la BD por rol (private.has_role), nunca
// por el nombre del perfil.
import { ROLE_LABELS, type AppRole } from './labels';

export type ProfileKey = 'comercial' | 'gestion';

export const PROFILES: Record<ProfileKey, { label: string; role: AppRole; extra: AppRole[]; description: string }> = {
  comercial: {
    label: 'Comercial',
    role: 'comercial',
    extra: [],
    description: 'Empresas, oportunidades, convenios, apoyo en jornadas y ventas.',
  },
  gestion: {
    label: 'Gestión',
    role: 'operacion',
    extra: ['administracion_cartera', 'costos'],
    description: 'Jornadas, producción, entrega, facturación, recaudo y costos.',
  },
};

/** Roles que se pueden sumar como adicionales (la BD rechaza los demás). */
export const EXTRA_ROLE_OPTIONS: AppRole[] = ['comercial', 'operacion', 'administracion_cartera', 'costos'];

function sameRoles(a: AppRole[], b: AppRole[]): boolean {
  return a.length === b.length && [...a].sort().every((r, i) => r === [...b].sort()[i]);
}

/** Perfil visible que corresponde a los roles del usuario, si coincide con una plantilla. */
export function profileOf(role: AppRole | null | undefined, extra: AppRole[] = []): ProfileKey | null {
  if (!role) return null;
  for (const [key, p] of Object.entries(PROFILES) as [ProfileKey, (typeof PROFILES)[ProfileKey]][]) {
    if (p.role === role && sameRoles(p.extra, extra)) return key;
  }
  return null;
}

/** Nombre a mostrar: el perfil si coincide; si no, el rol y sus adicionales. */
export function rolesLabel(role: AppRole | null | undefined, extra: AppRole[] = []): string {
  if (!role) return 'Sin rol';
  const key = profileOf(role, extra);
  if (key) return PROFILES[key].label;
  return [role, ...extra].map((r) => ROLE_LABELS[r]).join(' + ');
}
