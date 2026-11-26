-- =====================================================================
-- Backlog V0.2 · SOE-17 (SRS 1.6 RF-M04-03): aval de la empresa por orden
-- de nómina, con historial, rechazo y registro por listado.
--
-- * order_company_approvals: cada decisión que comunica la empresa
--   (aprobada | rechazada), con fecha, referencia del listado, soporte y
--   motivo (obligatorio al rechazar). Una decisión equivocada se anula
--   con motivo; nada se borra.
-- * La última decisión vigente deriva en la orden:
--   company_approval_decision / company_approval_on, y las columnas que ya
--   usan los requisitos y el candado (hr_approval_received y su archivo).
--   La app ya no escribe esas columnas directamente.
-- * Registran: Administración (cualquier orden) y el Comercial (las suyas).
-- * Tras un rechazo, la empresa puede aprobar después (nueva decisión).
-- * Un rechazo (o anular la aprobación) sobre una orden verificada y no
--   liberada retira la verificación. Una orden liberada no admite
--   decisiones nuevas.
-- =====================================================================

alter table public.orders
  add column company_approval_decision text check (company_approval_decision in ('aprobada', 'rechazada')),
  add column company_approval_on       date;

create table public.order_company_approvals (
  id           uuid primary key default gen_random_uuid(),
  -- Orden real de registro (now() es constante dentro de una transacción)
  seq          bigint generated always as identity,
  order_id     uuid not null references public.orders (id),
  decision     text not null check (decision in ('aprobada', 'rechazada')),
  decided_on   date not null,
  reference    text check (reference is null or length(trim(reference)) between 1 and 200),
  file_path    text check (file_path is null or length(trim(file_path)) > 0),
  reason       text check (reason is null or length(reason) <= 500),
  batch_id     uuid,
  recorded_by  uuid references public.users_profiles (id),
  recorded_at  timestamptz not null default now(),
  is_voided    boolean not null default false,
  void_reason  text,
  voided_by    uuid references public.users_profiles (id),
  voided_at    timestamptz,
  constraint company_approvals_reason_on_reject
    check (decision <> 'rechazada' or length(trim(coalesce(reason, ''))) > 0),
  constraint company_approvals_void_reason
    check (not is_voided or length(trim(coalesce(void_reason, ''))) > 0)
);

create index company_approvals_order_idx on public.order_company_approvals (order_id, seq desc);
create index company_approvals_batch_idx on public.order_company_approvals (batch_id) where batch_id is not null;
create index company_approvals_recorded_by_idx on public.order_company_approvals (recorded_by);
create index company_approvals_voided_by_idx on public.order_company_approvals (voided_by);

-- Solo lectura para usuarios internos; se escribe con las funciones de abajo
alter table public.order_company_approvals enable row level security;
revoke all on public.order_company_approvals from public, anon, authenticated;
grant select on public.order_company_approvals to authenticated;
create policy company_approvals_select on public.order_company_approvals
  for select to authenticated
  using ((select private.is_internal_user()));

create trigger company_approvals_audit
  after insert or update or delete on public.order_company_approvals
  for each row execute function private.audit_row_change();

-- El soporte debe existir y haberlo subido quien registra (como los demás)
create trigger a_support_files before insert or update on public.order_company_approvals
  for each row execute function private.support_files_guard('ordenes', 'file_path');

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
      or exists (select 1 from public.order_company_approvals x where x.file_path = p_path)
    when 'entregas' then exists (select 1 from public.order_deliveries x where x.evidence_file_path = p_path)
    when 'garantias' then exists (select 1 from public.post_sale_warranties x where x.evidence_file_path = p_path)
    when 'pagos' then exists (select 1 from public.collections_payments x where x.support_file_path = p_path)
    when 'retenciones' then exists (
      select 1 from public.payment_allocations x where x.withholding_certificate_file_path = p_path)
    else false
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION private.support_files_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_kind text := tg_argv[0];
  v_new jsonb := to_jsonb(new);
  v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  v_spec text;
  v_col text;
  v_flag text;
  v_path text;
  v_patch jsonb := '{}'::jsonb;
begin
  for i in 1 .. tg_nargs - 1 loop
    v_spec := tg_argv[i];
    v_col := split_part(v_spec, ':', 1);
    v_flag := nullif(split_part(v_spec, ':', 2), '');
    v_path := v_new ->> v_col;

    if v_path is not null and v_path is distinct from (v_old ->> v_col) then
      if split_part(v_path, '/', 1) <> v_kind then
        raise exception 'El archivo no corresponde a este tipo de soporte';
      end if;
      if not exists (select 1 from storage.objects o where o.bucket_id = 'soportes' and o.name = v_path) then
        raise exception 'El archivo no se encontró; súbalo de nuevo';
      end if;
      -- La sincronización interna del aval (sync_company_approval) puede restaurar
      -- el soporte de una decisión anterior registrada por otra persona
      if (select auth.uid()) is not null and split_part(v_path, '/', 2) <> (select auth.uid())::text
         and coalesce(current_setting('app.company_approval_sync', true), '') <> 'on' then
        raise exception 'Solo se vinculan archivos subidos por el mismo usuario';
      end if;
      if v_flag is not null then
        v_patch := v_patch || jsonb_build_object(v_flag, true);
      end if;
    end if;
  end loop;

  if v_patch <> '{}'::jsonb then
    new := jsonb_populate_record(new, v_patch);
  end if;
  return new;
end;
$function$;

-- ---------------------------------------------------------------------
-- Derivar el aval de la orden desde la última decisión vigente
-- ---------------------------------------------------------------------
create function private.sync_company_approval(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_last public.order_company_approvals;
  v_order public.orders;
begin
  select * into v_order from public.orders o where o.id = p_order_id for update;
  select * into v_last from public.order_company_approvals c
  where c.order_id = p_order_id and not c.is_voided
  order by c.seq desc
  limit 1;

  perform set_config('app.company_approval_sync', 'on', true);
  update public.orders o
  set company_approval_decision = v_last.decision,
      company_approval_on = v_last.decided_on,
      hr_approval_received = coalesce(v_last.decision = 'aprobada', false),
      hr_approval_file_path = case when v_last.decision = 'aprobada' then v_last.file_path end,
      -- Sin aval vigente, una orden verificada (no liberada) pierde la verificación
      requirements_verified = case
        when coalesce(v_last.decision, '') <> 'aprobada' and o.ops_status = 'pendiente_liberar' then false
        else o.requirements_verified end,
      requirements_verified_by = case
        when coalesce(v_last.decision, '') <> 'aprobada' and o.ops_status = 'pendiente_liberar' then null
        else o.requirements_verified_by end,
      requirements_verified_at = case
        when coalesce(v_last.decision, '') <> 'aprobada' and o.ops_status = 'pendiente_liberar' then null
        else o.requirements_verified_at end
  where o.id = p_order_id;
  perform set_config('app.company_approval_sync', 'off', true);
end;
$$;

revoke execute on function private.sync_company_approval(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- La app ya no escribe el aval directamente
-- ---------------------------------------------------------------------
create function private.orders_company_approval_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'authenticated'
     and (new.hr_approval_received, new.hr_approval_file_path, new.company_approval_decision, new.company_approval_on)
         is distinct from
         (old.hr_approval_received, old.hr_approval_file_path, old.company_approval_decision, old.company_approval_on) then
    raise exception 'El aval de la empresa se registra como decisión (aprobada o rechazada) en la orden';
  end if;
  return new;
end;
$$;

revoke execute on function private.orders_company_approval_guard() from public, anon, authenticated;

create trigger orders_company_approval_guard
  before update on public.orders
  for each row execute function private.orders_company_approval_guard();

-- Aval marcado al crear la orden (pantalla Nueva orden): queda como decisión
create function private.orders_company_approval_on_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.hr_approval_received and new.payment_modality = 'nomina_empresa' and not new.is_historical_migration then
    insert into public.order_company_approvals (order_id, decision, decided_on, reference, file_path, recorded_by)
    values (new.id, 'aprobada', private.today_co(), 'Registrado al crear la orden', new.hr_approval_file_path,
            coalesce((select auth.uid()), new.created_by));
  end if;
  return null;
end;
$$;

revoke execute on function private.orders_company_approval_on_insert() from public, anon, authenticated;

create trigger orders_company_approval_on_insert
  after insert on public.orders
  for each row execute function private.orders_company_approval_on_insert();

-- ---------------------------------------------------------------------
-- Registrar una decisión para una o varias órdenes (aval por listado)
-- ---------------------------------------------------------------------
create function public.record_company_approval(
  p_order_ids  uuid[],
  p_decision   text,
  p_decided_on date,
  p_reference  text default null,
  p_file_path  text default null,
  p_reason     text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_is_admin boolean := private.has_role('administracion_cartera');
  v_batch uuid := gen_random_uuid();
  v_order record;
  v_files boolean := private.get_setting('require_document_files') = 1;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_reference text := nullif(trim(coalesce(p_reference, '')), '');
begin
  if not (v_is_admin or private.has_role('comercial')) then
    raise exception 'Solo Administración o Comercial registran el aval de la empresa' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_order_ids), 0) = 0 then
    raise exception 'Seleccione al menos una orden';
  end if;
  if p_decision not in ('aprobada', 'rechazada') then
    raise exception 'Decisión no válida';
  end if;
  if p_decided_on is null or p_decided_on > private.today_co() then
    raise exception 'Indique la fecha en que la empresa comunicó la decisión (no futura)';
  end if;
  if p_decision = 'rechazada' and v_reason is null then
    raise exception 'Indique el motivo del rechazo';
  end if;
  if p_decision = 'aprobada' and v_files and p_file_path is null then
    raise exception 'Adjunte el soporte del aval (listado o comunicación de la empresa)';
  end if;

  for v_order in
    select o.id, o.order_number, o.created_by, o.payment_modality, o.is_cancelled, o.is_historical_migration,
           o.ops_status, o.company_approval_decision, a.hr_approval_required
    from public.orders o
    left join public.agreements_convenios a on a.id = o.agreement_id
    where o.id = any (p_order_ids)
    order by o.order_number
    for update of o
  loop
    if not v_is_admin and v_order.created_by is distinct from v_uid then
      raise exception 'La orden #% la registró otro Comercial', lpad(v_order.order_number::text, 5, '0')
        using errcode = '42501';
    end if;
    if v_order.is_cancelled then
      raise exception 'La orden #% está anulada', lpad(v_order.order_number::text, 5, '0');
    end if;
    if v_order.payment_modality <> 'nomina_empresa' or v_order.is_historical_migration
       or not coalesce(v_order.hr_approval_required, true) then
      raise exception 'La orden #% no requiere aval de la empresa', lpad(v_order.order_number::text, 5, '0');
    end if;
    if v_order.ops_status <> 'pendiente_liberar' then
      raise exception 'La orden #% ya fue liberada a producción', lpad(v_order.order_number::text, 5, '0');
    end if;
    if v_order.company_approval_decision is not distinct from p_decision then
      raise exception 'La orden #% ya está %', lpad(v_order.order_number::text, 5, '0'), p_decision;
    end if;

    insert into public.order_company_approvals (order_id, decision, decided_on, reference, file_path, reason, batch_id, recorded_by)
    values (v_order.id, p_decision, p_decided_on, v_reference, p_file_path, v_reason,
            case when cardinality(p_order_ids) > 1 then v_batch end, v_uid);
    perform private.sync_company_approval(v_order.id);
  end loop;

  if not found then
    raise exception 'No se encontraron las órdenes seleccionadas';
  end if;
  return v_batch;
end;
$$;

-- ---------------------------------------------------------------------
-- Anular una decisión registrada por error (la última vigente)
-- ---------------------------------------------------------------------
create function public.void_company_approval(p_approval_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.order_company_approvals;
  v_ops public.order_ops_status;
begin
  select * into v_row from public.order_company_approvals c where c.id = p_approval_id for update;
  if v_row.id is null or v_row.is_voided then
    raise exception 'La decisión no existe o ya está anulada';
  end if;
  if not (private.has_role('administracion_cartera') or v_row.recorded_by = (select auth.uid())) then
    raise exception 'Solo Administración o quien la registró anulan la decisión' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'Indique el motivo de la anulación';
  end if;
  if exists (
    select 1 from public.order_company_approvals c
    where c.order_id = v_row.order_id and not c.is_voided and c.seq > v_row.seq
  ) then
    raise exception 'Solo se anula la última decisión vigente';
  end if;
  select o.ops_status into v_ops from public.orders o where o.id = v_row.order_id;
  if v_ops <> 'pendiente_liberar' then
    raise exception 'La orden ya fue liberada a producción';
  end if;

  update public.order_company_approvals
  set is_voided = true, void_reason = trim(p_reason), voided_by = (select auth.uid()), voided_at = now()
  where id = p_approval_id;
  perform private.sync_company_approval(v_row.order_id);
end;
$$;

revoke execute on function public.record_company_approval(uuid[], text, date, text, text, text),
  public.void_company_approval(uuid, text) from public, anon;
grant execute on function public.record_company_approval(uuid[], text, date, text, text, text),
  public.void_company_approval(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- Vista de órdenes: decisión de la empresa al final
-- ---------------------------------------------------------------------
create or replace view public.v_orders
with (security_invoker = true)
as
SELECT o.id,
    o.order_number,
    o.campaign_id,
    j.deal_id,
    d.deal_name_branch,
    j.status AS campaign_status,
    o.company_id,
    c.name AS company_name,
    o.branch_id,
    br.name AS branch_name,
    o.city_id,
    ci.name AS city_name,
    o.agreement_id,
    o.buyer_id,
    b.full_name AS buyer_name,
    b.document_type AS buyer_document_type,
    b.document_id AS buyer_document_id,
    o.total_amount,
    o.balance_due,
    o.payment_modality,
    o.collection_responsible,
    o.installments_count,
    o.installment_periodicity,
    o.first_due_date,
    o.employee_auth_received,
    o.hr_approval_received,
    a.hr_approval_required,
    o.prepayment_exception_reason,
    o.prepayment_exception_by,
    o.prepayment_exception_at,
    o.requirements_verified,
    o.requirements_verified_by,
    o.requirements_verified_at,
    o.doc_status,
    o.ops_status,
    o.accounting_status,
    o.collection_status,
    o.is_cancelled,
    o.cancelled_by,
    o.cancelled_at,
    o.cancel_reason,
    o.notes,
    ( SELECT count(*) AS count
           FROM order_items i
          WHERE i.order_id = o.id) AS items_count,
    private.order_missing_requirements(o.*) AS missing_requirements,
    o.created_by,
    u.full_name AS created_by_name,
    o.created_at,
    o.updated_at,
    private.order_release_blockers(o.*) AS release_blockers,
    o.is_historical_migration,
    o.historical_stage,
    o.historical_collected_before_migration,
    o.historical_reference,
    o.historical_delivered_at,
    o.historical_delivery_receiver,
    o.employee_auth_file_path,
    o.hr_approval_file_path,
    o.company_approval_decision,
    o.company_approval_on
   FROM orders o
     JOIN buyers b ON b.id = o.buyer_id
     LEFT JOIN companies c ON c.id = o.company_id
     LEFT JOIN company_branches br ON br.id = o.branch_id
     LEFT JOIN cities ci ON ci.id = o.city_id
     LEFT JOIN campaigns_jornadas j ON j.id = o.campaign_id
     LEFT JOIN deals_opportunities d ON d.id = j.deal_id
     LEFT JOIN agreements_convenios a ON a.id = o.agreement_id
     LEFT JOIN users_profiles u ON u.id = o.created_by;

-- ---------------------------------------------------------------------
-- Datos existentes: el aval ya recibido pasa a ser una decisión aprobada
-- ---------------------------------------------------------------------
insert into public.order_company_approvals (order_id, decision, decided_on, reference, file_path, recorded_by, recorded_at)
select o.id, 'aprobada', (o.created_at at time zone 'America/Bogota')::date, 'Registro anterior al historial de avales',
       o.hr_approval_file_path, o.created_by, o.created_at
from public.orders o
where o.hr_approval_received and o.payment_modality = 'nomina_empresa';

update public.orders o
set company_approval_decision = 'aprobada',
    company_approval_on = (o.created_at at time zone 'America/Bogota')::date
where o.hr_approval_received and o.payment_modality = 'nomina_empresa';

-- ---------------------------------------------------------------------
-- Resumen del circuito: órdenes esperando aval y rechazadas
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
      -- Ventas de nómina que esperan la decisión de la empresa (SOE-17)
      'sin_aval', (select count(*) from public.orders o
                   join public.agreements_convenios a on a.id = o.agreement_id
                   where not o.is_cancelled and not o.is_historical_migration
                     and o.payment_modality = 'nomina_empresa' and a.hr_approval_required
                     and o.ops_status = 'pendiente_liberar' and o.company_approval_decision is null),
      'aval_rechazado', (select count(*) from public.orders o
                         where not o.is_cancelled and o.ops_status = 'pendiente_liberar'
                           and o.company_approval_decision = 'rechazada'),
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
