-- =====================================================================
-- M07: Control transversal (RF-M07-01 a RF-M07-03) y referencia del
-- pedido en el laboratorio (columna ORDEN del Excel de jornadas).
-- Las pantallas leen las vistas existentes; aquí solo se agrega lo que
-- no se puede armar con ellas.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Referencia del pedido en el laboratorio (texto opaco del proveedor;
--    no es un ID interno ni una factura)
-- ---------------------------------------------------------------------
alter table public.order_productions
  add column lab_order_reference text
    check (lab_order_reference is null or length(trim(lab_order_reference)) between 1 and 60);

create index order_productions_lab_order_reference_idx
  on public.order_productions (lower(lab_order_reference))
  where lab_order_reference is not null;

grant insert (lab_order_reference), update (lab_order_reference) on public.order_productions to authenticated;

create or replace view public.v_productions
with (security_invoker = true)
as
select
  p.id,
  p.order_id,
  o.order_number,
  p.warranty_id,
  p.lab_provider_id,
  l.name as lab_name,
  p.status,
  p.sent_to_lab_at,
  p.promised_date,
  p.ready_at,
  p.status = 'en_produccion' and p.promised_date < private.today_co() as is_overdue,
  p.cancel_reason,
  p.notes,
  p.released_at,
  p.released_by,
  u.full_name as released_by_name,
  b.full_name as buyer_name,
  b.document_id as buyer_document_id,
  c.name as company_name,
  ci.name as city_name,
  o.ops_status,
  p.lab_order_reference,
  o.buyer_id,
  o.company_id
from public.order_productions p
join public.orders o on o.id = p.order_id
join public.buyers b on b.id = o.buyer_id
join public.lab_providers l on l.id = p.lab_provider_id
left join public.companies c on c.id = o.company_id
left join public.cities ci on ci.id = o.city_id
left join public.users_profiles u on u.id = p.released_by;

-- ---------------------------------------------------------------------
-- 2. Cuotas con saldo (vigentes, de órdenes no anuladas) para el tablero
--    y las vistas 360°: vencidas y próximas a vencer, con responsable
-- ---------------------------------------------------------------------
create view public.v_installments_due
with (security_invoker = true)
as
select
  i.id,
  i.order_id,
  o.order_number,
  i.installment_number,
  i.due_date,
  i.expected_amount,
  i.paid_amount,
  i.expected_amount - i.paid_amount as pending_amount,
  i.due_date < private.today_co() as is_overdue,
  i.due_date - private.today_co() as days_to_due,
  o.collection_responsible,
  o.payment_modality,
  o.buyer_id,
  b.full_name as buyer_name,
  b.document_id as buyer_document_id,
  o.company_id,
  c.name as company_name
from public.order_installments i
join public.orders o on o.id = i.order_id
join public.buyers b on b.id = o.buyer_id
left join public.companies c on c.id = o.company_id
where i.superseded_by_reclassification_id is null
  and i.paid_amount < i.expected_amount
  and not o.is_cancelled;

revoke all on public.v_installments_due from anon, authenticated;
grant select on public.v_installments_due to authenticated;

-- ---------------------------------------------------------------------
-- 3. Línea de tiempo de auditoría de una empresa (RF-M07-02, bloque 6)
-- SECURITY INVOKER: la RLS de audit_logs decide quién la ve (Dirección,
-- Administración y Socio; la auditoría de costos solo Dirección y Socio).
-- ---------------------------------------------------------------------
create function public.company_timeline(p_company_id uuid, p_limit int default 80)
returns table (
  changed_at   timestamptz,
  table_name   text,
  record_id    text,
  action       text,
  changed_by   uuid,
  changed_by_name text,
  changed_fields text[]
)
language sql
stable
security invoker
set search_path = ''
as $$
  with related (table_name, record_id) as (
    select 'companies', p_company_id::text
    union all select 'company_branches', b.id::text from public.company_branches b where b.company_id = p_company_id
    union all select 'contacts', x.id::text from public.contacts x where x.company_id = p_company_id
    union all select 'deals_opportunities', d.id::text from public.deals_opportunities d where d.company_id = p_company_id
    union all select 'agreements_convenios', a.id::text from public.agreements_convenios a where a.company_id = p_company_id
    union all select 'agreement_documents', ad.id::text
      from public.agreement_documents ad join public.agreements_convenios a on a.id = ad.agreement_id
      where a.company_id = p_company_id
    union all select 'campaigns_jornadas', j.id::text from public.campaigns_jornadas j where j.company_id = p_company_id
    union all select 'orders', o.id::text from public.orders o where o.company_id = p_company_id
    union all select 'alegra_invoices', f.id::text from public.alegra_invoices f where f.company_id = p_company_id
    union all select 'collections_payments', p.id::text from public.collections_payments p where p.company_id = p_company_id
    union all select 'portfolio_reclassifications', r.id::text
      from public.portfolio_reclassifications r join public.orders o on o.id = r.order_id
      where o.company_id = p_company_id
  )
  select
    l.changed_at,
    l.table_name,
    l.record_id,
    l.action,
    l.changed_by,
    u.full_name,
    case when l.action = 'UPDATE' then (
      select coalesce(array_agg(k.key order by k.key), '{}')
      from jsonb_each(l.new_data) k
      where k.key not in ('updated_at', 'created_at')
        and k.value is distinct from (l.old_data -> k.key)
    ) end
  from public.audit_logs l
  join related r on r.table_name = l.table_name and r.record_id = l.record_id
  left join public.users_profiles u on u.id = l.changed_by
  order by l.changed_at desc
  limit greatest(1, least(coalesce(p_limit, 80), 500));
$$;

revoke execute on function public.company_timeline(uuid, int) from public, anon;
grant execute on function public.company_timeline(uuid, int) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Resumen financiero por empresa y por comprador (bloque de
--    facturación y cartera de las vistas 360°). SECURITY INVOKER: cada
--    rol suma solo lo que su RLS le deja ver (Operación no ve recaudo).
-- ---------------------------------------------------------------------
create view public.v_finance_by_order
with (security_invoker = true)
as
select
  o.id as order_id,
  o.company_id,
  o.buyer_id,
  o.is_cancelled,
  o.total_amount,
  o.balance_due,
  o.historical_collected_before_migration,
  coalesce(inv.billed, 0) as billed_amount,
  coalesce(al.money, 0) as collected_bank,
  coalesce(al.withholding, 0) as withholding_amount,
  due.overdue_amount,
  due.next_due_date
from public.orders o
left join lateral (
  select sum(l.amount_assigned) as billed
  from public.alegra_invoice_orders l
  join public.alegra_invoices i on i.id = l.invoice_id
  where l.order_id = o.id and not i.is_voided
) inv on true
left join lateral (
  select sum(a.amount_applied) as money, sum(a.withholding_applied) as withholding
  from public.payment_allocations a
  where a.order_id = o.id and not a.is_voided
) al on true
left join lateral (
  select coalesce(sum(i.expected_amount - i.paid_amount) filter (where i.due_date < private.today_co()), 0) as overdue_amount,
         min(i.due_date) as next_due_date
  from public.order_installments i
  where i.order_id = o.id and i.superseded_by_reclassification_id is null and i.paid_amount < i.expected_amount
) due on true;

create view public.v_company_finance
with (security_invoker = true)
as
select
  f.company_id,
  count(*) filter (where not f.is_cancelled) as active_orders,
  coalesce(sum(f.total_amount) filter (where not f.is_cancelled), 0) as total_sold,
  coalesce(sum(f.billed_amount) filter (where not f.is_cancelled), 0) as total_billed,
  coalesce(sum(f.collected_bank), 0) as collected_bank,
  coalesce(sum(f.withholding_amount), 0) as withholding_amount,
  coalesce(sum(f.historical_collected_before_migration) filter (where not f.is_cancelled), 0) as collected_before_migration,
  coalesce(sum(f.balance_due) filter (where not f.is_cancelled), 0) as balance_due,
  coalesce(sum(f.overdue_amount) filter (where not f.is_cancelled), 0) as overdue_amount,
  min(f.next_due_date) filter (where not f.is_cancelled) as next_due_date
from public.v_finance_by_order f
where f.company_id is not null
group by f.company_id;

create view public.v_buyer_finance
with (security_invoker = true)
as
select
  f.buyer_id,
  count(*) filter (where not f.is_cancelled) as active_orders,
  coalesce(sum(f.total_amount) filter (where not f.is_cancelled), 0) as total_sold,
  coalesce(sum(f.billed_amount) filter (where not f.is_cancelled), 0) as total_billed,
  coalesce(sum(f.collected_bank), 0) as collected_bank,
  coalesce(sum(f.withholding_amount), 0) as withholding_amount,
  coalesce(sum(f.historical_collected_before_migration) filter (where not f.is_cancelled), 0) as collected_before_migration,
  coalesce(sum(f.balance_due) filter (where not f.is_cancelled), 0) as balance_due,
  coalesce(sum(f.overdue_amount) filter (where not f.is_cancelled), 0) as overdue_amount,
  min(f.next_due_date) filter (where not f.is_cancelled) as next_due_date
from public.v_finance_by_order f
group by f.buyer_id;

revoke all on public.v_finance_by_order, public.v_company_finance, public.v_buyer_finance from anon, authenticated;
grant select on public.v_finance_by_order, public.v_company_finance, public.v_buyer_finance to authenticated;
