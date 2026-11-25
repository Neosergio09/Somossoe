-- =====================================================================
-- Seguimiento de asistentes que no compraron y nota crédito del
-- laboratorio en las garantías (análisis del Excel nuevo de Jornadas,
-- 2026-11-25).
--
-- 1. Seguimiento: a un asistente atendido sin compra se le registra
--    «pendiente de cierre» (con fecha para volver a llamar) o «desistió».
--    Nunca es una venta: la venta solo existe cuando se crea la orden.
--    Se puede registrar con la jornada en ejecución o ya cerrada, porque
--    el cierre suele ocurrir después de la jornada.
-- 2. Nota crédito: la garantía guarda a qué laboratorio se le cobra, el
--    estado de la nota (no aplica / por solicitar / solicitada / recibida),
--    su valor y su número. Se puede actualizar aunque la garantía esté
--    cerrada, porque la nota suele llegar después.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Seguimiento de asistentes sin compra
-- ---------------------------------------------------------------------
create type public.attendance_followup as enum ('pendiente_cierre', 'desistio');

alter table public.campaign_attendance
  add column followup_status     public.attendance_followup,
  add column followup_date       date,
  add column followup_note       text check (followup_note is null or length(followup_note) <= 500),
  add column followup_updated_by uuid references public.users_profiles (id),
  add column followup_updated_at timestamptz,
  add constraint campaign_attendance_followup_attended
    check (followup_status is null or status = 'atendido'),
  add constraint campaign_attendance_followup_date
    check (followup_status is distinct from 'pendiente_cierre' or followup_date is not null);

create index campaign_attendance_followup_idx
  on public.campaign_attendance (followup_date)
  where followup_status = 'pendiente_cierre';
create index campaign_attendance_followup_updated_by_idx
  on public.campaign_attendance (followup_updated_by);

grant update (followup_status, followup_date, followup_note) on public.campaign_attendance to authenticated;

create function private.campaign_attendance_followup_rules()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_changed boolean;
begin
  new.followup_note := nullif(trim(new.followup_note), '');
  v_changed := tg_op = 'UPDATE'
    and (new.followup_status, new.followup_date, new.followup_note)
        is distinct from (old.followup_status, old.followup_date, old.followup_note);

  if current_user = 'authenticated' then
    if tg_op = 'INSERT' and new.followup_status is not null then
      raise exception 'El seguimiento se registra después de atender al asistente';
    end if;
    if v_changed and new.followup_status is not null then
      if new.status <> 'atendido' then
        raise exception 'Solo se hace seguimiento a asistentes atendidos';
      end if;
      if new.buyer_id is not null then
        raise exception 'Este asistente ya compró en la jornada';
      end if;
      if new.followup_status = 'pendiente_cierre' and new.followup_date is null then
        raise exception 'Indique la fecha para volver a contactar al asistente';
      end if;
    end if;
    if v_changed then
      new.followup_updated_by := (select auth.uid());
      new.followup_updated_at := now();
    elsif tg_op = 'UPDATE' then
      new.followup_updated_by := old.followup_updated_by;
      new.followup_updated_at := old.followup_updated_at;
    end if;
  end if;

  -- Si deja de estar atendido, el seguimiento no aplica
  if new.status <> 'atendido' then
    new.followup_status := null;
  end if;
  if new.followup_status is null then
    new.followup_date := null;
    new.followup_note := null;
  elsif new.followup_status = 'desistio' then
    new.followup_date := null;
  end if;
  return new;
end;
$$;

-- Corre antes de campaign_attendance_guard (orden alfabético)
create trigger campaign_attendance_followup_rules
  before insert or update on public.campaign_attendance
  for each row execute function private.campaign_attendance_followup_rules();

-- La guardia de la jornada deja pasar los cambios que solo tocan el
-- seguimiento, también con la captura u operación cerradas
create or replace function private.campaign_attendance_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_status public.campaign_status;
  v_cmp public.campaign_attendance;
begin
  if current_user = 'authenticated' then
    select c.status into v_status
    from public.campaigns_jornadas c
    where c.id = coalesce(new.campaign_id, old.campaign_id);

    if tg_op = 'UPDATE' then
      v_cmp := new;
      v_cmp.followup_status := old.followup_status;
      v_cmp.followup_date := old.followup_date;
      v_cmp.followup_note := old.followup_note;
      v_cmp.followup_updated_by := old.followup_updated_by;
      v_cmp.followup_updated_at := old.followup_updated_at;
      v_cmp.updated_at := old.updated_at;
    end if;

    if tg_op = 'UPDATE' and v_cmp is not distinct from old then
      if v_status not in ('en_ejecucion', 'captura_cerrada', 'operacion_cerrada') then
        raise exception 'El seguimiento se registra con la jornada en ejecución o cerrada (está %)', v_status;
      end if;
    elsif v_status in ('borrador', 'programada') then
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

-- Lista de seguimiento. «Compró» si compró en la jornada o si después de
-- atenderlo se le registró cualquier orden vigente (por ejemplo, venta
-- directa o captura reabierta).
create view public.v_attendance_followups
with (security_invoker = true)
as
select
  a.id,
  a.campaign_id,
  j.company_id,
  co.name as company_name,
  d.deal_name_branch,
  j.status as campaign_status,
  a.full_name,
  a.document_id,
  a.area,
  a.attended_at,
  bp.phone,
  a.followup_status,
  a.followup_date,
  a.followup_note,
  a.followup_updated_at,
  u.full_name as followup_updated_by_name,
  lo.order_id as purchase_order_id,
  lo.order_number as purchase_order_number,
  lo.order_id is not null as purchased,
  a.followup_status = 'pendiente_cierre' and lo.order_id is null
    and a.followup_date < private.today_co() as is_overdue
from public.campaign_attendance a
join public.campaigns_jornadas j on j.id = a.campaign_id
left join public.companies co on co.id = j.company_id
left join public.deals_opportunities d on d.id = j.deal_id
left join public.users_profiles u on u.id = a.followup_updated_by
left join lateral (
  select b.phone from public.buyers b
  where b.document_id = a.document_id and b.phone is not null
  order by b.updated_at desc
  limit 1
) bp on true
left join lateral (
  select o.id as order_id, o.order_number
  from public.orders o
  join public.buyers b on b.id = o.buyer_id
  where not o.is_cancelled
    and (o.buyer_id = a.buyer_id
         or (b.document_id = a.document_id and o.created_at >= coalesce(a.attended_at, a.created_at)))
  order by o.created_at
  limit 1
) lo on true
where a.followup_status is not null;

grant select on public.v_attendance_followups to authenticated;

-- ---------------------------------------------------------------------
-- 2. Nota crédito del laboratorio en garantías
-- ---------------------------------------------------------------------
create type public.credit_note_status as enum ('no_aplica', 'por_solicitar', 'solicitada', 'recibida');

alter table public.post_sale_warranties
  add column credit_note_status          public.credit_note_status not null default 'no_aplica',
  add column credit_note_lab_provider_id uuid references public.lab_providers (id),
  add column credit_note_amount          numeric(14,0) check (credit_note_amount is null or credit_note_amount >= 0),
  add column credit_note_reference       text
    check (credit_note_reference is null or length(trim(credit_note_reference)) between 1 and 60),
  add column credit_note_updated_at      timestamptz,
  add constraint post_sale_warranties_credit_note_lab
    check (credit_note_status = 'no_aplica' or credit_note_lab_provider_id is not null),
  add constraint post_sale_warranties_credit_note_received
    check (credit_note_status <> 'recibida'
           or (credit_note_reference is not null and credit_note_amount is not null));

create index post_sale_warranties_credit_note_lab_idx
  on public.post_sale_warranties (credit_note_lab_provider_id);
create index post_sale_warranties_credit_note_pending_idx
  on public.post_sale_warranties (credit_note_status)
  where credit_note_status in ('por_solicitar', 'solicitada');

grant update (credit_note_status, credit_note_lab_provider_id, credit_note_amount, credit_note_reference)
  on public.post_sale_warranties to authenticated;

-- Reglas de garantías: igual que antes, más la nota crédito, que se puede
-- actualizar con la garantía cerrada
create or replace function private.post_sale_warranties_before_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $$
declare
  v_is_api boolean := current_user = 'authenticated';
  v_files boolean := private.get_setting('require_document_files') = 1;
  v_cmp public.post_sale_warranties;
  v_credit_only boolean := false;
begin
  -- Nota crédito: «no aplica» no guarda datos; se marca la hora del cambio
  new.credit_note_reference := nullif(trim(new.credit_note_reference), '');
  if new.credit_note_status = 'no_aplica' then
    new.credit_note_lab_provider_id := null;
    new.credit_note_amount := null;
    new.credit_note_reference := null;
  end if;
  if tg_op = 'UPDATE' then
    if (new.credit_note_status, new.credit_note_lab_provider_id, new.credit_note_amount, new.credit_note_reference)
       is distinct from
       (old.credit_note_status, old.credit_note_lab_provider_id, old.credit_note_amount, old.credit_note_reference) then
      new.credit_note_updated_at := now();
    else
      new.credit_note_updated_at := old.credit_note_updated_at;
    end if;
  end if;

  if not v_is_api then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.status := 'abierta';
    new.opened_by := (select auth.uid());
    new.closed_by := null;
    new.closed_at := null;
    if exists (select 1 from public.orders o where o.id = new.order_id and o.is_cancelled) then
      raise exception 'Una orden anulada no tiene posventa';
    end if;
    if not exists (
      select 1 from public.order_deliveries d where d.order_id = new.order_id and d.warranty_id is null
    ) then
      raise exception 'La posventa se registra sobre productos ya entregados';
    end if;
  else
    v_cmp := new;
    v_cmp.credit_note_status := old.credit_note_status;
    v_cmp.credit_note_lab_provider_id := old.credit_note_lab_provider_id;
    v_cmp.credit_note_amount := old.credit_note_amount;
    v_cmp.credit_note_reference := old.credit_note_reference;
    v_cmp.credit_note_updated_at := old.credit_note_updated_at;
    v_cmp.updated_at := old.updated_at;
    v_credit_only := v_cmp is not distinct from old;

    if new.order_id is distinct from old.order_id then
      raise exception 'La orden de una garantía no se cambia';
    end if;
    if old.status = 'cerrada' and not v_credit_only then
      raise exception 'Una garantía cerrada no se modifica';
    end if;

    if new.status is distinct from old.status then
      if new.status <> 'cerrada' then
        raise exception 'El estado En reposición lo fija la producción de reposición';
      end if;
      if not private.has_role('direccion') then
        raise exception 'Solo Dirección cierra garantías' using errcode = '42501';
      end if;
      if not new.evidence_received or (v_files and new.evidence_file_path is null) then
        raise exception 'Registre la evidencia de cierre de la garantía';
      end if;
      if exists (
        select 1 from public.order_productions p
        where p.warranty_id = old.id and p.status <> 'cancelada'
      ) and not exists (
        select 1 from public.order_deliveries d where d.warranty_id = old.id
      ) then
        raise exception 'Entregue la reposición antes de cerrar la garantía';
      end if;
      new.closed_by := (select auth.uid());
      new.closed_at := now();
    end if;
  end if;

  if (tg_op = 'INSERT' or new.responsible_user_id is distinct from old.responsible_user_id)
     and not exists (
       select 1 from public.users_profiles p
       where p.id = new.responsible_user_id and p.active and p.role in ('operacion', 'direccion')
     ) then
    raise exception 'El responsable debe ser un usuario activo de Operación o Dirección';
  end if;

  return new;
end;
$$;

-- v_warranties: columnas de la nota crédito al final
create or replace view public.v_warranties
with (security_invoker = true)
as
select
  w.id,
  w.order_id,
  o.order_number,
  w.incident_type,
  w.description,
  w.status,
  w.resolution,
  w.evidence_received,
  w.responsible_user_id,
  r.full_name as responsible_name,
  w.opened_by,
  ob.full_name as opened_by_name,
  w.created_at,
  w.closed_by,
  cb.full_name as closed_by_name,
  w.closed_at,
  b.full_name as buyer_name,
  b.document_id as buyer_document_id,
  c.name as company_name,
  w.updated_at,
  w.credit_note_status,
  w.credit_note_lab_provider_id,
  cl.name as credit_note_lab_name,
  w.credit_note_amount,
  w.credit_note_reference,
  w.credit_note_updated_at
from public.post_sale_warranties w
join public.orders o on o.id = w.order_id
join public.buyers b on b.id = o.buyer_id
join public.users_profiles r on r.id = w.responsible_user_id
left join public.users_profiles ob on ob.id = w.opened_by
left join public.users_profiles cb on cb.id = w.closed_by
left join public.companies c on c.id = o.company_id
left join public.lab_providers cl on cl.id = w.credit_note_lab_provider_id;
