-- =====================================================================
-- M06: Reclasificación de cartera por novedad de nómina (RF-M06-04)
-- Si el empleado se retira o se incapacita y la empresa no descuenta el
-- saldo, el cobro pasa de Empresa (nómina) a Empleado (cobro directo).
-- Decisiones del 2026-11-12:
--   * Dos pasos: Administración / Cartera solicita (motivo y plan nuevo);
--     Dirección autoriza o rechaza. Pendiente = nada cambia en la orden.
--   * Plan nuevo libre: n.º de cuotas, periodicidad y primera fecha, sin
--     tope del convenio (ya no es descuento de nómina).
--   * Después pagan empleado y empresa: solo cambia el responsable.
-- La modalidad de pago original no se modifica; las cuotas pendientes
-- quedan en el historial marcadas como reemplazadas.
-- =====================================================================

create type public.reclassification_status as enum ('pendiente', 'autorizada', 'rechazada', 'anulada');
create type public.reclassification_reason as enum ('retiro', 'incapacidad', 'otro');

create table public.portfolio_reclassifications (
  id                     uuid primary key default gen_random_uuid(),
  order_id               uuid not null references public.orders (id),
  from_responsible       public.collection_responsible not null default 'empresa',
  to_responsible         public.collection_responsible not null default 'empleado',
  reason                 public.reclassification_reason not null,
  notes                  text check (notes is null or length(notes) <= 1000),
  balance_at_request     numeric(14,0) not null default 0,
  balance_transferred    numeric(14,0),
  new_installments_count smallint not null check (new_installments_count between 1 and 24),
  new_periodicity        public.payroll_frequency not null,
  new_first_due_date     date not null,
  status                 public.reclassification_status not null default 'pendiente',
  requested_by           uuid default auth.uid() references public.users_profiles (id),
  requested_at           timestamptz not null default now(),
  decided_by             uuid references public.users_profiles (id),
  decided_at             timestamptz,
  decision_notes         text check (decision_notes is null or length(decision_notes) <= 1000),
  constraint portfolio_reclassifications_direction
    check (from_responsible = 'empresa' and to_responsible = 'empleado'),
  constraint portfolio_reclassifications_other_notes
    check (reason <> 'otro' or (notes is not null and length(trim(notes)) > 0)),
  constraint portfolio_reclassifications_decision_notes
    check (status not in ('rechazada', 'anulada')
           or (decision_notes is not null and length(trim(decision_notes)) > 0))
);

create unique index portfolio_reclassifications_one_pending_key
  on public.portfolio_reclassifications (order_id) where status = 'pendiente';
create index portfolio_reclassifications_order_id_idx on public.portfolio_reclassifications (order_id);
create index portfolio_reclassifications_requested_by_idx on public.portfolio_reclassifications (requested_by);
create index portfolio_reclassifications_decided_by_idx on public.portfolio_reclassifications (decided_by);
create index portfolio_reclassifications_status_idx on public.portfolio_reclassifications (status)
  where status = 'pendiente';

alter table public.order_installments
  add constraint order_installments_reclassification_fkey
  foreign key (superseded_by_reclassification_id) references public.portfolio_reclassifications (id);
create index order_installments_reclassification_idx
  on public.order_installments (superseded_by_reclassification_id);

-- Condiciones de la orden para reclasificar (se revisan al pedir y al autorizar)
create function private.assert_reclassifiable(p_order_id uuid)
returns numeric
language plpgsql
stable
set search_path = ''
as $$
declare
  v_order record;
begin
  select o.payment_modality, o.collection_responsible, o.is_cancelled, o.balance_due
    into v_order
  from public.orders o where o.id = p_order_id;
  if not found then
    raise exception 'Orden no encontrada';
  end if;
  if v_order.is_cancelled then
    raise exception 'La orden está anulada';
  end if;
  if v_order.payment_modality <> 'nomina_empresa' then
    raise exception 'Solo se reclasifican órdenes por descuento de nómina';
  end if;
  if v_order.collection_responsible <> 'empresa' then
    raise exception 'El cobro de esta orden ya está a cargo del comprador';
  end if;
  if v_order.balance_due <= 0 then
    raise exception 'La orden no tiene saldo por cobrar';
  end if;
  return v_order.balance_due;
end;
$$;

revoke execute on function private.assert_reclassifiable(uuid) from public, anon;
grant execute on function private.assert_reclassifiable(uuid) to authenticated;

create function private.reclassifications_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user <> 'authenticated' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.status := 'pendiente';
    new.requested_by := (select auth.uid());
    new.requested_at := now();
    new.decided_by := null;
    new.decided_at := null;
    new.decision_notes := null;
    new.balance_transferred := null;
    new.balance_at_request := private.assert_reclassifiable(new.order_id);
    if new.new_first_due_date < private.today_co() then
      raise exception 'La primera cuota del plan nuevo no puede vencer en el pasado';
    end if;
    return new;
  end if;

  -- UPDATE: solo la decisión sobre una solicitud pendiente
  if old.status <> 'pendiente' then
    raise exception 'La solicitud ya fue %', old.status;
  end if;
  if new.status = 'pendiente' then
    raise exception 'Indique la decisión: autorizar, rechazar o anular';
  end if;

  if new.status in ('autorizada', 'rechazada') and not private.has_role('direccion') then
    raise exception 'Solo Dirección autoriza o rechaza una reclasificación' using errcode = '42501';
  end if;
  if new.status = 'anulada' and not private.has_role('administracion_cartera') then
    raise exception 'Solo Administración / Cartera anula una solicitud' using errcode = '42501';
  end if;

  if new.status = 'autorizada' then
    new.balance_transferred := private.assert_reclassifiable(new.order_id);
    if new.new_first_due_date < private.today_co() then
      raise exception 'La primera cuota del plan ya venció; anule la solicitud y pida una nueva';
    end if;
  end if;

  new.decided_by := (select auth.uid());
  new.decided_at := now();
  return new;
end;
$$;

create trigger reclassifications_before_write
  before insert or update on public.portfolio_reclassifications
  for each row execute function private.reclassifications_before_write();

-- Al autorizar: reemplaza las cuotas pendientes, genera el plan nuevo por
-- el saldo y traslada el responsable de cobro
create function private.reclassifications_after_authorize()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_next int;
  v_base numeric(14,0);
begin
  if new.status <> 'autorizada' or old.status = 'autorizada' then
    return null;
  end if;

  update public.order_installments i
  set superseded_by_reclassification_id = new.id
  where i.order_id = new.order_id
    and i.superseded_by_reclassification_id is null
    and i.paid_amount < i.expected_amount;

  select coalesce(max(i.installment_number), 0) into v_next
  from public.order_installments i where i.order_id = new.order_id;

  v_base := floor(new.balance_transferred / new.new_installments_count);

  insert into public.order_installments (order_id, installment_number, due_date, expected_amount)
  select
    new.order_id,
    v_next + n,
    private.installment_due_date(new.new_first_due_date, new.new_periodicity, n),
    -- El residuo de la división va en la primera cuota
    case when n = 1 then new.balance_transferred - v_base * (new.new_installments_count - 1) else v_base end
  from generate_series(1, new.new_installments_count) as n;

  update public.orders o set collection_responsible = 'empleado' where o.id = new.order_id;
  return null;
end;
$$;

revoke execute on function private.reclassifications_after_authorize() from public, anon, authenticated;

create trigger reclassifications_after_authorize
  after update of status on public.portfolio_reclassifications
  for each row execute function private.reclassifications_after_authorize();

-- Con una solicitud pendiente o una reclasificación autorizada, el valor y
-- el plan original de la orden no se cambian (regenerarían las cuotas)
create function private.orders_reclassification_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_status public.reclassification_status;
begin
  if (new.total_amount, new.payment_modality, new.installments_count, new.first_due_date, new.agreement_id)
     is not distinct from
     (old.total_amount, old.payment_modality, old.installments_count, old.first_due_date, old.agreement_id) then
    return new;
  end if;

  select r.status into v_status
  from public.portfolio_reclassifications r
  where r.order_id = new.id and r.status in ('pendiente', 'autorizada')
  limit 1;

  if v_status = 'pendiente' then
    raise exception 'La orden tiene una reclasificación de cartera pendiente; su valor y plan no se cambian';
  elsif v_status = 'autorizada' then
    raise exception 'La orden tiene una reclasificación de cartera autorizada; su valor y plan no se cambian';
  end if;
  return new;
end;
$$;

create trigger orders_reclassification_guard
  before update on public.orders
  for each row execute function private.orders_reclassification_guard();

-- Una asignación sobre una cuota reemplazada no se anula: su saldo ya
-- quedó repartido en el plan nuevo
create function private.payment_allocations_reclassification_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.is_voided and not old.is_voided and old.installment_id is not null
     and exists (
       select 1 from public.order_installments i
       where i.id = old.installment_id and i.superseded_by_reclassification_id is not null
     ) then
    raise exception 'El pago se aplicó a una cuota reemplazada por una reclasificación de cartera; no se puede anular';
  end if;
  return new;
end;
$$;

create trigger payment_allocations_reclassification_guard
  before update on public.payment_allocations
  for each row execute function private.payment_allocations_reclassification_guard();

-- ---------------------------------------------------------------------
-- Vista
-- ---------------------------------------------------------------------
create view public.v_portfolio_reclassifications
with (security_invoker = true)
as
select
  r.id,
  r.order_id,
  o.order_number,
  o.company_id,
  c.name as company_name,
  o.buyer_id,
  b.full_name as buyer_name,
  b.document_id as buyer_document_id,
  o.balance_due as current_balance,
  r.from_responsible,
  r.to_responsible,
  r.reason,
  r.notes,
  r.balance_at_request,
  r.balance_transferred,
  r.new_installments_count,
  r.new_periodicity,
  r.new_first_due_date,
  r.status,
  r.requested_by,
  ur.full_name as requested_by_name,
  r.requested_at,
  r.decided_by,
  ud.full_name as decided_by_name,
  r.decided_at,
  r.decision_notes
from public.portfolio_reclassifications r
join public.orders o on o.id = r.order_id
join public.buyers b on b.id = o.buyer_id
left join public.companies c on c.id = o.company_id
left join public.users_profiles ur on ur.id = r.requested_by
left join public.users_profiles ud on ud.id = r.decided_by;

-- ---------------------------------------------------------------------
-- Auditoría, privilegios y RLS (matriz §3.2, Etapa 11)
-- ---------------------------------------------------------------------
create trigger portfolio_reclassifications_audit
  after insert or update or delete on public.portfolio_reclassifications
  for each row execute function private.audit_row_change();

revoke all on public.portfolio_reclassifications, public.v_portfolio_reclassifications from anon, authenticated;

grant select on public.portfolio_reclassifications to authenticated;
grant insert (order_id, reason, notes, new_installments_count, new_periodicity, new_first_due_date)
  on public.portfolio_reclassifications to authenticated;
grant update (status, decision_notes) on public.portfolio_reclassifications to authenticated;
grant select on public.v_portfolio_reclassifications to authenticated;

alter table public.portfolio_reclassifications enable row level security;

create policy portfolio_reclassifications_select on public.portfolio_reclassifications
  for select to authenticated
  using ((select private.has_role('administracion_cartera', 'direccion', 'comercial', 'socio')));
create policy portfolio_reclassifications_insert on public.portfolio_reclassifications
  for insert to authenticated
  with check ((select private.has_role('administracion_cartera')));
create policy portfolio_reclassifications_update on public.portfolio_reclassifications
  for update to authenticated
  using ((select private.has_role('administracion_cartera', 'direccion')))
  with check ((select private.has_role('administracion_cartera', 'direccion')));
