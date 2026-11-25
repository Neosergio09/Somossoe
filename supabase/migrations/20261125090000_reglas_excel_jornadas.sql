-- =====================================================================
-- Reglas aprobadas por el socio tras revisar el Excel nuevo de Jornadas
-- (2026-11-25):
--   1. El margen solo se muestra cuando la orden tiene todos sus costos.
--      Costos exigidos por tipo de ítem:
--        gafas completas → lente + montura + kit
--        lentes          → lente + kit
--        montura         → montura
--        otro            → otro
--        sin ítems (histórico importado del Excel) → lente + montura + kit
--   2. Un lente solo se marca recibido (listo para entregar) si la
--      producción tiene el n.º de pedido del laboratorio.
--   3. Días en laboratorio desde la fecha de la orden al laboratorio hasta
--      la fecha de recibido en SOE (ready_at), y días esperando entrega.
--   4. Un n.º de pedido no se repite en el mismo laboratorio para órdenes
--      distintas (la alerta de comprador con otras órdenes va en pantalla).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Margen solo con costos completos
-- ---------------------------------------------------------------------

-- Componentes de costo que exige una orden según sus ítems
create function private.order_required_cost_components(p_order_id uuid)
returns public.cost_component[]
language sql
stable
security definer
set search_path = ''
as $$
  select case
    -- Histórico sin ítems (Excel): no se sabe qué se vendió, se exigen los
    -- costos de unas gafas para no mostrar un margen falso
    when not exists (select 1 from public.order_items i where i.order_id = p_order_id)
      then array['lente', 'montura', 'kit']::public.cost_component[]
    else (
      select array_agg(distinct c order by c)
      from public.order_items i
      cross join lateral unnest(
        case i.item_type
          when 'gafas_completas' then array['lente', 'montura', 'kit']::public.cost_component[]
          when 'lentes' then array['lente', 'kit']::public.cost_component[]
          when 'montura' then array['montura']::public.cost_component[]
          else array['otro']::public.cost_component[]
        end
      ) c
      where i.order_id = p_order_id)
  end;
$$;

revoke execute on function private.order_required_cost_components(uuid) from public, anon;
grant execute on function private.order_required_cost_components(uuid) to authenticated;

-- Se conservan las columnas existentes y se agregan al final:
--   costs_complete, missing_cost_components
-- cost_basis gana el valor 'incompleto'. margin_amount y margin_ratio
-- quedan en null hasta que la orden tenga todos sus costos.
create or replace view public.v_order_margins
with (security_invoker = true)
as
select
  o.id as order_id,
  o.order_number,
  o.campaign_id,
  o.company_id,
  o.is_cancelled,
  o.total_amount,
  k.costs_count,
  k.cost_lente,
  k.cost_montura,
  k.cost_kit,
  k.cost_otro,
  case when k.costs_count > 0 then k.cost_total end as cost_total,
  case
    when k.costs_count = 0 then 'sin_costos'
    when cardinality(r.missing) > 0 then 'incompleto'
    when k.estimated_count > 0 then 'estimado'
    else 'verificado'
  end as cost_basis,
  case when k.costs_count > 0 and cardinality(r.missing) = 0 then o.total_amount - k.cost_total end as margin_amount,
  case
    when k.costs_count > 0 and cardinality(r.missing) = 0 and o.total_amount > 0
      then round((o.total_amount - k.cost_total) / o.total_amount, 4)
  end as margin_ratio,
  k.costs_count > 0 and cardinality(r.missing) = 0 as costs_complete,
  r.missing as missing_cost_components
from public.orders o
cross join lateral (
  select
    count(*) as costs_count,
    count(*) filter (where c.basis = 'estimado') as estimated_count,
    sum(c.amount) filter (where c.component = 'lente') as cost_lente,
    sum(c.amount) filter (where c.component = 'montura') as cost_montura,
    sum(c.amount) filter (where c.component = 'kit') as cost_kit,
    sum(c.amount) filter (where c.component = 'otro') as cost_otro,
    coalesce(sum(c.amount), 0) as cost_total,
    coalesce(array_agg(distinct c.component), '{}') as present
  from public.order_costs c
  where c.order_id = o.id and c.superseded_at is null and not c.is_voided
) k
cross join lateral (
  select coalesce(array_agg(x order by x), '{}')::public.cost_component[] as missing
  from unnest(private.order_required_cost_components(o.id)) x
  where not (x = any (k.present))
) r
where (select private.can_view_costs());

-- Margen de la jornada: solo si todas sus órdenes activas tienen costos
-- completos. Se agrega orders_incomplete_costs al final.
create or replace view public.v_campaign_margins
with (security_invoker = true)
as
select
  j.id as campaign_id,
  coalesce(sum(m.total_amount) filter (where not m.is_cancelled), 0) as sold_amount,
  count(m.order_id) filter (where not m.is_cancelled) as active_orders,
  count(m.order_id) filter (where not m.is_cancelled and m.costs_count = 0) as orders_without_costs,
  coalesce(sum(m.cost_total), 0) as cost_total,
  coalesce(bool_or(m.cost_basis = 'estimado'), false) as has_estimated,
  case
    when count(m.order_id) filter (where not m.is_cancelled and not m.costs_complete) = 0 then
      coalesce(sum(m.total_amount) filter (where not m.is_cancelled), 0) - coalesce(sum(m.cost_total), 0)
  end as margin_amount,
  case
    when count(m.order_id) filter (where not m.is_cancelled and not m.costs_complete) = 0
     and coalesce(sum(m.total_amount) filter (where not m.is_cancelled), 0) > 0 then
      round(
        (coalesce(sum(m.total_amount) filter (where not m.is_cancelled), 0) - coalesce(sum(m.cost_total), 0))
        / sum(m.total_amount) filter (where not m.is_cancelled),
        4)
  end as margin_ratio,
  count(m.order_id) filter (where not m.is_cancelled and not m.costs_complete) as orders_incomplete_costs
from public.campaigns_jornadas j
left join public.v_order_margins m on m.campaign_id = j.id
where (select private.can_view_costs())
group by j.id;

-- ---------------------------------------------------------------------
-- 2 y 4. Pedido del laboratorio: obligatorio para marcar recibido y sin
-- repetirse en el mismo laboratorio para otra orden
-- ---------------------------------------------------------------------
-- ¿El pedido ya está en uso en ese laboratorio por otra orden? (ve todas
-- las producciones, sin depender de lo que el usuario alcance a leer)
create function private.lab_order_reference_taken(
  p_lab_provider_id uuid, p_reference text, p_order_id uuid, p_production_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.order_productions p
    where p.id <> p_production_id
      and p.order_id <> p_order_id
      and p.status <> 'cancelada'
      and p.lab_provider_id = p_lab_provider_id
      and lower(p.lab_order_reference) = lower(p_reference)
  );
$$;

revoke execute on function private.lab_order_reference_taken(uuid, text, uuid, uuid) from public, anon;
grant execute on function private.lab_order_reference_taken(uuid, text, uuid, uuid) to authenticated;

create function private.order_productions_lab_reference_rules()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.lab_order_reference := nullif(trim(new.lab_order_reference), '');

  -- Datos heredados (importador, históricos) no pasan por estas reglas
  if current_user <> 'authenticated' then
    return new;
  end if;

  if new.status = 'listo_para_entregar' and new.lab_order_reference is null then
    raise exception 'Para marcar el lente como recibido en SOE registre el n.º de pedido del laboratorio';
  end if;

  if new.lab_order_reference is not null and new.status <> 'cancelada'
     and (tg_op = 'INSERT'
          or new.lab_order_reference is distinct from old.lab_order_reference
          or new.lab_provider_id is distinct from old.lab_provider_id)
     and private.lab_order_reference_taken(new.lab_provider_id, new.lab_order_reference, new.order_id, new.id) then
    raise exception 'El pedido % ya está registrado en este laboratorio para otra orden', new.lab_order_reference;
  end if;

  return new;
end;
$$;

revoke execute on function private.order_productions_lab_reference_rules() from public, anon, authenticated;

-- Corre después de order_productions_before_write (orden alfabético), que
-- ya fijó el estado y la fecha de recibido
create trigger order_productions_lab_reference_rules
  before insert or update on public.order_productions
  for each row execute function private.order_productions_lab_reference_rules();

-- ---------------------------------------------------------------------
-- 3. Días en laboratorio y esperando entrega (se agregan al final)
-- ---------------------------------------------------------------------
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
  o.company_id,
  case when p.status <> 'cancelada'
    then coalesce(p.ready_at, private.today_co()) - p.sent_to_lab_at end as days_in_lab,
  case when p.status = 'listo_para_entregar'
    then private.today_co() - p.ready_at end as days_since_received
from public.order_productions p
join public.orders o on o.id = p.order_id
join public.buyers b on b.id = o.buyer_id
join public.lab_providers l on l.id = p.lab_provider_id
left join public.companies c on c.id = o.company_id
left join public.cities ci on ci.id = o.city_id
left join public.users_profiles u on u.id = p.released_by;
