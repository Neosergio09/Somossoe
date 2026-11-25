-- =====================================================================
-- Super administrador (24-nov-2026)
--
-- * private.has_role(...) es verdadero para 'superadmin' con cualquier
--   rol pedido: pasa todas las políticas RLS y las guardas de triggers.
-- * Las funciones de propiedad comercial (owns_*) también lo aceptan,
--   así edita empresas, oportunidades, convenios y órdenes de cualquier
--   ejecutivo.
-- * Puede ser el ejecutivo asignado de una oportunidad.
-- * La guarda "Dirección solo cancela jornadas" se aplica solo a quien
--   tiene el rol Dirección, no al superadmin.
-- Las reglas de negocio (estados, montos, segregación de funciones)
-- siguen aplicando igual.
-- =====================================================================

create function private.is_superadmin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.current_app_role() = 'superadmin', false);
$$;

revoke execute on function private.is_superadmin() from public, anon;
grant execute on function private.is_superadmin() to authenticated;

create or replace function private.has_role(variadic roles public.app_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    private.current_app_role() = 'superadmin'
      or private.current_app_role() = any (roles),
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
  select private.is_superadmin() or exists (
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
  select private.is_superadmin() or exists (
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
  select private.is_superadmin() or exists (
    select 1 from public.orders o
    where o.id = p_order_id and o.created_by = (select auth.uid())
  );
$$;
-- owns_agreement delega en owns_company: no cambia.

-- ---------------------------------------------------------------------
-- Oportunidades: el superadmin puede ser el ejecutivo asignado
-- ---------------------------------------------------------------------
create or replace function private.deals_before_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
         where p.id = new.assigned_user_id and p.active and p.role in ('comercial', 'direccion', 'superadmin')
       ) then
      raise exception 'El ejecutivo asignado debe ser un usuario activo de Comercial, Dirección o Super administrador';
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
$function$

;

-- ---------------------------------------------------------------------
-- Jornadas: la restricción de Dirección no aplica al superadmin
-- ---------------------------------------------------------------------
create or replace function private.campaigns_cancel_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'authenticated' then
    return new;
  end if;

  if new.status = 'cancelada' and old.status is distinct from 'cancelada'
     and not private.has_role('operacion', 'direccion') then
    raise exception 'Solo Operación o Dirección cancelan jornadas' using errcode = '42501';
  end if;

  if private.current_app_role() = 'direccion'
     and (new.branch_id, new.city_id, new.responsible_user_id, new.logistics_confirmed, new.notes,
          new.checklist_staff, new.checklist_equipment, new.checklist_materials, new.checklist_notice,
          new.status is distinct from old.status and new.status <> 'cancelada')
         is distinct from
         (old.branch_id, old.city_id, old.responsible_user_id, old.logistics_confirmed, old.notes,
          old.checklist_staff, old.checklist_equipment, old.checklist_materials, old.checklist_notice, false) then
    raise exception 'Dirección solo puede cancelar la jornada' using errcode = '42501';
  end if;

  return new;
end;
$function$

;
