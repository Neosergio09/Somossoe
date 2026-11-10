-- =====================================================================
-- Fundación: esquema privado, roles, perfiles, catálogos, parámetros y
-- auditoría.
-- Referencias SRS v1.4: §3 (roles y RBAC), §5.1 (configuración y
-- seguridad), §5.8 (audit_logs), RNF-01 (trazabilidad).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Esquema privado: funciones auxiliares que no se exponen por la Data API
-- ---------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------
-- Roles de la aplicación (SRS §3.1)
-- ---------------------------------------------------------------------
create type public.app_role as enum (
  'comercial',
  'operacion',
  'administracion_cartera',
  'direccion',
  'proveedor_lab'
);

-- ---------------------------------------------------------------------
-- Trigger genérico de updated_at
-- ---------------------------------------------------------------------
create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- Perfiles de usuario (SRS §5.1.1)
-- Un perfil nace inactivo y sin rol cuando se crea el usuario en Auth.
-- Solo Dirección asigna rol y activa. El rol vive en esta tabla, nunca
-- en user_metadata (editable por el propio usuario).
-- ---------------------------------------------------------------------
create table public.users_profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  full_name       text not null check (length(trim(full_name)) > 0),
  email           text not null,
  role            public.app_role,
  lab_provider_id uuid,
  active          boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint users_profiles_active_requires_role
    check (not active or role is not null),
  constraint users_profiles_lab_only_for_provider
    check (lab_provider_id is null or role = 'proveedor_lab'),
  constraint users_profiles_provider_requires_lab
    check (role is distinct from 'proveedor_lab' or lab_provider_id is not null)
);

create unique index users_profiles_email_key on public.users_profiles (lower(email));
create index users_profiles_lab_provider_id_idx on public.users_profiles (lab_provider_id);

create trigger users_profiles_set_updated_at
  before update on public.users_profiles
  for each row execute function private.set_updated_at();

-- Alta automática del perfil al crear el usuario en Auth
create function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users_profiles (id, full_name, email)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), new.email, new.id::text),
    coalesce(new.email, '')
  );
  return new;
end;
$$;

revoke execute on function private.handle_new_auth_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_auth_user();

-- ---------------------------------------------------------------------
-- Funciones de autorización para las políticas RLS
-- SECURITY DEFINER para leer users_profiles sin recursión de RLS; siempre
-- filtran por auth.uid() y solo cuentan perfiles activos.
-- ---------------------------------------------------------------------
create function private.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.users_profiles p
  where p.id = (select auth.uid())
    and p.active;
$$;

create function private.has_role(variadic roles public.app_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.current_app_role() = any (roles), false);
$$;

-- Usuario interno activo (excluye proveedor_lab)
create function private.is_internal_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_role('comercial', 'operacion', 'administracion_cartera', 'direccion');
$$;

-- Laboratorio del usuario proveedor activo (null para los demás)
create function private.current_lab_provider_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.lab_provider_id
  from public.users_profiles p
  where p.id = (select auth.uid())
    and p.active
    and p.role = 'proveedor_lab';
$$;

revoke execute on function private.current_app_role() from public, anon;
revoke execute on function private.has_role(public.app_role[]) from public, anon;
revoke execute on function private.is_internal_user() from public, anon;
revoke execute on function private.current_lab_provider_id() from public, anon;
grant execute on function private.current_app_role() to authenticated;
grant execute on function private.has_role(public.app_role[]) to authenticated;
grant execute on function private.is_internal_user() to authenticated;
grant execute on function private.current_lab_provider_id() to authenticated;

-- ---------------------------------------------------------------------
-- Catálogo de laboratorios proveedores (SRS §5.1.4)
-- ---------------------------------------------------------------------
create table public.lab_providers (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (length(trim(name)) > 0),
  contact_info text,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create unique index lab_providers_name_key on public.lab_providers (lower(name));

create trigger lab_providers_set_updated_at
  before update on public.lab_providers
  for each row execute function private.set_updated_at();

alter table public.users_profiles
  add constraint users_profiles_lab_provider_id_fkey
  foreign key (lab_provider_id) references public.lab_providers (id);

-- ---------------------------------------------------------------------
-- Catálogo de ciudades (SRS §5.1.3) — reemplaza el ENUM de ciudades
-- ---------------------------------------------------------------------
create table public.cities (
  id             uuid primary key default gen_random_uuid(),
  name           text not null check (length(trim(name)) > 0),
  is_operational boolean not null default true,
  active         boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create unique index cities_name_key on public.cities (lower(name));

create trigger cities_set_updated_at
  before update on public.cities
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Parámetros globales (SRS §5.1.2)
-- Las claves son fijas (las crea una migración); Dirección solo edita
-- valores. El historial de cambios queda en audit_logs.
-- ---------------------------------------------------------------------
create table public.system_settings (
  key         text primary key,
  value       numeric not null,
  description text not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.users_profiles (id),
  constraint system_settings_known_key check (key in (
    'conversion_rate_c',
    'average_ticket_t',
    'inactivity_alert_days',
    'cash_min_prepayment_pct',
    'max_installments_monthly',
    'max_installments_biweekly'
  )),
  constraint system_settings_conversion_rate_range
    check (key <> 'conversion_rate_c' or (value > 0 and value <= 1)),
  constraint system_settings_ticket_positive
    check (key <> 'average_ticket_t' or (value > 0 and value = trunc(value))),
  constraint system_settings_prepayment_range
    check (key <> 'cash_min_prepayment_pct' or (value >= 0 and value <= 1)),
  constraint system_settings_positive_integers
    check (
      key not in ('inactivity_alert_days', 'max_installments_monthly', 'max_installments_biweekly')
      or (value >= 1 and value = trunc(value))
    )
);

create index system_settings_updated_by_idx on public.system_settings (updated_by);

create function private.set_settings_audit_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  new.updated_by := (select auth.uid());
  return new;
end;
$$;

create trigger system_settings_set_audit_fields
  before update on public.system_settings
  for each row execute function private.set_settings_audit_fields();

-- Lectura tipada de un parámetro; falla si la clave no existe
create function private.get_setting(p_key text)
returns numeric
language plpgsql
stable
set search_path = ''
as $$
declare
  v_value numeric;
begin
  select s.value into v_value from public.system_settings s where s.key = p_key;
  if v_value is null then
    raise exception 'Parámetro de sistema inexistente: %', p_key;
  end if;
  return v_value;
end;
$$;

revoke execute on function private.get_setting(text) from public, anon;
grant execute on function private.get_setting(text) to authenticated;

-- ---------------------------------------------------------------------
-- Auditoría inmutable (SRS §5.8, RNF-01)
-- ---------------------------------------------------------------------
create table public.audit_logs (
  id         bigint generated always as identity primary key,
  table_name text not null,
  record_id  text not null,
  action     text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  old_data   jsonb,
  new_data   jsonb,
  changed_by uuid,
  changed_at timestamptz not null default now()
);

create index audit_logs_record_idx on public.audit_logs (table_name, record_id, changed_at desc);
create index audit_logs_changed_by_idx on public.audit_logs (changed_by);

create function private.audit_row_change()
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
    coalesce(v_new ->> 'id', v_old ->> 'id', v_new ->> 'key', v_old ->> 'key'),
    tg_op,
    v_old,
    v_new,
    (select auth.uid())
  );
  return null;
end;
$$;

revoke execute on function private.audit_row_change() from public, anon, authenticated;

create trigger users_profiles_audit
  after insert or update or delete on public.users_profiles
  for each row execute function private.audit_row_change();
create trigger lab_providers_audit
  after insert or update or delete on public.lab_providers
  for each row execute function private.audit_row_change();
create trigger cities_audit
  after insert or update or delete on public.cities
  for each row execute function private.audit_row_change();
create trigger system_settings_audit
  after insert or update or delete on public.system_settings
  for each row execute function private.audit_row_change();

-- ---------------------------------------------------------------------
-- Privilegios: nada para anon; authenticated solo lo necesario.
-- RLS define además qué filas ve o cambia cada rol.
-- ---------------------------------------------------------------------
revoke all on public.users_profiles, public.lab_providers, public.cities,
  public.system_settings, public.audit_logs
  from anon, authenticated;

grant select on public.users_profiles to authenticated;
grant update (full_name, role, lab_provider_id, active) on public.users_profiles to authenticated;

grant select, insert, update on public.lab_providers to authenticated;
grant select, insert, update on public.cities to authenticated;

grant select on public.system_settings to authenticated;
grant update (value, description) on public.system_settings to authenticated;

grant select on public.audit_logs to authenticated;

-- ---------------------------------------------------------------------
-- RLS (SRS §3.2: parámetros y catálogos los edita Dirección; Administración
-- los consulta; todos los usuarios internos leen catálogos)
-- ---------------------------------------------------------------------
alter table public.users_profiles  enable row level security;
alter table public.lab_providers   enable row level security;
alter table public.cities          enable row level security;
alter table public.system_settings enable row level security;
alter table public.audit_logs      enable row level security;

-- users_profiles: internos ven a todos; cualquiera ve su propio perfil
create policy users_profiles_select on public.users_profiles
  for select to authenticated
  using ((select private.is_internal_user()) or id = (select auth.uid()));

create policy users_profiles_update_direccion on public.users_profiles
  for update to authenticated
  using ((select private.has_role('direccion')))
  with check ((select private.has_role('direccion')));

-- lab_providers: internos ven todos; el proveedor solo el suyo
create policy lab_providers_select on public.lab_providers
  for select to authenticated
  using (
    (select private.is_internal_user())
    or id = (select private.current_lab_provider_id())
  );

create policy lab_providers_insert_direccion on public.lab_providers
  for insert to authenticated
  with check ((select private.has_role('direccion')));

create policy lab_providers_update_direccion on public.lab_providers
  for update to authenticated
  using ((select private.has_role('direccion')))
  with check ((select private.has_role('direccion')));

-- cities
create policy cities_select on public.cities
  for select to authenticated
  using ((select private.is_internal_user()));

create policy cities_insert_direccion on public.cities
  for insert to authenticated
  with check ((select private.has_role('direccion')));

create policy cities_update_direccion on public.cities
  for update to authenticated
  using ((select private.has_role('direccion')))
  with check ((select private.has_role('direccion')));

-- system_settings
create policy system_settings_select on public.system_settings
  for select to authenticated
  using ((select private.is_internal_user()));

create policy system_settings_update_direccion on public.system_settings
  for update to authenticated
  using ((select private.has_role('direccion')))
  with check ((select private.has_role('direccion')));

-- audit_logs: lectura para usuarios internos; sin políticas de escritura
create policy audit_logs_select on public.audit_logs
  for select to authenticated
  using ((select private.is_internal_user()));

-- ---------------------------------------------------------------------
-- Datos de referencia
-- ---------------------------------------------------------------------
insert into public.cities (name, is_operational) values
  ('Pereira', true),
  ('Medellín', true);

insert into public.system_settings (key, value, description) values
  ('conversion_rate_c',         0.70,   'Tasa de conversión estimada C para Facturación Estimada (RF-M02-03)'),
  ('average_ticket_t',          300000, 'Ticket promedio T en COP por empleado comprador (RF-M02-03)'),
  ('inactivity_alert_days',     7,      'Días sin interacción en bitácora para alertar inactividad (RF-M02-04)'),
  ('cash_min_prepayment_pct',   1.00,   'Porcentaje mínimo de pago verificado para liberar a producción en contado (RF-M04-03)'),
  ('max_installments_monthly',  4,      'Máximo de cuotas con nómina mensual'),
  ('max_installments_biweekly', 8,      'Máximo de cuotas con nómina quincenal');
