-- =====================================================================
-- SRS 1.6 · RF-M04-07 y RNF-06: ficha de fabricación (RX OD/OI, ADD y
-- parámetros técnicos) por ítem con lente.
--
-- * Dato sensible de salud: la tabla NO tiene permisos para authenticated
--   ni políticas; solo se lee y escribe con funciones SECURITY DEFINER
--   que comprueban rol, estado de la orden y consentimiento, y registran
--   cada lectura (fabrication_spec_access_logs) y cada cambio sin valores
--   (fabrication_spec_events).
-- * Quién: Comercial que registró la orden captura y corrige hasta la
--   liberación; Operación lee, valida y corrige después de liberar.
--   Nadie más (tampoco Dirección, Socio, Administración, Costos ni el
--   Super administrador): se comprueba con los roles reales
--   (current_app_roles), no con has_role, que deja pasar al superadmin.
-- * Fuera de audit_logs, vistas, 360°, exportes e importador.
-- * Candado: con require_fabrication_spec = 1, cada ítem con lente debe
--   tener ficha vigente validada para liberar (no aplica a históricos ni
--   a reposiciones por garantía).
-- * Autorización expresa de datos sensibles del comprador (Ley 1581, art. 6).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Parámetros
-- ---------------------------------------------------------------------
alter table public.system_settings drop constraint system_settings_known_key;
alter table public.system_settings add constraint system_settings_known_key check (key in (
  'conversion_rate_c',
  'average_ticket_t',
  'inactivity_alert_days',
  'cash_min_prepayment_pct',
  'max_installments_monthly',
  'max_installments_biweekly',
  'require_document_files',
  'agreement_requires_direction_approval',
  'require_fabrication_spec',
  'fabrication_spec_retention_days'
));
alter table public.system_settings drop constraint system_settings_boolean_flags;
alter table public.system_settings add constraint system_settings_boolean_flags check (
  key not in ('require_document_files', 'agreement_requires_direction_approval', 'require_fabrication_spec')
  or value in (0, 1)
);
alter table public.system_settings add constraint system_settings_retention_days
  check (key <> 'fabrication_spec_retention_days' or (value >= 0 and value = trunc(value)));

insert into public.system_settings (key, value, description) values
  ('require_fabrication_spec', 1,
   'Ficha de fabricación (RX/ADD) validada obligatoria para liberar órdenes con lente: 1 = sí, 0 = solo aviso'),
  ('fabrication_spec_retention_days', 0,
   'Días tras la entrega completa para suprimir los valores de la ficha de fabricación (0 = sin definir, no se suprime)');

-- ---------------------------------------------------------------------
-- Autorización expresa de datos sensibles del comprador
-- ---------------------------------------------------------------------
alter table public.buyers
  add column sensitive_data_consent_at        timestamptz,
  add column sensitive_data_consent_by        uuid references public.users_profiles (id),
  add column sensitive_data_consent_file_path text
    check (sensitive_data_consent_file_path is null or length(trim(sensitive_data_consent_file_path)) > 0);

create index buyers_sensitive_data_consent_by_idx on public.buyers (sensitive_data_consent_by);

grant insert (sensitive_data_consent_at, sensitive_data_consent_file_path) on public.buyers to authenticated;
grant update (sensitive_data_consent_at, sensitive_data_consent_file_path) on public.buyers to authenticated;

-- Se registra una vez (fecha y usuario los pone la base) y no se retira
-- desde la aplicación; la revocatoria sigue el procedimiento RNF-05.
create function private.buyers_sensitive_consent()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user <> 'authenticated' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.sensitive_data_consent_at is not null then
    new.sensitive_data_consent_at := old.sensitive_data_consent_at;
    new.sensitive_data_consent_by := old.sensitive_data_consent_by;
    if old.sensitive_data_consent_file_path is not null then
      new.sensitive_data_consent_file_path := old.sensitive_data_consent_file_path;
    end if;
    return new;
  end if;
  if new.sensitive_data_consent_at is not null then
    new.sensitive_data_consent_at := now();
    new.sensitive_data_consent_by := (select auth.uid());
  else
    new.sensitive_data_consent_by := null;
  end if;
  return new;
end;
$$;

revoke execute on function private.buyers_sensitive_consent() from public, anon, authenticated;

create trigger buyers_sensitive_consent
  before insert or update on public.buyers
  for each row execute function private.buyers_sensitive_consent();

drop trigger a_support_files on public.buyers;
create trigger a_support_files before insert or update on public.buyers
  for each row execute function private.support_files_guard('compradores',
    'data_consent_file_path', 'sensitive_data_consent_file_path');

CREATE OR REPLACE FUNCTION private.support_visible(p_path text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
  return case split_part(p_path, '/', 1)
    when 'convenios' then exists (select 1 from public.agreement_documents x where x.file_path = p_path)
    when 'compradores' then exists (
      select 1 from public.buyers x
      where x.data_consent_file_path = p_path or x.sensitive_data_consent_file_path = p_path)
    when 'ordenes' then exists (
      select 1 from public.orders x where x.employee_auth_file_path = p_path or x.hr_approval_file_path = p_path)
    when 'entregas' then exists (select 1 from public.order_deliveries x where x.evidence_file_path = p_path)
    when 'garantias' then exists (select 1 from public.post_sale_warranties x where x.evidence_file_path = p_path)
    when 'pagos' then exists (select 1 from public.collections_payments x where x.support_file_path = p_path)
    when 'retenciones' then exists (
      select 1 from public.payment_allocations x where x.withholding_certificate_file_path = p_path)
    else false
  end;
end;
$function$;

-- ---------------------------------------------------------------------
-- Ficha de fabricación
-- ---------------------------------------------------------------------
create table public.order_fabrication_specs (
  id                uuid primary key default gen_random_uuid(),
  order_id          uuid not null references public.orders (id),
  order_item_id     uuid not null references public.order_items (id),
  version           smallint not null check (version >= 1),
  od_sphere         numeric(5,2) check (od_sphere between -30 and 30 and od_sphere * 4 = trunc(od_sphere * 4)),
  od_cylinder       numeric(5,2) check (od_cylinder between -10 and 10 and od_cylinder * 4 = trunc(od_cylinder * 4)),
  od_axis           smallint check (od_axis between 0 and 180),
  od_add            numeric(4,2) check (od_add between 0.5 and 4 and od_add * 4 = trunc(od_add * 4)),
  od_pd_mm          numeric(4,1) check (od_pd_mm between 20 and 40),
  od_height_mm      numeric(4,1) check (od_height_mm between 10 and 40),
  os_sphere         numeric(5,2) check (os_sphere between -30 and 30 and os_sphere * 4 = trunc(os_sphere * 4)),
  os_cylinder       numeric(5,2) check (os_cylinder between -10 and 10 and os_cylinder * 4 = trunc(os_cylinder * 4)),
  os_axis           smallint check (os_axis between 0 and 180),
  os_add            numeric(4,2) check (os_add between 0.5 and 4 and os_add * 4 = trunc(os_add * 4)),
  os_pd_mm          numeric(4,1) check (os_pd_mm between 20 and 40),
  os_height_mm      numeric(4,1) check (os_height_mm between 10 and 40),
  pd_total_mm       numeric(4,1) check (pd_total_mm between 40 and 80),
  technical_notes   text check (technical_notes is null or length(technical_notes) <= 200),
  prescription_date date,
  source            text not null check (source in ('formula_optometra_jornada', 'formula_externa')),
  replaces_id       uuid references public.order_fabrication_specs (id),
  superseded_at     timestamptz,
  change_reason     text,
  validated_by      uuid references public.users_profiles (id),
  validated_at      timestamptz,
  is_voided         boolean not null default false,
  void_reason       text,
  voided_by         uuid references public.users_profiles (id),
  voided_at         timestamptz,
  values_purged_at  timestamptz,
  created_by        uuid not null references public.users_profiles (id),
  created_at        timestamptz not null default now(),
  -- Esfera obligatoria en ambos ojos mientras los valores no se supriman
  constraint fabrication_specs_sphere_required
    check (values_purged_at is not null or (od_sphere is not null and os_sphere is not null)),
  -- Eje si y solo si hay cilindro distinto de cero
  constraint fabrication_specs_od_axis
    check (values_purged_at is not null or ((coalesce(od_cylinder, 0) = 0) = (od_axis is null))),
  constraint fabrication_specs_os_axis
    check (values_purged_at is not null or ((coalesce(os_cylinder, 0) = 0) = (os_axis is null))),
  constraint fabrication_specs_change_reason
    check (replaces_id is null or length(trim(coalesce(change_reason, ''))) > 0),
  constraint fabrication_specs_void_reason
    check (not is_voided or length(trim(coalesce(void_reason, ''))) > 0)
);

create unique index fabrication_specs_current_key
  on public.order_fabrication_specs (order_item_id) where superseded_at is null and not is_voided;
create unique index fabrication_specs_replaces_key
  on public.order_fabrication_specs (replaces_id) where replaces_id is not null;
create index fabrication_specs_order_id_idx on public.order_fabrication_specs (order_id);
create index fabrication_specs_created_by_idx on public.order_fabrication_specs (created_by);
create index fabrication_specs_validated_by_idx on public.order_fabrication_specs (validated_by);
create index fabrication_specs_voided_by_idx on public.order_fabrication_specs (voided_by);

-- Sin acceso directo: ni permisos ni políticas (RLS activa por defensa)
alter table public.order_fabrication_specs enable row level security;
revoke all on public.order_fabrication_specs from public, anon, authenticated;

-- Bitácora de lecturas (sin valores)
create table public.fabrication_spec_access_logs (
  id            uuid primary key default gen_random_uuid(),
  spec_id       uuid not null references public.order_fabrication_specs (id),
  order_id      uuid not null references public.orders (id),
  user_id       uuid not null references public.users_profiles (id),
  purpose       text not null check (purpose in ('captura', 'validacion', 'envio_laboratorio', 'correccion')),
  accessed_at   timestamptz not null default now()
);
create index fabrication_access_spec_idx on public.fabrication_spec_access_logs (spec_id);
create index fabrication_access_order_idx on public.fabrication_spec_access_logs (order_id);
create index fabrication_access_user_idx on public.fabrication_spec_access_logs (user_id);

-- Bitácora de cambios (sin valores)
create table public.fabrication_spec_events (
  id            uuid primary key default gen_random_uuid(),
  spec_id       uuid not null references public.order_fabrication_specs (id),
  order_id      uuid not null references public.orders (id),
  order_item_id uuid not null references public.order_items (id),
  event         text not null check (event in ('creada', 'version_nueva', 'validada', 'anulada', 'valores_suprimidos')),
  reason        text,
  user_id       uuid references public.users_profiles (id),
  created_at    timestamptz not null default now()
);
create index fabrication_events_spec_idx on public.fabrication_spec_events (spec_id);
create index fabrication_events_order_idx on public.fabrication_spec_events (order_id);
create index fabrication_events_item_idx on public.fabrication_spec_events (order_item_id);
create index fabrication_events_user_idx on public.fabrication_spec_events (user_id);

alter table public.fabrication_spec_access_logs enable row level security;
alter table public.fabrication_spec_events enable row level security;
revoke all on public.fabrication_spec_access_logs, public.fabrication_spec_events from public, anon, authenticated;
grant select on public.fabrication_spec_access_logs, public.fabrication_spec_events to authenticated;

-- Accesos: Dirección (y Super administrador) supervisan quién leyó
create policy fabrication_access_select on public.fabrication_spec_access_logs
  for select to authenticated
  using ((select private.has_role('direccion')));
-- Cambios: también Operación
create policy fabrication_events_select on public.fabrication_spec_events
  for select to authenticated
  using ((select private.has_role('direccion', 'operacion')));

-- ---------------------------------------------------------------------
-- Ayudantes
-- ---------------------------------------------------------------------

-- ¿El usuario tiene este rol de verdad? (sin el comodín del superadmin)
create function private.fabrication_role(p_role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_role = any (private.current_app_roles());
$$;

-- Ítems con lente de la orden sin ficha vigente validada
create function private.order_fabrication_missing(p_order_id uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int
  from public.order_items i
  where i.order_id = p_order_id
    and i.item_type in ('gafas_completas', 'lentes')
    and not exists (
      select 1 from public.order_fabrication_specs s
      where s.order_item_id = i.id and s.superseded_at is null and not s.is_voided
        and s.validated_at is not null);
$$;

revoke execute on function private.fabrication_role(public.app_role), private.order_fabrication_missing(uuid)
  from public, anon;
grant execute on function private.fabrication_role(public.app_role), private.order_fabrication_missing(uuid)
  to authenticated;

-- Orden e ítem, con las comprobaciones comunes. Devuelve si está liberada.
create function private.fabrication_context(p_order_item_id uuid, out o public.orders, out i public.order_items, out released boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  select * into i from public.order_items x where x.id = p_order_item_id;
  if i.id is null then
    raise exception 'Ítem de orden no encontrado';
  end if;
  if i.item_type not in ('gafas_completas', 'lentes') then
    raise exception 'Solo los ítems con lente llevan ficha de fabricación';
  end if;
  select * into o from public.orders x where x.id = i.order_id;
  if o.is_cancelled then
    raise exception 'La orden está anulada';
  end if;
  if o.is_historical_migration then
    raise exception 'Las órdenes históricas no llevan ficha de fabricación';
  end if;
  released := o.ops_status <> 'pendiente_liberar';
end;
$$;

revoke execute on function private.fabrication_context(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Estado de las fichas de una orden (sin valores clínicos)
-- ---------------------------------------------------------------------
create function public.fabrication_spec_status(p_order_id uuid)
returns table (
  order_item_id     uuid,
  item_type         public.order_item_type,
  item_label        text,
  spec_id           uuid,
  version           smallint,
  created_at        timestamptz,
  created_by_name   text,
  validated_at      timestamptz,
  validated_by_name text,
  values_purged_at  timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select i.id, i.item_type,
         coalesce(nullif(trim(concat_ws(' · ', i.lens_type, i.frame_description, i.description)), ''), i.item_type::text),
         s.id, s.version, s.created_at, cu.full_name, s.validated_at, vu.full_name, s.values_purged_at
  from public.order_items i
  left join public.order_fabrication_specs s
    on s.order_item_id = i.id and s.superseded_at is null and not s.is_voided
  left join public.users_profiles cu on cu.id = s.created_by
  left join public.users_profiles vu on vu.id = s.validated_by
  where i.order_id = p_order_id
    and i.item_type in ('gafas_completas', 'lentes')
    and private.is_internal_user()
  order by i.created_at;
$$;

-- ---------------------------------------------------------------------
-- Leer la ficha vigente de un ítem (registra la lectura)
-- ---------------------------------------------------------------------
create function public.get_fabrication_spec(p_order_item_id uuid, p_purpose text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx record;
  v_spec public.order_fabrication_specs;
  v_comercial boolean;
  v_operacion boolean := private.fabrication_role('operacion');
begin
  select * into v_ctx from private.fabrication_context(p_order_item_id);
  v_comercial := private.fabrication_role('comercial') and (v_ctx.o).created_by = (select auth.uid())
                 and not v_ctx.released;

  if not (v_operacion or v_comercial) then
    raise exception 'La ficha de fabricación solo la consultan quien registró la orden (antes de liberarla) y Operación'
      using errcode = '42501';
  end if;
  if p_purpose not in ('captura', 'validacion', 'envio_laboratorio', 'correccion') then
    raise exception 'Finalidad de consulta no válida';
  end if;
  if p_purpose in ('validacion', 'envio_laboratorio') and not v_operacion then
    raise exception 'Esa finalidad corresponde a Operación' using errcode = '42501';
  end if;

  select * into v_spec from public.order_fabrication_specs s
  where s.order_item_id = p_order_item_id and s.superseded_at is null and not s.is_voided;
  if v_spec.id is null then
    return null;
  end if;
  if v_spec.values_purged_at is not null then
    raise exception 'Los valores de esta ficha se suprimieron por el plazo de conservación';
  end if;

  insert into public.fabrication_spec_access_logs (spec_id, order_id, user_id, purpose)
  values (v_spec.id, v_spec.order_id, (select auth.uid()), p_purpose);

  return jsonb_build_object(
    'spec_id', v_spec.id, 'version', v_spec.version,
    'od_sphere', v_spec.od_sphere, 'od_cylinder', v_spec.od_cylinder, 'od_axis', v_spec.od_axis,
    'od_add', v_spec.od_add, 'od_pd_mm', v_spec.od_pd_mm, 'od_height_mm', v_spec.od_height_mm,
    'os_sphere', v_spec.os_sphere, 'os_cylinder', v_spec.os_cylinder, 'os_axis', v_spec.os_axis,
    'os_add', v_spec.os_add, 'os_pd_mm', v_spec.os_pd_mm, 'os_height_mm', v_spec.os_height_mm,
    'pd_total_mm', v_spec.pd_total_mm, 'technical_notes', v_spec.technical_notes,
    'prescription_date', v_spec.prescription_date, 'source', v_spec.source,
    'validated_at', v_spec.validated_at, 'change_reason', v_spec.change_reason);
end;
$$;

-- ---------------------------------------------------------------------
-- Guardar (crea la ficha o una versión nueva que reemplaza a la vigente)
-- ---------------------------------------------------------------------
create function public.save_fabrication_spec(p_order_item_id uuid, p_values jsonb, p_change_reason text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx record;
  v_prev public.order_fabrication_specs;
  v_new public.order_fabrication_specs;
  v_uid uuid := (select auth.uid());
  v_reason text := nullif(trim(coalesce(p_change_reason, '')), '');
  v_needs_add boolean;
begin
  select * into v_ctx from private.fabrication_context(p_order_item_id);
  perform 1 from public.order_items i where i.id = p_order_item_id for update;

  if not v_ctx.released then
    if not (private.fabrication_role('comercial') and (v_ctx.o).created_by = v_uid) then
      raise exception 'Antes de liberar, la ficha la registra quien registró la orden' using errcode = '42501';
    end if;
  else
    if not private.fabrication_role('operacion') then
      raise exception 'Con la orden liberada, solo Operación corrige la ficha' using errcode = '42501';
    end if;
    if v_reason is null then
      raise exception 'Indique el motivo de la corrección (por ejemplo, el laboratorio detectó un error)';
    end if;
  end if;

  if not exists (
    select 1 from public.buyers b
    where b.id = (v_ctx.o).buyer_id and b.sensitive_data_consent_at is not null
  ) then
    raise exception 'El comprador no ha autorizado el tratamiento de sus datos sensibles: regístrelo antes de guardar la ficha';
  end if;

  select * into v_prev from public.order_fabrication_specs s
  where s.order_item_id = p_order_item_id and s.superseded_at is null and not s.is_voided
  for update;
  if v_prev.id is not null and v_reason is null then
    raise exception 'Indique el motivo de la corrección';
  end if;

  if (p_values ->> 'prescription_date')::date > private.today_co() then
    raise exception 'La fecha de la fórmula no puede ser futura';
  end if;

  -- ADD obligatoria en progresivos y bifocales
  v_needs_add := coalesce((v_ctx.i).lens_type, '') ~* '(progres|bifocal|multifocal)';
  if v_needs_add and ((p_values ->> 'od_add') is null or (p_values ->> 'os_add') is null) then
    raise exception 'Un lente % requiere ADD en ambos ojos', (v_ctx.i).lens_type;
  end if;

  if v_prev.id is not null then
    update public.order_fabrication_specs set superseded_at = now() where id = v_prev.id;
  end if;

  insert into public.order_fabrication_specs (
    order_id, order_item_id, version,
    od_sphere, od_cylinder, od_axis, od_add, od_pd_mm, od_height_mm,
    os_sphere, os_cylinder, os_axis, os_add, os_pd_mm, os_height_mm,
    pd_total_mm, technical_notes, prescription_date, source,
    replaces_id, change_reason, validated_by, validated_at, created_by)
  values (
    (v_ctx.o).id, p_order_item_id, coalesce(v_prev.version, 0) + 1,
    (p_values ->> 'od_sphere')::numeric, (p_values ->> 'od_cylinder')::numeric, (p_values ->> 'od_axis')::smallint,
    (p_values ->> 'od_add')::numeric, (p_values ->> 'od_pd_mm')::numeric, (p_values ->> 'od_height_mm')::numeric,
    (p_values ->> 'os_sphere')::numeric, (p_values ->> 'os_cylinder')::numeric, (p_values ->> 'os_axis')::smallint,
    (p_values ->> 'os_add')::numeric, (p_values ->> 'os_pd_mm')::numeric, (p_values ->> 'os_height_mm')::numeric,
    (p_values ->> 'pd_total_mm')::numeric, nullif(trim(coalesce(p_values ->> 'technical_notes', '')), ''),
    (p_values ->> 'prescription_date')::date,
    coalesce(nullif(p_values ->> 'source', ''), 'formula_optometra_jornada'),
    v_prev.id, v_reason,
    -- La corrección de Operación tras liberar queda validada por quien la hace
    case when v_ctx.released then v_uid end,
    case when v_ctx.released then now() end,
    v_uid)
  returning * into v_new;

  insert into public.fabrication_spec_events (spec_id, order_id, order_item_id, event, reason, user_id)
  values (v_new.id, v_new.order_id, p_order_item_id,
          case when v_prev.id is null then 'creada' else 'version_nueva' end, v_reason, v_uid);
  if v_ctx.released then
    insert into public.fabrication_spec_events (spec_id, order_id, order_item_id, event, user_id)
    values (v_new.id, v_new.order_id, p_order_item_id, 'validada', v_uid);
  end if;
  return v_new.id;
end;
$$;

-- ---------------------------------------------------------------------
-- Validar (Operación, antes de liberar)
-- ---------------------------------------------------------------------
create function public.validate_fabrication_spec(p_spec_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_spec public.order_fabrication_specs;
  v_ctx record;
begin
  if not private.fabrication_role('operacion') then
    raise exception 'Solo Operación valida la ficha de fabricación' using errcode = '42501';
  end if;
  select * into v_spec from public.order_fabrication_specs s where s.id = p_spec_id for update;
  if v_spec.id is null or v_spec.superseded_at is not null or v_spec.is_voided then
    raise exception 'Solo se valida la versión vigente de la ficha';
  end if;
  if v_spec.validated_at is not null then
    raise exception 'La ficha ya está validada';
  end if;
  select * into v_ctx from private.fabrication_context(v_spec.order_item_id);
  if v_ctx.released then
    raise exception 'La orden ya fue liberada: corrija la ficha con una versión nueva';
  end if;

  update public.order_fabrication_specs
  set validated_by = (select auth.uid()), validated_at = now()
  where id = p_spec_id;
  insert into public.fabrication_spec_events (spec_id, order_id, order_item_id, event, user_id)
  values (p_spec_id, v_spec.order_id, v_spec.order_item_id, 'validada', (select auth.uid()));
end;
$$;

-- ---------------------------------------------------------------------
-- Anular la versión vigente (error de captura), con motivo
-- ---------------------------------------------------------------------
create function public.void_fabrication_spec(p_spec_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_spec public.order_fabrication_specs;
  v_ctx record;
  v_uid uuid := (select auth.uid());
begin
  select * into v_spec from public.order_fabrication_specs s where s.id = p_spec_id for update;
  if v_spec.id is null or v_spec.superseded_at is not null or v_spec.is_voided then
    raise exception 'Solo se anula la versión vigente de la ficha';
  end if;
  select * into v_ctx from private.fabrication_context(v_spec.order_item_id);
  if not (private.fabrication_role('operacion')
          or (not v_ctx.released and private.fabrication_role('comercial') and (v_ctx.o).created_by = v_uid)) then
    raise exception 'No puede anular esta ficha' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'Indique el motivo de la anulación';
  end if;

  update public.order_fabrication_specs
  set is_voided = true, void_reason = trim(p_reason), voided_by = v_uid, voided_at = now()
  where id = p_spec_id;
  insert into public.fabrication_spec_events (spec_id, order_id, order_item_id, event, reason, user_id)
  values (p_spec_id, v_spec.order_id, v_spec.order_item_id, 'anulada', trim(p_reason), v_uid);
end;
$$;

revoke execute on function
  public.fabrication_spec_status(uuid),
  public.get_fabrication_spec(uuid, text),
  public.save_fabrication_spec(uuid, jsonb, text),
  public.validate_fabrication_spec(uuid),
  public.void_fabrication_spec(uuid, text)
  from public, anon;
grant execute on function
  public.fabrication_spec_status(uuid),
  public.get_fabrication_spec(uuid, text),
  public.save_fabrication_spec(uuid, jsonb, text),
  public.validate_fabrication_spec(uuid),
  public.void_fabrication_spec(uuid, text)
  to authenticated;

-- ---------------------------------------------------------------------
-- Supresión por plazo de conservación (RNF-06). Sin programar: se
-- ejecuta como postgres cuando el responsable sanitario fije el plazo.
-- ---------------------------------------------------------------------
create function private.purge_fabrication_specs()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_days numeric := private.get_setting('fabrication_spec_retention_days');
  v_count int;
begin
  if v_days <= 0 then
    return 0;
  end if;
  with purged as (
    update public.order_fabrication_specs s
    set od_sphere = null, od_cylinder = null, od_axis = null, od_add = null, od_pd_mm = null, od_height_mm = null,
        os_sphere = null, os_cylinder = null, os_axis = null, os_add = null, os_pd_mm = null, os_height_mm = null,
        pd_total_mm = null, technical_notes = null, prescription_date = null,
        values_purged_at = now()
    from public.orders o
    where o.id = s.order_id and s.values_purged_at is null
      and o.ops_status = 'entrega_completa'
      and (select max(d.delivered_at) from public.order_deliveries d where d.order_id = o.id)
          < private.today_co() - v_days::int
    returning s.id, s.order_id, s.order_item_id
  ), ev as (
    insert into public.fabrication_spec_events (spec_id, order_id, order_item_id, event)
    select id, order_id, order_item_id, 'valores_suprimidos' from purged
    returning 1
  )
  select count(*) into v_count from ev;
  return v_count;
end;
$$;

revoke execute on function private.purge_fabrication_specs() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Candado de liberación (RF-M05-01)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.order_release_blockers(o orders)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_blockers text[] := '{}';
  v_pct numeric;
  v_required numeric;
  v_missing int;
begin
  if o.is_cancelled then
    return array['La orden está anulada'];
  end if;
  if o.doc_status <> 'requisitos_verificados' then
    v_blockers := v_blockers || 'Requisitos sin verificar por Administración / Cartera'::text;
  end if;
  if o.payment_modality = 'contado' and o.prepayment_exception_reason is null then
    v_pct := private.get_setting('cash_min_prepayment_pct');
    v_required := ceil(o.total_amount * v_pct);
    if private.order_verified_paid(o.id) < v_required then
      v_blockers := v_blockers || format(
        'Pago verificado inferior al %s%% del valor (o excepción de anticipo de Dirección)',
        round(v_pct * 100))::text;
    end if;
  end if;
  -- Ficha de fabricación validada por cada ítem con lente (RF-M04-07)
  if not o.is_historical_migration and private.get_setting('require_fabrication_spec') = 1 then
    v_missing := private.order_fabrication_missing(o.id);
    if v_missing > 0 then
      v_blockers := v_blockers || format(
        'Ficha de fabricación validada por Operación (%s ítem%s con lente sin ficha validada)',
        v_missing, case when v_missing = 1 then '' else 's' end)::text;
    end if;
  end if;
  return v_blockers;
end;
$function$;
