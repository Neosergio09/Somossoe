-- =====================================================================
-- SRS 1.6 · §3.3: roles adicionales por usuario y rol 'costos'
--
-- * users_profiles.extra_roles: roles que se suman al rol principal. Los
--   permisos son la UNIÓN de todos los roles (private.has_role). No se
--   admiten como adicionales Dirección, Socio, Super administrador ni
--   Laboratorio (la regla «al menos una Dirección activa» sigue mirando el
--   rol principal).
-- * Perfiles visibles (solo interfaz): Comercial = comercial;
--   Gestión = operacion + administracion_cartera + costos.
-- * Rol 'costos' (auxiliar contable): registra, corrige y anula costos y
--   los consulta junto con Dirección y Socio (RF-M04-06).
-- * is_superadmin() sigue mirando solo el rol principal.
-- =====================================================================

alter table public.users_profiles
  add column extra_roles public.app_role[] not null default '{}',
  add constraint users_profiles_extra_roles_allowed
    check (not (extra_roles && array['direccion', 'socio', 'superadmin', 'proveedor_lab']::public.app_role[])),
  add constraint users_profiles_extra_roles_need_role
    check (role is not null or cardinality(extra_roles) = 0),
  add constraint users_profiles_extra_roles_not_main
    check (role is null or not (role = any (extra_roles)));

grant update (extra_roles) on public.users_profiles to authenticated;

-- Sin repetidos y en orden estable
create function private.users_profiles_normalize_roles()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.extra_roles := coalesce(
    (select array_agg(distinct r order by r) from unnest(new.extra_roles) r),
    '{}'::public.app_role[]);
  return new;
end;
$$;

revoke execute on function private.users_profiles_normalize_roles() from public, anon, authenticated;

create trigger users_profiles_normalize_roles
  before insert or update of extra_roles on public.users_profiles
  for each row execute function private.users_profiles_normalize_roles();

-- ---------------------------------------------------------------------
-- Roles del usuario actual y comprobación por unión
-- ---------------------------------------------------------------------
create function private.current_app_roles()
returns public.app_role[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select array[p.role] || p.extra_roles
    from public.users_profiles p
    where p.id = (select auth.uid()) and p.active and p.role is not null
  ), '{}'::public.app_role[]);
$$;

revoke execute on function private.current_app_roles() from public, anon;
grant execute on function private.current_app_roles() to authenticated;

create or replace function private.has_role(variadic roles public.app_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    private.current_app_role() = 'superadmin'
      or private.current_app_roles() && roles,
    false);
$$;

-- Un usuario con solo el rol Costos también es interno
create or replace function private.is_internal_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_role('comercial', 'operacion', 'administracion_cartera', 'direccion', 'socio', 'costos');
$$;

-- ---------------------------------------------------------------------
-- Costos: Dirección, Socio y Costos consultan; Dirección y Costos registran
-- ---------------------------------------------------------------------
create or replace function private.can_view_costs()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_role('direccion', 'socio', 'costos');
$$;

drop policy order_costs_insert on public.order_costs;
create policy order_costs_insert on public.order_costs
  for insert to authenticated
  with check ((select private.has_role('direccion', 'costos')));
drop policy order_costs_update on public.order_costs;
create policy order_costs_update on public.order_costs
  for update to authenticated
  using ((select private.has_role('direccion', 'costos')))
  with check ((select private.has_role('direccion', 'costos')));

-- ---------------------------------------------------------------------
-- Jornadas: Dirección que además tiene rol de Operación gestiona la jornada
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.campaigns_cancel_guard()
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

  -- Dirección sin rol de Operación solo cancela (SRS §3.2)
  if private.current_app_role() = 'direccion'
     and not ('operacion' = any (private.current_app_roles()))
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
$function$;

-- ---------------------------------------------------------------------
-- Resumen del circuito: órdenes con costos incompletos (rol Costos)
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
    -- Órdenes no anuladas a las que les faltan costos (solo cuenta para
    -- quien ve costos: v_order_margins no devuelve filas a los demás)
    'costos_incompletos', (select count(*) from public.v_order_margins m
                           where not m.is_cancelled and not m.costs_complete),
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
