-- =====================================================================
-- Propiedad comercial y cancelación de jornadas (11-nov-2026)
--
-- Cada Comercial edita solo lo suyo:
-- * Empresa (y sus sedes, contactos y convenios): la del ejecutivo
--   asignado. Una empresa sin ejecutivo la edita cualquier Comercial,
--   que puede asignársela.
-- * Oportunidad (y su bitácora): la del ejecutivo asignado.
-- * Orden (y sus ítems): la de quien la registró.
-- La lectura sigue abierta a todos los usuarios internos. Administración,
-- Dirección y Operación conservan sus permisos. En jornadas, cualquier
-- Comercial sigue apoyando sesiones y asistencia.
--
-- Cancelar jornadas: solo Operación y Dirección (Dirección no modifica
-- nada más de la jornada).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Funciones de propiedad (SECURITY DEFINER: se usan dentro de políticas)
-- ---------------------------------------------------------------------
create function private.owns_company(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.companies c
    where c.id = p_company_id
      and (c.assigned_user_id is null or c.assigned_user_id = (select auth.uid()))
  );
$$;

create function private.owns_deal(p_deal_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.deals_opportunities d
    where d.id = p_deal_id and d.assigned_user_id = (select auth.uid())
  );
$$;

create function private.owns_agreement(p_agreement_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.agreements_convenios a
    where a.id = p_agreement_id and private.owns_company(a.company_id)
  );
$$;

create function private.owns_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.orders o
    where o.id = p_order_id and o.created_by = (select auth.uid())
  );
$$;

revoke execute on function private.owns_company(uuid), private.owns_deal(uuid),
  private.owns_agreement(uuid), private.owns_order(uuid) from public, anon;
grant execute on function private.owns_company(uuid), private.owns_deal(uuid),
  private.owns_agreement(uuid), private.owns_order(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Empresas, sedes y contactos
-- ---------------------------------------------------------------------
drop policy companies_insert on public.companies;
create policy companies_insert on public.companies
  for insert to authenticated
  with check (
    (select private.has_role('comercial'))
    and (assigned_user_id is null or assigned_user_id = (select auth.uid()))
  );

drop policy companies_update on public.companies;
create policy companies_update on public.companies
  for update to authenticated
  using (
    (select private.has_role('administracion_cartera'))
    or ((select private.has_role('comercial'))
        and (assigned_user_id is null or assigned_user_id = (select auth.uid())))
  )
  with check (
    (select private.has_role('administracion_cartera'))
    or ((select private.has_role('comercial'))
        and (assigned_user_id is null or assigned_user_id = (select auth.uid())))
  );

drop policy company_branches_insert on public.company_branches;
create policy company_branches_insert on public.company_branches
  for insert to authenticated
  with check ((select private.has_role('comercial')) and private.owns_company(company_id));

drop policy company_branches_update on public.company_branches;
create policy company_branches_update on public.company_branches
  for update to authenticated
  using (
    (select private.has_role('administracion_cartera'))
    or ((select private.has_role('comercial')) and private.owns_company(company_id))
  )
  with check (
    (select private.has_role('administracion_cartera'))
    or ((select private.has_role('comercial')) and private.owns_company(company_id))
  );

drop policy contacts_insert on public.contacts;
create policy contacts_insert on public.contacts
  for insert to authenticated
  with check ((select private.has_role('comercial')) and private.owns_company(company_id));

drop policy contacts_update on public.contacts;
create policy contacts_update on public.contacts
  for update to authenticated
  using (
    (select private.has_role('administracion_cartera'))
    or ((select private.has_role('comercial')) and private.owns_company(company_id))
  )
  with check (
    (select private.has_role('administracion_cartera'))
    or ((select private.has_role('comercial')) and private.owns_company(company_id))
  );

-- ---------------------------------------------------------------------
-- Oportunidades y bitácora. Dirección reasigna oportunidades.
-- ---------------------------------------------------------------------
drop policy deals_insert on public.deals_opportunities;
create policy deals_insert on public.deals_opportunities
  for insert to authenticated
  with check (
    (select private.has_role('comercial'))
    and assigned_user_id = (select auth.uid())
    and private.owns_company(company_id)
  );

drop policy deals_update on public.deals_opportunities;
create policy deals_update on public.deals_opportunities
  for update to authenticated
  using (
    (select private.has_role('direccion'))
    or ((select private.has_role('comercial')) and assigned_user_id = (select auth.uid()))
  )
  with check (
    (select private.has_role('direccion'))
    or ((select private.has_role('comercial')) and assigned_user_id = (select auth.uid()))
  );

drop policy deal_logs_insert on public.deal_interaction_logs;
create policy deal_logs_insert on public.deal_interaction_logs
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (
      (select private.has_role('direccion'))
      or ((select private.has_role('comercial')) and private.owns_deal(deal_id))
    )
  );

-- ---------------------------------------------------------------------
-- Convenios y sus documentos: los de las empresas del Comercial
-- ---------------------------------------------------------------------
drop policy agreements_insert on public.agreements_convenios;
create policy agreements_insert on public.agreements_convenios
  for insert to authenticated
  with check ((select private.has_role('comercial')) and private.owns_company(company_id));

drop policy agreements_update on public.agreements_convenios;
create policy agreements_update on public.agreements_convenios
  for update to authenticated
  using (
    (select private.has_role('administracion_cartera', 'direccion'))
    or ((select private.has_role('comercial')) and private.owns_company(company_id))
  )
  with check (
    (select private.has_role('administracion_cartera', 'direccion'))
    or ((select private.has_role('comercial')) and private.owns_company(company_id))
  );

drop policy agreement_documents_insert on public.agreement_documents;
create policy agreement_documents_insert on public.agreement_documents
  for insert to authenticated
  with check (
    (select private.has_role('administracion_cartera'))
    or ((select private.has_role('comercial')) and private.owns_agreement(agreement_id))
  );

drop policy agreement_documents_update on public.agreement_documents;
create policy agreement_documents_update on public.agreement_documents
  for update to authenticated
  using (
    (select private.has_role('administracion_cartera'))
    or ((select private.has_role('comercial')) and private.owns_agreement(agreement_id))
  )
  with check (
    (select private.has_role('administracion_cartera'))
    or ((select private.has_role('comercial')) and private.owns_agreement(agreement_id))
  );

drop policy agreement_documents_delete on public.agreement_documents;
create policy agreement_documents_delete on public.agreement_documents
  for delete to authenticated
  using (
    (select private.has_role('administracion_cartera'))
    or ((select private.has_role('comercial')) and private.owns_agreement(agreement_id))
  );

-- ---------------------------------------------------------------------
-- Órdenes e ítems: las que registró el Comercial
-- ---------------------------------------------------------------------
drop policy orders_update on public.orders;
create policy orders_update on public.orders
  for update to authenticated
  using (
    (select private.has_role('administracion_cartera', 'direccion'))
    or ((select private.has_role('comercial')) and created_by = (select auth.uid()))
  )
  with check (
    (select private.has_role('administracion_cartera', 'direccion'))
    or ((select private.has_role('comercial')) and created_by = (select auth.uid()))
  );

drop policy order_items_insert on public.order_items;
create policy order_items_insert on public.order_items
  for insert to authenticated
  with check (
    (select private.has_role('administracion_cartera'))
    or ((select private.has_role('comercial')) and private.owns_order(order_id))
  );

drop policy order_items_update on public.order_items;
create policy order_items_update on public.order_items
  for update to authenticated
  using (
    (select private.has_role('administracion_cartera'))
    or ((select private.has_role('comercial')) and private.owns_order(order_id))
  )
  with check (
    (select private.has_role('administracion_cartera'))
    or ((select private.has_role('comercial')) and private.owns_order(order_id))
  );

drop policy order_items_delete on public.order_items;
create policy order_items_delete on public.order_items
  for delete to authenticated
  using (
    (select private.has_role('administracion_cartera'))
    or ((select private.has_role('comercial')) and private.owns_order(order_id))
  );

-- ---------------------------------------------------------------------
-- Jornadas: cancelan Operación y Dirección
-- ---------------------------------------------------------------------
drop policy campaigns_update on public.campaigns_jornadas;
create policy campaigns_update on public.campaigns_jornadas
  for update to authenticated
  using ((select private.has_role('operacion', 'comercial', 'direccion')))
  with check ((select private.has_role('operacion', 'comercial', 'direccion')));

create function private.campaigns_cancel_guard()
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

  -- Dirección solo cancela: el resto de la jornada lo gestiona Operación
  if private.has_role('direccion')
     and (new.branch_id, new.city_id, new.responsible_user_id, new.logistics_confirmed, new.notes,
          new.status is distinct from old.status and new.status <> 'cancelada')
         is distinct from
         (old.branch_id, old.city_id, old.responsible_user_id, old.logistics_confirmed, old.notes, false) then
    raise exception 'Dirección solo puede cancelar la jornada' using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger campaigns_cancel_guard
  before update on public.campaigns_jornadas
  for each row execute function private.campaigns_cancel_guard();
