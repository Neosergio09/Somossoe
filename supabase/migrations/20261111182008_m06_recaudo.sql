-- =====================================================================
-- M06 (parte 2) Recaudo verificado y recibo de caja corporativo (Etapa 11)
-- Referencias SRS v1.4: RF-M06-02, RF-M06-03 (F1), §5.7.24-26, RF-M04-04
-- (estado de cartera y saldo), RF-M05-01 (anticipo en contado), §3.2.
--
-- * Regla de Oro de Cartera: el saldo solo baja con pagos recibidos y
--   verificados en bancos que Administración registra y asigna.
-- * Retención no es pago: cada asignación separa el dinero recibido de la
--   retención (con certificado). Propuesta del SRS aplicada por defecto:
--   la retención reduce el saldo por cobrar, pero el recaudo en bancos
--   solo suma dinero recibido.
-- * Un pago (de una empresa o de un comprador) se asigna a una o varias
--   órdenes de ese pagador; lo no asignado queda visible.
-- * En órdenes con plan de cuotas, lo asignado se aplica a las cuotas
--   pendientes en orden de vencimiento.
-- * Nada se borra: pagos y asignaciones se anulan con motivo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Pagos recibidos y verificados en bancos (§5.7.25)
-- ---------------------------------------------------------------------
create table public.collections_payments (
  id                   uuid primary key default gen_random_uuid(),
  payment_number       bigint generated always as identity,
  company_id           uuid references public.companies (id),
  buyer_id             uuid references public.buyers (id),
  payment_date         date not null,
  total_received_bank  numeric(14,0) not null check (total_received_bank > 0),
  bank_reference       text not null check (length(trim(bank_reference)) > 0),
  support_received     boolean not null default false,
  support_file_r2_key  text check (support_file_r2_key is null or length(trim(support_file_r2_key)) > 0),
  notes                text,
  verified_by          uuid default auth.uid() references public.users_profiles (id),
  verified_at          timestamptz not null default now(),
  is_voided            boolean not null default false,
  void_reason          text,
  voided_by            uuid references public.users_profiles (id),
  voided_at            timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint collections_payments_number_key unique (payment_number),
  constraint collections_payments_payer check (num_nonnulls(company_id, buyer_id) = 1),
  constraint collections_payments_void_reason check (
    not is_voided or (void_reason is not null and length(trim(void_reason)) > 0)
  )
);

-- Evita registrar dos veces el mismo movimiento bancario
create unique index collections_payments_bank_movement_key
  on public.collections_payments (upper(trim(bank_reference)), payment_date, total_received_bank)
  where not is_voided;
create index collections_payments_company_id_idx on public.collections_payments (company_id);
create index collections_payments_buyer_id_idx on public.collections_payments (buyer_id);
create index collections_payments_verified_by_idx on public.collections_payments (verified_by);
create index collections_payments_voided_by_idx on public.collections_payments (voided_by);
create index collections_payments_date_idx on public.collections_payments (payment_date desc);

create trigger collections_payments_set_updated_at
  before update on public.collections_payments
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Asignaciones del pago a órdenes y cuotas (§5.7.26)
-- ---------------------------------------------------------------------
create table public.payment_allocations (
  id                               uuid primary key default gen_random_uuid(),
  payment_id                       uuid not null references public.collections_payments (id),
  order_id                         uuid not null references public.orders (id),
  installment_id                   uuid references public.order_installments (id),
  amount_applied                   numeric(14,0) not null default 0 check (amount_applied >= 0),
  withholding_applied              numeric(14,0) not null default 0 check (withholding_applied >= 0),
  withholding_certificate_received boolean not null default false,
  withholding_certificate_r2_key   text check (withholding_certificate_r2_key is null or length(trim(withholding_certificate_r2_key)) > 0),
  created_by                       uuid default auth.uid() references public.users_profiles (id),
  created_at                       timestamptz not null default now(),
  is_voided                        boolean not null default false,
  void_reason                      text,
  voided_by                        uuid references public.users_profiles (id),
  voided_at                        timestamptz,
  constraint payment_allocations_positive check (amount_applied + withholding_applied > 0),
  constraint payment_allocations_void_reason check (
    not is_voided or (void_reason is not null and length(trim(void_reason)) > 0)
  )
);

create index payment_allocations_payment_id_idx on public.payment_allocations (payment_id);
create index payment_allocations_order_id_idx on public.payment_allocations (order_id) where not is_voided;
create index payment_allocations_installment_id_idx on public.payment_allocations (installment_id);
create index payment_allocations_created_by_idx on public.payment_allocations (created_by);
create index payment_allocations_voided_by_idx on public.payment_allocations (voided_by);

-- ---------------------------------------------------------------------
-- Pago verificado de una orden (reemplaza el marcador de M05): dinero
-- recibido + retención soportada de las asignaciones vigentes
-- ---------------------------------------------------------------------
create or replace function private.order_verified_paid(p_order_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(a.amount_applied + a.withholding_applied), 0)
  from public.payment_allocations a
  where a.order_id = p_order_id and not a.is_voided;
$$;

-- Saldo y estado de cartera derivados (RF-M04-04). Se ejecuta después de
-- orders_before_write (orden alfabético de los triggers).
create function private.orders_compute_collection()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_paid numeric := private.order_verified_paid(new.id);
begin
  if tg_op = 'UPDATE' and v_paid > 0
     and (new.payment_modality, new.installments_count, new.first_due_date)
         is distinct from (old.payment_modality, old.installments_count, old.first_due_date) then
    raise exception 'La orden ya tiene pagos aplicados: su modalidad y plan de pagos no se cambian';
  end if;
  if new.total_amount < v_paid then
    raise exception 'El valor de la orden (%) no puede quedar por debajo de lo ya recaudado (%)', new.total_amount, v_paid;
  end if;
  new.balance_due := new.total_amount - v_paid;
  new.collection_status := case
    when v_paid = 0 then 'con_saldo'
    when new.balance_due = 0 then 'recaudado_total'
    else 'parcialmente_recaudado'
  end;
  return new;
end;
$$;

create trigger orders_compute_collection
  before insert or update on public.orders
  for each row execute function private.orders_compute_collection();

-- Recalcula cuotas y saldo de una orden
create function private.refresh_order_collection(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.order_installments i
  set paid_amount = coalesce((
    select sum(a.amount_applied + a.withholding_applied)
    from public.payment_allocations a
    where a.installment_id = i.id and not a.is_voided
  ), 0)
  where i.order_id = p_order_id;

  -- Un UPDATE sin cambios dispara orders_compute_collection
  update public.orders o set balance_due = o.balance_due where o.id = p_order_id;
end;
$$;

revoke execute on function private.refresh_order_collection(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Reglas de pagos
-- ---------------------------------------------------------------------
create function private.collections_payments_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_files boolean := private.get_setting('require_document_files') = 1;
  v_allocated numeric;
begin
  new.bank_reference := trim(new.bank_reference);

  if current_user <> 'authenticated' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.verified_by := (select auth.uid());
    new.verified_at := now();
    new.is_voided := false;
    new.void_reason := null;
  else
    if old.is_voided then
      raise exception 'Un pago anulado no se modifica';
    end if;
    if (new.company_id, new.buyer_id) is distinct from (old.company_id, old.buyer_id) then
      raise exception 'El pagador no se cambia; anule el pago y regístrelo de nuevo';
    end if;
    select coalesce(sum(a.amount_applied), 0) into v_allocated
    from public.payment_allocations a where a.payment_id = old.id and not a.is_voided;
    if not new.is_voided and new.total_received_bank < v_allocated then
      raise exception 'El valor recibido no puede ser menor que lo ya asignado (%)', v_allocated;
    end if;
    if new.is_voided then
      new.voided_by := (select auth.uid());
      new.voided_at := now();
    end if;
  end if;

  if new.payment_date > private.today_co() then
    raise exception 'La fecha del pago no puede ser futura';
  end if;
  if not new.support_received or (v_files and new.support_file_r2_key is null) then
    raise exception 'Registre el soporte bancario del pago';
  end if;

  return new;
end;
$$;

create trigger collections_payments_before_write
  before insert or update on public.collections_payments
  for each row execute function private.collections_payments_before_write();

-- Anular un pago anula sus asignaciones
create function private.collections_payments_after_void()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.is_voided and not old.is_voided then
    update public.payment_allocations a
    set is_voided = true,
        void_reason = 'Pago anulado: ' || new.void_reason,
        voided_by = new.voided_by,
        voided_at = coalesce(new.voided_at, now())
    where a.payment_id = new.id and not a.is_voided;
  end if;
  return null;
end;
$$;

revoke execute on function private.collections_payments_after_void() from public, anon, authenticated;

create trigger collections_payments_after_void
  after update of is_voided on public.collections_payments
  for each row execute function private.collections_payments_after_void();

-- ---------------------------------------------------------------------
-- Reglas de asignaciones
-- ---------------------------------------------------------------------
create function private.payment_allocations_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_files boolean := private.get_setting('require_document_files') = 1;
  v_payment public.collections_payments;
  v_order public.orders;
  v_allocated numeric;
  v_installment record;
begin
  if current_user <> 'authenticated' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.is_voided then
      raise exception 'Una asignación anulada no se modifica';
    end if;
    if (new.payment_id, new.order_id, new.installment_id, new.amount_applied, new.withholding_applied,
        new.withholding_certificate_received)
       is distinct from
       (old.payment_id, old.order_id, old.installment_id, old.amount_applied, old.withholding_applied,
        old.withholding_certificate_received) then
      raise exception 'Una asignación no se edita: anúlela y registre una nueva';
    end if;
    if new.is_voided then
      new.voided_by := (select auth.uid());
      new.voided_at := now();
    end if;
    return new;
  end if;

  new.created_by := (select auth.uid());
  new.is_voided := false;

  select * into v_payment from public.collections_payments p where p.id = new.payment_id;
  if v_payment.is_voided then
    raise exception 'El pago está anulado';
  end if;

  select * into v_order from public.orders o where o.id = new.order_id;
  if v_order.is_cancelled then
    raise exception 'No se aplican pagos a una orden anulada';
  end if;
  if v_payment.company_id is not null and v_order.company_id is distinct from v_payment.company_id then
    raise exception 'La orden no es de la empresa que hizo el pago';
  end if;
  if v_payment.buyer_id is not null and v_order.buyer_id is distinct from v_payment.buyer_id then
    raise exception 'La orden no es del comprador que hizo el pago';
  end if;

  -- Lo asignado en dinero no supera lo recibido en bancos
  select coalesce(sum(a.amount_applied), 0) into v_allocated
  from public.payment_allocations a where a.payment_id = new.payment_id and not a.is_voided;
  if v_allocated + new.amount_applied > v_payment.total_received_bank then
    raise exception 'Se asignarían % de un pago por %', v_allocated + new.amount_applied, v_payment.total_received_bank;
  end if;

  -- No se abona más del saldo de la orden
  if new.amount_applied + new.withholding_applied > v_order.balance_due then
    raise exception 'El abono (%) supera el saldo de la orden (%)',
      new.amount_applied + new.withholding_applied, v_order.balance_due;
  end if;

  if new.withholding_applied > 0
     and (not new.withholding_certificate_received or (v_files and new.withholding_certificate_r2_key is null)) then
    raise exception 'La retención requiere el certificado de retención';
  end if;

  if new.installment_id is not null then
    select i.order_id, i.expected_amount, i.paid_amount, i.superseded_by_reclassification_id
      into v_installment
    from public.order_installments i where i.id = new.installment_id;
    if v_installment.order_id is distinct from new.order_id then
      raise exception 'La cuota no pertenece a la orden';
    end if;
    if v_installment.superseded_by_reclassification_id is not null then
      raise exception 'La cuota fue reemplazada por una reprogramación';
    end if;
    if new.amount_applied + new.withholding_applied > v_installment.expected_amount - v_installment.paid_amount then
      raise exception 'El abono supera lo pendiente de la cuota';
    end if;
  end if;

  return new;
end;
$$;

create trigger payment_allocations_before_write
  before insert or update on public.payment_allocations
  for each row execute function private.payment_allocations_before_write();

create function private.payment_allocations_after_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.refresh_order_collection(new.order_id);
  return null;
end;
$$;

revoke execute on function private.payment_allocations_after_write() from public, anon, authenticated;

create trigger payment_allocations_after_write
  after insert or update on public.payment_allocations
  for each row execute function private.payment_allocations_after_write();

-- ---------------------------------------------------------------------
-- Aplicación de un pago a una orden (SECURITY INVOKER). Con plan de
-- cuotas, reparte el abono en las cuotas pendientes por vencimiento
-- (primero el dinero y luego la retención de cada tramo).
-- ---------------------------------------------------------------------
create function public.apply_payment(
  p_payment_id uuid,
  p_order_id uuid,
  p_amount numeric,
  p_withholding numeric default 0,
  p_certificate_received boolean default false
)
returns int
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_money numeric := coalesce(p_amount, 0);
  v_withholding numeric := coalesce(p_withholding, 0);
  v_rows int := 0;
  v_take numeric;
  v_take_money numeric;
  v_inst record;
begin
  if v_money < 0 or v_withholding < 0 or v_money + v_withholding <= 0 then
    raise exception 'Indique un valor de dinero recibido o de retención mayor que cero';
  end if;

  if not exists (
    select 1 from public.order_installments i
    where i.order_id = p_order_id and i.superseded_by_reclassification_id is null
  ) then
    insert into public.payment_allocations (payment_id, order_id, amount_applied, withholding_applied,
      withholding_certificate_received)
    values (p_payment_id, p_order_id, v_money, v_withholding, coalesce(p_certificate_received, false));
    return 1;
  end if;

  for v_inst in
    select i.id, i.expected_amount - i.paid_amount as pending
    from public.order_installments i
    where i.order_id = p_order_id
      and i.superseded_by_reclassification_id is null
      and i.paid_amount < i.expected_amount
    order by i.due_date, i.installment_number
  loop
    exit when v_money + v_withholding <= 0;
    v_take := least(v_inst.pending, v_money + v_withholding);
    v_take_money := least(v_take, v_money);
    insert into public.payment_allocations (payment_id, order_id, installment_id, amount_applied,
      withholding_applied, withholding_certificate_received)
    values (p_payment_id, p_order_id, v_inst.id, v_take_money, v_take - v_take_money,
      coalesce(p_certificate_received, false));
    v_money := v_money - v_take_money;
    v_withholding := v_withholding - (v_take - v_take_money);
    v_rows := v_rows + 1;
  end loop;

  if v_money + v_withholding > 0 then
    raise exception 'El abono supera lo pendiente de las cuotas de la orden';
  end if;
  return v_rows;
end;
$$;

revoke execute on function public.apply_payment(uuid, uuid, numeric, numeric, boolean) from public, anon;
grant execute on function public.apply_payment(uuid, uuid, numeric, numeric, boolean) to authenticated;

-- Recibo de caja corporativo (RF-M06-03 F1): reparte un pago entre varias
-- órdenes en una sola transacción. p_items: [{order_id, amount, withholding,
-- certificate_received}]
create function public.apply_payment_batch(p_payment_id uuid, p_items jsonb)
returns int
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_item record;
  v_rows int := 0;
begin
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'Asignaciones inválidas';
  end if;
  for v_item in
    select x.order_id, coalesce(x.amount, 0) as amount, coalesce(x.withholding, 0) as withholding,
           coalesce(x.certificate_received, false) as certificate_received
    from jsonb_to_recordset(p_items) as x (order_id uuid, amount numeric, withholding numeric, certificate_received boolean)
    where coalesce(x.amount, 0) + coalesce(x.withholding, 0) > 0
  loop
    v_rows := v_rows + public.apply_payment(p_payment_id, v_item.order_id, v_item.amount, v_item.withholding,
                                            v_item.certificate_received);
  end loop;
  if v_rows = 0 then
    raise exception 'Indique al menos una orden con valor a aplicar';
  end if;
  return v_rows;
end;
$$;

revoke execute on function public.apply_payment_batch(uuid, jsonb) from public, anon;
grant execute on function public.apply_payment_batch(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- Vistas
-- ---------------------------------------------------------------------
create view public.v_payments
with (security_invoker = true)
as
select
  p.id,
  p.payment_number,
  p.company_id,
  p.buyer_id,
  coalesce(c.name, b.full_name) as payer_name,
  c.nit as company_nit,
  b.document_id as buyer_document_id,
  p.payment_date,
  p.total_received_bank,
  p.bank_reference,
  p.support_received,
  p.notes,
  p.verified_by,
  u.full_name as verified_by_name,
  p.verified_at,
  p.is_voided,
  p.void_reason,
  p.voided_at,
  coalesce(a.money, 0) as allocated_amount,
  coalesce(a.withholding, 0) as withholding_amount,
  p.total_received_bank - coalesce(a.money, 0) as unassigned_amount,
  coalesce(a.orders, 0) as orders_count,
  p.created_at
from public.collections_payments p
left join public.companies c on c.id = p.company_id
left join public.buyers b on b.id = p.buyer_id
left join public.users_profiles u on u.id = p.verified_by
left join lateral (
  select sum(x.amount_applied) as money,
         sum(x.withholding_applied) as withholding,
         count(distinct x.order_id) as orders
  from public.payment_allocations x
  where x.payment_id = p.id and not x.is_voided
) a on true;

create view public.v_payment_allocations
with (security_invoker = true)
as
select
  a.id,
  a.payment_id,
  p.payment_number,
  p.payment_date,
  p.bank_reference,
  a.order_id,
  o.order_number,
  b.full_name as buyer_name,
  b.document_id as buyer_document_id,
  a.installment_id,
  i.installment_number,
  i.due_date as installment_due_date,
  a.amount_applied,
  a.withholding_applied,
  a.withholding_certificate_received,
  a.is_voided,
  a.void_reason,
  a.created_by,
  u.full_name as created_by_name,
  a.created_at
from public.payment_allocations a
join public.collections_payments p on p.id = a.payment_id
join public.orders o on o.id = a.order_id
join public.buyers b on b.id = o.buyer_id
left join public.order_installments i on i.id = a.installment_id
left join public.users_profiles u on u.id = a.created_by;

-- Cartera por cobrar
create view public.v_receivables
with (security_invoker = true)
as
select
  o.id,
  o.order_number,
  o.company_id,
  c.name as company_name,
  o.buyer_id,
  b.full_name as buyer_name,
  b.document_id as buyer_document_id,
  o.payment_modality,
  o.collection_responsible,
  o.total_amount,
  o.total_amount - o.balance_due as collected_amount,
  o.balance_due,
  o.collection_status,
  inst.overdue_count,
  inst.overdue_amount,
  inst.next_due_date,
  o.created_at
from public.orders o
join public.buyers b on b.id = o.buyer_id
left join public.companies c on c.id = o.company_id
left join lateral (
  select count(*) filter (where i.due_date < private.today_co() and i.paid_amount < i.expected_amount) as overdue_count,
         coalesce(sum(i.expected_amount - i.paid_amount)
           filter (where i.due_date < private.today_co() and i.paid_amount < i.expected_amount), 0) as overdue_amount,
         min(i.due_date) filter (where i.paid_amount < i.expected_amount) as next_due_date
  from public.order_installments i
  where i.order_id = o.id and i.superseded_by_reclassification_id is null
) inst on true
where not o.is_cancelled and o.balance_due > 0 and o.total_amount > 0;

-- ---------------------------------------------------------------------
-- Auditoría (RNF-01)
-- ---------------------------------------------------------------------
create trigger collections_payments_audit
  after insert or update or delete on public.collections_payments
  for each row execute function private.audit_row_change();
create trigger payment_allocations_audit
  after insert or update or delete on public.payment_allocations
  for each row execute function private.audit_row_change();

-- ---------------------------------------------------------------------
-- Privilegios
-- ---------------------------------------------------------------------
grant select on public.collections_payments to authenticated;
grant insert (company_id, buyer_id, payment_date, total_received_bank, bank_reference,
              support_received, support_file_r2_key, notes)
  on public.collections_payments to authenticated;
grant update (payment_date, total_received_bank, bank_reference, support_received,
              support_file_r2_key, notes, is_voided, void_reason)
  on public.collections_payments to authenticated;

grant select on public.payment_allocations to authenticated;
grant insert (payment_id, order_id, installment_id, amount_applied, withholding_applied,
              withholding_certificate_received, withholding_certificate_r2_key)
  on public.payment_allocations to authenticated;
grant update (is_voided, void_reason, withholding_certificate_r2_key) on public.payment_allocations to authenticated;

grant select on public.v_payments, public.v_payment_allocations, public.v_receivables to authenticated;

-- ---------------------------------------------------------------------
-- RLS (matriz §3.2, Etapa 11): Administración / Cartera crea, edita y
-- verifica; Comercial y Dirección consultan; Operación sin acceso.
-- ---------------------------------------------------------------------
alter table public.collections_payments enable row level security;
alter table public.payment_allocations  enable row level security;

create policy collections_payments_select on public.collections_payments
  for select to authenticated
  using ((select private.has_role('administracion_cartera', 'direccion', 'comercial')));
create policy collections_payments_insert on public.collections_payments
  for insert to authenticated
  with check ((select private.has_role('administracion_cartera')));
create policy collections_payments_update on public.collections_payments
  for update to authenticated
  using ((select private.has_role('administracion_cartera')))
  with check ((select private.has_role('administracion_cartera')));

create policy payment_allocations_select on public.payment_allocations
  for select to authenticated
  using ((select private.has_role('administracion_cartera', 'direccion', 'comercial')));
create policy payment_allocations_insert on public.payment_allocations
  for insert to authenticated
  with check ((select private.has_role('administracion_cartera')));
create policy payment_allocations_update on public.payment_allocations
  for update to authenticated
  using ((select private.has_role('administracion_cartera')))
  with check ((select private.has_role('administracion_cartera')));
