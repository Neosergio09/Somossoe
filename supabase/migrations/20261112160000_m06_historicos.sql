-- =====================================================================
-- M06: Carga de históricos con contexto mínimo (RF-M06-05)
-- Órdenes reales anteriores al CRM que entran directamente en la Etapa
-- 07 (venta), 08 (producción) u 11 (entregada, solo falta cobrar) sin
-- inventar las etapas 01 a 06.
-- Decisiones del 2026-11-12:
--   * Formulario uno a uno (sin importación masiva). Carga Administración
--     / Cartera mediante public.create_historical_order.
--   * "Responsable actual" = responsable de cobro (empresa o comprador).
--   * Un histórico por nómina se permite sin convenio en el CRM.
-- Saldo vivo: lo recaudado antes de la migración (= valor − saldo vivo)
-- queda en historical_collected_before_migration; los pagos posteriores
-- siguen la Regla de Oro.
-- =====================================================================

create type public.historical_stage as enum ('venta', 'produccion', 'entregada');

alter table public.orders
  add column is_historical_migration               boolean not null default false,
  add column historical_stage                      public.historical_stage,
  add column historical_collected_before_migration numeric(14,0) not null default 0
    check (historical_collected_before_migration >= 0),
  add column historical_reference                  text,
  add column historical_delivered_at               date,
  add column historical_delivery_receiver          text,
  add constraint orders_historical_fields check (
    (is_historical_migration
      and historical_stage is not null
      and historical_reference is not null and length(trim(historical_reference)) between 3 and 200
      and historical_collected_before_migration <= total_amount)
    or (not is_historical_migration
      and historical_stage is null and historical_reference is null
      and historical_collected_before_migration = 0
      and historical_delivered_at is null and historical_delivery_receiver is null)
  );

-- Una misma referencia de origen (hoja/fila/orden del archivo) no se carga dos veces
create unique index orders_historical_reference_key
  on public.orders (lower(trim(historical_reference)))
  where is_historical_migration;
create index orders_historical_idx on public.orders (created_at) where is_historical_migration;

-- Un histórico por nómina puede no tener convenio en el CRM, y si ya no
-- tiene saldo, tampoco plan de cuotas
alter table public.orders drop constraint orders_payroll_plan;
alter table public.orders add constraint orders_payroll_plan check (
  payment_modality <> 'nomina_empresa'
  or (company_id is not null
      and (agreement_id is not null or is_historical_migration)
      and ((installments_count is not null and installment_periodicity is not null and first_due_date is not null)
           or (is_historical_migration and installments_count is null and first_due_date is null)))
);

-- ---------------------------------------------------------------------
-- 1. Pagado = asignaciones vigentes + lo recaudado antes de migrar
-- ---------------------------------------------------------------------
create or replace function private.order_verified_paid(p_order_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select sum(a.amount_applied + a.withholding_applied)
    from public.payment_allocations a
    where a.order_id = p_order_id and not a.is_voided
  ), 0)
  + coalesce((select o.historical_collected_before_migration from public.orders o where o.id = p_order_id), 0);
$$;

-- Usa el valor de la fila (en un INSERT la orden aún no existe en la tabla)
create or replace function private.orders_compute_collection()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_paid numeric := coalesce((
    select sum(a.amount_applied + a.withholding_applied)
    from public.payment_allocations a
    where a.order_id = new.id and not a.is_voided
  ), 0) + new.historical_collected_before_migration;
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

-- ---------------------------------------------------------------------
-- 2. Reglas de la orden, plan de cuotas y estado operativo
-- orders_before_write (misma función; cambian 4 puntos para históricos):
--   responsable de cobro declarado, nómina sin convenio, periodicidad del
--   plan restante y sin revalidar requisitos de una venta anterior al CRM.
-- ---------------------------------------------------------------------
-- orders_before_write: ver cabecera (§2)
create or replace function private.orders_before_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $$
declare
  v_is_api boolean := current_user = 'authenticated';
  v_campaign record;
  v_agreement record;
  v_max numeric;
  v_missing text[];
  v_plan_changed boolean;
begin
  if tg_op = 'INSERT' then
    if v_is_api then
      new.total_amount := 0;
      new.balance_due := 0;
      new.requirements_verified := false;
      new.requirements_verified_by := null;
      new.requirements_verified_at := null;
      new.prepayment_exception_reason := null;
      new.prepayment_exception_by := null;
      new.prepayment_exception_at := null;
      new.ops_status := 'pendiente_liberar';
      new.accounting_status := 'pendiente_vincular';
      new.collection_status := 'con_saldo';
      new.is_cancelled := false;
      new.cancelled_by := null;
      new.cancelled_at := null;
      new.cancel_reason := null;
    end if;

    -- Herencia de contexto (RF-M04-01)
    if new.campaign_id is not null then
      select c.company_id, c.branch_id, c.city_id, c.agreement_id, c.status
        into v_campaign
      from public.campaigns_jornadas c
      where c.id = new.campaign_id;
      if not found then
        raise exception 'Jornada no encontrada';
      end if;
      if v_is_api and v_campaign.status <> 'en_ejecucion' then
        raise exception 'Las órdenes de jornada se registran con la jornada en_ejecucion (está %). Para una venta tardía, reabra la captura',
          v_campaign.status;
      end if;
      new.company_id := v_campaign.company_id;
      new.branch_id := v_campaign.branch_id;
      new.city_id := v_campaign.city_id;
      new.agreement_id := v_campaign.agreement_id;
    elsif new.company_id is null then
      new.branch_id := null;
      new.agreement_id := null;
    end if;

    if v_is_api and not exists (
      select 1 from public.buyers b where b.id = new.buyer_id and b.data_consent_at is not null
    ) then
      raise exception 'Registre la autorización de tratamiento de datos del comprador antes de crear la orden';
    end if;

    -- Un histórico declara su responsable de cobro actual (RF-M06-05)
    if not new.is_historical_migration then
      new.collection_responsible := case when new.payment_modality = 'nomina_empresa' then 'empresa' else 'empleado' end;
    end if;

  elsif v_is_api then
    if old.is_cancelled then
      raise exception 'Una orden anulada no se modifica';
    end if;

    if (new.campaign_id, new.company_id, new.buyer_id)
       is distinct from (old.campaign_id, old.company_id, old.buyer_id) then
      raise exception 'La jornada, la empresa y el comprador de una orden no se cambian; anule y registre una nueva';
    end if;

    if new.campaign_id is not null and new.agreement_id is distinct from old.agreement_id then
      raise exception 'Una orden de jornada usa el convenio de la jornada';
    end if;
    if new.campaign_id is not null and new.branch_id is distinct from old.branch_id then
      raise exception 'Una orden de jornada usa la sede de la jornada';
    end if;

    -- Datos de la venta: Comercial hasta la verificación; después, Administración
    if (new.branch_id, new.agreement_id, new.payment_modality, new.installments_count, new.first_due_date,
        new.employee_auth_received, new.employee_auth_file_r2_key, new.hr_approval_received,
        new.hr_approval_r2_key, new.notes)
       is distinct from
       (old.branch_id, old.agreement_id, old.payment_modality, old.installments_count, old.first_due_date,
        old.employee_auth_received, old.employee_auth_file_r2_key, old.hr_approval_received,
        old.hr_approval_r2_key, old.notes) then
      if old.doc_status = 'pendiente_soportes' then
        if not private.has_role('comercial', 'administracion_cartera') then
          raise exception 'Solo Comercial o Administración / Cartera modifican la orden' using errcode = '42501';
        end if;
      elsif not private.has_role('administracion_cartera') then
        raise exception 'Con los requisitos verificados, solo Administración / Cartera modifica la orden'
          using errcode = '42501';
      end if;

      if old.ops_status <> 'pendiente_liberar'
         and (new.agreement_id, new.payment_modality, new.installments_count, new.first_due_date)
             is distinct from
             (old.agreement_id, old.payment_modality, old.installments_count, old.first_due_date) then
        raise exception 'La orden ya fue liberada a producción; su modalidad y plan de pagos no se cambian';
      end if;
    end if;

    -- Excepción de anticipo en contado (RF-M04-03): solo Dirección
    if new.prepayment_exception_reason is distinct from old.prepayment_exception_reason then
      if not private.has_role('direccion') then
        raise exception 'Solo Dirección autoriza la excepción de anticipo' using errcode = '42501';
      end if;
      if old.ops_status <> 'pendiente_liberar' then
        raise exception 'La orden ya fue liberada a producción';
      end if;
      if new.prepayment_exception_reason is null then
        new.prepayment_exception_by := null;
        new.prepayment_exception_at := null;
      else
        new.prepayment_exception_by := (select auth.uid());
        new.prepayment_exception_at := now();
      end if;
    end if;

    -- Verificación de requisitos (Etapa 07 → 08): Administración / Cartera
    if new.requirements_verified is distinct from old.requirements_verified then
      if not private.has_role('administracion_cartera') then
        raise exception 'Solo Administración / Cartera verifica los requisitos de la orden' using errcode = '42501';
      end if;
      if new.requirements_verified then
        new.requirements_verified_by := (select auth.uid());
        new.requirements_verified_at := now();
      else
        if old.ops_status <> 'pendiente_liberar' then
          raise exception 'La orden ya fue liberada a producción; la verificación no se revierte';
        end if;
        new.requirements_verified_by := null;
        new.requirements_verified_at := null;
      end if;
    end if;

    -- Anulación (RF-M04-05)
    if new.is_cancelled and not old.is_cancelled then
      if not (private.has_role('administracion_cartera')
              or (private.has_role('comercial') and old.doc_status = 'pendiente_soportes')) then
        raise exception 'Con los requisitos verificados, solo Administración / Cartera anula la orden'
          using errcode = '42501';
      end if;
      if old.accounting_status <> 'pendiente_vincular'
         or old.collection_status <> 'con_saldo'
         or old.balance_due < old.total_amount then
        raise exception 'La orden tiene pagos aplicados o factura vinculada: gestiónela como posventa o nota crédito en Alegra';
      end if;
      new.cancelled_by := (select auth.uid());
      new.cancelled_at := now();
    end if;
  end if;

  -- Ciudad de la Venta Directa: la de la sede elegida
  if new.campaign_id is null then
    new.city_id := (select b.city_id from public.company_branches b where b.id = new.branch_id);
  end if;

  v_plan_changed := tg_op = 'INSERT'
    or (new.payment_modality, new.agreement_id, new.installments_count)
       is distinct from (old.payment_modality, old.agreement_id, old.installments_count);

  -- Convenio de una Venta Directa: aprobado y vigente
  if v_is_api and new.campaign_id is null and new.agreement_id is not null
     and (tg_op = 'INSERT' or new.agreement_id is distinct from old.agreement_id
          or new.payment_modality is distinct from old.payment_modality)
     and not exists (
       select 1 from public.agreements_convenios a
       where a.id = new.agreement_id
         and a.company_id = new.company_id
         and a.status = 'aprobado'
         and (a.valid_until is null or a.valid_until >= private.today_co())
     ) then
    raise exception 'El convenio de la orden debe estar aprobado y vigente';
  end if;

  -- Descuento de nómina: periodicidad y tope de cuotas del convenio
  if new.payment_modality = 'nomina_empresa' then
    if new.agreement_id is null and not new.is_historical_migration then
      raise exception 'El descuento de nómina requiere una empresa con convenio aprobado';
    end if;
    select a.status, a.payroll_frequency, a.max_installments
      into v_agreement
    from public.agreements_convenios a
    where a.id = new.agreement_id;

    -- Un histórico conserva la periodicidad de su plan restante
    if not new.is_historical_migration then
      new.installment_periodicity := v_agreement.payroll_frequency;
    end if;

    if v_is_api and v_plan_changed then
      if v_agreement.status <> 'aprobado' then
        raise exception 'El descuento de nómina requiere un convenio aprobado (el de esta orden está %)',
          v_agreement.status;
      end if;
      v_max := least(
        v_agreement.max_installments,
        private.get_setting(case v_agreement.payroll_frequency
          when 'mensual' then 'max_installments_monthly'
          else 'max_installments_biweekly' end)
      );
      if new.installments_count > v_max then
        raise exception 'El convenio permite hasta % cuotas con nómina %', v_max, v_agreement.payroll_frequency;
      end if;
    end if;
  else
    new.installments_count := null;
    new.installment_periodicity := null;
    new.first_due_date := null;
    new.employee_auth_received := false;
    new.employee_auth_file_r2_key := null;
    new.hr_approval_received := false;
    new.hr_approval_r2_key := null;
  end if;

  if tg_op = 'UPDATE' and new.payment_modality is distinct from old.payment_modality then
    new.collection_responsible := case when new.payment_modality = 'nomina_empresa' then 'empresa' else 'empleado' end;
    if new.payment_modality <> 'contado' then
      new.prepayment_exception_reason := null;
      new.prepayment_exception_by := null;
      new.prepayment_exception_at := null;
    end if;
  end if;

  -- Una orden verificada debe seguir cumpliendo sus requisitos
  if new.requirements_verified and not new.is_cancelled and not new.is_historical_migration then
    v_missing := private.order_missing_requirements(new);
    if cardinality(v_missing) > 0 then
      raise exception 'Faltan requisitos: %', array_to_string(v_missing, '; ');
    end if;
  end if;

  -- Estados derivados (RF-M04-04). Saldo = valor total hasta que M06
  -- registre pagos; los demás estados los derivan M05 y M06.
  new.doc_status := case when new.requirements_verified then 'requisitos_verificados' else 'pendiente_soportes' end;
  new.balance_due := new.total_amount;

  return new;
end;
$$;

-- Plan de cuotas: un histórico reparte el saldo vivo
create or replace function private.rebuild_order_installments(p_order_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_order public.orders;
  v_base numeric(14,0);
  v_total numeric(14,0);
begin
  select * into v_order from public.orders o where o.id = p_order_id;

  if exists (select 1 from public.order_installments i where i.order_id = p_order_id and i.paid_amount > 0) then
    raise exception 'La orden tiene pagos aplicados a sus cuotas; el plan no se puede regenerar';
  end if;

  delete from public.order_installments i where i.order_id = p_order_id;

  if v_order.payment_modality <> 'nomina_empresa' or v_order.installments_count is null then
    return;
  end if;

  -- Un histórico reparte solo lo que faltaba al migrar
  v_total := v_order.total_amount - v_order.historical_collected_before_migration;
  v_base := floor(v_total / v_order.installments_count);

  insert into public.order_installments (order_id, installment_number, due_date, expected_amount)
  select
    v_order.id,
    n,
    private.installment_due_date(v_order.first_due_date, v_order.installment_periodicity, n),
    -- El residuo de la división va en la primera cuota
    case when n = 1 then v_total - v_base * (v_order.installments_count - 1) else v_base end
  from generate_series(1, v_order.installments_count) as n;
end;
$$;

-- Estado operativo: un histórico sin producción conserva lo declarado
create or replace function private.refresh_order_ops_status(p_order_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_production public.production_status;
  v_full boolean;
  v_any boolean;
  v_status public.order_ops_status;
begin
  select p.status into v_production
  from public.order_productions p
  where p.order_id = p_order_id and p.warranty_id is null and p.status <> 'cancelada';

  -- Histórico cargado en producción o entregado sin registro de laboratorio:
  -- conserva el estado declarado
  if v_production is null and exists (
    select 1 from public.orders o
    where o.id = p_order_id and o.is_historical_migration and o.historical_stage <> 'venta'
  ) then
    return;
  end if;

  select coalesce(bool_and(coalesce(d.qty, 0) >= i.quantity), false),
         coalesce(bool_or(coalesce(d.qty, 0) > 0), false)
    into v_full, v_any
  from public.order_items i
  left join (
    select di.order_item_id, sum(di.quantity) as qty
    from public.order_delivery_items di
    join public.order_deliveries dl on dl.id = di.delivery_id
    where di.order_id = p_order_id and dl.warranty_id is null
    group by di.order_item_id
  ) d on d.order_item_id = i.id
  where i.order_id = p_order_id;

  v_status := case
    when v_production is null then 'pendiente_liberar'
    when v_full then 'entrega_completa'
    when v_any then 'entrega_parcial'
    when v_production = 'listo_para_entregar' then 'listo_para_entregar'
    else 'en_produccion'
  end;

  update public.orders o
  set ops_status = v_status
  where o.id = p_order_id and o.ops_status is distinct from v_status;
end;
$$;

-- Un histórico no cambia su origen ni su plan por la API: se anula y se
-- carga de nuevo
create function private.orders_historical_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user <> 'authenticated' then
    return new;
  end if;
  if new.is_historical_migration is distinct from old.is_historical_migration
     or (old.is_historical_migration
         and (new.payment_modality, new.installments_count, new.first_due_date, new.agreement_id,
              new.company_id, new.historical_collected_before_migration, new.historical_stage,
              new.historical_reference)
             is distinct from
             (old.payment_modality, old.installments_count, old.first_due_date, old.agreement_id,
              old.company_id, old.historical_collected_before_migration, old.historical_stage,
              old.historical_reference)) then
    raise exception 'Una orden histórica no cambia su modalidad, plan ni datos de origen; anúlela y cárguela de nuevo';
  end if;
  return new;
end;
$$;

create trigger orders_historical_guard
  before update on public.orders
  for each row execute function private.orders_historical_guard();

-- ---------------------------------------------------------------------
-- 3. Carga de una orden histórica (Administración / Cartera)
-- p_order: buyer_id, company_id, agreement_id, payment_modality,
--   collection_responsible, total_amount, balance_due (saldo vivo),
--   historical_stage, historical_reference, installments_count,
--   installment_periodicity, first_due_date, notes
-- p_items: opcional en producción/entregada; obligatorio en venta. Si se
--   envían, deben sumar el valor total.
-- ---------------------------------------------------------------------
create function public.create_historical_order(p_order jsonb, p_items jsonb default '[]'::jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_balance numeric;
  v_items_total numeric;
  v_items_count int;
  v_id uuid;
  v_ops public.order_ops_status;
begin
  if not private.has_role('administracion_cartera') then
    raise exception 'Solo Administración / Cartera carga órdenes históricas' using errcode = '42501';
  end if;

  select * into r from jsonb_to_record(p_order) as x (
    buyer_id uuid, company_id uuid, agreement_id uuid, payment_modality public.payment_modality,
    collection_responsible public.collection_responsible, total_amount numeric, balance_due numeric,
    historical_stage public.historical_stage, historical_reference text, installments_count smallint,
    installment_periodicity public.payroll_frequency, first_due_date date, notes text
  );

  if r.buyer_id is null or r.payment_modality is null or r.collection_responsible is null
     or r.total_amount is null or r.balance_due is null or r.historical_stage is null then
    raise exception 'Faltan datos: comprador, modalidad, responsable de cobro, valor total, saldo vivo y etapa son obligatorios';
  end if;
  if not exists (select 1 from public.buyers b where b.id = r.buyer_id and b.data_consent_at is not null) then
    raise exception 'Registre la autorización de tratamiento de datos del comprador antes de cargar la orden';
  end if;
  if r.total_amount <= 0 or r.total_amount <> trunc(r.total_amount) then
    raise exception 'El valor total debe ser un entero mayor que cero';
  end if;
  if r.balance_due < 0 or r.balance_due > r.total_amount or r.balance_due <> trunc(r.balance_due) then
    raise exception 'El saldo vivo debe estar entre 0 y el valor total';
  end if;
  v_balance := r.balance_due;

  if r.payment_modality = 'nomina_empresa' then
    if r.company_id is null then
      raise exception 'Una orden por nómina necesita la empresa';
    end if;
  elsif r.collection_responsible <> 'empleado' then
    raise exception 'Una venta de contado se cobra al comprador';
  end if;
  if r.agreement_id is not null and r.company_id is null then
    raise exception 'El convenio requiere la empresa';
  end if;

  -- Plan restante: solo nómina con saldo
  if r.payment_modality = 'nomina_empresa' and v_balance > 0 then
    if r.installments_count is null or r.installment_periodicity is null or r.first_due_date is null then
      raise exception 'Con saldo por nómina indique cuotas restantes, periodicidad y fecha de la próxima cuota';
    end if;
    if r.installments_count not between 1 and 24 then
      raise exception 'Las cuotas restantes deben estar entre 1 y 24';
    end if;
  else
    r.installments_count := null;
    r.installment_periodicity := null;
    r.first_due_date := null;
  end if;

  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) is distinct from 'array' then
    raise exception 'Ítems inválidos';
  end if;
  select count(*), coalesce(sum(x.quantity * x.unit_price), 0) into v_items_count, v_items_total
  from jsonb_to_recordset(coalesce(p_items, '[]'::jsonb)) as x (quantity int, unit_price numeric);
  if r.historical_stage = 'venta' and v_items_count = 0 then
    raise exception 'Una venta pendiente de producir necesita sus ítems (montura, lente…) para seguir el flujo normal';
  end if;
  if v_items_count > 0 and v_items_total <> r.total_amount then
    raise exception 'Los ítems suman % y el valor total es %', v_items_total, r.total_amount;
  end if;

  v_ops := case r.historical_stage
    when 'venta' then 'pendiente_liberar'
    when 'produccion' then 'en_produccion'
    else 'entrega_completa'
  end;

  insert into public.orders (
    company_id, agreement_id, buyer_id, payment_modality, collection_responsible,
    installments_count, installment_periodicity, first_due_date, total_amount,
    is_historical_migration, historical_stage, historical_collected_before_migration, historical_reference,
    requirements_verified, requirements_verified_by, requirements_verified_at,
    ops_status, notes, created_by
  ) values (
    r.company_id, r.agreement_id, r.buyer_id, r.payment_modality, r.collection_responsible,
    r.installments_count, r.installment_periodicity, r.first_due_date, r.total_amount,
    true, r.historical_stage, r.total_amount - v_balance, trim(r.historical_reference),
    r.historical_stage <> 'venta',
    case when r.historical_stage <> 'venta' then (select auth.uid()) end,
    case when r.historical_stage <> 'venta' then now() end,
    v_ops, nullif(trim(r.notes), ''), (select auth.uid())
  )
  returning id into v_id;

  insert into public.order_items (
    order_id, item_type, frame_description, lens_type, lens_filter, description, quantity, unit_price
  )
  select v_id, x.item_type, x.frame_description, x.lens_type, x.lens_filter, x.description, x.quantity, x.unit_price
  from jsonb_populate_recordset(null::public.order_items, coalesce(p_items, '[]'::jsonb)) x;

  return v_id;
end;
$$;

revoke execute on function public.create_historical_order(jsonb, jsonb) from public, anon;
grant execute on function public.create_historical_order(jsonb, jsonb) to authenticated;

-- Entrega de un histórico cargado en producción sin registro de laboratorio
create function public.register_historical_delivery(p_order_id uuid, p_delivered_at date, p_receiver text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
begin
  if not private.has_role('operacion') then
    raise exception 'Solo Operación registra entregas' using errcode = '42501';
  end if;
  select o.is_historical_migration, o.historical_stage, o.is_cancelled, o.ops_status into v_order
  from public.orders o where o.id = p_order_id for update;
  if not found or not v_order.is_historical_migration or v_order.historical_stage <> 'produccion' then
    raise exception 'Solo aplica a órdenes históricas cargadas en producción';
  end if;
  if v_order.is_cancelled then
    raise exception 'La orden está anulada';
  end if;
  if v_order.ops_status not in ('en_produccion', 'listo_para_entregar') then
    raise exception 'La orden ya está entregada';
  end if;
  if exists (select 1 from public.order_productions p
             where p.order_id = p_order_id and p.warranty_id is null and p.status <> 'cancelada') then
    raise exception 'La orden tiene producción registrada: use el registro de entregas normal';
  end if;
  if p_delivered_at is null or p_delivered_at > private.today_co() then
    raise exception 'La fecha de entrega no puede ser futura';
  end if;
  if p_receiver is null or length(trim(p_receiver)) = 0 then
    raise exception 'Indique quién recibió';
  end if;

  update public.orders o
  set historical_delivered_at = p_delivered_at,
      historical_delivery_receiver = trim(p_receiver),
      ops_status = 'entrega_completa'
  where o.id = p_order_id;
end;
$$;

revoke execute on function public.register_historical_delivery(uuid, date, text) from public, anon;
grant execute on function public.register_historical_delivery(uuid, date, text) to authenticated;


-- ---------------------------------------------------------------------
-- 4. v_orders: datos del histórico (columnas nuevas al final)
-- ---------------------------------------------------------------------
create or replace view public.v_orders
with (security_invoker = true)
as
 SELECT o.id,
    o.order_number,
    o.campaign_id,
    j.deal_id,
    d.deal_name_branch,
    j.status AS campaign_status,
    o.company_id,
    c.name AS company_name,
    o.branch_id,
    br.name AS branch_name,
    o.city_id,
    ci.name AS city_name,
    o.agreement_id,
    o.buyer_id,
    b.full_name AS buyer_name,
    b.document_type AS buyer_document_type,
    b.document_id AS buyer_document_id,
    o.total_amount,
    o.balance_due,
    o.payment_modality,
    o.collection_responsible,
    o.installments_count,
    o.installment_periodicity,
    o.first_due_date,
    o.employee_auth_received,
    o.hr_approval_received,
    a.hr_approval_required,
    o.prepayment_exception_reason,
    o.prepayment_exception_by,
    o.prepayment_exception_at,
    o.requirements_verified,
    o.requirements_verified_by,
    o.requirements_verified_at,
    o.doc_status,
    o.ops_status,
    o.accounting_status,
    o.collection_status,
    o.is_cancelled,
    o.cancelled_by,
    o.cancelled_at,
    o.cancel_reason,
    o.notes,
    ( SELECT count(*) AS count
           FROM order_items i
          WHERE (i.order_id = o.id)) AS items_count,
    private.order_missing_requirements(o.*) AS missing_requirements,
    o.created_by,
    u.full_name AS created_by_name,
    o.created_at,
    o.updated_at,
    private.order_release_blockers(o.*) AS release_blockers,
    o.is_historical_migration,
    o.historical_stage,
    o.historical_collected_before_migration,
    o.historical_reference,
    o.historical_delivered_at,
    o.historical_delivery_receiver
   FROM ((((((((orders o
     JOIN buyers b ON ((b.id = o.buyer_id)))
     LEFT JOIN companies c ON ((c.id = o.company_id)))
     LEFT JOIN company_branches br ON ((br.id = o.branch_id)))
     LEFT JOIN cities ci ON ((ci.id = o.city_id)))
     LEFT JOIN campaigns_jornadas j ON ((j.id = o.campaign_id)))
     LEFT JOIN deals_opportunities d ON ((d.id = j.deal_id)))
     LEFT JOIN agreements_convenios a ON ((a.id = o.agreement_id)))
     LEFT JOIN users_profiles u ON ((u.id = o.created_by)));
