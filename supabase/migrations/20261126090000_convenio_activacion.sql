-- =====================================================================
-- SRS 1.6 · RF-M01-01 y RF-M01-03 (Backlog V0.2, SOE-09, 25/11/2026)
--
-- 1. Activación de convenio sin aprobación previa de Dirección:
--    Borrador → Aprobado («Activo») con «Activar convenio» (Comercial
--    dueño de la empresa, Administración o Dirección) si la base verifica:
--      · NIT en firme de la empresa
--      · convenio firmado vigente CON archivo (siempre, aunque
--        require_document_files = 0)
--      · vigencia completa y no vencida
--      · cuotas dentro de los topes (ya lo exige el trigger)
--    Con agreement_requires_direction_approval = 1 vuelve el flujo 1.5
--    (Borrador → Pendiente → Administración verifica → Dirección aprueba),
--    con los mismos requisitos.
-- 2. Control posterior de Dirección: revisa (reviewed_*) o cancela con
--    motivo. Condiciones congeladas al activar; solo Administración o
--    Dirección prorrogan la vigencia, con motivo.
-- 3. Versiones del convenio firmado: un documento nuevo reemplaza al
--    anterior (replaces_id) sin borrarlo.
-- 4. NIT en firme también por Comercial (empresa propia o sin ejecutivo),
--    con DV verificado. Con convenio activo o factura vinculada, solo
--    Administración cambia el NIT.
-- 5. Migración de los convenios en Pendiente de aprobación.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Parámetro de reversión
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
  'agreement_requires_direction_approval'
));
alter table public.system_settings drop constraint system_settings_boolean_flags;
alter table public.system_settings add constraint system_settings_boolean_flags check (
  key not in ('require_document_files', 'agreement_requires_direction_approval') or value in (0, 1)
);

insert into public.system_settings (key, value, description) values
  ('agreement_requires_direction_approval', 0,
   'Convenios: exigir aprobación previa de Dirección (0 = se activan al cumplir requisitos y Dirección revisa después, 1 = flujo con aprobación)');

-- ---------------------------------------------------------------------
-- Columnas nuevas
-- ---------------------------------------------------------------------
alter table public.agreements_convenios
  add column reviewed_by               uuid references public.users_profiles (id),
  add column reviewed_at               timestamptz,
  add column activated_by_migration    boolean not null default false,
  add column validity_extension_reason text,
  add column validity_extended_by      uuid references public.users_profiles (id),
  add column validity_extended_at      timestamptz,
  add constraint agreements_cancel_reason_required
    check (status <> 'cancelado' or length(trim(coalesce(cancel_reason, ''))) > 0) not valid;

create index agreements_reviewed_by_idx on public.agreements_convenios (reviewed_by);
create index agreements_validity_extended_by_idx on public.agreements_convenios (validity_extended_by);
create index agreements_pending_review_idx on public.agreements_convenios (approved_at)
  where status = 'aprobado' and reviewed_at is null;

alter table public.agreement_documents
  add column replaces_id    uuid references public.agreement_documents (id),
  add column superseded_at  timestamptz,
  add column replace_reason text,
  add constraint agreement_documents_replace_reason
    check (replaces_id is null or length(trim(coalesce(replace_reason, ''))) > 0),
  add constraint agreement_documents_not_self_replace
    check (replaces_id is distinct from id);

create unique index agreement_documents_replaces_id_key
  on public.agreement_documents (replaces_id) where replaces_id is not null;

-- La aplicación escribe solo estas columnas nuevas; el resto lo deriva la base
grant update (reviewed_at, validity_extension_reason) on public.agreements_convenios to authenticated;
grant insert (replaces_id, replace_reason) on public.agreement_documents to authenticated;

-- ---------------------------------------------------------------------
-- Requisitos del convenio firmado: vigente (no reemplazado) y con archivo
-- ---------------------------------------------------------------------
create or replace function private.assert_signed_agreement_document(p_agreement_id uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.agreement_documents d
    where d.agreement_id = p_agreement_id
      and d.document_type = 'convenio_firmado'
      and d.superseded_at is null
      and d.file_path is not null
  ) then
    raise exception 'Falta cargar el archivo PDF del convenio firmado por el cliente';
  end if;
end;
$$;

-- Requisitos para activar (o aprobar) un convenio. Recibe los valores
-- nuevos porque se llama desde el BEFORE UPDATE. Reporta todo lo que falta.
create function private.assert_agreement_activable(
  p_agreement_id uuid,
  p_company_id   uuid,
  p_valid_from   date,
  p_valid_until  date
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_missing text[] := '{}';
begin
  if exists (select 1 from public.companies c where c.id = p_company_id and c.is_nit_provisional) then
    v_missing := v_missing || 'NIT de la empresa en firme'::text;
  end if;

  if not exists (
    select 1 from public.agreement_documents d
    where d.agreement_id = p_agreement_id
      and d.document_type = 'convenio_firmado'
      and d.superseded_at is null
      and d.file_path is not null
  ) then
    v_missing := v_missing || 'archivo PDF del convenio firmado'::text;
  end if;

  if p_valid_from is null or p_valid_until is null then
    v_missing := v_missing || 'vigencia completa (desde y hasta)'::text;
  elsif p_valid_until < private.today_co() then
    v_missing := v_missing || 'vigencia no vencida'::text;
  end if;

  if cardinality(v_missing) > 0 then
    raise exception 'Faltan requisitos para activar el convenio: %', array_to_string(v_missing, '; ');
  end if;
end;
$$;

revoke execute on function private.assert_agreement_activable(uuid, uuid, date, date) from public, anon;
grant execute on function private.assert_agreement_activable(uuid, uuid, date, date) to authenticated;

-- ---------------------------------------------------------------------
-- Reglas del convenio (reemplaza la versión de m01_convenios_m03_jornadas)
-- ---------------------------------------------------------------------
create or replace function private.agreements_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_api boolean := current_user = 'authenticated';
  v_needs_approval boolean := private.get_setting('agreement_requires_direction_approval') = 1;
  v_max numeric;
begin
  v_max := private.get_setting(
    case new.payroll_frequency
      when 'mensual' then 'max_installments_monthly'
      else 'max_installments_biweekly'
    end
  );
  if new.max_installments > v_max then
    raise exception 'Con nómina % el máximo es de % cuotas', new.payroll_frequency, v_max;
  end if;

  if tg_op = 'INSERT' then
    if v_is_api then
      if new.status <> 'borrador' then
        raise exception 'Todo convenio nace en Borrador';
      end if;
      new.documents_verified := false;
      new.documents_verified_by := null;
      new.documents_verified_at := null;
      new.approved_by := null;
      new.approved_at := null;
      new.cancelled_by := null;
      new.cancelled_at := null;
      new.cancel_reason := null;
      new.reviewed_by := null;
      new.reviewed_at := null;
      new.activated_by_migration := false;
      new.validity_extension_reason := null;
      new.validity_extended_by := null;
      new.validity_extended_at := null;
    end if;
    return new;
  end if;

  if not v_is_api then
    return new;
  end if;

  -- Campos que solo escribe la base
  new.activated_by_migration := old.activated_by_migration;
  new.documents_verified_by := old.documents_verified_by;
  new.documents_verified_at := old.documents_verified_at;
  new.validity_extended_by := old.validity_extended_by;
  new.validity_extended_at := old.validity_extended_at;
  if new.status is not distinct from old.status then
    new.approved_by := old.approved_by;
    new.approved_at := old.approved_at;
    new.cancelled_by := old.cancelled_by;
    new.cancelled_at := old.cancelled_at;
    new.cancel_reason := old.cancel_reason;
  end if;

  if old.status = 'cancelado' then
    raise exception 'Un convenio cancelado no se puede modificar; registre uno nuevo';
  end if;

  -- ------------------------------------------------------------------
  -- Convenio activo: condiciones congeladas; revisar, prorrogar o cancelar
  -- ------------------------------------------------------------------
  if old.status = 'aprobado' then
    if (new.company_id, new.deal_id, new.payroll_frequency, new.max_installments, new.payroll_conditions,
        new.hr_approval_required, new.valid_from, new.documents_verified)
       is distinct from
       (old.company_id, old.deal_id, old.payroll_frequency, old.max_installments, old.payroll_conditions,
        old.hr_approval_required, old.valid_from, old.documents_verified) then
      raise exception 'Las condiciones de un convenio activo no se modifican; registre uno nuevo';
    end if;

    -- Revisión posterior de Dirección (una sola vez)
    if new.reviewed_at is distinct from old.reviewed_at or new.reviewed_by is distinct from old.reviewed_by then
      if not private.has_role('direccion') then
        raise exception 'Solo Dirección revisa los convenios activados' using errcode = '42501';
      end if;
      if old.reviewed_at is not null or new.reviewed_at is null then
        raise exception 'El convenio ya fue revisado';
      end if;
      new.reviewed_by := (select auth.uid());
      new.reviewed_at := now();
    end if;

    -- Prórroga de la vigencia
    if new.valid_until is distinct from old.valid_until then
      if not private.has_role('administracion_cartera', 'direccion') then
        raise exception 'Solo Administración o Dirección prorrogan la vigencia del convenio' using errcode = '42501';
      end if;
      if new.valid_until is null or (old.valid_until is not null and new.valid_until <= old.valid_until) then
        raise exception 'La prórroga debe ampliar la fecha final de la vigencia';
      end if;
      if new.valid_until < private.today_co() then
        raise exception 'La nueva fecha final de la vigencia ya pasó';
      end if;
      if length(trim(coalesce(new.validity_extension_reason, ''))) = 0
         or new.validity_extension_reason is not distinct from old.validity_extension_reason then
        raise exception 'Indique el motivo de la prórroga';
      end if;
      new.validity_extended_by := (select auth.uid());
      new.validity_extended_at := now();
    elsif new.validity_extension_reason is distinct from old.validity_extension_reason then
      raise exception 'El motivo de prórroga solo se registra al cambiar la vigencia';
    end if;

    if new.status = 'cancelado' then
      if not private.has_role('direccion') then
        raise exception 'Solo Dirección cancela convenios' using errcode = '42501';
      end if;
      if length(trim(coalesce(new.cancel_reason, ''))) = 0 then
        raise exception 'Indique el motivo de la cancelación';
      end if;
      new.approved_by := old.approved_by;
      new.approved_at := old.approved_at;
      new.cancelled_by := (select auth.uid());
      new.cancelled_at := now();
    elsif new.status <> 'aprobado' then
      raise exception 'Transición de convenio no permitida: % → %', old.status, new.status;
    end if;
    return new;
  end if;

  -- ------------------------------------------------------------------
  -- Borrador o Pendiente de aprobación
  -- ------------------------------------------------------------------
  new.reviewed_by := old.reviewed_by;
  new.reviewed_at := old.reviewed_at;
  new.validity_extension_reason := old.validity_extension_reason;

  -- Verificación documental (solo en el flujo con aprobación)
  if new.documents_verified is distinct from old.documents_verified then
    if not private.has_role('administracion_cartera') then
      raise exception 'Solo Administración / Cartera verifica la documentación del convenio'
        using errcode = '42501';
    end if;
    if new.documents_verified then
      if old.status <> 'pendiente_aprobacion' then
        raise exception 'La documentación se verifica con el convenio en Pendiente de Aprobación';
      end if;
      perform private.assert_signed_agreement_document(new.id);
      new.documents_verified_by := (select auth.uid());
      new.documents_verified_at := now();
    else
      new.documents_verified_by := null;
      new.documents_verified_at := null;
    end if;
  end if;

  if new.status is distinct from old.status then
    -- Activar (sin aprobación previa)
    if new.status = 'aprobado' and (old.status = 'borrador' or not v_needs_approval) then
      if v_needs_approval then
        raise exception 'El convenio requiere aprobación de Dirección: envíelo a aprobación';
      end if;
      if not private.has_role('comercial', 'administracion_cartera', 'direccion') then
        raise exception 'Solo Comercial, Administración o Dirección activan convenios' using errcode = '42501';
      end if;
      perform private.assert_agreement_activable(new.id, new.company_id, new.valid_from, new.valid_until);
      new.approved_by := (select auth.uid());
      new.approved_at := now();
      -- Si lo activa Dirección, queda revisado
      if private.has_role('direccion') and not private.has_role('comercial', 'administracion_cartera') then
        new.reviewed_by := new.approved_by;
        new.reviewed_at := new.approved_at;
      end if;

    elsif old.status = 'borrador' and new.status = 'pendiente_aprobacion' then
      if not v_needs_approval then
        raise exception 'Los convenios ya no se envían a aprobación: use Activar convenio';
      end if;
      if not private.has_role('comercial', 'administracion_cartera') then
        raise exception 'Solo Comercial o Administración envían el convenio a aprobación'
          using errcode = '42501';
      end if;
      perform private.assert_agreement_activable(new.id, new.company_id, new.valid_from, new.valid_until);

    elsif old.status = 'pendiente_aprobacion' and new.status = 'borrador' then
      new.documents_verified := false;
      new.documents_verified_by := null;
      new.documents_verified_at := null;

    elsif old.status = 'pendiente_aprobacion' and new.status = 'aprobado' then
      -- Flujo con aprobación (v_needs_approval)
      if not private.has_role('direccion') then
        raise exception 'Solo Dirección aprueba convenios' using errcode = '42501';
      end if;
      if not new.documents_verified then
        raise exception 'La documentación debe estar verificada por Administración / Cartera';
      end if;
      perform private.assert_agreement_activable(new.id, new.company_id, new.valid_from, new.valid_until);
      new.approved_by := (select auth.uid());
      new.approved_at := now();
      new.reviewed_by := new.approved_by;
      new.reviewed_at := new.approved_at;

    elsif new.status = 'cancelado' then
      if not private.has_role('direccion') then
        raise exception 'Solo Dirección cancela convenios' using errcode = '42501';
      end if;
      if length(trim(coalesce(new.cancel_reason, ''))) = 0 then
        raise exception 'Indique el motivo de la cancelación';
      end if;
      new.cancelled_by := (select auth.uid());
      new.cancelled_at := now();

    else
      raise exception 'Transición de convenio no permitida: % → %', old.status, new.status;
    end if;
  end if;

  return new;
end;
$$;

-- El reinicio automático de la verificación también aplica a la revisión:
-- sin cambios (sigue limitado a Pendiente de aprobación).

-- ---------------------------------------------------------------------
-- Documentos: versiones del convenio firmado
-- ---------------------------------------------------------------------
create or replace function private.agreement_documents_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_status public.agreement_status;
  v_target public.agreement_documents;
begin
  if current_user <> 'authenticated' then
    return coalesce(new, old);
  end if;

  select a.status into v_status
  from public.agreements_convenios a
  where a.id = coalesce(new.agreement_id, old.agreement_id);

  if tg_op = 'INSERT' then
    if v_status = 'cancelado' then
      raise exception 'No se agregan documentos a un convenio cancelado';
    end if;
    new.superseded_at := null;

    if new.replaces_id is not null then
      select * into v_target from public.agreement_documents d where d.id = new.replaces_id;
      if v_target.id is null or v_target.agreement_id <> new.agreement_id then
        raise exception 'El documento reemplazado no pertenece a este convenio';
      end if;
      if v_target.document_type <> new.document_type then
        raise exception 'Un documento solo se reemplaza por otro del mismo tipo';
      end if;
      if v_target.superseded_at is not null then
        raise exception 'Ese documento ya fue reemplazado; reemplace la versión vigente';
      end if;
    end if;

    -- En un convenio activo, el convenio firmado solo entra como versión
    -- nueva del vigente y con su archivo
    if v_status = 'aprobado' and new.document_type = 'convenio_firmado' then
      if new.replaces_id is null then
        raise exception 'El convenio ya está activo: cargue el nuevo convenio firmado como versión que reemplaza al vigente';
      end if;
      if new.file_path is null then
        raise exception 'La nueva versión del convenio firmado debe tener su archivo';
      end if;
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE'
     and (new.replaces_id, new.superseded_at, new.replace_reason)
         is distinct from (old.replaces_id, old.superseded_at, old.replace_reason) then
    raise exception 'El historial de versiones de un documento no se modifica';
  end if;

  if v_status in ('borrador', 'pendiente_aprobacion') then
    -- Una versión anterior ya reemplazada se conserva
    if tg_op = 'DELETE' and exists (select 1 from public.agreement_documents d where d.replaces_id = old.id) then
      raise exception 'Este documento tiene una versión posterior; no se elimina';
    end if;
    return coalesce(new, old);
  end if;

  if tg_op = 'UPDATE'
     and (new.document_name, new.document_type) is not distinct from (old.document_name, old.document_type)
     and old.file_path is null then
    return new;
  end if;

  raise exception 'Los documentos de un convenio % no se modifican ni se eliminan', v_status;
end;
$$;

-- Al insertar una versión nueva se marca la anterior como reemplazada.
-- Si se elimina esa versión nueva (solo posible en Borrador o Pendiente),
-- la anterior vuelve a ser la vigente.
create function private.agreement_documents_supersede()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.replaces_id is not null then
    update public.agreement_documents d
    set superseded_at = now()
    where d.id = new.replaces_id and d.superseded_at is null;
  elsif tg_op = 'DELETE' and old.replaces_id is not null then
    update public.agreement_documents d
    set superseded_at = null
    where d.id = old.replaces_id;
  end if;
  return null;
end;
$$;

revoke execute on function private.agreement_documents_supersede() from public, anon, authenticated;

create trigger agreement_documents_supersede
  after insert or delete on public.agreement_documents
  for each row execute function private.agreement_documents_supersede();

-- ---------------------------------------------------------------------
-- NIT en firme: también Comercial (RF-M01-01, 1.6)
-- ---------------------------------------------------------------------
create or replace function private.companies_guard_nit()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_admin boolean := private.has_role('administracion_cartera');
  v_is_comercial boolean := private.has_role('comercial');
  v_locked boolean;
begin
  if current_user = 'authenticated' then
    if tg_op = 'INSERT' then
      if not v_is_admin then
        new.is_nit_provisional := true;
      end if;
    else
      -- ¿Cambia el estado o el NIT en firme?
      if new.is_nit_provisional is distinct from old.is_nit_provisional
         or (not old.is_nit_provisional
             and (new.nit is distinct from old.nit or new.nit_dv is distinct from old.nit_dv)) then
        if not (v_is_admin or v_is_comercial) then
          raise exception 'Solo Comercial o Administración confirman el NIT en firme' using errcode = '42501';
        end if;
        if not v_is_admin then
          -- Comercial: solo empresas propias o sin ejecutivo
          if old.assigned_user_id is not null and old.assigned_user_id is distinct from (select auth.uid()) then
            raise exception 'Solo el ejecutivo asignado confirma el NIT de esta empresa' using errcode = '42501';
          end if;
          -- Con convenio activo o factura vinculada, el NIT en firme solo lo cambia Administración
          if not old.is_nit_provisional then
            v_locked := exists (
                select 1 from public.agreements_convenios a
                where a.company_id = old.id and a.status = 'aprobado')
              or exists (
                select 1 from public.alegra_invoices i where i.company_id = old.id);
            if v_locked then
              raise exception 'La empresa tiene convenio activo o facturas: solo Administración cambia su NIT'
                using errcode = '42501';
            end if;
          end if;
        end if;
      end if;
    end if;
    -- NIT completo y DV correcto: restricciones companies_firm_nit_complete
    -- y companies_nit_dv_valid
  end if;

  if new.is_nit_provisional then
    new.nit_verified_by := null;
    new.nit_verified_at := null;
  elsif tg_op = 'INSERT'
     or old.is_nit_provisional
     or new.nit is distinct from old.nit
     or new.nit_dv is distinct from old.nit_dv then
    new.nit_verified_by := (select auth.uid());
    new.nit_verified_at := now();
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- Vista de convenios: columnas nuevas al final
-- ---------------------------------------------------------------------
create or replace view public.v_agreements
with (security_invoker = true)
as
select
  a.id,
  a.company_id,
  c.name as company_name,
  a.deal_id,
  d.deal_name_branch,
  a.payroll_frequency,
  a.max_installments,
  a.payroll_conditions,
  a.hr_approval_required,
  a.valid_from,
  a.valid_until,
  a.status,
  case
    when a.status = 'aprobado' and a.valid_until < private.today_co() then 'vencido'
    else a.status::text
  end as effective_status,
  a.documents_verified,
  a.documents_verified_by,
  a.documents_verified_at,
  a.approved_by,
  a.approved_at,
  a.cancelled_at,
  a.cancel_reason,
  exists (
    select 1 from public.agreement_documents x
    where x.agreement_id = a.id and x.document_type = 'convenio_firmado' and x.superseded_at is null
  ) as has_signed_document,
  (select count(*) from public.agreement_documents x where x.agreement_id = a.id and x.superseded_at is null) as documents_count,
  (select count(*) from public.agreement_documents x
   where x.agreement_id = a.id and x.file_path is null and x.superseded_at is null) as documents_pending_file,
  a.created_at,
  a.updated_at,
  exists (
    select 1 from public.agreement_documents x
    where x.agreement_id = a.id and x.document_type = 'convenio_firmado'
      and x.superseded_at is null and x.file_path is not null
  ) as has_signed_file,
  a.reviewed_by,
  a.reviewed_at,
  a.activated_by_migration,
  a.validity_extension_reason,
  a.validity_extended_by,
  a.validity_extended_at,
  a.cancelled_by,
  c.is_nit_provisional as company_nit_provisional
from public.agreements_convenios a
join public.companies c on c.id = a.company_id
left join public.deals_opportunities d on d.id = a.deal_id;

-- ---------------------------------------------------------------------
-- Resumen del circuito: convenios activados por revisar (Dirección)
-- ---------------------------------------------------------------------
create or replace function public.circuit_summary()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'vender', jsonb_build_object(
      'abiertas', (select count(*) from public.deals_opportunities d
                   where d.stage between 'prospecto' and 'convenio_firmado'),
      'quietas', (select count(*) from public.v_deals_board d
                  where d.stage between 'prospecto' and 'convenio_firmado'
                    and (d.inactivity_alert or d.next_action_overdue))
    ),
    'convenios_por_aprobar', (select count(*) from public.agreements_convenios a where a.status = 'pendiente_aprobacion'),
    'convenios_por_revisar', (select count(*) from public.agreements_convenios a
                              where a.status = 'aprobado' and a.reviewed_at is null),
    'jornada', jsonb_build_object(
      'en_ejecucion', (select count(*) from public.campaigns_jornadas j where j.status = 'en_ejecucion'),
      'por_ejecutar', (select count(*) from public.campaigns_jornadas j where j.status in ('borrador', 'programada')),
      'captura_cerrada', (select count(*) from public.campaigns_jornadas j where j.status = 'captura_cerrada')
    ),
    'orden', jsonb_build_object(
      'por_verificar', (select count(*) from public.orders o where not o.is_cancelled and o.doc_status = 'pendiente_soportes'),
      'por_liberar', (select count(*) from public.orders o
                      where not o.is_cancelled and o.doc_status = 'requisitos_verificados' and o.ops_status = 'pendiente_liberar')
    ),
    'producir', jsonb_build_object(
      'en_lab', (select count(*) from public.order_productions p where p.status = 'en_produccion'),
      'atrasadas', (select count(*) from public.order_productions p
                    where p.status = 'en_produccion' and p.promised_date < private.today_co())
    ),
    'entregar', jsonb_build_object(
      'listas', (select count(*) from public.orders o where not o.is_cancelled and o.ops_status = 'listo_para_entregar'),
      'parciales', (select count(*) from public.orders o where not o.is_cancelled and o.ops_status = 'entrega_parcial')
    ),
    'posventa', (select count(*) from public.post_sale_warranties w where w.status <> 'cerrada'),
    'facturar', jsonb_build_object(
      'sin_factura', (select count(*) from public.v_orders_to_invoice),
      'diferencias', (select count(*) from public.orders o
                      where not o.is_cancelled and o.accounting_status = 'factura_con_diferencia')
    ),
    'cobrar', jsonb_build_object(
      'saldo', (select coalesce(sum(o.balance_due), 0) from public.orders o where not o.is_cancelled),
      'vencidas', (select count(*) from public.v_installments_due i where i.due_date <= private.today_co()),
      'monto_vencido', (select coalesce(sum(i.pending_amount), 0) from public.v_installments_due i
                        where i.due_date <= private.today_co()),
      'proximas', (select count(*) from public.v_installments_due i
                   where i.due_date > private.today_co() and i.due_date <= private.today_co() + 7),
      'pagos_sin_asignar', (select count(*) from public.v_payments p where not p.is_voided and p.unassigned_amount > 0),
      'reclasificaciones', (select count(*) from public.portfolio_reclassifications r where r.status = 'pendiente')
    )
  );
$$;

-- ---------------------------------------------------------------------
-- Migración de datos existentes (como postgres: los triggers de reglas
-- no aplican; la auditoría sí registra el cambio)
-- ---------------------------------------------------------------------

-- Convenios aprobados por Dirección en el flujo anterior: ya revisados
update public.agreements_convenios a
set reviewed_by = a.approved_by,
    reviewed_at = a.approved_at
where a.status = 'aprobado' and a.reviewed_at is null;

-- Pendientes de aprobación que cumplen los requisitos: activos
update public.agreements_convenios a
set status = 'aprobado',
    approved_at = now(),
    approved_by = null,
    activated_by_migration = true
where a.status = 'pendiente_aprobacion'
  and exists (select 1 from public.companies c where c.id = a.company_id and not c.is_nit_provisional)
  and exists (
    select 1 from public.agreement_documents d
    where d.agreement_id = a.id and d.document_type = 'convenio_firmado'
      and d.superseded_at is null and d.file_path is not null)
  and a.valid_from is not null
  and a.valid_until is not null
  and a.valid_until >= private.today_co();

-- El resto vuelve a Borrador para completarse y activarse
update public.agreements_convenios a
set status = 'borrador',
    documents_verified = false,
    documents_verified_by = null,
    documents_verified_at = null
where a.status = 'pendiente_aprobacion';
