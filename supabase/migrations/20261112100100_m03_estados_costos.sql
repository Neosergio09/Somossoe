-- =====================================================================
-- M03 Jornadas: estados nuevos de jornada y asistencia, rol Socio y
-- costos directos por orden con margen restringido.
-- Fuente: CRM_SOE_Modulo_Jornadas_Especificacion_V01 (§3, §5, §6) y
-- decisiones del 2026-11-12:
--   * Costos y utilidad entran al Piloto. Solo Dirección los edita; el
--     Socio los consulta; ningún otro rol los recibe (ni por API, vistas
--     ni auditoría).
--   * Jornada: borrador → programada → en_ejecucion → captura_cerrada →
--     operacion_cerrada; cancelación desde borrador o programada.
--   * Órdenes de jornada solo con la jornada En ejecución; una venta
--     tardía exige reabrir la captura (con motivo).
--   * Facturación Cerrada (etapa 7) depende de operacion_cerrada.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Rol Socio: lectura total, sin escritura
-- Las políticas de escritura usan roles explícitos, así que basta con
-- incluirlo en las de lectura.
-- ---------------------------------------------------------------------
create or replace function private.is_internal_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_role('comercial', 'operacion', 'administracion_cartera', 'direccion', 'socio');
$$;

-- Costos y márgenes: Dirección (edita) y Socio (consulta)
create function private.can_view_costs()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_role('direccion', 'socio');
$$;

revoke execute on function private.can_view_costs() from public, anon;
grant execute on function private.can_view_costs() to authenticated;

drop policy collections_payments_select on public.collections_payments;
create policy collections_payments_select on public.collections_payments
  for select to authenticated
  using ((select private.has_role('administracion_cartera', 'direccion', 'comercial', 'socio')));

drop policy payment_allocations_select on public.payment_allocations;
create policy payment_allocations_select on public.payment_allocations
  for select to authenticated
  using ((select private.has_role('administracion_cartera', 'direccion', 'comercial', 'socio')));

drop policy alegra_sync_events_select on public.alegra_sync_events;
create policy alegra_sync_events_select on public.alegra_sync_events
  for select to authenticated
  using ((select private.has_role('administracion_cartera', 'direccion', 'socio')));

-- La auditoría de costos solo la ve quien puede ver costos
drop policy audit_logs_select on public.audit_logs;
create policy audit_logs_select on public.audit_logs
  for select to authenticated
  using (
    (select private.has_role('direccion', 'administracion_cartera', 'socio'))
    and (table_name <> 'order_costs' or (select private.can_view_costs()))
  );

-- ---------------------------------------------------------------------
-- 2. Jornada: borrador, captura cerrada y operación cerrada
-- closed_at pasa a significar "operación cerrada".
-- ---------------------------------------------------------------------
alter table public.campaigns_jornadas alter column status set default 'borrador';

alter table public.campaigns_jornadas
  add column scheduled_at        timestamptz,
  add column capture_closed_at   timestamptz,
  add column capture_reopened_at timestamptz,
  add column reopen_reason       text check (reopen_reason is null or length(reopen_reason) <= 1000);

comment on column public.campaigns_jornadas.closed_at is 'Fecha de cierre operativo (operacion_cerrada)';

update public.campaigns_jornadas set scheduled_at = created_at where status <> 'borrador';
update public.campaigns_jornadas set capture_closed_at = closed_at where status = 'operacion_cerrada';

grant update (reopen_reason) on public.campaigns_jornadas to authenticated;

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
        if not new.logistics_confirmed then
          raise exception 'No se puede iniciar la jornada sin logística confirmada';
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

-- Sesiones: editables hasta la ejecución
create or replace function private.campaign_sessions_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_campaign record;
begin
  if current_user <> 'authenticated' then
    return coalesce(new, old);
  end if;

  select c.status, a.valid_from, a.valid_until
    into v_campaign
  from public.campaigns_jornadas c
  join public.agreements_convenios a on a.id = c.agreement_id
  where c.id = coalesce(new.campaign_id, old.campaign_id);

  if v_campaign.status not in ('borrador', 'programada', 'en_ejecucion') then
    raise exception 'Las sesiones de una jornada % no se modifican', v_campaign.status;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  if (v_campaign.valid_from is not null and new.session_date < v_campaign.valid_from)
     or (v_campaign.valid_until is not null and new.session_date > v_campaign.valid_until) then
    raise exception 'La fecha de la sesión (%) está fuera de la vigencia del convenio', new.session_date;
  end if;

  if (tg_op = 'INSERT' or new.responsible_user_id is distinct from old.responsible_user_id)
     and not exists (
       select 1 from public.users_profiles p
       where p.id = new.responsible_user_id and p.active and p.role in ('operacion', 'comercial')
     ) then
    raise exception 'El responsable de la sesión debe ser un usuario activo de Operación o Comercial';
  end if;

  return new;
end;
$$;

-- Etapa 7: todas las jornadas (no canceladas) con la operación cerrada
create or replace function private.refresh_deal_billing_stage(p_deal_id uuid)
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
    exists (select 1 from public.campaigns_jornadas j where j.deal_id = p_deal_id and j.status = 'operacion_cerrada')
    and not exists (
      select 1 from public.campaigns_jornadas j
      where j.deal_id = p_deal_id
        and j.status in ('borrador', 'programada', 'en_ejecucion', 'captura_cerrada')
    )
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

-- ---------------------------------------------------------------------
-- 3. Estado de asistencia
-- Agendado (antes de ejecutar) → presente → atendido; no_asistio y
-- cancelado. Un solo "atendido" por persona y jornada. Comprar es un
-- hecho aparte (orden).
-- ---------------------------------------------------------------------
create type public.attendance_status as enum ('agendado', 'presente', 'atendido', 'no_asistio', 'cancelado');

alter table public.campaign_attendance
  add column status      public.attendance_status not null default 'atendido',
  add column attended_at timestamptz;

-- Históricos: quien estaba en el listado fue atendido (una vez por jornada)
with ranked as (
  select a.id, row_number() over (partition by a.campaign_id, a.document_id order by a.created_at, a.id) as n
  from public.campaign_attendance a
)
update public.campaign_attendance a
set status = case when r.n = 1 then 'atendido'::public.attendance_status else 'presente'::public.attendance_status end,
    attended_at = case when r.n = 1 then a.created_at end
from ranked r
where r.id = a.id;

alter table public.campaign_attendance alter column status set default 'agendado';

create unique index campaign_attendance_one_attended_key
  on public.campaign_attendance (campaign_id, document_id)
  where status = 'atendido';

create or replace function private.campaign_attendance_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_status public.campaign_status;
begin
  if current_user = 'authenticated' then
    select c.status into v_status
    from public.campaigns_jornadas c
    where c.id = coalesce(new.campaign_id, old.campaign_id);

    if v_status in ('borrador', 'programada') then
      if tg_op <> 'DELETE' and new.status not in ('agendado', 'cancelado') then
        raise exception 'Antes de iniciar la jornada solo se agenda o cancela la asistencia';
      end if;
    elsif v_status is distinct from 'en_ejecucion' then
      raise exception 'La asistencia solo se modifica con la jornada en borrador, programada o en_ejecucion (está %)',
        v_status;
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  -- attended_at no está en los permisos de la API: allí siempre llega el
  -- valor anterior (o null) y se completa con la hora actual
  if new.status = 'atendido' then
    new.attended_at := coalesce(new.attended_at, now());
  else
    new.attended_at := null;
  end if;
  return new;
end;
$$;

revoke insert, update on public.campaign_attendance from authenticated;
grant insert (campaign_id, session_id, full_name, document_id, area, status)
  on public.campaign_attendance to authenticated;
grant update (full_name, document_id, area, status)
  on public.campaign_attendance to authenticated;

-- v_campaigns: asistencia = atendidos únicos; columnas nuevas al final
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
  coalesce(att.no_show_count, 0) as no_show_count
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
-- 4. Órdenes de jornada: solo con la jornada En ejecución
-- (misma función de M04; cambia únicamente la condición de estado)
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- 5. Costos directos por orden (Especificación §3.2, §4.6, §5)
-- * Un registro por componente (lente, montura, kit, otro), con fuente y
--   marca estimado / verificado. Nunca se rellena con cero.
-- * No se edita ni se borra: una corrección es una versión nueva que
--   reemplaza a la vigente (replaces_id); un error se anula con motivo.
-- * Solo Dirección escribe; Dirección y Socio leen; nadie más recibe
--   filas (RLS), ni vistas de margen, ni su auditoría.
-- ---------------------------------------------------------------------
create type public.cost_component as enum ('lente', 'montura', 'kit', 'otro');
create type public.cost_basis as enum ('estimado', 'verificado');

create table public.order_costs (
  id              uuid primary key default gen_random_uuid(),
  order_id        uuid not null references public.orders (id),
  order_item_id   uuid,
  component       public.cost_component not null,
  amount          numeric(14,0) not null check (amount >= 0),
  basis           public.cost_basis not null,
  source          text not null check (length(trim(source)) between 3 and 300),
  lab_provider_id uuid references public.lab_providers (id),
  notes           text check (notes is null or length(notes) <= 1000),
  replaces_id     uuid,
  superseded_at   timestamptz,
  is_voided       boolean not null default false,
  void_reason     text,
  voided_by       uuid references public.users_profiles (id),
  voided_at       timestamptz,
  created_by      uuid default auth.uid() references public.users_profiles (id),
  created_at      timestamptz not null default now(),
  constraint order_costs_id_order_key unique (id, order_id),
  constraint order_costs_replaces_key unique (replaces_id),
  constraint order_costs_item_same_order
    foreign key (order_item_id, order_id) references public.order_items (id, order_id),
  constraint order_costs_replaces_same_order
    foreign key (replaces_id, order_id) references public.order_costs (id, order_id),
  constraint order_costs_void_reason
    check (not is_voided or (void_reason is not null and length(trim(void_reason)) > 0))
);

create index order_costs_order_id_idx on public.order_costs (order_id);
create index order_costs_order_item_id_idx on public.order_costs (order_item_id);
create index order_costs_lab_provider_id_idx on public.order_costs (lab_provider_id);
create index order_costs_created_by_idx on public.order_costs (created_by);
create index order_costs_voided_by_idx on public.order_costs (voided_by);
create index order_costs_current_idx on public.order_costs (order_id)
  where superseded_at is null and not is_voided;

create function private.order_costs_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_prev record;
begin
  if current_user <> 'authenticated' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.superseded_at := null;
    new.is_voided := false;
    new.void_reason := null;
    new.voided_by := null;
    new.voided_at := null;
    new.created_by := (select auth.uid());
    new.created_at := now();

    if new.replaces_id is not null then
      select c.superseded_at, c.is_voided into v_prev
      from public.order_costs c
      where c.id = new.replaces_id and c.order_id = new.order_id
      for update;
      if not found then
        raise exception 'El costo a reemplazar no pertenece a esta orden';
      end if;
      if v_prev.superseded_at is not null or v_prev.is_voided then
        raise exception 'Solo se reemplaza la versión vigente de un costo';
      end if;
    end if;
    return new;
  end if;

  -- UPDATE: solo anular, una vez, la versión vigente
  if old.is_voided then
    raise exception 'El costo ya está anulado';
  end if;
  if not new.is_voided then
    raise exception 'Un costo no se edita: registre una versión nueva que lo reemplace';
  end if;
  if old.superseded_at is not null then
    raise exception 'Ese costo ya fue reemplazado; anule la versión vigente';
  end if;
  new.voided_by := (select auth.uid());
  new.voided_at := now();
  return new;
end;
$$;

create trigger order_costs_before_write
  before insert or update on public.order_costs
  for each row execute function private.order_costs_before_write();

-- La versión anterior queda marcada como reemplazada
create function private.order_costs_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.replaces_id is not null then
    update public.order_costs c set superseded_at = now() where c.id = new.replaces_id;
  end if;
  return null;
end;
$$;

revoke execute on function private.order_costs_after_insert() from public, anon, authenticated;

create trigger order_costs_after_insert
  after insert on public.order_costs
  for each row execute function private.order_costs_after_insert();

create trigger order_costs_audit
  after insert or update or delete on public.order_costs
  for each row execute function private.audit_row_change();

-- Costos con nombres (vigentes e históricos)
create view public.v_order_costs
with (security_invoker = true)
as
select
  c.id,
  c.order_id,
  c.order_item_id,
  c.component,
  c.amount,
  c.basis,
  c.source,
  c.lab_provider_id,
  lp.name as lab_provider_name,
  c.notes,
  c.replaces_id,
  c.superseded_at,
  c.is_voided,
  c.void_reason,
  c.voided_at,
  c.superseded_at is null and not c.is_voided as is_current,
  c.created_by,
  u.full_name as created_by_name,
  c.created_at
from public.order_costs c
left join public.lab_providers lp on lp.id = c.lab_provider_id
left join public.users_profiles u on u.id = c.created_by
where (select private.can_view_costs());

-- Margen por orden: diferencia venta − costo directo (no es utilidad neta).
-- Sin costos registrados el margen es "no disponible" (null), nunca cero.
create view public.v_order_margins
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
    when k.estimated_count > 0 then 'estimado'
    else 'verificado'
  end as cost_basis,
  case when k.costs_count > 0 then o.total_amount - k.cost_total end as margin_amount,
  case
    when k.costs_count > 0 and o.total_amount > 0
      then round((o.total_amount - k.cost_total) / o.total_amount, 4)
  end as margin_ratio
from public.orders o
cross join lateral (
  select
    count(*) as costs_count,
    count(*) filter (where c.basis = 'estimado') as estimated_count,
    sum(c.amount) filter (where c.component = 'lente') as cost_lente,
    sum(c.amount) filter (where c.component = 'montura') as cost_montura,
    sum(c.amount) filter (where c.component = 'kit') as cost_kit,
    sum(c.amount) filter (where c.component = 'otro') as cost_otro,
    coalesce(sum(c.amount), 0) as cost_total
  from public.order_costs c
  where c.order_id = o.id and c.superseded_at is null and not c.is_voided
) k
where (select private.can_view_costs());

-- Margen por jornada. Venta = órdenes no anuladas; costo = costos vigentes
-- de todas sus órdenes (un costo incurrido en una orden anulada se pierde).
create view public.v_campaign_margins
with (security_invoker = true)
as
select
  j.id as campaign_id,
  coalesce(sum(m.total_amount) filter (where not m.is_cancelled), 0) as sold_amount,
  count(m.order_id) filter (where not m.is_cancelled) as active_orders,
  count(m.order_id) filter (where not m.is_cancelled and m.costs_count = 0) as orders_without_costs,
  coalesce(sum(m.cost_total), 0) as cost_total,
  coalesce(bool_or(m.cost_basis = 'estimado'), false) as has_estimated,
  coalesce(sum(m.total_amount) filter (where not m.is_cancelled), 0) - coalesce(sum(m.cost_total), 0)
    as margin_amount,
  case
    when coalesce(sum(m.total_amount) filter (where not m.is_cancelled), 0) > 0 then
      round(
        (coalesce(sum(m.total_amount) filter (where not m.is_cancelled), 0) - coalesce(sum(m.cost_total), 0))
        / sum(m.total_amount) filter (where not m.is_cancelled),
        4)
  end as margin_ratio
from public.campaigns_jornadas j
left join public.v_order_margins m on m.campaign_id = j.id
where (select private.can_view_costs())
group by j.id;

revoke all on public.order_costs, public.v_order_costs, public.v_order_margins, public.v_campaign_margins
  from anon, authenticated;

grant select on public.order_costs to authenticated;
grant insert (order_id, order_item_id, component, amount, basis, source, lab_provider_id, notes, replaces_id)
  on public.order_costs to authenticated;
grant update (is_voided, void_reason) on public.order_costs to authenticated;
grant select on public.v_order_costs, public.v_order_margins, public.v_campaign_margins to authenticated;

alter table public.order_costs enable row level security;

create policy order_costs_select on public.order_costs
  for select to authenticated
  using ((select private.can_view_costs()));
create policy order_costs_insert on public.order_costs
  for insert to authenticated
  with check ((select private.has_role('direccion')));
create policy order_costs_update on public.order_costs
  for update to authenticated
  using ((select private.has_role('direccion')))
  with check ((select private.has_role('direccion')));
