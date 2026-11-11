-- =====================================================================
-- M04 Ventas y Órdenes (Etapa 07)
-- Referencias SRS v1.4: RF-M04-01 a RF-M04-05, §5.5 (buyers, orders,
-- order_items), §5.7.24 (order_installments), §3.2 (matriz RBAC),
-- RNF-05 (autorización de tratamiento de datos).
--
-- Decisiones de alcance (11-nov-2026):
-- * Órdenes de jornada: se registran con la jornada En Ejecución o Cerrada.
-- * Crea órdenes solo Comercial; Administración / Cartera verifica
--   requisitos y, después de verificar, es la única que modifica.
-- * Venta Directa: contado (con o sin empresa) o nómina si la empresa
--   tiene un convenio aprobado y vigente.
-- * El plan de cuotas se genera aquí. Los estados operativo, contable y
--   de cartera quedan en su valor inicial hasta M05/M06, que los derivan
--   de producción, entregas, facturas y pagos.
-- * La carga de históricos (RF-M06-05) llega con M06.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------
create type public.buyer_document_type as enum ('cc', 'ce', 'ti', 'pasaporte', 'otro');
create type public.payment_modality as enum ('contado', 'nomina_empresa');
create type public.collection_responsible as enum ('empresa', 'empleado');
create type public.order_item_type as enum ('gafas_completas', 'montura', 'lentes', 'otro');
create type public.order_doc_status as enum ('pendiente_soportes', 'requisitos_verificados');
create type public.order_ops_status as enum (
  'pendiente_liberar', 'en_produccion', 'listo_para_entregar', 'entrega_parcial', 'entrega_completa'
);
create type public.order_accounting_status as enum (
  'pendiente_vincular', 'factura_vinculada', 'factura_con_diferencia'
);
create type public.order_collection_status as enum (
  'con_saldo', 'parcialmente_recaudado', 'recaudado_total'
);

-- ---------------------------------------------------------------------
-- Compradores (RF-M04-02, §5.5.15)
-- ---------------------------------------------------------------------
create table public.buyers (
  id                  uuid primary key default gen_random_uuid(),
  document_type       public.buyer_document_type not null,
  document_id         text not null check (document_id ~ '^[0-9A-Z]{4,15}$'),
  full_name           text not null check (length(trim(full_name)) > 0),
  phone               text check (phone is null or phone ~ '^\+?[0-9 ()-]{7,20}$'),
  email               text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  current_company_id  uuid references public.companies (id),
  data_consent_at     timestamptz,
  data_consent_by     uuid references public.users_profiles (id),
  data_consent_r2_key text check (data_consent_r2_key is null or length(trim(data_consent_r2_key)) > 0),
  created_by          uuid default auth.uid() references public.users_profiles (id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint buyers_document_key unique (document_type, document_id)
);

create index buyers_document_id_idx on public.buyers (document_id);
create index buyers_current_company_id_idx on public.buyers (current_company_id);
create index buyers_data_consent_by_idx on public.buyers (data_consent_by);
create index buyers_created_by_idx on public.buyers (created_by);

create trigger buyers_set_updated_at
  before update on public.buyers
  for each row execute function private.set_updated_at();

create function private.buyers_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.document_id := upper(regexp_replace(coalesce(new.document_id, ''), '[\s.-]', '', 'g'));
  new.full_name := trim(new.full_name);

  if current_user <> 'authenticated' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if (new.document_type, new.document_id) is distinct from (old.document_type, old.document_id)
       and exists (select 1 from public.orders o where o.buyer_id = old.id) then
      raise exception 'El documento de un comprador con órdenes no se cambia';
    end if;

    -- La autorización de tratamiento de datos se registra una vez y no se retira
    -- desde la aplicación (las solicitudes de supresión siguen el procedimiento RNF-05)
    if old.data_consent_at is not null then
      new.data_consent_at := old.data_consent_at;
      new.data_consent_by := old.data_consent_by;
      if old.data_consent_r2_key is not null then
        new.data_consent_r2_key := old.data_consent_r2_key;
      end if;
      return new;
    end if;
  end if;

  if new.data_consent_at is not null then
    new.data_consent_at := now();
    new.data_consent_by := (select auth.uid());
  else
    new.data_consent_by := null;
  end if;
  return new;
end;
$$;

create trigger buyers_before_write
  before insert or update on public.buyers
  for each row execute function private.buyers_before_write();

-- ---------------------------------------------------------------------
-- Órdenes (RF-M04-01 a RF-M04-05, §5.5.16)
-- ---------------------------------------------------------------------
create table public.orders (
  id                          uuid primary key default gen_random_uuid(),
  order_number                bigint generated always as identity,
  campaign_id                 uuid references public.campaigns_jornadas (id),
  company_id                  uuid references public.companies (id),
  branch_id                   uuid,
  city_id                     uuid references public.cities (id),
  agreement_id                uuid,
  buyer_id                    uuid not null references public.buyers (id),
  total_amount                numeric(14,0) not null default 0 check (total_amount >= 0),
  payment_modality            public.payment_modality not null,
  collection_responsible      public.collection_responsible not null default 'empleado',
  installments_count          smallint check (installments_count between 1 and 24),
  installment_periodicity     public.payroll_frequency,
  first_due_date              date,
  employee_auth_received      boolean not null default false,
  employee_auth_file_r2_key   text check (employee_auth_file_r2_key is null or length(trim(employee_auth_file_r2_key)) > 0),
  hr_approval_received        boolean not null default false,
  hr_approval_r2_key          text check (hr_approval_r2_key is null or length(trim(hr_approval_r2_key)) > 0),
  prepayment_exception_reason text check (prepayment_exception_reason is null or length(trim(prepayment_exception_reason)) > 0),
  prepayment_exception_by     uuid references public.users_profiles (id),
  prepayment_exception_at     timestamptz,
  requirements_verified       boolean not null default false,
  requirements_verified_by    uuid references public.users_profiles (id),
  requirements_verified_at    timestamptz,
  doc_status                  public.order_doc_status not null default 'pendiente_soportes',
  ops_status                  public.order_ops_status not null default 'pendiente_liberar',
  accounting_status           public.order_accounting_status not null default 'pendiente_vincular',
  collection_status           public.order_collection_status not null default 'con_saldo',
  balance_due                 numeric(14,0) not null default 0 check (balance_due >= 0),
  is_cancelled                boolean not null default false,
  cancelled_by                uuid references public.users_profiles (id),
  cancelled_at                timestamptz,
  cancel_reason               text,
  notes                       text,
  created_by                  uuid default auth.uid() references public.users_profiles (id),
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  constraint orders_order_number_key unique (order_number),
  constraint orders_branch_same_company
    foreign key (branch_id, company_id) references public.company_branches (id, company_id),
  constraint orders_agreement_same_company
    foreign key (agreement_id, company_id) references public.agreements_convenios (id, company_id),
  constraint orders_payroll_plan check (
    payment_modality <> 'nomina_empresa'
    or (company_id is not null and agreement_id is not null and installments_count is not null
        and installment_periodicity is not null and first_due_date is not null)
  ),
  constraint orders_cash_without_plan check (
    payment_modality = 'nomina_empresa'
    or (installments_count is null and installment_periodicity is null and first_due_date is null)
  ),
  constraint orders_prepayment_exception_cash check (
    prepayment_exception_reason is null or payment_modality = 'contado'
  ),
  constraint orders_cancel_reason check (
    not is_cancelled or (cancel_reason is not null and length(trim(cancel_reason)) > 0)
  )
);

create index orders_campaign_id_idx on public.orders (campaign_id);
create index orders_company_id_idx on public.orders (company_id);
create index orders_branch_id_idx on public.orders (branch_id);
create index orders_city_id_idx on public.orders (city_id);
create index orders_agreement_id_idx on public.orders (agreement_id);
create index orders_buyer_id_idx on public.orders (buyer_id);
create index orders_doc_status_idx on public.orders (doc_status) where not is_cancelled;
create index orders_prepayment_exception_by_idx on public.orders (prepayment_exception_by);
create index orders_requirements_verified_by_idx on public.orders (requirements_verified_by);
create index orders_cancelled_by_idx on public.orders (cancelled_by);
create index orders_created_by_idx on public.orders (created_by);

create trigger orders_set_updated_at
  before update on public.orders
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Ítems de la orden (RF-M04-02, §5.5.17) — sin historia clínica
-- ---------------------------------------------------------------------
create table public.order_items (
  id                uuid primary key default gen_random_uuid(),
  order_id          uuid not null references public.orders (id),
  item_type         public.order_item_type not null,
  frame_description text,
  lens_type         text,
  lens_filter       text,
  description       text,
  quantity          integer not null check (quantity > 0),
  unit_price        numeric(14,0) not null check (unit_price >= 0),
  line_total        numeric(14,0) generated always as (quantity * unit_price) stored,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint order_items_described check (
    num_nonnulls(nullif(trim(frame_description), ''), nullif(trim(lens_type), ''),
                 nullif(trim(description), '')) >= 1
  )
);

create index order_items_order_id_idx on public.order_items (order_id);

create trigger order_items_set_updated_at
  before update on public.order_items
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Plan de cuotas de nómina (RF-M04-03, §5.7.24)
-- Lo genera la base de datos; paid_amount lo derivará M06 de las
-- asignaciones de pago. El estado (pendiente, parcial, pagada, vencida)
-- se calcula en v_order_installments.
-- ---------------------------------------------------------------------
create table public.order_installments (
  id                                uuid primary key default gen_random_uuid(),
  order_id                          uuid not null references public.orders (id),
  installment_number                smallint not null check (installment_number >= 1),
  due_date                          date not null,
  expected_amount                   numeric(14,0) not null check (expected_amount >= 0),
  paid_amount                       numeric(14,0) not null default 0 check (paid_amount >= 0),
  superseded_by_reclassification_id uuid,
  created_at                        timestamptz not null default now(),
  constraint order_installments_number_key unique (order_id, installment_number)
);

-- Fecha de la cuota n: mensual suma meses; quincenal alterna día 15 y
-- fin de mes (o la fecha + 15 días, sin pasar del fin de mes)
create function private.installment_due_date(p_first date, p_periodicity public.payroll_frequency, p_n int)
returns date
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_base date;
begin
  if p_periodicity = 'mensual' then
    return (p_first + make_interval(months => p_n - 1))::date;
  end if;

  v_base := (p_first + make_interval(months => (p_n - 1) / 2))::date;
  if (p_n - 1) % 2 = 0 then
    return v_base;
  end if;
  if extract(day from p_first) <= 15 then
    return least(v_base + 15, (date_trunc('month', v_base) + interval '1 month - 1 day')::date);
  end if;
  return (date_trunc('month', v_base) + interval '1 month 14 days')::date;
end;
$$;

revoke execute on function private.installment_due_date(date, public.payroll_frequency, int) from public, anon;
grant execute on function private.installment_due_date(date, public.payroll_frequency, int) to authenticated;

-- ---------------------------------------------------------------------
-- Requisitos pendientes para la verificación de Administración
-- (RF-M04-03). Lista vacía = la orden se puede verificar.
-- ---------------------------------------------------------------------
create function private.order_missing_requirements(o public.orders)
returns text[]
language plpgsql
stable
set search_path = ''
as $$
declare
  v_missing text[] := '{}';
  v_files boolean := private.get_setting('require_document_files') = 1;
  v_agreement record;
begin
  if o.total_amount <= 0 or not exists (select 1 from public.order_items i where i.order_id = o.id) then
    v_missing := v_missing || 'Al menos un ítem con valor'::text;
  end if;

  if not exists (
    select 1 from public.buyers b
    where b.id = o.buyer_id and b.data_consent_at is not null
      and (not v_files or b.data_consent_r2_key is not null)
  ) then
    v_missing := v_missing || 'Autorización de tratamiento de datos del comprador'::text;
  end if;

  if o.payment_modality = 'nomina_empresa' then
    select a.status, a.hr_approval_required into v_agreement
    from public.agreements_convenios a where a.id = o.agreement_id;

    if v_agreement.status is distinct from 'aprobado' then
      v_missing := v_missing || 'Convenio de nómina aprobado'::text;
    end if;
    if not o.employee_auth_received or (v_files and o.employee_auth_file_r2_key is null) then
      v_missing := v_missing || 'Autorización de descuento firmada por el empleado'::text;
    end if;
    if coalesce(v_agreement.hr_approval_required, true)
       and (not o.hr_approval_received or (v_files and o.hr_approval_r2_key is null)) then
      v_missing := v_missing || 'Aval de RRHH'::text;
    end if;
  end if;

  return v_missing;
end;
$$;

revoke execute on function private.order_missing_requirements(public.orders) from public, anon;
grant execute on function private.order_missing_requirements(public.orders) to authenticated;

-- ---------------------------------------------------------------------
-- Reglas de la orden
-- ---------------------------------------------------------------------
create function private.orders_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
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
      if v_is_api and v_campaign.status not in ('en_ejecucion', 'cerrada') then
        raise exception 'Las órdenes de jornada se registran con la jornada En Ejecución o Cerrada (está %)',
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

    new.collection_responsible := case when new.payment_modality = 'nomina_empresa' then 'empresa' else 'empleado' end;

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
    if new.agreement_id is null then
      raise exception 'El descuento de nómina requiere una empresa con convenio aprobado';
    end if;
    select a.status, a.payroll_frequency, a.max_installments
      into v_agreement
    from public.agreements_convenios a
    where a.id = new.agreement_id;

    new.installment_periodicity := v_agreement.payroll_frequency;

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
  if new.requirements_verified and not new.is_cancelled then
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

create trigger orders_before_write
  before insert or update on public.orders
  for each row execute function private.orders_before_write();

-- Regenera el plan de cuotas cuando cambian el valor o las condiciones
create function private.rebuild_order_installments(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders;
  v_base numeric(14,0);
begin
  select * into v_order from public.orders o where o.id = p_order_id;

  if exists (select 1 from public.order_installments i where i.order_id = p_order_id and i.paid_amount > 0) then
    raise exception 'La orden tiene pagos aplicados a sus cuotas; el plan no se puede regenerar';
  end if;

  delete from public.order_installments i where i.order_id = p_order_id;

  if v_order.payment_modality <> 'nomina_empresa' then
    return;
  end if;

  v_base := floor(v_order.total_amount / v_order.installments_count);

  insert into public.order_installments (order_id, installment_number, due_date, expected_amount)
  select
    v_order.id,
    n,
    private.installment_due_date(v_order.first_due_date, v_order.installment_periodicity, n),
    -- El residuo de la división va en la primera cuota
    case when n = 1 then v_order.total_amount - v_base * (v_order.installments_count - 1) else v_base end
  from generate_series(1, v_order.installments_count) as n;
end;
$$;

revoke execute on function private.rebuild_order_installments(uuid) from public, anon, authenticated;

create function private.orders_after_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT'
     or (new.total_amount, new.payment_modality, new.installments_count, new.first_due_date,
         new.installment_periodicity)
        is distinct from
        (old.total_amount, old.payment_modality, old.installments_count, old.first_due_date,
         old.installment_periodicity) then
    perform private.rebuild_order_installments(new.id);
  end if;

  if tg_op = 'INSERT' then
    -- Empresa actual del comprador
    if new.company_id is not null then
      update public.buyers b
      set current_company_id = new.company_id
      where b.id = new.buyer_id
        and b.current_company_id is distinct from new.company_id;
    end if;

    -- Vincula al comprador con su registro de asistencia en la jornada
    if new.campaign_id is not null then
      update public.campaign_attendance a
      set buyer_id = new.buyer_id
      from public.buyers b
      where b.id = new.buyer_id
        and a.campaign_id = new.campaign_id
        and a.document_id = b.document_id
        and a.buyer_id is null;
    end if;
  end if;

  return null;
end;
$$;

revoke execute on function private.orders_after_write() from public, anon, authenticated;

create trigger orders_after_write
  after insert or update on public.orders
  for each row execute function private.orders_after_write();

-- Ítems: misma regla de edición que la orden
create function private.order_items_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_order record;
begin
  if current_user <> 'authenticated' then
    return coalesce(new, old);
  end if;

  if tg_op = 'UPDATE' and new.order_id is distinct from old.order_id then
    raise exception 'Un ítem no se traslada a otra orden';
  end if;

  select o.is_cancelled, o.doc_status, o.ops_status into v_order
  from public.orders o
  where o.id = coalesce(new.order_id, old.order_id);

  if v_order.is_cancelled then
    raise exception 'Una orden anulada no se modifica';
  end if;
  if v_order.ops_status <> 'pendiente_liberar' then
    raise exception 'La orden ya fue liberada a producción; sus ítems no se modifican';
  end if;
  if v_order.doc_status = 'pendiente_soportes' then
    if not private.has_role('comercial', 'administracion_cartera') then
      raise exception 'Solo Comercial o Administración / Cartera modifican la orden' using errcode = '42501';
    end if;
  elsif not private.has_role('administracion_cartera') then
    raise exception 'Con los requisitos verificados, solo Administración / Cartera modifica la orden'
      using errcode = '42501';
  end if;

  return coalesce(new, old);
end;
$$;

create trigger order_items_guard
  before insert or update or delete on public.order_items
  for each row execute function private.order_items_guard();

-- Valor total de la orden = suma de sus ítems
create function private.order_items_after_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid := coalesce(new.order_id, old.order_id);
begin
  update public.orders o
  set total_amount = coalesce((
    select sum(i.line_total) from public.order_items i where i.order_id = v_order_id
  ), 0)
  where o.id = v_order_id;
  return null;
end;
$$;

revoke execute on function private.order_items_after_write() from public, anon, authenticated;

create trigger order_items_after_write
  after insert or update or delete on public.order_items
  for each row execute function private.order_items_after_write();

-- ---------------------------------------------------------------------
-- Asistencia: vínculo con el comprador (RF-M03-03). Lo escribe solo la
-- base de datos al registrar la orden.
-- ---------------------------------------------------------------------
alter table public.campaign_attendance
  add column buyer_id uuid references public.buyers (id);

create index campaign_attendance_buyer_id_idx on public.campaign_attendance (buyer_id);

-- ---------------------------------------------------------------------
-- Creación atómica de la orden con sus ítems (SECURITY INVOKER: aplican
-- los permisos y reglas del usuario que llama)
-- ---------------------------------------------------------------------
create function public.create_order(p_order jsonb, p_items jsonb)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La orden necesita al menos un ítem';
  end if;

  insert into public.orders (
    campaign_id, company_id, branch_id, agreement_id, buyer_id, payment_modality,
    installments_count, first_due_date, employee_auth_received, hr_approval_received, notes
  )
  select
    r.campaign_id, r.company_id, r.branch_id, r.agreement_id, r.buyer_id, r.payment_modality,
    r.installments_count, r.first_due_date,
    coalesce(r.employee_auth_received, false), coalesce(r.hr_approval_received, false), r.notes
  from jsonb_populate_record(null::public.orders, p_order) r
  returning id into v_id;

  insert into public.order_items (
    order_id, item_type, frame_description, lens_type, lens_filter, description, quantity, unit_price
  )
  select
    v_id, r.item_type, r.frame_description, r.lens_type, r.lens_filter, r.description, r.quantity, r.unit_price
  from jsonb_populate_recordset(null::public.order_items, p_items) r;

  return v_id;
end;
$$;

revoke execute on function public.create_order(jsonb, jsonb) from public, anon;
grant execute on function public.create_order(jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- Vistas
-- ---------------------------------------------------------------------
create view public.v_orders
with (security_invoker = true)
as
select
  o.id,
  o.order_number,
  o.campaign_id,
  j.deal_id,
  d.deal_name_branch,
  j.status as campaign_status,
  o.company_id,
  c.name as company_name,
  o.branch_id,
  br.name as branch_name,
  o.city_id,
  ci.name as city_name,
  o.agreement_id,
  o.buyer_id,
  b.full_name as buyer_name,
  b.document_type as buyer_document_type,
  b.document_id as buyer_document_id,
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
  (select count(*) from public.order_items i where i.order_id = o.id) as items_count,
  private.order_missing_requirements(o) as missing_requirements,
  o.created_by,
  u.full_name as created_by_name,
  o.created_at,
  o.updated_at
from public.orders o
join public.buyers b on b.id = o.buyer_id
left join public.companies c on c.id = o.company_id
left join public.company_branches br on br.id = o.branch_id
left join public.cities ci on ci.id = o.city_id
left join public.campaigns_jornadas j on j.id = o.campaign_id
left join public.deals_opportunities d on d.id = j.deal_id
left join public.agreements_convenios a on a.id = o.agreement_id
left join public.users_profiles u on u.id = o.created_by;

create view public.v_order_installments
with (security_invoker = true)
as
select
  i.id,
  i.order_id,
  i.installment_number,
  i.due_date,
  i.expected_amount,
  i.paid_amount,
  i.expected_amount - i.paid_amount as pending_amount,
  case
    when i.paid_amount >= i.expected_amount then 'pagada'
    when i.due_date < private.today_co() then 'vencida'
    when i.paid_amount > 0 then 'parcial'
    else 'pendiente'
  end as status,
  i.superseded_by_reclassification_id
from public.order_installments i;

-- ---------------------------------------------------------------------
-- Auditoría (RNF-01)
-- ---------------------------------------------------------------------
create trigger buyers_audit
  after insert or update or delete on public.buyers
  for each row execute function private.audit_row_change();
create trigger orders_audit
  after insert or update or delete on public.orders
  for each row execute function private.audit_row_change();
create trigger order_items_audit
  after insert or update or delete on public.order_items
  for each row execute function private.audit_row_change();
create trigger order_installments_audit
  after insert or update or delete on public.order_installments
  for each row execute function private.audit_row_change();

-- ---------------------------------------------------------------------
-- Privilegios
-- ---------------------------------------------------------------------
revoke all on public.buyers, public.orders, public.order_items, public.order_installments,
  public.v_orders, public.v_order_installments
  from anon, authenticated;

grant select on public.buyers to authenticated;
grant insert (document_type, document_id, full_name, phone, email, current_company_id,
              data_consent_at, data_consent_r2_key)
  on public.buyers to authenticated;
grant update (document_type, document_id, full_name, phone, email, current_company_id,
              data_consent_at, data_consent_r2_key)
  on public.buyers to authenticated;

grant select on public.orders to authenticated;
grant insert (campaign_id, company_id, branch_id, agreement_id, buyer_id, payment_modality,
              installments_count, first_due_date, employee_auth_received, employee_auth_file_r2_key,
              hr_approval_received, hr_approval_r2_key, notes)
  on public.orders to authenticated;
grant update (branch_id, agreement_id, payment_modality, installments_count, first_due_date,
              employee_auth_received, employee_auth_file_r2_key, hr_approval_received,
              hr_approval_r2_key, notes, requirements_verified, prepayment_exception_reason,
              is_cancelled, cancel_reason)
  on public.orders to authenticated;

grant select, delete on public.order_items to authenticated;
grant insert (order_id, item_type, frame_description, lens_type, lens_filter, description,
              quantity, unit_price)
  on public.order_items to authenticated;
grant update (item_type, frame_description, lens_type, lens_filter, description, quantity, unit_price)
  on public.order_items to authenticated;

grant select on public.order_installments to authenticated;

grant select on public.v_orders, public.v_order_installments to authenticated;

-- ---------------------------------------------------------------------
-- RLS (matriz §3.2, Etapa 07)
-- Comercial crea y edita hasta la verificación; Administración / Cartera
-- verifica y edita después; Dirección autoriza la excepción de anticipo;
-- Operación consulta.
-- ---------------------------------------------------------------------
alter table public.buyers             enable row level security;
alter table public.orders             enable row level security;
alter table public.order_items        enable row level security;
alter table public.order_installments enable row level security;

create policy buyers_select on public.buyers
  for select to authenticated
  using ((select private.is_internal_user()));
create policy buyers_insert on public.buyers
  for insert to authenticated
  with check ((select private.has_role('comercial', 'administracion_cartera')));
create policy buyers_update on public.buyers
  for update to authenticated
  using ((select private.has_role('comercial', 'administracion_cartera')))
  with check ((select private.has_role('comercial', 'administracion_cartera')));

create policy orders_select on public.orders
  for select to authenticated
  using ((select private.is_internal_user()));
create policy orders_insert on public.orders
  for insert to authenticated
  with check ((select private.has_role('comercial')));
create policy orders_update on public.orders
  for update to authenticated
  using ((select private.has_role('comercial', 'administracion_cartera', 'direccion')))
  with check ((select private.has_role('comercial', 'administracion_cartera', 'direccion')));

create policy order_items_select on public.order_items
  for select to authenticated
  using ((select private.is_internal_user()));
create policy order_items_insert on public.order_items
  for insert to authenticated
  with check ((select private.has_role('comercial', 'administracion_cartera')));
create policy order_items_update on public.order_items
  for update to authenticated
  using ((select private.has_role('comercial', 'administracion_cartera')))
  with check ((select private.has_role('comercial', 'administracion_cartera')));
create policy order_items_delete on public.order_items
  for delete to authenticated
  using ((select private.has_role('comercial', 'administracion_cartera')));

create policy order_installments_select on public.order_installments
  for select to authenticated
  using ((select private.is_internal_user()));
