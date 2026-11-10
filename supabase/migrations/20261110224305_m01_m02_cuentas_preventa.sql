-- =====================================================================
-- M01 (Cuentas) + M02 (Preventa): empresas, sedes, contactos,
-- orígenes, oportunidades con Facturación Estimada y bitácora.
-- Referencias SRS v1.4: §4.1 (RF-M01-01, RF-M01-02), §4.2 (RF-M02-01 a
-- RF-M02-05), §5.2, §5.3, §3.2 (matriz RBAC).
-- Los convenios (RF-M01-03) llegan en la siguiente migración; hasta
-- entonces la etapa Convenio Firmado queda bloqueada.
-- =====================================================================

create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------
create type public.payroll_frequency as enum ('mensual', 'quincenal');
create type public.contact_area as enum ('rrhh', 'sst', 'gerencia', 'compras', 'otra');
create type public.deal_stage as enum (
  'prospecto',
  'reunion_exploratoria',
  'propuesta_enviada',
  'negociacion',
  'convenio_firmado',
  'jornada_en_ejecucion',
  'facturacion_cerrada',
  'cierre_perdido'
);
create type public.lost_substatus as enum ('nurturing', 'no_contactar');
create type public.interaction_type as enum ('reunion', 'llamada', 'whatsapp', 'correo');

-- ---------------------------------------------------------------------
-- La auditoría también identifica registros por "code" (catálogos)
-- ---------------------------------------------------------------------
create or replace function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
begin
  if tg_op = 'UPDATE' and v_old = v_new then
    return null;
  end if;

  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by)
  values (
    tg_table_name,
    coalesce(v_new ->> 'id', v_old ->> 'id', v_new ->> 'key', v_old ->> 'key',
             v_new ->> 'code', v_old ->> 'code'),
    tg_op,
    v_old,
    v_new,
    (select auth.uid())
  );
  return null;
end;
$$;

-- ---------------------------------------------------------------------
-- Funciones de apoyo: normalización de razón social y dígito de
-- verificación del NIT (algoritmo DIAN, módulo 11)
-- ---------------------------------------------------------------------
create function private.normalize_company_name(p_name text)
returns text
language plpgsql
immutable
parallel safe
set search_path = ''
as $$
declare
  v text;
begin
  v := lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p_name, '')));
  v := replace(v, '.', '');
  v := trim(regexp_replace(v, '[^a-z0-9]+', ' ', 'g'));
  -- Sufijos societarios al final (dos pasadas para casos como "sas bic")
  for i in 1..2 loop
    v := trim(regexp_replace(v, '\s(sas|s a s|sa|s a|ltda|limitada|s en c|s en cs|sca|eu|e u|bic|y cia|cia)$', ''));
  end loop;
  return v;
end;
$$;

create function private.nit_check_digit(p_nit text)
returns smallint
language plpgsql
immutable
parallel safe
set search_path = ''
as $$
declare
  weights constant int[] := array[3, 7, 13, 17, 19, 23, 29, 37, 41, 43, 47, 53, 59, 67, 71];
  n int := length(p_nit);
  s int := 0;
  r int;
begin
  for i in 1..n loop
    s := s + substr(p_nit, n - i + 1, 1)::int * weights[i];
  end loop;
  r := s % 11;
  return (case when r in (0, 1) then r else 11 - r end)::smallint;
end;
$$;

revoke execute on function private.normalize_company_name(text) from public, anon;
revoke execute on function private.nit_check_digit(text) from public, anon;
grant execute on function private.normalize_company_name(text) to authenticated;
grant execute on function private.nit_check_digit(text) to authenticated;

-- ---------------------------------------------------------------------
-- Empresas (RF-M01-01, §5.2.5)
-- ---------------------------------------------------------------------
create table public.companies (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null check (length(trim(name)) > 0),
  name_normalized    text generated always as (private.normalize_company_name(name)) stored,
  nit                text check (nit ~ '^[0-9]{5,10}$'),
  nit_dv             smallint check (nit_dv between 0 and 9),
  is_nit_provisional boolean not null default true,
  nit_verified_by    uuid references public.users_profiles (id),
  nit_verified_at    timestamptz,
  sector             text not null check (length(trim(sector)) > 0),
  total_employees    integer check (total_employees > 0),
  payroll_frequency  public.payroll_frequency,
  website            text,
  assigned_user_id   uuid references public.users_profiles (id),
  created_by         uuid default auth.uid() references public.users_profiles (id),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint companies_nit_dv_valid
    check (nit is null or nit_dv is null or nit_dv = private.nit_check_digit(nit)),
  constraint companies_firm_nit_complete
    check (is_nit_provisional or (nit is not null and nit_dv is not null))
);

-- Anti-duplicados: NIT único y razón social normalizada única
create unique index companies_nit_key on public.companies (nit) where nit is not null;
create unique index companies_name_normalized_key on public.companies (name_normalized);
create index companies_name_trgm_idx on public.companies
  using gin (name_normalized extensions.gin_trgm_ops);
create index companies_assigned_user_id_idx on public.companies (assigned_user_id);
create index companies_created_by_idx on public.companies (created_by);
create index companies_nit_verified_by_idx on public.companies (nit_verified_by);

create trigger companies_set_updated_at
  before update on public.companies
  for each row execute function private.set_updated_at();

-- Solo Administración / Cartera confirma el NIT en firme (matriz §3.2)
create function private.companies_guard_nit()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_admin boolean := private.has_role('administracion_cartera');
begin
  if current_user = 'authenticated' and not v_is_admin then
    if tg_op = 'INSERT' then
      new.is_nit_provisional := true;
    elsif new.is_nit_provisional is distinct from old.is_nit_provisional
       or (not old.is_nit_provisional
           and (new.nit is distinct from old.nit or new.nit_dv is distinct from old.nit_dv)) then
      raise exception 'Solo Administración / Cartera puede confirmar o modificar un NIT en firme'
        using errcode = '42501';
    end if;
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

create trigger companies_guard_nit
  before insert or update on public.companies
  for each row execute function private.companies_guard_nit();

-- Búsqueda de duplicados antes de crear una empresa (RF-M01-01)
create function public.find_company_duplicates(p_name text, p_nit text default null)
returns table (
  id                 uuid,
  name               text,
  nit                text,
  is_nit_provisional boolean,
  match_reason       text,
  similarity         real
)
language sql
stable
security invoker
set search_path = ''
as $$
  with q as (
    select
      private.normalize_company_name(p_name) as n,
      nullif(regexp_replace(split_part(coalesce(p_nit, ''), '-', 1), '\D', '', 'g'), '') as nit
  )
  select
    c.id,
    c.name,
    c.nit,
    c.is_nit_provisional,
    case
      when q.nit is not null and c.nit = q.nit then 'nit'
      when c.name_normalized = q.n then 'nombre_exacto'
      else 'nombre_similar'
    end,
    extensions.similarity(c.name_normalized, q.n)
  from public.companies c
  cross join q
  where (q.nit is not null and c.nit = q.nit)
     or c.name_normalized = q.n
     or extensions.similarity(c.name_normalized, q.n) >= 0.4
  order by 6 desc
  limit 10;
$$;

-- ---------------------------------------------------------------------
-- Sedes (RF-M01-01, §5.2.6)
-- ---------------------------------------------------------------------
create table public.company_branches (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id),
  name       text not null check (length(trim(name)) > 0),
  city_id    uuid references public.cities (id),
  city_other text check (city_other is null or length(trim(city_other)) > 0),
  address    text,
  is_main    boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint company_branches_one_city check (num_nonnulls(city_id, city_other) = 1),
  constraint company_branches_id_company_key unique (id, company_id)
);

create unique index company_branches_name_key on public.company_branches (company_id, lower(name));
create unique index company_branches_one_main_key on public.company_branches (company_id) where is_main;
create index company_branches_city_id_idx on public.company_branches (city_id);

create trigger company_branches_set_updated_at
  before update on public.company_branches
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Contactos (RF-M01-02, §5.2.7)
-- ---------------------------------------------------------------------
create table public.contacts (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references public.companies (id),
  branch_id         uuid,
  full_name         text not null check (length(trim(full_name)) > 0),
  role_title        text not null check (length(trim(role_title)) > 0),
  area              public.contact_area not null,
  is_coordinator    boolean not null default false,
  is_decision_maker boolean not null default false,
  phone_whatsapp    text check (phone_whatsapp is null or phone_whatsapp ~ '^\+?[0-9 ()-]{7,20}$'),
  email             text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  active            boolean not null default true,
  created_by        uuid default auth.uid() references public.users_profiles (id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint contacts_has_channel check (num_nonnulls(phone_whatsapp, email) >= 1),
  constraint contacts_branch_same_company
    foreign key (branch_id, company_id) references public.company_branches (id, company_id),
  constraint contacts_id_company_key unique (id, company_id)
);

create index contacts_company_id_idx on public.contacts (company_id);
create index contacts_branch_id_idx on public.contacts (branch_id);
create index contacts_created_by_idx on public.contacts (created_by);

create trigger contacts_set_updated_at
  before update on public.contacts
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Orígenes de prospecto (RF-M02-01) — catálogo parametrizable
-- ---------------------------------------------------------------------
create table public.deal_origins (
  code       text primary key check (code ~ '^[a-z_]+$'),
  label      text not null check (length(trim(label)) > 0),
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger deal_origins_set_updated_at
  before update on public.deal_origins
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Oportunidades (RF-M02-01 a RF-M02-05, §5.3.10)
-- ---------------------------------------------------------------------
create table public.deals_opportunities (
  id                         uuid primary key default gen_random_uuid(),
  company_id                 uuid not null references public.companies (id),
  branch_id                  uuid,
  city_id                    uuid not null references public.cities (id),
  primary_contact_id         uuid,
  assigned_user_id           uuid not null references public.users_profiles (id),
  deal_name_branch           text not null check (length(trim(deal_name_branch)) > 0),
  origin_code                text not null references public.deal_origins (code),
  stage                      public.deal_stage not null default 'prospecto',
  lost_substatus             public.lost_substatus,
  next_action                text,
  next_action_due_date       date,
  next_action_owner_id       uuid references public.users_profiles (id),
  payroll_frequency          public.payroll_frequency,
  target_employees_n         integer check (target_employees_n > 0),
  conversion_rate_c_snapshot numeric(5, 4) not null,
  average_ticket_t_snapshot  numeric(14, 0) not null,
  estimated_billing_amount   numeric(14, 0) generated always as (
    round(target_employees_n * conversion_rate_c_snapshot * average_ticket_t_snapshot)
  ) stored,
  estimated_close_date       date,
  tentative_campaign_date    date,
  reached_agreement_at       timestamptz,
  last_interaction_type      public.interaction_type,
  last_interaction_note      text,
  last_interaction_at        timestamptz,
  created_by                 uuid default auth.uid() references public.users_profiles (id),
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),
  constraint deals_branch_same_company
    foreign key (branch_id, company_id) references public.company_branches (id, company_id),
  constraint deals_contact_same_company
    foreign key (primary_contact_id, company_id) references public.contacts (id, company_id),
  constraint deals_lost_substatus
    check ((stage = 'cierre_perdido') = (lost_substatus is not null)),
  -- Siguiente acción obligatoria en etapas 1–4 y en Nurturing (RF-M02-01)
  constraint deals_next_action_required check (
    not (
      stage in ('prospecto', 'reunion_exploratoria', 'propuesta_enviada', 'negociacion')
      or (stage = 'cierre_perdido' and lost_substatus = 'nurturing')
    )
    or (
      next_action is not null and length(trim(next_action)) > 0
      and next_action_due_date is not null
      and next_action_owner_id is not null
    )
  ),
  -- Desde Propuesta Enviada se conocen N y la fecha estimada de cierre
  constraint deals_proposal_data check (
    stage in ('prospecto', 'reunion_exploratoria', 'cierre_perdido')
    or (target_employees_n is not null and estimated_close_date is not null)
  ),
  -- Fecha tentativa de jornada obligatoria desde Convenio Firmado
  constraint deals_campaign_date check (
    stage not between 'convenio_firmado' and 'facturacion_cerrada'
    or tentative_campaign_date is not null
  )
);

create index deals_company_id_idx on public.deals_opportunities (company_id);
create index deals_branch_id_idx on public.deals_opportunities (branch_id);
create index deals_city_id_idx on public.deals_opportunities (city_id);
create index deals_primary_contact_id_idx on public.deals_opportunities (primary_contact_id);
create index deals_assigned_user_id_idx on public.deals_opportunities (assigned_user_id);
create index deals_next_action_owner_id_idx on public.deals_opportunities (next_action_owner_id);
create index deals_origin_code_idx on public.deals_opportunities (origin_code);
create index deals_created_by_idx on public.deals_opportunities (created_by);
create index deals_stage_idx on public.deals_opportunities (stage);

create trigger deals_set_updated_at
  before update on public.deals_opportunities
  for each row execute function private.set_updated_at();

-- Reglas de negocio de la oportunidad
create function private.deals_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_api boolean := current_user = 'authenticated';
begin
  if tg_op = 'INSERT' then
    -- Parámetros de Facturación Estimada congelados al crear (RF-M02-03)
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
      if new.stage = 'convenio_firmado' then
        raise exception 'Convenio Firmado requiere un convenio aprobado (se habilita con el módulo de convenios)';
      end if;
    end if;
  end if;

  -- Al reabrir desde Cierre Perdido se limpia el sub-estado
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

create trigger deals_before_write
  before insert or update on public.deals_opportunities
  for each row execute function private.deals_before_write();

-- Recalcular la Facturación Estimada con los parámetros vigentes (Dirección)
create function public.recalculate_deal_forecast(p_deal_id uuid)
returns numeric
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_amount numeric;
begin
  if not private.has_role('direccion') then
    raise exception 'Solo Dirección puede recalcular la Facturación Estimada' using errcode = '42501';
  end if;

  update public.deals_opportunities d
  set conversion_rate_c_snapshot = private.get_setting('conversion_rate_c'),
      average_ticket_t_snapshot = private.get_setting('average_ticket_t')
  where d.id = p_deal_id
  returning d.estimated_billing_amount into v_amount;

  if not found then
    raise exception 'Oportunidad no encontrada' using errcode = 'P0002';
  end if;
  return v_amount;
end;
$$;

-- ---------------------------------------------------------------------
-- Bitácora tipificada (RF-M02-04, §5.3.11) — solo inserción
-- ---------------------------------------------------------------------
create table public.deal_interaction_logs (
  id               uuid primary key default gen_random_uuid(),
  deal_id          uuid not null references public.deals_opportunities (id),
  user_id          uuid not null default auth.uid() references public.users_profiles (id),
  interaction_type public.interaction_type not null,
  interaction_note text not null check (length(trim(interaction_note)) > 0),
  created_at       timestamptz not null default now()
);

create index deal_interaction_logs_deal_idx on public.deal_interaction_logs (deal_id, created_at desc);
create index deal_interaction_logs_user_id_idx on public.deal_interaction_logs (user_id);

-- La última interacción actualiza la tarjeta del negocio
create function private.deal_logs_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.deals_opportunities d
  set last_interaction_type = new.interaction_type,
      last_interaction_note = new.interaction_note,
      last_interaction_at = new.created_at
  where d.id = new.deal_id
    and (d.last_interaction_at is null or d.last_interaction_at <= new.created_at);
  return null;
end;
$$;

revoke execute on function private.deal_logs_after_insert() from public, anon, authenticated;

create trigger deal_logs_after_insert
  after insert on public.deal_interaction_logs
  for each row execute function private.deal_logs_after_insert();

-- ---------------------------------------------------------------------
-- Tablero Kanban (RF-M02-05): inactividad, siguiente acción vencida y
-- Nuevo Negocio. Fechas en hora de Colombia.
-- ---------------------------------------------------------------------
create view public.v_deals_board
with (security_invoker = true)
as
with params as (
  select
    private.get_setting('inactivity_alert_days') as inactivity_days,
    (now() at time zone 'America/Bogota')::date as today
)
select
  d.id,
  d.company_id,
  c.name as company_name,
  d.branch_id,
  d.deal_name_branch,
  d.city_id,
  ci.name as city_name,
  d.stage,
  d.lost_substatus,
  d.origin_code,
  d.assigned_user_id,
  u.full_name as assigned_user_name,
  d.target_employees_n,
  d.estimated_billing_amount,
  d.estimated_close_date,
  d.tentative_campaign_date,
  d.next_action,
  d.next_action_due_date,
  d.next_action_owner_id,
  coalesce(d.next_action_due_date < p.today, false) as next_action_overdue,
  d.last_interaction_type,
  d.last_interaction_note,
  d.last_interaction_at,
  p.today - (coalesce(d.last_interaction_at, d.created_at) at time zone 'America/Bogota')::date as days_inactive,
  (
    d.stage between 'prospecto' and 'convenio_firmado'
    and p.today - (coalesce(d.last_interaction_at, d.created_at) at time zone 'America/Bogota')::date
        > p.inactivity_days
  ) as inactivity_alert,
  not exists (
    select 1 from public.deals_opportunities o
    where o.company_id = d.company_id
      and o.id <> d.id
      and o.reached_agreement_at < d.created_at
  ) as is_new_business,
  d.created_at,
  d.updated_at
from public.deals_opportunities d
join public.companies c on c.id = d.company_id
join public.cities ci on ci.id = d.city_id
join public.users_profiles u on u.id = d.assigned_user_id
cross join params p;

-- ---------------------------------------------------------------------
-- Auditoría
-- ---------------------------------------------------------------------
create trigger companies_audit
  after insert or update or delete on public.companies
  for each row execute function private.audit_row_change();
create trigger company_branches_audit
  after insert or update or delete on public.company_branches
  for each row execute function private.audit_row_change();
create trigger contacts_audit
  after insert or update or delete on public.contacts
  for each row execute function private.audit_row_change();
create trigger deal_origins_audit
  after insert or update or delete on public.deal_origins
  for each row execute function private.audit_row_change();
create trigger deals_audit
  after insert or update or delete on public.deals_opportunities
  for each row execute function private.audit_row_change();

-- ---------------------------------------------------------------------
-- Privilegios (por columna: los campos derivados no se escriben desde la API)
-- ---------------------------------------------------------------------
revoke all on public.companies, public.company_branches, public.contacts,
  public.deal_origins, public.deals_opportunities, public.deal_interaction_logs,
  public.v_deals_board
  from anon, authenticated;

revoke execute on function public.find_company_duplicates(text, text) from public, anon;
revoke execute on function public.recalculate_deal_forecast(uuid) from public, anon;
grant execute on function public.find_company_duplicates(text, text) to authenticated;
grant execute on function public.recalculate_deal_forecast(uuid) to authenticated;

grant select on public.companies to authenticated;
grant insert (name, nit, nit_dv, is_nit_provisional, sector, total_employees,
              payroll_frequency, website, assigned_user_id)
  on public.companies to authenticated;
grant update (name, nit, nit_dv, is_nit_provisional, sector, total_employees,
              payroll_frequency, website, assigned_user_id)
  on public.companies to authenticated;

grant select on public.company_branches to authenticated;
grant insert (company_id, name, city_id, city_other, address, is_main)
  on public.company_branches to authenticated;
grant update (name, city_id, city_other, address, is_main)
  on public.company_branches to authenticated;

grant select on public.contacts to authenticated;
grant insert (company_id, branch_id, full_name, role_title, area, is_coordinator,
              is_decision_maker, phone_whatsapp, email, active)
  on public.contacts to authenticated;
grant update (branch_id, full_name, role_title, area, is_coordinator,
              is_decision_maker, phone_whatsapp, email, active)
  on public.contacts to authenticated;

grant select on public.deal_origins to authenticated;
grant insert (code, label, active) on public.deal_origins to authenticated;
grant update (label, active) on public.deal_origins to authenticated;

grant select on public.deals_opportunities to authenticated;
grant insert (company_id, branch_id, city_id, primary_contact_id, assigned_user_id,
              deal_name_branch, origin_code, stage, lost_substatus, next_action,
              next_action_due_date, next_action_owner_id, payroll_frequency,
              target_employees_n, estimated_close_date, tentative_campaign_date)
  on public.deals_opportunities to authenticated;
grant update (branch_id, city_id, primary_contact_id, assigned_user_id,
              deal_name_branch, origin_code, stage, lost_substatus, next_action,
              next_action_due_date, next_action_owner_id, payroll_frequency,
              target_employees_n, estimated_close_date, tentative_campaign_date,
              conversion_rate_c_snapshot, average_ticket_t_snapshot)
  on public.deals_opportunities to authenticated;

grant select on public.deal_interaction_logs to authenticated;
grant insert (deal_id, interaction_type, interaction_note)
  on public.deal_interaction_logs to authenticated;

grant select on public.v_deals_board to authenticated;

-- ---------------------------------------------------------------------
-- RLS (matriz §3.2)
-- 02 Empresa / 03 Contactos: Comercial crea y edita; Administración edita.
-- 01 / 04 Oportunidad: Comercial crea y edita; Dirección edita (valida).
-- Lectura: todos los usuarios internos activos.
-- ---------------------------------------------------------------------
alter table public.companies             enable row level security;
alter table public.company_branches      enable row level security;
alter table public.contacts              enable row level security;
alter table public.deal_origins          enable row level security;
alter table public.deals_opportunities   enable row level security;
alter table public.deal_interaction_logs enable row level security;

-- companies
create policy companies_select on public.companies
  for select to authenticated
  using ((select private.is_internal_user()));
create policy companies_insert on public.companies
  for insert to authenticated
  with check ((select private.has_role('comercial')));
create policy companies_update on public.companies
  for update to authenticated
  using ((select private.has_role('comercial', 'administracion_cartera')))
  with check ((select private.has_role('comercial', 'administracion_cartera')));

-- company_branches
create policy company_branches_select on public.company_branches
  for select to authenticated
  using ((select private.is_internal_user()));
create policy company_branches_insert on public.company_branches
  for insert to authenticated
  with check ((select private.has_role('comercial')));
create policy company_branches_update on public.company_branches
  for update to authenticated
  using ((select private.has_role('comercial', 'administracion_cartera')))
  with check ((select private.has_role('comercial', 'administracion_cartera')));

-- contacts
create policy contacts_select on public.contacts
  for select to authenticated
  using ((select private.is_internal_user()));
create policy contacts_insert on public.contacts
  for insert to authenticated
  with check ((select private.has_role('comercial')));
create policy contacts_update on public.contacts
  for update to authenticated
  using ((select private.has_role('comercial', 'administracion_cartera')))
  with check ((select private.has_role('comercial', 'administracion_cartera')));

-- deal_origins (parámetro: Dirección)
create policy deal_origins_select on public.deal_origins
  for select to authenticated
  using ((select private.is_internal_user()));
create policy deal_origins_insert on public.deal_origins
  for insert to authenticated
  with check ((select private.has_role('direccion')));
create policy deal_origins_update on public.deal_origins
  for update to authenticated
  using ((select private.has_role('direccion')))
  with check ((select private.has_role('direccion')));

-- deals_opportunities
create policy deals_select on public.deals_opportunities
  for select to authenticated
  using ((select private.is_internal_user()));
create policy deals_insert on public.deals_opportunities
  for insert to authenticated
  with check ((select private.has_role('comercial')));
create policy deals_update on public.deals_opportunities
  for update to authenticated
  using ((select private.has_role('comercial', 'direccion')))
  with check ((select private.has_role('comercial', 'direccion')));

-- deal_interaction_logs (sin update ni delete)
create policy deal_logs_select on public.deal_interaction_logs
  for select to authenticated
  using ((select private.is_internal_user()));
create policy deal_logs_insert on public.deal_interaction_logs
  for insert to authenticated
  with check (
    (select private.has_role('comercial', 'direccion'))
    and user_id = (select auth.uid())
  );

-- ---------------------------------------------------------------------
-- Datos de referencia
-- ---------------------------------------------------------------------
insert into public.deal_origins (code, label) values
  ('referido',           'Referido'),
  ('inbound_web',        'Inbound web'),
  ('llamada_saliente',   'Llamada saliente'),
  ('evento',             'Evento'),
  ('cliente_recurrente', 'Cliente recurrente'),
  ('otro',               'Otro');
