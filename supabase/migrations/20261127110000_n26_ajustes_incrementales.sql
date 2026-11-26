-- =====================================================================
-- Paquete incremental N26 (CRM_SOE_Paquete_Incremental V0.3, 26/11/2026)
--
-- N26-02/03  Sede sin nombre obligatorio: basta ciudad + dirección; el
--            nombre se arma solo («Pereira · Cra 7 # 20-15»).
-- N26-02/11  Catálogos buscables editables por SOE (sectores, tipos de lente).
-- N26-05     Orígenes: Referido, Outbound, Evento, Inbound, Otro. «Cliente
--            recurrente» queda inactivo (los históricos lo conservan).
--            Nota de excepción cuando la nómina difiere de la empresa.
-- N26-06     Bitácora: «ocurrió el» (lo elige quien registra, no futuro)
--            separado de «registrado el» (created_at). Sigue sin edición.
-- N26-07     Propuestas comerciales por oportunidad (versiones, sin borrar).
--            Pasar a Propuesta enviada o más allá exige una propuesta con
--            archivo o una justificación escrita.
-- N26-13     v_orders: tipos de lente y laboratorio.
-- N26-15     v_warranties: teléfono, días abiertos, plazo prometido,
--            laboratorio y atraso.
-- =====================================================================

-- ---------------------------------------------------------------------
-- N26-02/03 · Sedes: nombre opcional
-- ---------------------------------------------------------------------
alter table public.company_branches
  add column name_auto boolean not null default false,
  alter column name set default ''; -- vacío = el trigger arma el nombre

create function private.company_branches_auto_name()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_city text;
begin
  if tg_op = 'UPDATE' and new.name_auto and new.name is not distinct from old.name then
    new.name := null; -- nombre automático: se recalcula con la ciudad/dirección nuevas
  end if;

  if nullif(trim(new.name), '') is null then
    if nullif(trim(new.address), '') is null then
      raise exception 'Indique la dirección de la sede (o un nombre que la identifique)';
    end if;
    select coalesce(c.name, new.city_other) into v_city
    from (select 1) one
    left join public.cities c on c.id = new.city_id;
    v_city := coalesce(v_city, new.city_other, 'Sede');
    new.name := v_city || ' · ' || trim(new.address);
    new.name_auto := true;
  else
    new.name := trim(new.name);
    new.name_auto := false;
  end if;
  return new;
end;
$$;

revoke execute on function private.company_branches_auto_name() from public, anon, authenticated;

-- «0_» para correr antes que los demás BEFORE (orden alfabético) y que el
-- NOT NULL del nombre se cumpla
create trigger "0_company_branches_auto_name"
  before insert or update on public.company_branches
  for each row execute function private.company_branches_auto_name();

-- ---------------------------------------------------------------------
-- N26-02 / N26-11 · Catálogos buscables (lista la entrega SOE: C01, C03)
-- ---------------------------------------------------------------------
create table public.catalog_items (
  id         uuid primary key default gen_random_uuid(),
  kind       text not null check (kind in ('sector', 'tipo_lente')),
  name       text not null check (length(trim(name)) between 1 and 150),
  active     boolean not null default true,
  created_by uuid default auth.uid() references public.users_profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index catalog_items_kind_name_key on public.catalog_items (kind, lower(name));
create index catalog_items_created_by_idx on public.catalog_items (created_by);

create trigger catalog_items_set_updated_at
  before update on public.catalog_items
  for each row execute function private.set_updated_at();
create trigger catalog_items_audit
  after insert or update or delete on public.catalog_items
  for each row execute function private.audit_row_change();

alter table public.catalog_items enable row level security;

create policy catalog_items_select on public.catalog_items
  for select to authenticated
  using ((select private.is_internal_user()));
create policy catalog_items_insert on public.catalog_items
  for insert to authenticated
  with check ((select private.has_role('direccion', 'administracion_cartera', 'costos')));
create policy catalog_items_update on public.catalog_items
  for update to authenticated
  using ((select private.has_role('direccion', 'administracion_cartera', 'costos')))
  with check ((select private.has_role('direccion', 'administracion_cartera', 'costos')));

grant select on public.catalog_items to authenticated;
grant insert (kind, name, active) on public.catalog_items to authenticated;
grant update (name, active) on public.catalog_items to authenticated;

-- ---------------------------------------------------------------------
-- N26-05 · Orígenes y excepción de nómina
-- ---------------------------------------------------------------------
update public.deal_origins set label = 'Outbound' where code = 'llamada_saliente';
update public.deal_origins set label = 'Inbound' where code = 'inbound_web';
update public.deal_origins set active = false where code = 'cliente_recurrente';

alter table public.deals_opportunities
  add column payroll_frequency_note text
    check (payroll_frequency_note is null or length(trim(payroll_frequency_note)) between 1 and 300);

grant insert (payroll_frequency_note) on public.deals_opportunities to authenticated;
grant update (payroll_frequency_note) on public.deals_opportunities to authenticated;

-- ---------------------------------------------------------------------
-- N26-06 · Fecha real de la interacción
-- ---------------------------------------------------------------------
alter table public.deal_interaction_logs add column occurred_at timestamptz;
update public.deal_interaction_logs set occurred_at = created_at;
alter table public.deal_interaction_logs
  alter column occurred_at set default now(),
  alter column occurred_at set not null,
  add constraint deal_interaction_logs_not_future
    check (occurred_at <= created_at + interval '5 minutes');

create index deal_interaction_logs_deal_occurred_idx
  on public.deal_interaction_logs (deal_id, occurred_at desc);

grant insert (occurred_at) on public.deal_interaction_logs to authenticated;

-- La tarjeta y el contador de inactividad usan la fecha real
create or replace function private.deal_logs_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.deals_opportunities d
  set last_interaction_type = new.interaction_type,
      last_interaction_note = new.interaction_note,
      last_interaction_at = new.occurred_at
  where d.id = new.deal_id
    and (d.last_interaction_at is null or d.last_interaction_at <= new.occurred_at);
  return null;
end;
$$;

-- ---------------------------------------------------------------------
-- N26-07 · Propuestas comerciales
-- ---------------------------------------------------------------------
create table public.deal_proposals (
  id             uuid primary key default gen_random_uuid(),
  deal_id        uuid not null references public.deals_opportunities (id),
  version        int not null default 0, -- lo asigna el trigger
  document_name  text not null check (length(trim(document_name)) between 1 and 200),
  file_path      text,
  no_file_reason text check (no_file_reason is null or length(trim(no_file_reason)) between 5 and 500),
  sent_on        date not null default ((now() at time zone 'America/Bogota')::date),
  uploaded_by    uuid not null default auth.uid() references public.users_profiles (id),
  created_at     timestamptz not null default now(),
  constraint deal_proposals_file_or_reason check (num_nonnulls(file_path, no_file_reason) = 1),
  constraint deal_proposals_version_key unique (deal_id, version)
);

create index deal_proposals_uploaded_by_idx on public.deal_proposals (uploaded_by);

create function private.deal_proposals_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.sent_on > (now() at time zone 'America/Bogota')::date then
    raise exception 'La fecha de envío de la propuesta no puede ser futura';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('deal_proposals:' || new.deal_id::text, 0));
  select coalesce(max(p.version), 0) + 1 into new.version
  from public.deal_proposals p where p.deal_id = new.deal_id;
  new.created_at := now();
  return new;
end;
$$;

revoke execute on function private.deal_proposals_before_insert() from public, anon, authenticated;

create trigger deal_proposals_before_insert
  before insert on public.deal_proposals
  for each row execute function private.deal_proposals_before_insert();
create trigger a_support_files before insert on public.deal_proposals
  for each row execute function private.support_files_guard('propuestas', 'file_path');
create trigger deal_proposals_audit
  after insert or update or delete on public.deal_proposals
  for each row execute function private.audit_row_change();

alter table public.deal_proposals enable row level security;

create policy deal_proposals_select on public.deal_proposals
  for select to authenticated
  using ((select private.is_internal_user()));
create policy deal_proposals_insert on public.deal_proposals
  for insert to authenticated
  with check (
    uploaded_by = (select auth.uid())
    and (
      (select private.has_role('direccion'))
      or ((select private.has_role('comercial')) and private.owns_deal(deal_id))
    )
  );

-- Sin UPDATE ni DELETE: una versión nueva no borra la anterior
grant select on public.deal_proposals to authenticated;
grant insert (deal_id, document_name, file_path, no_file_reason, sent_on)
  on public.deal_proposals to authenticated;

-- Storage: tipo de soporte «propuestas»
create or replace function private.can_upload_support(p_kind text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_kind
    when 'convenios'   then private.has_role('comercial', 'administracion_cartera')
    when 'compradores' then private.has_role('comercial', 'administracion_cartera')
    when 'ordenes'     then private.has_role('comercial', 'administracion_cartera')
    when 'entregas'    then private.has_role('operacion')
    when 'garantias'   then private.has_role('operacion', 'direccion')
    when 'pagos'       then private.has_role('administracion_cartera')
    when 'retenciones' then private.has_role('administracion_cartera')
    when 'propuestas'  then private.has_role('comercial', 'direccion')
    else false
  end;
$$;

create or replace function private.support_visible(p_path text)
 returns boolean
 language plpgsql
 stable
 set search_path to ''
as $function$
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
    when 'propuestas' then exists (select 1 from public.deal_proposals x where x.file_path = p_path)
    else false
  end;
end;
$function$;

-- ---------------------------------------------------------------------
-- Reglas del embudo: origen activo (N26-05) y propuesta (N26-07)
-- ---------------------------------------------------------------------
create or replace function private.deals_before_write()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
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
      -- N26-07: al llegar a Propuesta enviada (o saltarla) debe haber propuesta
      if new.stage in ('propuesta_enviada', 'negociacion', 'convenio_firmado')
         and old.stage in ('prospecto', 'reunion_exploratoria', 'cierre_perdido')
         and not exists (select 1 from public.deal_proposals p where p.deal_id = new.id) then
        raise exception 'Para pasar a % registre la propuesta comercial: adjunte el archivo o justifique por qué no lo hay',
          case new.stage when 'propuesta_enviada' then 'Propuesta Enviada'
                         when 'negociacion' then 'Negociación' else 'Convenio Firmado' end;
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
    -- N26-05: un origen retirado no se asigna, pero los históricos lo conservan
    if (tg_op = 'INSERT' or new.origin_code is distinct from old.origin_code)
       and not exists (select 1 from public.deal_origins o where o.code = new.origin_code and o.active) then
      raise exception 'El origen elegido ya no está disponible; elija Referido, Outbound, Evento, Inbound u Otro';
    end if;

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
$function$;

-- ---------------------------------------------------------------------
-- N26-13 / N26-15 · Vistas (columnas nuevas al final)
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
    o.company_approval_on,
    ( SELECT string_agg(DISTINCT i.lens_type, ' · ' ORDER BY i.lens_type)
           FROM order_items i
          WHERE i.order_id = o.id AND i.lens_type IS NOT NULL) AS lens_types,
    lab.lab_provider_id,
    lab.lab_name
   FROM orders o
     JOIN buyers b ON b.id = o.buyer_id
     LEFT JOIN companies c ON c.id = o.company_id
     LEFT JOIN company_branches br ON br.id = o.branch_id
     LEFT JOIN cities ci ON ci.id = o.city_id
     LEFT JOIN campaigns_jornadas j ON j.id = o.campaign_id
     LEFT JOIN deals_opportunities d ON d.id = j.deal_id
     LEFT JOIN agreements_convenios a ON a.id = o.agreement_id
     LEFT JOIN users_profiles u ON u.id = o.created_by
     LEFT JOIN LATERAL ( SELECT lp.id AS lab_provider_id, lp.name AS lab_name
           FROM lab_providers lp
          WHERE lp.id = COALESCE(( SELECT pr.lab_provider_id
                   FROM order_productions pr
                  WHERE pr.order_id = o.id AND pr.warranty_id IS NULL AND pr.status <> 'cancelada'::production_status
                  ORDER BY pr.released_at DESC
                 LIMIT 1), o.planned_lab_provider_id)) lab ON true;

create or replace view public.v_warranties
with (security_invoker = true)
as
 SELECT w.id,
    w.order_id,
    o.order_number,
    w.incident_type,
    w.description,
    w.status,
    w.resolution,
    w.evidence_received,
    w.responsible_user_id,
    r.full_name AS responsible_name,
    w.opened_by,
    ob.full_name AS opened_by_name,
    w.created_at,
    w.closed_by,
    cb.full_name AS closed_by_name,
    w.closed_at,
    b.full_name AS buyer_name,
    b.document_id AS buyer_document_id,
    c.name AS company_name,
    w.updated_at,
    w.credit_note_status,
    w.credit_note_lab_provider_id,
    cl.name AS credit_note_lab_name,
    w.credit_note_amount,
    w.credit_note_reference,
    w.credit_note_updated_at,
    b.phone AS buyer_phone,
    o.company_id,
    wp.promised_date,
    wp.ready_at AS production_ready_at,
    wl.id AS lab_provider_id,
    wl.name AS lab_name,
    (COALESCE(w.closed_at, now()) AT TIME ZONE 'America/Bogota')::date - (w.created_at AT TIME ZONE 'America/Bogota')::date AS days_open,
    COALESCE(w.status <> 'cerrada'::warranty_status AND wp.ready_at IS NULL
      AND wp.promised_date < (now() AT TIME ZONE 'America/Bogota')::date, false) AS is_overdue
   FROM post_sale_warranties w
     JOIN orders o ON o.id = w.order_id
     JOIN buyers b ON b.id = o.buyer_id
     JOIN users_profiles r ON r.id = w.responsible_user_id
     LEFT JOIN users_profiles ob ON ob.id = w.opened_by
     LEFT JOIN users_profiles cb ON cb.id = w.closed_by
     LEFT JOIN companies c ON c.id = o.company_id
     LEFT JOIN lab_providers cl ON cl.id = w.credit_note_lab_provider_id
     LEFT JOIN LATERAL ( SELECT pr.promised_date, pr.ready_at, pr.lab_provider_id
           FROM order_productions pr
          WHERE pr.warranty_id = w.id AND pr.status <> 'cancelada'::production_status
          ORDER BY pr.released_at DESC
         LIMIT 1) wp ON true
     LEFT JOIN lab_providers wl ON wl.id = COALESCE(wp.lab_provider_id, ( SELECT pr.lab_provider_id
           FROM order_productions pr
          WHERE pr.order_id = w.order_id AND pr.warranty_id IS NULL AND pr.status <> 'cancelada'::production_status
          ORDER BY pr.released_at DESC
         LIMIT 1), o.planned_lab_provider_id);
