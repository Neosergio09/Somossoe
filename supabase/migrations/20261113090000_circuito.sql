-- =====================================================================
-- Rediseño "Circuito SOE": resumen del circuito para el inicio y los
-- contadores de la barra lateral. Solo agrega una función de lectura
-- (no cambia datos ni reglas): volver a la disposición anterior no exige
-- revertir esta migración.
-- SECURITY INVOKER: cada rol cuenta solo lo que su RLS le deja ver.
-- =====================================================================

create function public.circuit_summary()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'vender', jsonb_build_object(
      'abiertas', (select count(*) from public.deals_opportunities d
                   where d.stage between 'prospecto' and 'convenio_firmado'),
      'quietas', (select count(*) from public.v_deals_board d
                  where d.stage between 'prospecto' and 'convenio_firmado'
                    and (d.inactivity_alert or d.next_action_overdue))
    ),
    'convenios_por_aprobar', (select count(*) from public.agreements_convenios a where a.status = 'pendiente_aprobacion'),
    'jornada', jsonb_build_object(
      'en_ejecucion', (select count(*) from public.campaigns_jornadas j where j.status = 'en_ejecucion'),
      'por_ejecutar', (select count(*) from public.campaigns_jornadas j where j.status in ('borrador', 'programada')),
      'captura_cerrada', (select count(*) from public.campaigns_jornadas j where j.status = 'captura_cerrada')
    ),
    'orden', jsonb_build_object(
      'por_verificar', (select count(*) from public.orders o where not o.is_cancelled and o.doc_status = 'pendiente_soportes'),
      'por_liberar', (select count(*) from public.orders o
                      where not o.is_cancelled and o.doc_status = 'requisitos_verificados' and o.ops_status = 'pendiente_liberar')
    ),
    'producir', jsonb_build_object(
      'en_lab', (select count(*) from public.order_productions p where p.status = 'en_produccion'),
      'atrasadas', (select count(*) from public.order_productions p
                    where p.status = 'en_produccion' and p.promised_date < private.today_co())
    ),
    'entregar', jsonb_build_object(
      'listas', (select count(*) from public.orders o where not o.is_cancelled and o.ops_status = 'listo_para_entregar'),
      'parciales', (select count(*) from public.orders o where not o.is_cancelled and o.ops_status = 'entrega_parcial')
    ),
    'posventa', (select count(*) from public.post_sale_warranties w where w.status <> 'cerrada'),
    'facturar', jsonb_build_object(
      'sin_factura', (select count(*) from public.v_orders_to_invoice),
      'diferencias', (select count(*) from public.orders o
                      where not o.is_cancelled and o.accounting_status = 'factura_con_diferencia')
    ),
    'cobrar', jsonb_build_object(
      'saldo', (select coalesce(sum(o.balance_due), 0) from public.orders o where not o.is_cancelled),
      'vencidas', (select count(*) from public.v_installments_due i where i.due_date <= private.today_co()),
      'monto_vencido', (select coalesce(sum(i.pending_amount), 0) from public.v_installments_due i
                        where i.due_date <= private.today_co()),
      'proximas', (select count(*) from public.v_installments_due i
                   where i.due_date > private.today_co() and i.due_date <= private.today_co() + 7),
      'pagos_sin_asignar', (select count(*) from public.v_payments p where not p.is_voided and p.unassigned_amount > 0),
      'reclasificaciones', (select count(*) from public.portfolio_reclassifications r where r.status = 'pendiente')
    )
  );
$$;

revoke execute on function public.circuit_summary() from public, anon;
grant execute on function public.circuit_summary() to authenticated;
