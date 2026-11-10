-- =====================================================================
-- M01 Convenios (Etapa 05) + M03 Jornadas (Etapa 06)
-- Referencias SRS v1.4: RF-M01-03, RF-M02-05 (etapas 5 y 6),
-- RF-M03-01 a RF-M03-03, §5.2.8–9, §5.4, §3.2.
-- La carga de archivos a Cloudflare R2 se integra después: mientras
-- require_document_files = 0, el soporte se registra sin archivo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Parámetro: exigir archivo en los soportes documentales
-- ---------------------------------------------------------------------
alter table public.system_settings drop constraint system_settings_known_key;
alter table public.system_settings add constraint system_settings_known_key check (key in (
  'conversion_rate_c',
  'average_ticket_t',
  'inactivity_alert_days',
  'cash_min_prepayment_pct',
  'max_installments_monthly',
  'max_installments_biweekly',
  'require_document_files'
));
alter table public.system_settings add constraint system_settings_boolean_flags
  check (key <> 'require_document_files' or value in (0, 1));

insert into public.system_settings (key, value, description) values
  ('require_document_files', 0,
   'Exigir archivo cargado (R2) en los soportes documentales: 0 = no (hasta integrar R2), 1 = sí');

-- ---------------------------------------------------------------------
-- Fecha de hoy en Colombia
-- ---------------------------------------------------------------------
create function private.today_co()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'America/Bogota')::date;
$$;

revoke execute on function private.today_co() from public, anon;
grant execute on function private.today_co() to authenticated;

-- ---------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------
create type public.agreement_status as enum (
  'borrador', 'pendiente_aprobacion', 'aprobado', 'cancelado'
);
create type public.agreement_document_type as enum (
  'convenio_firmado', 'camara_comercio', 'rut', 'formato_rrhh', 'otro'
);
create type public.campaign_status as enum (
  'programada', 'en_ejecucion', 'cerrada', 'cancelada'
);

alter table public.deals_opportunities
  add constraint deals_id_company_key unique (id, company_id);

-- ---------------------------------------------------------------------
-- Convenios (RF-M01-03, §5.2.8)
-- Flujo: borrador → pendiente_aprobacion → (Administración verifica
-- documentación) → aprobado (Dirección). Aprobado o cancelado ya no se
-- modifica; un cambio de condiciones exige un convenio nuevo.
-- deal_id nulo = convenio marco para todas las sedes de la empresa.
-- "Vencido" se deriva de valid_until (ver v_agreements).
-- ---------------------------------------------------------------------
create table public.agreements_convenios (
  id                    uuid primary key default gen_random_uuid(),
  company_id            uuid not null references public.companies (id),
  deal_id               uuid,
  payroll_frequency     public.payroll_frequency not null,
  max_installments      smallint not null check (max_installments >= 1),
  payroll_conditions    text,
  hr_approval_required  boolean not null default true,
  valid_from            date,
  valid_until           date,
  status                public.agreement_status not null default 'borrador',
  documents_verified    boolean not null default false,
  documents_verified_by uuid references public.users_profiles (id),
  documents_verified_at timestamptz,
  approved_by           uuid references public.users_profiles (id),
  approved_at           timestamptz,
  cancelled_by          uuid references public.users_profiles (id),
  cancelled_at          timestamptz,
  cancel_reason         text,
  created_by            uuid default auth.uid() references public.users_profiles (id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint agreements_validity
    check (valid_from is null or valid_until is null or valid_until >= valid_from),
  constraint agreements_deal_same_company
    foreign key (deal_id, company_id) references public.deals_opportunities (id, company_id),
  constraint agreements_id_company_key unique (id, company_id)
);

create index agreements_company_id_idx on public.agreements_convenios (company_id);
create index agreements_deal_id_idx on public.agreements_convenios (deal_id);
create index agreements_status_idx on public.agreements_convenios (status);
create index agreements_documents_verified_by_idx on public.agreements_convenios (documents_verified_by);
create index agreements_approved_by_idx on public.agreements_convenios (approved_by);
create index agreements_cancelled_by_idx on public.agreements_convenios (cancelled_by);
create index agreements_created_by_idx on public.agreements_convenios (created_by);

create trigger agreements_set_updated_at
  before update on public.agreements_convenios
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Documentación del convenio (§5.2.9)
-- ---------------------------------------------------------------------
create table public.agreement_documents (
  id            uuid primary key default gen_random_uuid(),
  agreement_id  uuid not null references public.agreements_convenios (id),
  document_name text not null check (length(trim(document_name)) > 0),
  document_type public.agreement_document_type not null,
  file_r2_key   text check (file_r2_key is null or length(trim(file_r2_key)) > 0),
  uploaded_by   uuid default auth.uid() references public.users_profiles (id),
  uploaded_at   timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index agreement_documents_agreement_id_idx on public.agreement_documents (agreement_id);
create index agreement_documents_uploaded_by_idx on public.agreement_documents (uploaded_by);

create trigger agreement_documents_set_updated_at
  before update on public.agreement_documents
  for each row execute function private.set_updated_at();

-- Debe existir el convenio firmado (con archivo si el parámetro lo exige)
create function private.assert_signed_agreement_document(p_agreement_id uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_files_required boolean := private.get_setting('require_document_files') = 1;
begin
  if not exists (
    select 1 from public.agreement_documents d
    where d.agreement_id = p_agreement_id
      and d.document_type = 'convenio_firmado'
      and (not v_files_required or d.file_r2_key is not null)
  ) then
    raise exception '%', case when v_files_required
      then 'Falta cargar el archivo del convenio firmado por el cliente'
      else 'Falta registrar el documento de convenio firmado por el cliente' end;
  end if;
end;
$$;

revoke execute on function private.assert_signed_agreement_document(uuid) from public, anon;
grant execute on function private.assert_signed_agreement_document(uuid) to authenticated;

-- Reglas del convenio
create function private.agreements_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_api boolean := current_user = 'authenticated';
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
    end if;
    return new;
  end if;

  if not v_is_api then
    return new;
  end if;

  -- Convenio aprobado o cancelado: solo se permite cancelar el aprobado
  if old.status in ('aprobado', 'cancelado') then
    if old.status = 'aprobado'
       and new.status = 'cancelado'
       and private.has_role('direccion')
       and (new.payroll_frequency, new.max_installments, new.payroll_conditions,
            new.hr_approval_required, new.valid_from, new.valid_until, new.deal_id)
           is not distinct from
           (old.payroll_frequency, old.max_installments, old.payroll_conditions,
            old.hr_approval_required, old.valid_from, old.valid_until, old.deal_id) then
      new.cancelled_by := (select auth.uid());
      new.cancelled_at := now();
      return new;
    end if;
    raise exception 'Un convenio % no se puede modificar; registre uno nuevo', old.status;
  end if;

  -- Verificación documental (Administración / Cartera)
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
    if old.status = 'borrador' and new.status = 'pendiente_aprobacion' then
      if not private.has_role('comercial', 'administracion_cartera') then
        raise exception 'Solo Comercial o Administración envían el convenio a aprobación'
          using errcode = '42501';
      end if;
      perform private.assert_signed_agreement_document(new.id);

    elsif old.status = 'pendiente_aprobacion' and new.status = 'borrador' then
      new.documents_verified := false;
      new.documents_verified_by := null;
      new.documents_verified_at := null;

    elsif old.status = 'pendiente_aprobacion' and new.status = 'aprobado' then
      if not private.has_role('direccion') then
        raise exception 'Solo Dirección aprueba convenios' using errcode = '42501';
      end if;
      if not new.documents_verified then
        raise exception 'La documentación debe estar verificada por Administración / Cartera';
      end if;
      if exists (
        select 1 from public.companies c
        where c.id = new.company_id and c.is_nit_provisional
      ) then
        raise exception 'La empresa debe tener el NIT en firme para aprobar el convenio';
      end if;
      if new.valid_until is not null and new.valid_until < private.today_co() then
        raise exception 'La vigencia del convenio ya terminó';
      end if;
      perform private.assert_signed_agreement_document(new.id);
      new.approved_by := (select auth.uid());
      new.approved_at := now();

    elsif new.status = 'cancelado' then
      if not private.has_role('direccion') then
        raise exception 'Solo Dirección cancela convenios' using errcode = '42501';
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

create trigger agreements_before_write
  before insert or update on public.agreements_convenios
  for each row execute function private.agreements_before_write();

-- Documentos: no se cambian ni se borran en convenios aprobados o
-- cancelados, salvo completar el archivo pendiente (integración R2)
create function private.agreement_documents_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_status public.agreement_status;
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
    return new;
  end if;

  if v_status in ('borrador', 'pendiente_aprobacion') then
    return coalesce(new, old);
  end if;

  if tg_op = 'UPDATE'
     and (new.document_name, new.document_type) is not distinct from (old.document_name, old.document_type)
     and old.file_r2_key is null then
    return new;
  end if;

  raise exception 'Los documentos de un convenio % no se modifican ni se eliminan', v_status;
end;
$$;

create trigger agreement_documents_guard
  before insert or update or delete on public.agreement_documents
  for each row execute function private.agreement_documents_guard();

-- ---------------------------------------------------------------------
-- Oportunidades: Convenio Firmado exige convenio aprobado y vigente
-- (reemplaza el bloqueo temporal de la migración anterior)
-- ---------------------------------------------------------------------
create or replace function private.deals_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_api boolean := current_user = 'authenticated';
begin
  if tg_op = 'INSERT' then
    new.conversion_rate_c_snapshot := private.get_setting('conversion_rate_c');
    new.average_ticket_t_snapshot := private.get_setting('average_ticket_t');
    new.reached_agreement_at := null;
    new.last_interaction_type := null;
    new.last_interaction_note := null;
    new.last_interaction_at := null;
    if new.payroll_frequency is null then
      new.payroll_frequency := (select c.payroll_frequency from public.companies c where c.id = new.company_id);
    end if;
    if v_is_api and new.stage <> 'prospecto' then
      raise exception 'Toda oportunidad nace en la etapa Prospecto';
    end if;
  elsif v_is_api then
    if (new.conversion_rate_c_snapshot, new.average_ticket_t_snapshot)
       is distinct from (old.conversion_rate_c_snapshot, old.average_ticket_t_snapshot)
       and not private.has_role('direccion') then
      raise exception 'Solo Dirección puede recalcular la Facturación Estimada' using errcode = '42501';
    end if;

    if new.stage is distinct from old.stage then
      if old.stage in ('jornada_en_ejecucion', 'facturacion_cerrada')
         or new.stage in ('jornada_en_ejecucion', 'facturacion_cerrada') then
        raise exception 'Las etapas Jornada en Ejecución y Facturación Cerrada avanzan automáticamente';
      end if;
      if old.stage = 'cierre_perdido' then
        if old.lost_substatus = 'no_contactar' then
          raise exception 'Una oportunidad descartada (No Contactar) no se puede reabrir';
        end if;
        if new.stage not in ('prospecto', 'reunion_exploratoria', 'propuesta_enviada', 'negociacion') then
          raise exception 'Una oportunidad en Nurturing solo se reabre en las etapas 1 a 4';
        end if;
      end if;
      if new.stage in ('reunion_exploratoria', 'propuesta_enviada', 'negociacion', 'convenio_firmado')
         and not exists (
           select 1 from public.deal_interaction_logs l
           where l.deal_id = new.id and l.interaction_type = 'reunion'
         ) then
        raise exception 'Para pasar a % se requiere al menos una Reunión registrada en la bitácora', new.stage;
      end if;
      if new.stage = 'convenio_firmado' and not exists (
        select 1 from public.agreements_convenios a
        where a.company_id = new.company_id
          and a.status = 'aprobado'
          and (a.deal_id is null or a.deal_id = new.id)
          and (a.valid_until is null or a.valid_until >= private.today_co())
      ) then
        raise exception 'Convenio Firmado requiere un convenio aprobado y vigente para esta oportunidad';
      end if;
    end if;
  end if;

  if new.stage <> 'cierre_perdido' then
    new.lost_substatus := null;
  end if;

  if new.stage between 'convenio_firmado' and 'facturacion_cerrada' and new.reached_agreement_at is null then
    new.reached_agreement_at := now();
  end if;

  if v_is_api then
    if tg_op = 'INSERT' or new.city_id is distinct from old.city_id then
      if not exists (
        select 1 from public.cities c
        where c.id = new.city_id and c.active and c.is_operational
      ) then
        raise exception 'La ciudad de la oportunidad debe ser una ciudad operativa activa';
      end if;
    end if;

    if new.primary_contact_id is not null
       and (tg_op = 'INSERT' or new.primary_contact_id is distinct from old.primary_contact_id)
       and not exists (
         select 1 from public.contacts ct where ct.id = new.primary_contact_id and ct.active
       ) then
      raise exception 'El contacto principal debe estar activo';
    end if;

    if (tg_op = 'INSERT' or new.assigned_user_id is distinct from old.assigned_user_id)
       and not exists (
         select 1 from public.users_profiles p
         where p.id = new.assigned_user_id and p.active and p.role in ('comercial', 'direccion')
       ) then
      raise exception 'El ejecutivo asignado debe ser un usuario activo de Comercial o Dirección';
    end if;

    if new.target_employees_n > (
      select c.total_employees from public.companies c where c.id = new.company_id
    ) then
      raise exception 'N (% empleados a atender) no puede superar el total de empleados de la empresa',
        new.target_employees_n;
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- Jornadas (RF-M03-02, §5.4.12)
-- ---------------------------------------------------------------------
create table public.campaigns_jornadas (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references public.companies (id),
  deal_id             uuid not null,
  agreement_id        uuid not null,
  branch_id           uuid,
  city_id             uuid not null references public.cities (id),
  responsible_user_id uuid not null references public.users_profiles (id),
  logistics_confirmed boolean not null default false,
  status              public.campaign_status not null default 'programada',
  notes               text,
  started_at          timestamptz,
  closed_at           timestamptz,
  cancelled_at        timestamptz,
  cancel_reason       text,
  created_by          uuid default auth.uid() references public.users_profiles (id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint campaigns_deal_same_company
    foreign key (deal_id, company_id) references public.deals_opportunities (id, company_id),
  constraint campaigns_agreement_same_company
    foreign key (agreement_id, company_id) references public.agreements_convenios (id, company_id),
  constraint campaigns_branch_same_company
    foreign key (branch_id, company_id) references public.company_branches (id, company_id),
  constraint campaigns_cancel_reason
    check (status <> 'cancelada' or (cancel_reason is not null and length(trim(cancel_reason)) > 0))
);

create index campaigns_company_id_idx on public.campaigns_jornadas (company_id);
create index campaigns_deal_id_idx on public.campaigns_jornadas (deal_id);
create index campaigns_agreement_id_idx on public.campaigns_jornadas (agreement_id);
create index campaigns_branch_id_idx on public.campaigns_jornadas (branch_id);
create index campaigns_city_id_idx on public.campaigns_jornadas (city_id);
create index campaigns_responsible_user_id_idx on public.campaigns_jornadas (responsible_user_id);
create index campaigns_created_by_idx on public.campaigns_jornadas (created_by);
create index campaigns_status_idx on public.campaigns_jornadas (status);

create trigger campaigns_set_updated_at
  before update on public.campaigns_jornadas
  for each row execute function private.set_updated_at();

create function private.campaigns_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_api boolean := current_user = 'authenticated';
  v_deal record;
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
      if new.status <> 'programada' then
        raise exception 'Toda jornada nace Programada';
      end if;
      new.started_at := null;
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
    if old.status in ('cerrada', 'cancelada') then
      raise exception 'Una jornada % no se puede modificar', old.status;
    end if;

    if new.status is distinct from old.status then
      if old.status = 'programada' and new.status = 'en_ejecucion' then
        if not new.logistics_confirmed then
          raise exception 'No se puede iniciar la jornada sin logística confirmada';
        end if;
        if not exists (select 1 from public.campaign_sessions s where s.campaign_id = new.id) then
          raise exception 'La jornada necesita al menos una sesión programada';
        end if;
        new.started_at := now();
      elsif old.status = 'en_ejecucion' and new.status = 'cerrada' then
        new.closed_at := now();
      elsif old.status = 'programada' and new.status = 'cancelada' then
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

create trigger campaigns_before_write
  before insert or update on public.campaigns_jornadas
  for each row execute function private.campaigns_before_write();

-- Al iniciar la primera jornada, la oportunidad pasa a Jornada en Ejecución
create function private.campaigns_after_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'en_ejecucion' then
    update public.deals_opportunities d
    set stage = 'jornada_en_ejecucion'
    where d.id = new.deal_id
      and d.stage = 'convenio_firmado';
  end if;
  return null;
end;
$$;

revoke execute on function private.campaigns_after_status() from public, anon, authenticated;

create trigger campaigns_after_status
  after update of status on public.campaigns_jornadas
  for each row execute function private.campaigns_after_status();

-- ---------------------------------------------------------------------
-- Sesiones de jornada (§5.4.13)
-- ---------------------------------------------------------------------
create table public.campaign_sessions (
  id                  uuid primary key default gen_random_uuid(),
  campaign_id         uuid not null references public.campaigns_jornadas (id),
  session_date        date not null,
  start_time          time not null,
  end_time            time not null,
  location_detail     text,
  responsible_user_id uuid not null references public.users_profiles (id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint campaign_sessions_time check (end_time > start_time),
  constraint campaign_sessions_id_campaign_key unique (id, campaign_id)
);

create index campaign_sessions_campaign_id_idx on public.campaign_sessions (campaign_id);
create index campaign_sessions_responsible_date_idx
  on public.campaign_sessions (responsible_user_id, session_date);

create trigger campaign_sessions_set_updated_at
  before update on public.campaign_sessions
  for each row execute function private.set_updated_at();

create function private.campaign_sessions_guard()
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

  if v_campaign.status not in ('programada', 'en_ejecucion') then
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

create trigger campaign_sessions_guard
  before insert or update or delete on public.campaign_sessions
  for each row execute function private.campaign_sessions_guard();

-- ---------------------------------------------------------------------
-- Asistencia operativa sin datos clínicos (RF-M03-03, §5.4.14)
-- El vínculo con el comprador (buyer_id) llega con el módulo de órdenes.
-- ---------------------------------------------------------------------
create table public.campaign_attendance (
  id            uuid primary key default gen_random_uuid(),
  campaign_id   uuid not null references public.campaigns_jornadas (id),
  session_id    uuid not null,
  full_name     text not null check (length(trim(full_name)) > 0),
  document_id   text not null check (document_id ~ '^[0-9A-Za-z]{4,15}$'),
  area          text,
  registered_by uuid default auth.uid() references public.users_profiles (id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint campaign_attendance_session_same_campaign
    foreign key (session_id, campaign_id) references public.campaign_sessions (id, campaign_id),
  constraint campaign_attendance_unique_person unique (session_id, document_id)
);

create index campaign_attendance_campaign_id_idx on public.campaign_attendance (campaign_id);
create index campaign_attendance_document_id_idx on public.campaign_attendance (document_id);
create index campaign_attendance_registered_by_idx on public.campaign_attendance (registered_by);

create trigger campaign_attendance_set_updated_at
  before update on public.campaign_attendance
  for each row execute function private.set_updated_at();

create function private.campaign_attendance_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'authenticated' and not exists (
    select 1 from public.campaigns_jornadas c
    where c.id = coalesce(new.campaign_id, old.campaign_id)
      and c.status = 'en_ejecucion'
  ) then
    raise exception 'La asistencia solo se registra con la jornada En Ejecución';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger campaign_attendance_guard
  before insert or update or delete on public.campaign_attendance
  for each row execute function private.campaign_attendance_guard();

-- ---------------------------------------------------------------------
-- Vistas
-- ---------------------------------------------------------------------
create view public.v_agreements
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
    where x.agreement_id = a.id and x.document_type = 'convenio_firmado'
  ) as has_signed_document,
  (select count(*) from public.agreement_documents x where x.agreement_id = a.id) as documents_count,
  (select count(*) from public.agreement_documents x
   where x.agreement_id = a.id and x.file_r2_key is null) as documents_pending_file,
  a.created_at,
  a.updated_at
from public.agreements_convenios a
join public.companies c on c.id = a.company_id
left join public.deals_opportunities d on d.id = a.deal_id;

create view public.v_campaigns
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
  j.updated_at
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
  select count(distinct y.document_id) as attended_headcount
  from public.campaign_attendance y
  where y.campaign_id = j.id
) att on true;

-- Calendario (RF-M03-01): advierte cruces del mismo responsable
create view public.v_campaign_calendar
with (security_invoker = true)
as
select
  s.id as session_id,
  s.campaign_id,
  j.status as campaign_status,
  c.name as company_name,
  d.deal_name_branch,
  j.city_id,
  ci.name as city_name,
  b.name as branch_name,
  s.session_date,
  s.start_time,
  s.end_time,
  s.location_detail,
  s.responsible_user_id,
  u.full_name as responsible_user_name,
  exists (
    select 1
    from public.campaign_sessions s2
    join public.campaigns_jornadas j2 on j2.id = s2.campaign_id
    where s2.id <> s.id
      and s2.responsible_user_id = s.responsible_user_id
      and s2.session_date = s.session_date
      and s2.start_time < s.end_time
      and s2.end_time > s.start_time
      and j2.status <> 'cancelada'
  ) as has_conflict
from public.campaign_sessions s
join public.campaigns_jornadas j on j.id = s.campaign_id
join public.companies c on c.id = j.company_id
join public.deals_opportunities d on d.id = j.deal_id
join public.cities ci on ci.id = j.city_id
join public.users_profiles u on u.id = s.responsible_user_id
left join public.company_branches b on b.id = j.branch_id
where j.status <> 'cancelada';

-- ---------------------------------------------------------------------
-- Auditoría
-- ---------------------------------------------------------------------
create trigger agreements_audit
  after insert or update or delete on public.agreements_convenios
  for each row execute function private.audit_row_change();
create trigger agreement_documents_audit
  after insert or update or delete on public.agreement_documents
  for each row execute function private.audit_row_change();
create trigger campaigns_audit
  after insert or update or delete on public.campaigns_jornadas
  for each row execute function private.audit_row_change();
create trigger campaign_sessions_audit
  after insert or update or delete on public.campaign_sessions
  for each row execute function private.audit_row_change();
create trigger campaign_attendance_audit
  after insert or update or delete on public.campaign_attendance
  for each row execute function private.audit_row_change();

-- ---------------------------------------------------------------------
-- Privilegios
-- ---------------------------------------------------------------------
revoke all on public.agreements_convenios, public.agreement_documents,
  public.campaigns_jornadas, public.campaign_sessions, public.campaign_attendance,
  public.v_agreements, public.v_campaigns, public.v_campaign_calendar
  from anon, authenticated;

grant select on public.agreements_convenios to authenticated;
grant insert (company_id, deal_id, payroll_frequency, max_installments, payroll_conditions,
              hr_approval_required, valid_from, valid_until)
  on public.agreements_convenios to authenticated;
grant update (deal_id, payroll_frequency, max_installments, payroll_conditions,
              hr_approval_required, valid_from, valid_until, status,
              documents_verified, cancel_reason)
  on public.agreements_convenios to authenticated;

grant select, delete on public.agreement_documents to authenticated;
grant insert (agreement_id, document_name, document_type, file_r2_key)
  on public.agreement_documents to authenticated;
grant update (document_name, document_type, file_r2_key)
  on public.agreement_documents to authenticated;

grant select on public.campaigns_jornadas to authenticated;
grant insert (deal_id, agreement_id, branch_id, city_id, responsible_user_id,
              logistics_confirmed, notes)
  on public.campaigns_jornadas to authenticated;
grant update (branch_id, city_id, responsible_user_id, logistics_confirmed, status,
              notes, cancel_reason)
  on public.campaigns_jornadas to authenticated;

grant select, delete on public.campaign_sessions to authenticated;
grant insert (campaign_id, session_date, start_time, end_time, location_detail, responsible_user_id)
  on public.campaign_sessions to authenticated;
grant update (session_date, start_time, end_time, location_detail, responsible_user_id)
  on public.campaign_sessions to authenticated;

grant select, delete on public.campaign_attendance to authenticated;
grant insert (campaign_id, session_id, full_name, document_id, area)
  on public.campaign_attendance to authenticated;
grant update (full_name, document_id, area)
  on public.campaign_attendance to authenticated;

grant select on public.v_agreements, public.v_campaigns, public.v_campaign_calendar to authenticated;

-- ---------------------------------------------------------------------
-- RLS (matriz §3.2)
-- 05 Convenio: Comercial crea y carga soportes; Administración edita y
--    verifica documentación; Dirección aprueba / cancela.
-- 06 Jornada: Operación crea y edita; Comercial edita y apoya asistencia.
-- ---------------------------------------------------------------------
alter table public.agreements_convenios enable row level security;
alter table public.agreement_documents  enable row level security;
alter table public.campaigns_jornadas   enable row level security;
alter table public.campaign_sessions    enable row level security;
alter table public.campaign_attendance  enable row level security;

-- agreements_convenios
create policy agreements_select on public.agreements_convenios
  for select to authenticated
  using ((select private.is_internal_user()));
create policy agreements_insert on public.agreements_convenios
  for insert to authenticated
  with check ((select private.has_role('comercial')));
create policy agreements_update on public.agreements_convenios
  for update to authenticated
  using ((select private.has_role('comercial', 'administracion_cartera', 'direccion')))
  with check ((select private.has_role('comercial', 'administracion_cartera', 'direccion')));

-- agreement_documents
create policy agreement_documents_select on public.agreement_documents
  for select to authenticated
  using ((select private.is_internal_user()));
create policy agreement_documents_insert on public.agreement_documents
  for insert to authenticated
  with check ((select private.has_role('comercial', 'administracion_cartera')));
create policy agreement_documents_update on public.agreement_documents
  for update to authenticated
  using ((select private.has_role('comercial', 'administracion_cartera')))
  with check ((select private.has_role('comercial', 'administracion_cartera')));
create policy agreement_documents_delete on public.agreement_documents
  for delete to authenticated
  using ((select private.has_role('comercial', 'administracion_cartera')));

-- campaigns_jornadas
create policy campaigns_select on public.campaigns_jornadas
  for select to authenticated
  using ((select private.is_internal_user()));
create policy campaigns_insert on public.campaigns_jornadas
  for insert to authenticated
  with check ((select private.has_role('operacion')));
create policy campaigns_update on public.campaigns_jornadas
  for update to authenticated
  using ((select private.has_role('operacion', 'comercial')))
  with check ((select private.has_role('operacion', 'comercial')));

-- campaign_sessions
create policy campaign_sessions_select on public.campaign_sessions
  for select to authenticated
  using ((select private.is_internal_user()));
create policy campaign_sessions_insert on public.campaign_sessions
  for insert to authenticated
  with check ((select private.has_role('operacion')));
create policy campaign_sessions_update on public.campaign_sessions
  for update to authenticated
  using ((select private.has_role('operacion', 'comercial')))
  with check ((select private.has_role('operacion', 'comercial')));
create policy campaign_sessions_delete on public.campaign_sessions
  for delete to authenticated
  using ((select private.has_role('operacion')));

-- campaign_attendance
create policy campaign_attendance_select on public.campaign_attendance
  for select to authenticated
  using ((select private.is_internal_user()));
create policy campaign_attendance_insert on public.campaign_attendance
  for insert to authenticated
  with check ((select private.has_role('operacion', 'comercial')));
create policy campaign_attendance_update on public.campaign_attendance
  for update to authenticated
  using ((select private.has_role('operacion', 'comercial')))
  with check ((select private.has_role('operacion', 'comercial')));
create policy campaign_attendance_delete on public.campaign_attendance
  for delete to authenticated
  using ((select private.has_role('operacion', 'comercial')));
