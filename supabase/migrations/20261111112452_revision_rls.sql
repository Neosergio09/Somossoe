-- =====================================================================
-- Revisión de RLS y privilegios (11-nov-2026)
-- 1. Convenios: cambiar condiciones o documentos de un convenio
--    pendiente anula la verificación de documentación.
-- 2. Siempre debe quedar al menos un usuario de Dirección activo.
-- 3. audit_logs: solo Dirección y Administración / Cartera (RNF-05).
-- 4. Privilegios por defecto: las tablas y funciones nuevas no quedan
--    abiertas a anon / authenticated; cada migración otorga lo necesario.
-- 5. cities y lab_providers: escritura solo en columnas editables.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Convenios: la verificación de Administración cubre exactamente lo
--    que Dirección aprueba
-- ---------------------------------------------------------------------
-- Se ejecuta después de agreements_before_write (orden alfabético)
create function private.agreements_reset_verification()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'pendiente_aprobacion'
     and old.documents_verified
     and new.documents_verified
     and (new.payroll_frequency, new.max_installments, new.payroll_conditions,
          new.hr_approval_required, new.valid_from, new.valid_until, new.deal_id)
         is distinct from
         (old.payroll_frequency, old.max_installments, old.payroll_conditions,
          old.hr_approval_required, old.valid_from, old.valid_until, old.deal_id) then
    new.documents_verified := false;
    new.documents_verified_by := null;
    new.documents_verified_at := null;
  end if;
  return new;
end;
$$;

create trigger agreements_reset_verification
  before update on public.agreements_convenios
  for each row execute function private.agreements_reset_verification();

-- Agregar, cambiar o quitar documentos también anula la verificación
create function private.agreement_documents_reset_verification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.agreements_convenios a
  set documents_verified = false,
      documents_verified_by = null,
      documents_verified_at = null
  where a.id = coalesce(new.agreement_id, old.agreement_id)
    and a.status = 'pendiente_aprobacion'
    and a.documents_verified;
  return null;
end;
$$;

revoke execute on function private.agreement_documents_reset_verification() from public, anon, authenticated;

create trigger agreement_documents_reset_verification
  after insert or update or delete on public.agreement_documents
  for each row execute function private.agreement_documents_reset_verification();

-- ---------------------------------------------------------------------
-- 2. Al menos un usuario de Dirección activo
-- ---------------------------------------------------------------------
create function private.users_profiles_keep_direccion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.role = 'direccion' and old.active
     and (tg_op = 'DELETE' or new.role is distinct from 'direccion' or not new.active) then
    -- Bloquea los perfiles de Dirección para evitar que dos cambios
    -- simultáneos dejen el sistema sin Dirección
    perform 1 from public.users_profiles p
    where p.role = 'direccion' and p.active
    for update;

    if not exists (
      select 1 from public.users_profiles p
      where p.role = 'direccion' and p.active and p.id <> old.id
    ) then
      raise exception 'Debe quedar al menos un usuario de Dirección activo; active a otro antes de este cambio';
    end if;
  end if;
  return coalesce(new, old);
end;
$$;

revoke execute on function private.users_profiles_keep_direccion() from public, anon, authenticated;

create trigger users_profiles_keep_direccion
  before update or delete on public.users_profiles
  for each row execute function private.users_profiles_keep_direccion();

-- ---------------------------------------------------------------------
-- 3. Auditoría: acceso mínimo
-- ---------------------------------------------------------------------
drop policy audit_logs_select on public.audit_logs;
create policy audit_logs_select on public.audit_logs
  for select to authenticated
  using ((select private.has_role('direccion', 'administracion_cartera')));

-- ---------------------------------------------------------------------
-- 4. Privilegios por defecto de los objetos que crean las migraciones
-- ---------------------------------------------------------------------
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated;
alter default privileges for role postgres
  revoke execute on functions from public;

-- ---------------------------------------------------------------------
-- 5. Catálogos: escritura por columna
-- ---------------------------------------------------------------------
revoke insert, update on public.cities, public.lab_providers from authenticated;

grant insert (name, is_operational, active) on public.cities to authenticated;
grant update (name, is_operational, active) on public.cities to authenticated;

grant insert (name, contact_info, active) on public.lab_providers to authenticated;
grant update (name, contact_info, active) on public.lab_providers to authenticated;
