-- =====================================================================
-- Reglas del doc «Módulo Jornadas V01» que no esperan validación:
--   1. Descuento por línea de orden (§4.3: 0 ≤ descuento ≤ cantidad ×
--      precio; neto = cantidad × precio − descuento; total del servidor).
--   2. Reprogramar una sesión con historial (§2: conserva fecha anterior,
--      motivo y actor).
--   3. Capacidad por sesión y checklist de la jornada (§4.1).
--   4. Control de edición simultánea (§4.8): la versión de sesiones se
--      verifica aquí; órdenes y jornadas la comparan en la aplicación.
-- Decisiones del 2026-11-16:
--   * Descuento en pesos, lo pone Comercial libremente; motivo obligatorio
--     si es > 0; editable solo antes de liberar (regla ya existente de
--     los ítems); queda auditado.
--   * Reprogramar es por sesión, con motivo, solo en borrador/programada y
--     solo Operación o Dirección.
--   * Capacidad opcional por sesión: superarla avisa, no bloquea.
--   * Checklist fijo obligatorio para iniciar la jornada (reemplaza a
--     «logística confirmada», que pasa a ser su primer ítem).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Descuento por línea
-- ---------------------------------------------------------------------
alter table public.order_items
  add column discount_amount numeric(14,0) not null default 0,
  add column discount_reason text;

alter table public.order_items
  add constraint order_items_discount_range
    check (discount_amount >= 0 and discount_amount <= quantity * unit_price),
  add constraint order_items_discount_reason
    check (
      (discount_amount = 0 and discount_reason is null)
      or (discount_amount > 0 and discount_reason is not null
          and length(trim(discount_reason)) > 0 and length(discount_reason) <= 500)
    );

-- Neto de la línea (V1.1): cantidad × precio unitario − descuento
alter table public.order_items
  alter column line_total set expression as (quantity * unit_price - discount_amount);

comment on column public.order_items.discount_amount is 'Descuento de la línea en pesos (0 ≤ descuento ≤ cantidad × precio unitario)';
comment on column public.order_items.line_total is 'Neto de la línea = cantidad × precio unitario − descuento';

grant insert (discount_amount, discount_reason) on public.order_items to authenticated;
grant update (discount_amount, discount_reason) on public.order_items to authenticated;

-- Creación atómica de la orden: ahora con descuento por ítem
create or replace function public.create_order(p_order jsonb, p_items jsonb)
returns uuid
language plpgsql
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
    installments_count, first_due_date, employee_auth_received, hr_approval_received,
    employee_auth_file_path, hr_approval_file_path, notes
  )
  select
    r.campaign_id, r.company_id, r.branch_id, r.agreement_id, r.buyer_id, r.payment_modality,
    r.installments_count, r.first_due_date,
    coalesce(r.employee_auth_received, false), coalesce(r.hr_approval_received, false),
    r.employee_auth_file_path, r.hr_approval_file_path, r.notes
  from jsonb_populate_record(null::public.orders, p_order) r
  returning id into v_id;

  insert into public.order_items (
    order_id, item_type, frame_description, lens_type, lens_filter, description, quantity, unit_price,
    discount_amount, discount_reason
  )
  select
    v_id, r.item_type, r.frame_description, r.lens_type, r.lens_filter, r.description, r.quantity, r.unit_price,
    coalesce(r.discount_amount, 0), nullif(trim(r.discount_reason), '')
  from jsonb_populate_recordset(null::public.order_items, p_items) r;

  return v_id;
end;
$$;

-- Orden histórica: los ítems suman su neto (con descuento)
create or replace function public.create_historical_order(p_order jsonb, p_items jsonb default '[]'::jsonb)
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
  select count(*), coalesce(sum(x.quantity * x.unit_price - coalesce(x.discount_amount, 0)), 0)
    into v_items_count, v_items_total
  from jsonb_to_recordset(coalesce(p_items, '[]'::jsonb)) as x (quantity int, unit_price numeric, discount_amount numeric);
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
    order_id, item_type, frame_description, lens_type, lens_filter, description, quantity, unit_price,
    discount_amount, discount_reason
  )
  select v_id, x.item_type, x.frame_description, x.lens_type, x.lens_filter, x.description, x.quantity, x.unit_price,
         coalesce(x.discount_amount, 0), nullif(trim(x.discount_reason), '')
  from jsonb_populate_recordset(null::public.order_items, coalesce(p_items, '[]'::jsonb)) x;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Checklist de la jornada (ítems fijos)
-- logistics_confirmed se conserva como primer ítem.
-- ---------------------------------------------------------------------
alter table public.campaigns_jornadas
  add column checklist_staff     boolean not null default false,
  add column checklist_equipment boolean not null default false,
  add column checklist_materials boolean not null default false,
  add column checklist_notice    boolean not null default false,
  add column checklist_complete  boolean generated always as (
    logistics_confirmed and checklist_staff and checklist_equipment and checklist_materials and checklist_notice
  ) stored;

comment on column public.campaigns_jornadas.logistics_confirmed is 'Checklist: lugar y logística confirmados';
comment on column public.campaigns_jornadas.checklist_staff is 'Checklist: personal asignado (optometría y asesores)';
comment on column public.campaigns_jornadas.checklist_equipment is 'Checklist: equipos de examen revisados';
comment on column public.campaigns_jornadas.checklist_materials is 'Checklist: muestrario de monturas y material listos';
comment on column public.campaigns_jornadas.checklist_notice is 'Checklist: la empresa avisó a los empleados';

-- Las jornadas que ya iniciaron cumplieron la preparación
update public.campaigns_jornadas
set logistics_confirmed = true, checklist_staff = true, checklist_equipment = true,
    checklist_materials = true, checklist_notice = true
where status in ('en_ejecucion', 'captura_cerrada', 'operacion_cerrada');

grant insert (checklist_staff, checklist_equipment, checklist_materials, checklist_notice)
  on public.campaigns_jornadas to authenticated;
grant update (checklist_staff, checklist_equipment, checklist_materials, checklist_notice)
  on public.campaigns_jornadas to authenticated;

-- Iniciar exige el checklist completo (el resto, igual que antes)
create or replace function private.campaigns_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_api boolean := current_user = 'authenticated';
  v_deal record;
  v_pending integer;
begin
  if tg_op = 'INSERT' then
    select d.company_id, d.city_id, d.branch_id, d.stage
      into v_deal
    from public.deals_opportunities d
    where d.id = new.deal_id;
    if not found then
      raise exception 'Oportunidad no encontrada';
    end if;

    -- Herencia de contexto desde la oportunidad
    new.company_id := v_deal.company_id;
    new.city_id := coalesce(new.city_id, v_deal.city_id);
    new.branch_id := coalesce(new.branch_id, v_deal.branch_id);

    if v_is_api then
      if new.status <> 'borrador' then
        raise exception 'Toda jornada nace en borrador';
      end if;
      new.scheduled_at := null;
      new.started_at := null;
      new.capture_closed_at := null;
      new.capture_reopened_at := null;
      new.reopen_reason := null;
      new.closed_at := null;
      new.cancelled_at := null;

      if v_deal.stage not in ('convenio_firmado', 'jornada_en_ejecucion') then
        raise exception 'La oportunidad debe estar en Convenio Firmado o Jornada en Ejecución (está en %)', v_deal.stage;
      end if;
      if not exists (
        select 1 from public.agreements_convenios a
        where a.id = new.agreement_id
          and a.company_id = new.company_id
          and a.status = 'aprobado'
          and (a.deal_id is null or a.deal_id = new.deal_id)
          and (a.valid_until is null or a.valid_until >= private.today_co())
      ) then
        raise exception 'La jornada requiere un convenio aprobado y vigente de la empresa para esta oportunidad';
      end if;
    end if;
  elsif v_is_api then
    if old.status in ('operacion_cerrada', 'cancelada') then
      raise exception 'Una jornada % no se puede modificar', old.status;
    end if;

    if new.reopen_reason is distinct from old.reopen_reason
       and not (old.status = 'captura_cerrada' and new.status = 'en_ejecucion') then
      raise exception 'El motivo de reapertura solo se registra al reabrir la captura';
    end if;

    if new.status is distinct from old.status then
      if old.status = 'borrador' and new.status = 'programada' then
        if not exists (select 1 from public.campaign_sessions s where s.campaign_id = new.id) then
          raise exception 'Para programar la jornada agregue al menos una sesión';
        end if;
        new.scheduled_at := now();
      elsif old.status = 'programada' and new.status = 'en_ejecucion' then
        if not (new.logistics_confirmed and new.checklist_staff and new.checklist_equipment
                and new.checklist_materials and new.checklist_notice) then
          raise exception 'No se puede iniciar la jornada con el checklist incompleto';
        end if;
        if not exists (select 1 from public.campaign_sessions s where s.campaign_id = new.id) then
          raise exception 'La jornada necesita al menos una sesión programada';
        end if;
        new.started_at := now();
      elsif old.status = 'en_ejecucion' and new.status = 'captura_cerrada' then
        new.capture_closed_at := now();
      elsif old.status = 'captura_cerrada' and new.status = 'en_ejecucion' then
        -- Reapertura para una corrección o venta tardía: exige motivo nuevo
        if new.reopen_reason is null or length(trim(new.reopen_reason)) = 0
           or new.reopen_reason is not distinct from old.reopen_reason then
          raise exception 'Indique el motivo para reabrir la captura';
        end if;
        new.capture_reopened_at := now();
        new.capture_closed_at := null;
      elsif old.status = 'captura_cerrada' and new.status = 'operacion_cerrada' then
        select count(*) into v_pending
        from public.orders o
        where o.campaign_id = new.id and not o.is_cancelled and o.ops_status <> 'entrega_completa';
        if v_pending > 0 then
          raise exception 'No se puede cerrar la operación: % orden(es) sin entrega completa', v_pending;
        end if;
        select count(*) into v_pending
        from public.post_sale_warranties w
        join public.orders o on o.id = w.order_id
        where o.campaign_id = new.id and w.status <> 'cerrada';
        if v_pending > 0 then
          raise exception 'No se puede cerrar la operación: % caso(s) de posventa abiertos', v_pending;
        end if;
        new.closed_at := now();
      elsif old.status in ('borrador', 'programada') and new.status = 'cancelada' then
        new.cancelled_at := now();
      else
        raise exception 'Transición de jornada no permitida: % → %', old.status, new.status;
      end if;
    end if;
  end if;

  if v_is_api then
    if (tg_op = 'INSERT' or new.city_id is distinct from old.city_id)
       and not exists (
         select 1 from public.cities c
         where c.id = new.city_id and c.active and c.is_operational
       ) then
      raise exception 'La jornada debe realizarse en una ciudad operativa activa';
    end if;

    if (tg_op = 'INSERT' or new.responsible_user_id is distinct from old.responsible_user_id)
       and not exists (
         select 1 from public.users_profiles p
         where p.id = new.responsible_user_id and p.active and p.role = 'operacion'
       ) then
      raise exception 'El responsable de la jornada debe ser un usuario activo de Operación';
    end if;
  end if;

  return new;
end;
$$;

-- Dirección solo cancela: tampoco marca el checklist
create or replace function private.campaigns_cancel_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user <> 'authenticated' then
    return new;
  end if;

  if new.status = 'cancelada' and old.status is distinct from 'cancelada'
     and not private.has_role('operacion', 'direccion') then
    raise exception 'Solo Operación o Dirección cancelan jornadas' using errcode = '42501';
  end if;

  if private.has_role('direccion')
     and (new.branch_id, new.city_id, new.responsible_user_id, new.logistics_confirmed, new.notes,
          new.checklist_staff, new.checklist_equipment, new.checklist_materials, new.checklist_notice,
          new.status is distinct from old.status and new.status <> 'cancelada')
         is distinct from
         (old.branch_id, old.city_id, old.responsible_user_id, old.logistics_confirmed, old.notes,
          old.checklist_staff, old.checklist_equipment, old.checklist_materials, old.checklist_notice, false) then
    raise exception 'Dirección solo puede cancelar la jornada' using errcode = '42501';
  end if;

  return new;
end;
$$;

-- v_campaigns: checklist completo (columna nueva al final)
create or replace view public.v_campaigns
with (security_invoker = true)
as
select
  j.id,
  j.company_id,
  c.name as company_name,
  j.deal_id,
  d.deal_name_branch,
  j.agreement_id,
  j.branch_id,
  b.name as branch_name,
  j.city_id,
  ci.name as city_name,
  j.status,
  j.logistics_confirmed,
  j.responsible_user_id,
  u.full_name as responsible_user_name,
  s.sessions_count,
  s.first_session_date,
  s.last_session_date,
  coalesce(att.attended_headcount, 0) as attended_headcount,
  d.target_employees_n,
  d.estimated_billing_amount,
  j.started_at,
  j.closed_at,
  j.cancelled_at,
  j.cancel_reason,
  j.notes,
  j.created_at,
  j.updated_at,
  j.scheduled_at,
  j.capture_closed_at,
  j.capture_reopened_at,
  j.reopen_reason,
  coalesce(att.scheduled_count, 0) as scheduled_count,
  coalesce(att.no_show_count, 0) as no_show_count,
  j.checklist_complete
from public.campaigns_jornadas j
join public.companies c on c.id = j.company_id
join public.deals_opportunities d on d.id = j.deal_id
join public.cities ci on ci.id = j.city_id
join public.users_profiles u on u.id = j.responsible_user_id
left join public.company_branches b on b.id = j.branch_id
left join lateral (
  select count(*) as sessions_count,
         min(x.session_date) as first_session_date,
         max(x.session_date) as last_session_date
  from public.campaign_sessions x
  where x.campaign_id = j.id
) s on true
left join lateral (
  select count(distinct y.document_id) filter (where y.status = 'atendido') as attended_headcount,
         count(distinct y.document_id) filter (where y.status = 'agendado') as scheduled_count,
         count(distinct y.document_id) filter (where y.status = 'no_asistio') as no_show_count
  from public.campaign_attendance y
  where y.campaign_id = j.id
) att on true;

-- ---------------------------------------------------------------------
-- 3. Capacidad por sesión (opcional; superarla solo avisa)
-- ---------------------------------------------------------------------
alter table public.campaign_sessions
  add column capacity integer;

alter table public.campaign_sessions
  add constraint campaign_sessions_capacity_positive check (capacity is null or capacity > 0);

comment on column public.campaign_sessions.capacity is 'Personas que caben en la sesión; opcional, superarla solo avisa';

grant insert (capacity) on public.campaign_sessions to authenticated;

-- Fecha, horario y lugar solo cambian al reprogramar (con historial)
revoke update on public.campaign_sessions from authenticated;
grant update (responsible_user_id, capacity) on public.campaign_sessions to authenticated;

-- ---------------------------------------------------------------------
-- 4. Reprogramación de sesiones con historial
-- ---------------------------------------------------------------------
create table public.campaign_session_reschedules (
  id                     uuid primary key default gen_random_uuid(),
  session_id             uuid not null,
  campaign_id            uuid not null references public.campaigns_jornadas (id),
  previous_date          date not null,
  previous_start_time    time not null,
  previous_end_time      time not null,
  previous_location      text,
  new_date               date not null,
  new_start_time         time not null,
  new_end_time           time not null,
  new_location           text,
  reason                 text not null check (length(trim(reason)) > 0 and length(reason) <= 1000),
  rescheduled_by         uuid references public.users_profiles (id),
  rescheduled_at         timestamptz not null default now(),
  constraint campaign_session_reschedules_session_same_campaign
    foreign key (session_id, campaign_id) references public.campaign_sessions (id, campaign_id)
);

create index campaign_session_reschedules_session_id_idx on public.campaign_session_reschedules (session_id, campaign_id);
create index campaign_session_reschedules_campaign_id_idx on public.campaign_session_reschedules (campaign_id);
create index campaign_session_reschedules_rescheduled_by_idx on public.campaign_session_reschedules (rescheduled_by);

alter table public.campaign_session_reschedules enable row level security;
revoke all on public.campaign_session_reschedules from anon, authenticated;
grant select on public.campaign_session_reschedules to authenticated;

create policy campaign_session_reschedules_select on public.campaign_session_reschedules
  for select to authenticated
  using ((select private.is_internal_user()));

-- Una sesión con historial no se borra: se conserva la trazabilidad
create or replace function private.campaign_sessions_keep_history()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'authenticated'
     and exists (select 1 from public.campaign_session_reschedules r where r.session_id = old.id) then
    raise exception 'Una sesión reprogramada no se elimina: conserva su historial';
  end if;
  return old;
end;
$$;

create trigger campaign_sessions_keep_history
  before delete on public.campaign_sessions
  for each row execute function private.campaign_sessions_keep_history();

create function public.reschedule_campaign_session(
  p_session_id          uuid,
  p_session_date        date,
  p_start_time          time,
  p_end_time            time,
  p_location_detail     text,
  p_reason              text,
  p_expected_updated_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.campaign_sessions%rowtype;
  v_campaign record;
  v_location text := nullif(trim(p_location_detail), '');
  v_reason text := nullif(trim(p_reason), '');
begin
  if not private.has_role('operacion', 'direccion') then
    raise exception 'Solo Operación o Dirección reprograman sesiones' using errcode = '42501';
  end if;

  select * into v_session from public.campaign_sessions s where s.id = p_session_id for update;
  if not found then
    raise exception 'Sesión no encontrada';
  end if;

  if p_expected_updated_at is not null and v_session.updated_at <> p_expected_updated_at then
    raise exception 'Otra persona modificó esta sesión mientras la editaba. Recargue la página y vuelva a intentarlo.';
  end if;

  select c.status, a.valid_from, a.valid_until
    into v_campaign
  from public.campaigns_jornadas c
  join public.agreements_convenios a on a.id = c.agreement_id
  where c.id = v_session.campaign_id;

  if v_campaign.status not in ('borrador', 'programada') then
    raise exception 'Solo se reprograman sesiones de jornadas en borrador o programadas (está %)', v_campaign.status;
  end if;
  if v_reason is null then
    raise exception 'Indique el motivo de la reprogramación';
  end if;
  if length(v_reason) > 1000 then
    raise exception 'El motivo admite hasta 1000 caracteres';
  end if;
  if p_session_date is null or p_start_time is null or p_end_time is null then
    raise exception 'Indique la nueva fecha y el horario';
  end if;
  if p_end_time <= p_start_time then
    raise exception 'La hora de fin debe ser posterior a la de inicio';
  end if;
  if (v_campaign.valid_from is not null and p_session_date < v_campaign.valid_from)
     or (v_campaign.valid_until is not null and p_session_date > v_campaign.valid_until) then
    raise exception 'La fecha de la sesión (%) está fuera de la vigencia del convenio', p_session_date;
  end if;
  if (p_session_date, p_start_time, p_end_time, v_location)
     is not distinct from (v_session.session_date, v_session.start_time, v_session.end_time, v_session.location_detail) then
    raise exception 'La nueva fecha, horario y lugar son iguales a los actuales';
  end if;

  insert into public.campaign_session_reschedules (
    session_id, campaign_id, previous_date, previous_start_time, previous_end_time, previous_location,
    new_date, new_start_time, new_end_time, new_location, reason, rescheduled_by
  ) values (
    v_session.id, v_session.campaign_id, v_session.session_date, v_session.start_time, v_session.end_time,
    v_session.location_detail, p_session_date, p_start_time, p_end_time, v_location, v_reason, (select auth.uid())
  );

  update public.campaign_sessions s
  set session_date = p_session_date,
      start_time = p_start_time,
      end_time = p_end_time,
      location_detail = v_location
  where s.id = v_session.id;
end;
$$;

revoke execute on function public.reschedule_campaign_session(uuid, date, time, time, text, text, timestamptz)
  from public, anon;
grant execute on function public.reschedule_campaign_session(uuid, date, time, time, text, text, timestamptz)
  to authenticated;
