import type { Database } from './database.types';

type Enums = Database['public']['Enums'];
export type AppRole = Enums['app_role'];
export type DealStage = Enums['deal_stage'];

export const ROLE_LABELS: Record<AppRole, string> = {
  comercial: 'Comercial',
  operacion: 'Operación',
  administracion_cartera: 'Administración / Cartera',
  direccion: 'Dirección',
  socio: 'Socio (consulta)',
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

export type CampaignStatus = Enums['campaign_status'];

export const CAMPAIGN_STATUS_LABELS: Record<CampaignStatus, string> = {
  borrador: 'Borrador',
  programada: 'Programada',
  en_ejecucion: 'En ejecución',
  captura_cerrada: 'Captura cerrada',
  operacion_cerrada: 'Operación cerrada',
  cancelada: 'Cancelada',
};

export const CAMPAIGN_STATUS_BADGE: Record<CampaignStatus, string> = {
  borrador: 'badge',
  programada: 'badge badge-blue',
  en_ejecucion: 'badge badge-amber',
  captura_cerrada: 'badge badge-blue',
  operacion_cerrada: 'badge badge-green',
  cancelada: 'badge badge-red',
};

/** Jornadas que todavía requieren gestión (no cerradas ni canceladas). */
export const ACTIVE_CAMPAIGN_STATUSES: CampaignStatus[] = ['borrador', 'programada', 'en_ejecucion', 'captura_cerrada'];

export type AttendanceStatus = Enums['attendance_status'];

export const ATTENDANCE_STATUS_LABELS: Record<AttendanceStatus, string> = {
  agendado: 'Agendado',
  presente: 'Presente',
  atendido: 'Atendido',
  no_asistio: 'No asistió',
  cancelado: 'Cancelado',
};

export const ATTENDANCE_STATUS_BADGE: Record<AttendanceStatus, string> = {
  agendado: 'badge badge-blue',
  presente: 'badge badge-amber',
  atendido: 'badge badge-green',
  no_asistio: 'badge',
  cancelado: 'badge badge-red',
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

// ---------------------------------------------------------------------
// M06 Facturación
// ---------------------------------------------------------------------
export const RADICATION_LABELS: Record<Enums['invoice_radication_status'], string> = {
  pendiente: 'Radicación pendiente',
  radicada: 'Radicada',
  rechazada: 'Rechazada',
};

export const RADICATION_BADGE: Record<Enums['invoice_radication_status'], string> = {
  pendiente: 'badge badge-amber',
  radicada: 'badge badge-green',
  rechazada: 'badge badge-red',
};

// ---------------------------------------------------------------------
// Costos directos (solo Dirección y Socio)
// ---------------------------------------------------------------------
export type CostComponent = Enums['cost_component'];
export type CostBasis = Enums['cost_basis'];

export const COST_COMPONENT_LABELS: Record<CostComponent, string> = {
  lente: 'Lente',
  montura: 'Montura',
  kit: 'Kit',
  otro: 'Otro',
};

export const COST_BASIS_LABELS: Record<CostBasis, string> = {
  estimado: 'Estimado',
  verificado: 'Verificado',
};

export const COST_BASIS_BADGE: Record<CostBasis, string> = {
  estimado: 'badge badge-amber',
  verificado: 'badge badge-green',
};

/** Estado del margen: sin costos no hay margen (nunca se asume cero). */
export const MARGIN_BASIS_LABELS: Record<string, string> = {
  sin_costos: 'Sin costos',
  estimado: 'Estimado',
  verificado: 'Verificado',
};

export const MARGIN_BASIS_BADGE: Record<string, string> = {
  sin_costos: 'badge',
  estimado: 'badge badge-amber',
  verificado: 'badge badge-green',
};

// ---------------------------------------------------------------------
// M06 Reclasificación de cartera
// ---------------------------------------------------------------------
export type ReclassificationStatus = Enums['reclassification_status'];
export type ReclassificationReason = Enums['reclassification_reason'];

export const RECLASSIFICATION_STATUS_LABELS: Record<ReclassificationStatus, string> = {
  pendiente: 'Pendiente de autorización',
  autorizada: 'Autorizada',
  rechazada: 'Rechazada',
  anulada: 'Anulada',
};

export const RECLASSIFICATION_STATUS_BADGE: Record<ReclassificationStatus, string> = {
  pendiente: 'badge badge-amber',
  autorizada: 'badge badge-green',
  rechazada: 'badge badge-red',
  anulada: 'badge',
};

export const RECLASSIFICATION_REASON_LABELS: Record<ReclassificationReason, string> = {
  retiro: 'Retiro del empleado',
  incapacidad: 'Incapacidad',
  otro: 'Otro',
};
