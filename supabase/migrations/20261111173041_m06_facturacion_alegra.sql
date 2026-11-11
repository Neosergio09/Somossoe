-- =====================================================================
-- M06 (parte 1) Facturación vinculada a Alegra (Etapa 10)
-- Referencias SRS v1.4: RF-M06-01 (F1 manual, F2 consulta API), §5.7.22-23,
-- RF-M04-04 (estado contable), RF-M02-05 (etapa 7 automática),
-- RF-M01-01 (NIT en firme para vincular factura), §3.2.
--
-- * F1: Administración / Cartera registra la factura de Alegra (número,
--   fecha, monto, radicación) y la vincula a una o varias órdenes con el
--   monto de cada una. Si lo vinculado a una orden difiere de su valor,
--   el estado contable queda en factura_con_diferencia (Diferencia Visible).
-- * F2 (infraestructura, apagada): columnas y bitácora de sincronización
--   que solo escribe el servidor con la clave secreta al consultar la API
--   de Alegra (solo lectura). Se activa al configurar las credenciales.
-- * Etapa 7 (Facturación Cerrada) se fija sola cuando todas las jornadas
--   de la oportunidad están cerradas y todas sus órdenes no anuladas
--   tienen factura vinculada sin diferencias (se exige al menos una orden).
-- =====================================================================

create type public.invoice_radication_status as enum ('pendiente', 'radicada', 'rechazada');

-- ---------------------------------------------------------------------
-- Facturas de Alegra (§5.7.22)
-- ---------------------------------------------------------------------
create table public.alegra_invoices (
  id                    uuid primary key default gen_random_uuid(),
  alegra_invoice_number text not null check (length(trim(alegra_invoice_number)) > 0),
  invoice_date          date not null,
  invoiced_amount       numeric(14,0) not null check (invoiced_amount > 0),
  -- Sujeto facturado: la empresa (nómina) o el comprador (particular). Kick-off §7.6
  company_id            uuid references public.companies (id),
  buyer_id              uuid references public.buyers (id),
  radication_status     public.invoice_radication_status not null default 'pendiente',
  notes                 text,
  is_voided             boolean not null default false,
  void_reason           text,
  voided_by             uuid references public.users_profiles (id),
  voided_at             timestamptz,
  registered_by         uuid default auth.uid() references public.users_profiles (id),
  -- F2: ID interno de la factura en Alegra (lo registra Administración)
  alegra_external_id    text check (alegra_external_id is null or alegra_external_id ~ '^[0-9A-Za-z-]{1,40}$'),
  -- F2: los escribe solo el servidor al consultar la API de Alegra
  alegra_status         text,
  alegra_total          numeric(14,0),
  alegra_synced_at      timestamptz,
  alegra_sync_error     text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint alegra_invoices_subject check (num_nonnulls(company_id, buyer_id) = 1),
  constraint alegra_invoices_void_reason check (
    not is_voided or (void_reason is not null and length(trim(void_reason)) > 0)
  )
);

create unique index alegra_invoices_number_key on public.alegra_invoices (upper(trim(alegra_invoice_number)));
create index alegra_invoices_company_id_idx on public.alegra_invoices (company_id);
create index alegra_invoices_buyer_id_idx on public.alegra_invoices (buyer_id);
create index alegra_invoices_registered_by_idx on public.alegra_invoices (registered_by);
create index alegra_invoices_voided_by_idx on public.alegra_invoices (voided_by);

create trigger alegra_invoices_set_updated_at
  before update on public.alegra_invoices
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Vínculo factura ↔ órdenes (§5.7.23). La diferencia se calcula en las
-- vistas (depende del valor vigente de la orden).
-- ---------------------------------------------------------------------
create table public.alegra_invoice_orders (
  id              uuid primary key default gen_random_uuid(),
  invoice_id      uuid not null references public.alegra_invoices (id),
  order_id        uuid not null references public.orders (id),
  amount_assigned numeric(14,0) not null check (amount_assigned > 0),
  created_by      uuid default auth.uid() references public.users_profiles (id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint alegra_invoice_orders_unique unique (invoice_id, order_id)
);

create index alegra_invoice_orders_order_id_idx on public.alegra_invoice_orders (order_id);
create index alegra_invoice_orders_created_by_idx on public.alegra_invoice_orders (created_by);

create trigger alegra_invoice_orders_set_updated_at
  before update on public.alegra_invoice_orders
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Bitácora de consultas a la API de Alegra (F2). Solo la escribe el
-- servidor; Administración y Dirección la consultan.
-- ---------------------------------------------------------------------
create table public.alegra_sync_events (
  id            bigint generated always as identity primary key,
  invoice_id    uuid not null references public.alegra_invoices (id),
  ok            boolean not null,
  alegra_status text,
  alegra_total  numeric(14,0),
  message       text,
  requested_by  uuid references public.users_profiles (id),
  created_at    timestamptz not null default now()
);

create index alegra_sync_events_invoice_idx on public.alegra_sync_events (invoice_id, created_at desc);
create index alegra_sync_events_requested_by_idx on public.alegra_sync_events (requested_by);

-- ---------------------------------------------------------------------
-- Estado contable derivado (RF-M04-04)
-- ---------------------------------------------------------------------
create function private.refresh_order_accounting_status(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_total numeric;
  v_billed numeric;
  v_status public.order_accounting_status;
begin
  select o.total_amount into v_total from public.orders o where o.id = p_order_id;

  select sum(l.amount_assigned) into v_billed
  from public.alegra_invoice_orders l
  join public.alegra_invoices i on i.id = l.invoice_id
  where l.order_id = p_order_id and not i.is_voided;

  v_status := case
    when v_billed is null then 'pendiente_vincular'
    when v_billed = v_total then 'factura_vinculada'
    else 'factura_con_diferencia'
  end;

  update public.orders o
  set accounting_status = v_status
  where o.id = p_order_id and o.accounting_status is distinct from v_status;
end;
$$;

revoke execute on function private.refresh_order_accounting_status(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Etapa 7 automática de la oportunidad (RF-M02-05)
-- ---------------------------------------------------------------------
create function private.refresh_deal_billing_stage(p_deal_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stage public.deal_stage;
  v_closed boolean;
begin
  if p_deal_id is null then
    return;
  end if;
  select d.stage into v_stage from public.deals_opportunities d where d.id = p_deal_id;
  if v_stage not in ('jornada_en_ejecucion', 'facturacion_cerrada') then
    return;
  end if;

  select
    -- todas las jornadas (no canceladas) cerradas, al menos una
    exists (select 1 from public.campaigns_jornadas j where j.deal_id = p_deal_id and j.status = 'cerrada')
    and not exists (
      select 1 from public.campaigns_jornadas j
      where j.deal_id = p_deal_id and j.status in ('programada', 'en_ejecucion')
    )
    -- todas las órdenes no anuladas con factura vinculada sin diferencias, al menos una
    and exists (
      select 1 from public.orders o join public.campaigns_jornadas j on j.id = o.campaign_id
      where j.deal_id = p_deal_id and not o.is_cancelled
    )
    and not exists (
      select 1 from public.orders o join public.campaigns_jornadas j on j.id = o.campaign_id
      where j.deal_id = p_deal_id and not o.is_cancelled and o.accounting_status <> 'factura_vinculada'
    )
  into v_closed;

  if v_closed and v_stage = 'jornada_en_ejecucion' then
    update public.deals_opportunities d set stage = 'facturacion_cerrada' where d.id = p_deal_id;
  elsif not v_closed and v_stage = 'facturacion_cerrada' then
    update public.deals_opportunities d set stage = 'jornada_en_ejecucion' where d.id = p_deal_id;
  end if;
end;
$$;

revoke execute on function private.refresh_deal_billing_stage(uuid) from public, anon, authenticated;

-- Cambios de la orden que afectan facturación y etapa 7
create function private.orders_after_billing_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.total_amount is distinct from old.total_amount then
    perform private.refresh_order_accounting_status(new.id);
  end if;
  if (new.accounting_status, new.is_cancelled) is distinct from (old.accounting_status, old.is_cancelled)
     and new.campaign_id is not null then
    perform private.refresh_deal_billing_stage(
      (select j.deal_id from public.campaigns_jornadas j where j.id = new.campaign_id)
    );
  end if;
  return null;
end;
$$;

revoke execute on function private.orders_after_billing_change() from public, anon, authenticated;

create trigger orders_after_billing_change
  after update of total_amount, accounting_status, is_cancelled on public.orders
  for each row execute function private.orders_after_billing_change();

create function private.campaigns_after_billing_stage()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.refresh_deal_billing_stage(new.deal_id);
  return null;
end;
$$;

revoke execute on function private.campaigns_after_billing_stage() from public, anon, authenticated;

create trigger campaigns_after_billing_stage
  after update of status on public.campaigns_jornadas
  for each row execute function private.campaigns_after_billing_stage();

-- ---------------------------------------------------------------------
-- Reglas de facturas
-- ---------------------------------------------------------------------
create function private.alegra_invoices_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.alegra_invoice_number := upper(trim(new.alegra_invoice_number));

  if current_user <> 'authenticated' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.registered_by := (select auth.uid());
    new.is_voided := false;
    new.void_reason := null;
  else
    if old.is_voided then
      raise exception 'Una factura anulada no se modifica';
    end if;
    if (new.company_id, new.buyer_id) is distinct from (old.company_id, old.buyer_id) then
      raise exception 'El sujeto facturado no se cambia; anule la factura y regístrela de nuevo';
    end if;
    if new.is_voided then
      new.voided_by := (select auth.uid());
      new.voided_at := now();
    end if;
    if new.invoiced_amount < (
      select coalesce(sum(l.amount_assigned), 0) from public.alegra_invoice_orders l where l.invoice_id = old.id
    ) then
      raise exception 'El monto facturado no puede ser menor que lo ya asignado a órdenes';
    end if;
  end if;

  if new.invoice_date > private.today_co() then
    raise exception 'La fecha de la factura no puede ser futura';
  end if;

  -- RF-M01-01: para facturar a una empresa, su NIT debe estar en firme
  if new.company_id is not null and (tg_op = 'INSERT') and exists (
    select 1 from public.companies c where c.id = new.company_id and c.is_nit_provisional
  ) then
    raise exception 'La empresa debe tener el NIT en firme para vincular facturas';
  end if;

  return new;
end;
$$;

create trigger alegra_invoices_before_write
  before insert or update on public.alegra_invoices
  for each row execute function private.alegra_invoices_before_write();

create function private.alegra_invoices_after_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order uuid;
begin
  if new.is_voided is distinct from old.is_voided then
    for v_order in select l.order_id from public.alegra_invoice_orders l where l.invoice_id = new.id loop
      perform private.refresh_order_accounting_status(v_order);
    end loop;
  end if;
  return null;
end;
$$;

revoke execute on function private.alegra_invoices_after_write() from public, anon, authenticated;

create trigger alegra_invoices_after_write
  after update on public.alegra_invoices
  for each row execute function private.alegra_invoices_after_write();

-- Reglas de vínculo
create function private.alegra_invoice_orders_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_invoice public.alegra_invoices;
  v_order public.orders;
  v_assigned numeric;
begin
  if current_user <> 'authenticated' then
    return coalesce(new, old);
  end if;

  select * into v_invoice from public.alegra_invoices i where i.id = coalesce(new.invoice_id, old.invoice_id);
  if v_invoice.is_voided then
    raise exception 'La factura está anulada';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  if tg_op = 'UPDATE' and (new.invoice_id, new.order_id) is distinct from (old.invoice_id, old.order_id) then
    raise exception 'Solo se corrige el monto; para cambiar la orden quite el vínculo y créelo de nuevo';
  end if;

  select * into v_order from public.orders o where o.id = new.order_id;
  if v_order.is_cancelled then
    raise exception 'No se factura una orden anulada';
  end if;
  if v_invoice.company_id is not null and v_order.company_id is distinct from v_invoice.company_id then
    raise exception 'La orden no es de la empresa a la que se emitió la factura';
  end if;
  if v_invoice.buyer_id is not null and v_order.buyer_id is distinct from v_invoice.buyer_id then
    raise exception 'La orden no es del comprador al que se emitió la factura';
  end if;

  select coalesce(sum(l.amount_assigned), 0) into v_assigned
  from public.alegra_invoice_orders l
  where l.invoice_id = new.invoice_id and l.id is distinct from new.id;
  if v_assigned + new.amount_assigned > v_invoice.invoiced_amount then
    raise exception 'Se asignarían % de una factura por %', v_assigned + new.amount_assigned, v_invoice.invoiced_amount;
  end if;

  return new;
end;
$$;

create trigger alegra_invoice_orders_before_write
  before insert or update or delete on public.alegra_invoice_orders
  for each row execute function private.alegra_invoice_orders_before_write();

create function private.alegra_invoice_orders_after_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.refresh_order_accounting_status(coalesce(new.order_id, old.order_id));
  return null;
end;
$$;

revoke execute on function private.alegra_invoice_orders_after_write() from public, anon, authenticated;

create trigger alegra_invoice_orders_after_write
  after insert or update or delete on public.alegra_invoice_orders
  for each row execute function private.alegra_invoice_orders_after_write();

-- ---------------------------------------------------------------------
-- Vistas
-- ---------------------------------------------------------------------
create view public.v_invoices
with (security_invoker = true)
as
select
  i.id,
  i.alegra_invoice_number,
  i.invoice_date,
  i.invoiced_amount,
  i.company_id,
  c.name as company_name,
  c.nit as company_nit,
  i.buyer_id,
  b.full_name as buyer_name,
  b.document_id as buyer_document_id,
  coalesce(c.name, b.full_name) as subject_name,
  i.radication_status,
  i.notes,
  i.is_voided,
  i.void_reason,
  i.voided_at,
  i.registered_by,
  u.full_name as registered_by_name,
  coalesce(a.assigned, 0) as assigned_amount,
  i.invoiced_amount - coalesce(a.assigned, 0) as unassigned_amount,
  coalesce(a.links, 0) as orders_count,
  coalesce(a.with_difference, 0) as orders_with_difference,
  i.alegra_external_id,
  i.alegra_status,
  i.alegra_total,
  i.alegra_synced_at,
  i.alegra_sync_error,
  (i.alegra_total is not null and i.alegra_total <> i.invoiced_amount) as alegra_discrepancy,
  i.created_at,
  i.updated_at
from public.alegra_invoices i
left join public.companies c on c.id = i.company_id
left join public.buyers b on b.id = i.buyer_id
left join public.users_profiles u on u.id = i.registered_by
left join lateral (
  select sum(l.amount_assigned) as assigned,
         count(*) as links,
         count(*) filter (where o.accounting_status = 'factura_con_diferencia') as with_difference
  from public.alegra_invoice_orders l
  join public.orders o on o.id = l.order_id
  where l.invoice_id = i.id
) a on true;

-- Vínculos con la Diferencia Visible por orden (lo facturado en todas sus
-- facturas vigentes frente a su valor)
create view public.v_invoice_orders
with (security_invoker = true)
as
select
  l.id,
  l.invoice_id,
  i.alegra_invoice_number,
  i.invoice_date,
  i.is_voided as invoice_voided,
  l.order_id,
  o.order_number,
  b.full_name as buyer_name,
  b.document_id as buyer_document_id,
  o.total_amount as order_total,
  l.amount_assigned,
  l.amount_assigned - o.total_amount as discrepancy_amount,
  t.billed as order_billed_total,
  coalesce(t.billed, 0) - o.total_amount as order_difference,
  o.accounting_status,
  o.is_cancelled as order_cancelled,
  l.created_at
from public.alegra_invoice_orders l
join public.alegra_invoices i on i.id = l.invoice_id
join public.orders o on o.id = l.order_id
join public.buyers b on b.id = o.buyer_id
left join lateral (
  select sum(l2.amount_assigned) as billed
  from public.alegra_invoice_orders l2
  join public.alegra_invoices i2 on i2.id = l2.invoice_id
  where l2.order_id = l.order_id and not i2.is_voided
) t on true;

-- Órdenes por facturar o con diferencia
create view public.v_orders_to_invoice
with (security_invoker = true)
as
select
  o.id,
  o.order_number,
  o.company_id,
  c.name as company_name,
  c.is_nit_provisional as company_nit_provisional,
  o.buyer_id,
  b.full_name as buyer_name,
  b.document_id as buyer_document_id,
  o.payment_modality,
  o.total_amount,
  coalesce(t.billed, 0) as billed_amount,
  o.total_amount - coalesce(t.billed, 0) as pending_amount,
  o.accounting_status,
  o.ops_status,
  o.created_at
from public.orders o
join public.buyers b on b.id = o.buyer_id
left join public.companies c on c.id = o.company_id
left join lateral (
  select sum(l.amount_assigned) as billed
  from public.alegra_invoice_orders l
  join public.alegra_invoices i on i.id = l.invoice_id
  where l.order_id = o.id and not i.is_voided
) t on true
where not o.is_cancelled
  and o.doc_status = 'requisitos_verificados'
  and o.accounting_status <> 'factura_vinculada';

-- ---------------------------------------------------------------------
-- Auditoría (RNF-01)
-- ---------------------------------------------------------------------
create trigger alegra_invoices_audit
  after insert or update or delete on public.alegra_invoices
  for each row execute function private.audit_row_change();
create trigger alegra_invoice_orders_audit
  after insert or update or delete on public.alegra_invoice_orders
  for each row execute function private.audit_row_change();

-- ---------------------------------------------------------------------
-- Privilegios (los resultados de sincronización alegra_status, alegra_total,
-- alegra_synced_at y alegra_sync_error no se otorgan: solo el servidor)
-- ---------------------------------------------------------------------
grant select on public.alegra_invoices to authenticated;
grant insert (alegra_invoice_number, invoice_date, invoiced_amount, company_id, buyer_id,
              radication_status, notes, alegra_external_id)
  on public.alegra_invoices to authenticated;
grant update (alegra_invoice_number, invoice_date, invoiced_amount, radication_status, notes,
              is_voided, void_reason, alegra_external_id)
  on public.alegra_invoices to authenticated;

grant select, delete on public.alegra_invoice_orders to authenticated;
grant insert (invoice_id, order_id, amount_assigned) on public.alegra_invoice_orders to authenticated;
grant update (amount_assigned) on public.alegra_invoice_orders to authenticated;

grant select on public.alegra_sync_events to authenticated;

grant select on public.v_invoices, public.v_invoice_orders, public.v_orders_to_invoice to authenticated;

-- ---------------------------------------------------------------------
-- RLS (matriz §3.2, Etapa 10: Administración / Cartera crea y edita;
-- los demás consultan)
-- ---------------------------------------------------------------------
alter table public.alegra_invoices       enable row level security;
alter table public.alegra_invoice_orders enable row level security;
alter table public.alegra_sync_events    enable row level security;

create policy alegra_invoices_select on public.alegra_invoices
  for select to authenticated
  using ((select private.is_internal_user()));
create policy alegra_invoices_insert on public.alegra_invoices
  for insert to authenticated
  with check ((select private.has_role('administracion_cartera')));
create policy alegra_invoices_update on public.alegra_invoices
  for update to authenticated
  using ((select private.has_role('administracion_cartera')))
  with check ((select private.has_role('administracion_cartera')));

create policy alegra_invoice_orders_select on public.alegra_invoice_orders
  for select to authenticated
  using ((select private.is_internal_user()));
create policy alegra_invoice_orders_insert on public.alegra_invoice_orders
  for insert to authenticated
  with check ((select private.has_role('administracion_cartera')));
create policy alegra_invoice_orders_update on public.alegra_invoice_orders
  for update to authenticated
  using ((select private.has_role('administracion_cartera')))
  with check ((select private.has_role('administracion_cartera')));
create policy alegra_invoice_orders_delete on public.alegra_invoice_orders
  for delete to authenticated
  using ((select private.has_role('administracion_cartera')));

create policy alegra_sync_events_select on public.alegra_sync_events
  for select to authenticated
  using ((select private.has_role('administracion_cartera', 'direccion')));
