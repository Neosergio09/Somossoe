-- =====================================================================
-- Acceso total para Comercial y Super administrador (27-nov-2026,
-- decisión del usuario).
--
-- * private.has_full_access(): Super administrador (rol principal) o
--   cualquier usuario con el rol Comercial (principal o adicional).
-- * has_role(...) es verdadero para ellos con cualquier rol pedido: pasan
--   todas las políticas RLS y guardas (costos, cartera, facturas,
--   reclasificación, parámetros, catálogos, importador...).
-- * Propiedad comercial (owns_*): editan registros de cualquiera.
-- * Ficha RX/ADD: actúan como Operación (consultan, capturan, validan,
--   corrigen y anulan en cualquier estado). Todo queda en las bitácoras.
-- * Gestión de usuarios: solo Super administrador y Dirección (rol
--   principal real), NO Comercial.
-- * «Debe quedar al menos un usuario de Dirección activo» pasa a contar
--   también al Super administrador (quien puede gestionar usuarios).
-- Las reglas de negocio (estados, montos, candados) siguen aplicando.
-- =====================================================================

create function private.has_full_access()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    private.current_app_role() = 'superadmin'
      or 'comercial' = any (private.current_app_roles()),
    false);
$$;

revoke execute on function private.has_full_access() from public, anon;
grant execute on function private.has_full_access() to authenticated;

create function private.can_manage_users()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.current_app_role() in ('superadmin', 'direccion'), false);
$$;

revoke execute on function private.can_manage_users() from public, anon;
grant execute on function private.can_manage_users() to authenticated;

create or replace function private.has_role(variadic roles public.app_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    private.has_full_access()
      or private.current_app_roles() && roles,
    false);
$$;

-- ---------------------------------------------------------------------
-- Propiedad comercial
-- ---------------------------------------------------------------------
create or replace function private.owns_company(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_full_access() or exists (
    select 1 from public.companies c
    where c.id = p_company_id
      and (c.assigned_user_id is null or c.assigned_user_id = (select auth.uid()))
  );
$$;

create or replace function private.owns_deal(p_deal_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_full_access() or exists (
    select 1 from public.deals_opportunities d
    where d.id = p_deal_id and d.assigned_user_id = (select auth.uid())
  );
$$;

create or replace function private.owns_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_full_access() or exists (
    select 1 from public.orders o
    where o.id = p_order_id and o.created_by = (select auth.uid())
  );
$$;

-- ---------------------------------------------------------------------
-- Ficha RX: acceso total actúa como Operación
-- ---------------------------------------------------------------------
create or replace function private.fabrication_role(p_role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_full_access() or p_role = any (private.current_app_roles());
$$;

create or replace function public.get_fabrication_spec(p_order_item_id uuid, p_purpose text)
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
    raise exception 'La ficha de fabricación solo la consultan Comercial, Operación y el Super administrador'
      using errcode = '42501';
  end if;
  if p_purpose not in ('captura', 'validacion', 'envio_laboratorio', 'correccion', 'consulta') then
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

-- Guardar la ficha antes de liberar: también con acceso total (no solo quien registró la orden)
create or replace function public.save_fabrication_spec(p_order_item_id uuid, p_values jsonb, p_change_reason text default null)
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
    if not (private.has_full_access()
            or (private.fabrication_role('comercial') and (v_ctx.o).created_by = v_uid)) then
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
-- Usuarios: solo Super administrador y Dirección
-- ---------------------------------------------------------------------
drop policy users_profiles_update_direccion on public.users_profiles;
create policy users_profiles_update_direccion on public.users_profiles
  for update to authenticated
  using ((select private.can_manage_users()))
  with check ((select private.can_manage_users()));

create or replace function private.users_profiles_keep_direccion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.role in ('direccion', 'superadmin') and old.active
     and (tg_op = 'DELETE' or new.role not in ('direccion', 'superadmin') or new.role is null or not new.active) then
    -- Bloquea los perfiles que gestionan usuarios para evitar que dos
    -- cambios simultáneos dejen el sistema sin ninguno
    perform 1 from public.users_profiles p
    where p.role in ('direccion', 'superadmin') and p.active
    for update;

    if not exists (
      select 1 from public.users_profiles p
      where p.role in ('direccion', 'superadmin') and p.active and p.id <> old.id
    ) then
      raise exception 'Debe quedar al menos un usuario de Dirección o Super administrador activo; active a otro antes de este cambio';
    end if;
  end if;
  return coalesce(new, old);
end;
$$;
