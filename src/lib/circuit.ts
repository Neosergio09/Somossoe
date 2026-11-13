import type { AppRole } from './labels';

/** Resumen del circuito (public.circuit_summary); cada rol ve lo que su RLS permite. */
export type CircuitSummary = {
  vender: { abiertas: number; quietas: number };
  convenios_por_aprobar: number;
  jornada: { en_ejecucion: number; por_ejecutar: number; captura_cerrada: number };
  orden: { por_verificar: number; por_liberar: number };
  producir: { en_lab: number; atrasadas: number };
  entregar: { listas: number; parciales: number };
  posventa: number;
  facturar: { sin_factura: number; diferencias: number };
  cobrar: {
    saldo: number;
    vencidas: number;
    monto_vencido: number;
    proximas: number;
    pagos_sin_asignar: number;
    reclasificaciones: number;
  };
};

export const EMPTY_SUMMARY: CircuitSummary = {
  vender: { abiertas: 0, quietas: 0 },
  convenios_por_aprobar: 0,
  jornada: { en_ejecucion: 0, por_ejecutar: 0, captura_cerrada: 0 },
  orden: { por_verificar: 0, por_liberar: 0 },
  producir: { en_lab: 0, atrasadas: 0 },
  entregar: { listas: 0, parciales: 0 },
  posventa: 0,
  facturar: { sin_factura: 0, diferencias: 0 },
  cobrar: { saldo: 0, vencidas: 0, monto_vencido: 0, proximas: 0, pagos_sin_asignar: 0, reclasificaciones: 0 },
};

export async function loadSummary(supabase: App.Locals['supabase']): Promise<CircuitSummary> {
  const { data, error } = await supabase.rpc('circuit_summary');
  if (error || !data) return EMPTY_SUMMARY;
  return data as unknown as CircuitSummary;
}

/** Roles que ven facturación y cartera (Operación no, matriz §3.2). */
export const MONEY_ROLES: AppRole[] = ['administracion_cartera', 'direccion', 'comercial', 'socio'];
