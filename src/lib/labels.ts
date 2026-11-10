import type { Database } from './database.types';

type Enums = Database['public']['Enums'];
export type AppRole = Enums['app_role'];
export type DealStage = Enums['deal_stage'];

export const ROLE_LABELS: Record<AppRole, string> = {
  comercial: 'Comercial',
  operacion: 'Operación',
  administracion_cartera: 'Administración / Cartera',
  direccion: 'Dirección',
  proveedor_lab: 'Laboratorio',
};

export const STAGE_LABELS: Record<DealStage, string> = {
  prospecto: '1. Prospecto',
  reunion_exploratoria: '2. Reunión Exploratoria',
  propuesta_enviada: '3. Propuesta Enviada',
  negociacion: '4. Negociación',
  convenio_firmado: '5. Convenio Firmado',
  jornada_en_ejecucion: '6. Jornada en Ejecución',
  facturacion_cerrada: '7. Facturación Cerrada',
  cierre_perdido: '8. Cierre Perdido',
};

export const KANBAN_STAGES: DealStage[] = [
  'prospecto',
  'reunion_exploratoria',
  'propuesta_enviada',
  'negociacion',
  'convenio_firmado',
  'jornada_en_ejecucion',
  'facturacion_cerrada',
];

/** Etapas que se pueden elegir a mano (6 y 7 son automáticas). */
export const MANUAL_STAGES: DealStage[] = [
  'prospecto',
  'reunion_exploratoria',
  'propuesta_enviada',
  'negociacion',
  'convenio_firmado',
  'cierre_perdido',
];

export const LOST_LABELS: Record<Enums['lost_substatus'], string> = {
  nurturing: 'Nurturing (re-contacto futuro)',
  no_contactar: 'No Contactar (descarte definitivo)',
};

export const INTERACTION_LABELS: Record<Enums['interaction_type'], string> = {
  reunion: 'Reunión',
  llamada: 'Llamada',
  whatsapp: 'WhatsApp',
  correo: 'Correo',
};

export const PAYROLL_LABELS: Record<Enums['payroll_frequency'], string> = {
  mensual: 'Mensual',
  quincenal: 'Quincenal',
};

export const AREA_LABELS: Record<Enums['contact_area'], string> = {
  rrhh: 'RRHH',
  sst: 'SST',
  gerencia: 'Gerencia',
  compras: 'Compras',
  otra: 'Otra',
};

export const AGREEMENT_STATUS_LABELS: Record<string, string> = {
  borrador: 'Borrador',
  pendiente_aprobacion: 'Pendiente de aprobación',
  aprobado: 'Aprobado',
  vencido: 'Vencido',
  cancelado: 'Cancelado',
};

export const AGREEMENT_STATUS_BADGE: Record<string, string> = {
  borrador: 'badge',
  pendiente_aprobacion: 'badge badge-amber',
  aprobado: 'badge badge-green',
  vencido: 'badge badge-red',
  cancelado: 'badge badge-red',
};

export const DOCUMENT_TYPE_LABELS: Record<Enums['agreement_document_type'], string> = {
  convenio_firmado: 'Convenio firmado',
  camara_comercio: 'Cámara de comercio',
  rut: 'RUT',
  formato_rrhh: 'Formato RRHH',
  otro: 'Otro',
};

export const CAMPAIGN_STATUS_LABELS: Record<Enums['campaign_status'], string> = {
  programada: 'Programada',
  en_ejecucion: 'En ejecución',
  cerrada: 'Cerrada',
  cancelada: 'Cancelada',
};

export const CAMPAIGN_STATUS_BADGE: Record<Enums['campaign_status'], string> = {
  programada: 'badge badge-blue',
  en_ejecucion: 'badge badge-amber',
  cerrada: 'badge badge-green',
  cancelada: 'badge badge-red',
};
