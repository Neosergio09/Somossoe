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

// ---------------------------------------------------------------------
// M04 Órdenes
// ---------------------------------------------------------------------
export type PaymentModality = Enums['payment_modality'];
export type OrderItemType = Enums['order_item_type'];

export const BUYER_DOCUMENT_LABELS: Record<Enums['buyer_document_type'], string> = {
  cc: 'C.C.',
  ce: 'C.E.',
  ti: 'T.I.',
  pasaporte: 'Pasaporte',
  otro: 'Otro',
};

export const PAYMENT_MODALITY_LABELS: Record<PaymentModality, string> = {
  contado: 'Contado',
  nomina_empresa: 'Descuento de nómina',
};

export const COLLECTION_RESPONSIBLE_LABELS: Record<Enums['collection_responsible'], string> = {
  empresa: 'Empresa (nómina)',
  empleado: 'Comprador',
};

export const ITEM_TYPE_LABELS: Record<OrderItemType, string> = {
  gafas_completas: 'Gafas completas',
  montura: 'Montura',
  lentes: 'Lentes',
  otro: 'Otro',
};

export const DOC_STATUS_LABELS: Record<Enums['order_doc_status'], string> = {
  pendiente_soportes: 'Pendiente de soportes',
  requisitos_verificados: 'Requisitos verificados',
};

export const DOC_STATUS_BADGE: Record<Enums['order_doc_status'], string> = {
  pendiente_soportes: 'badge badge-amber',
  requisitos_verificados: 'badge badge-green',
};

export const OPS_STATUS_LABELS: Record<Enums['order_ops_status'], string> = {
  pendiente_liberar: 'Pendiente de liberar',
  en_produccion: 'En producción',
  listo_para_entregar: 'Listo para entregar',
  entrega_parcial: 'Entrega parcial',
  entrega_completa: 'Entrega completa',
};

export const OPS_STATUS_BADGE: Record<Enums['order_ops_status'], string> = {
  pendiente_liberar: 'badge',
  en_produccion: 'badge badge-blue',
  listo_para_entregar: 'badge badge-amber',
  entrega_parcial: 'badge badge-amber',
  entrega_completa: 'badge badge-green',
};

export const ACCOUNTING_STATUS_LABELS: Record<Enums['order_accounting_status'], string> = {
  pendiente_vincular: 'Factura pendiente',
  factura_vinculada: 'Factura vinculada',
  factura_con_diferencia: 'Factura con diferencia',
};

export const ACCOUNTING_STATUS_BADGE: Record<Enums['order_accounting_status'], string> = {
  pendiente_vincular: 'badge',
  factura_vinculada: 'badge badge-green',
  factura_con_diferencia: 'badge badge-red',
};

export const COLLECTION_STATUS_LABELS: Record<Enums['order_collection_status'], string> = {
  con_saldo: 'Con saldo',
  parcialmente_recaudado: 'Recaudo parcial',
  recaudado_total: 'Recaudado',
};

export const COLLECTION_STATUS_BADGE: Record<Enums['order_collection_status'], string> = {
  con_saldo: 'badge',
  parcialmente_recaudado: 'badge badge-amber',
  recaudado_total: 'badge badge-green',
};

export const INSTALLMENT_STATUS_LABELS: Record<string, string> = {
  pendiente: 'Pendiente',
  parcial: 'Parcial',
  pagada: 'Pagada',
  vencida: 'Vencida',
};

export const INSTALLMENT_STATUS_BADGE: Record<string, string> = {
  pendiente: 'badge',
  parcial: 'badge badge-amber',
  pagada: 'badge badge-green',
  vencida: 'badge badge-red',
};

// ---------------------------------------------------------------------
// M05 Cumplimiento
// ---------------------------------------------------------------------
export const PRODUCTION_STATUS_LABELS: Record<Enums['production_status'], string> = {
  en_produccion: 'En producción',
  listo_para_entregar: 'Lista para entregar',
  cancelada: 'Cancelada',
};

export const PRODUCTION_STATUS_BADGE: Record<Enums['production_status'], string> = {
  en_produccion: 'badge badge-blue',
  listo_para_entregar: 'badge badge-green',
  cancelada: 'badge badge-red',
};

export const WARRANTY_STATUS_LABELS: Record<Enums['warranty_status'], string> = {
  abierta: 'Abierta',
  en_reposicion: 'En reposición',
  cerrada: 'Cerrada',
};

export const WARRANTY_STATUS_BADGE: Record<Enums['warranty_status'], string> = {
  abierta: 'badge badge-amber',
  en_reposicion: 'badge badge-blue',
  cerrada: 'badge badge-green',
};

export const WARRANTY_TYPE_LABELS: Record<Enums['warranty_incident_type'], string> = {
  garantia: 'Garantía',
  reclamo: 'Reclamo',
  ajuste: 'Ajuste',
  otro: 'Otro',
};
