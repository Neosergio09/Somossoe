-- =====================================================================
-- Importador del Excel histórico «INFORME JORNADAS SOE» (doc de Jornadas
-- §3 y §8). Decisiones del 2026-11-16 (carta blanca del socio):
--   * El archivo se sube, la aplicación lo lee por encabezados (mapas
--     L1–L9) y guarda cada fila en un área de revisión con hoja, fila y
--     huella. Dirección clasifica cada hoja (empresa, modalidad, etapa,
--     saldo) y carga: se crean compradores y órdenes históricas con costos
--     estimados. Reimportar no duplica (huella por fila).
--   * RX/ADD nunca se leen; las columnas no reconocidas no se guardan; la
--     hoja GARANTIAS se omite (doc §3.2). El archivo original no se guarda.
--   * ORDEN = referencia del laboratorio; LABORATORIO = proveedor;
--     MONTURA/TIPO DE LENTE = descripción; costos solo del bloque COSTO
--     LENTE/MONTURA/KIT (estimados); UTILIDAD no se importa; ABONO =
--     recaudo declarado; FACTURADO/PENDIENTE/X/OBSERVACIONES = nota legada
--     que queda solo en el área de revisión.
--   * Solo Dirección usa el importador (las filas llevan costos).
--   * Un comprador importado no recibe una autorización de datos ficticia:
--     queda sin ella y se regulariza antes de una venta nueva.
-- =====================================================================

create type public.excel_import_status as enum ('en_revision', 'cargada', 'descartada');
create type public.excel_sheet_status as enum ('pendiente', 'omitida', 'cargada');
create type public.excel_row_status as enum ('lista', 'con_error', 'duplicada', 'omitida', 'cargada');
create type public.excel_modality_rule as enum ('segun_cuotas', 'contado', 'nomina');
create type public.excel_balance_rule as enum ('total_pendiente', 'pagado');

-- ---------------------------------------------------------------------
-- Importaciones
-- ---------------------------------------------------------------------
create table public.excel_imports (
  id            uuid primary key default gen_random_uuid(),
  file_name     text not null check (length(trim(file_name)) between 1 and 255),
  file_sha256   text not null check (file_sha256 ~ '^[0-9a-f]{64}$'),
  status        public.excel_import_status not null default 'en_revision',
  notes         text check (notes is null or length(notes) <= 2000),
  uploaded_by   uuid default auth.uid() references public.users_profiles (id),
  uploaded_at   timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- El mismo archivo no se sube dos veces mientras su importación siga viva
create unique index excel_imports_sha_key on public.excel_imports (file_sha256) where status <> 'descartada';
create index excel_imports_uploaded_by_idx on public.excel_imports (uploaded_by);

create trigger excel_imports_set_updated_at
  before update on public.excel_imports
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Hojas: clasificación humana (doc §2: ninguna pestaña es una jornada
-- automáticamente)
-- ---------------------------------------------------------------------
create table public.excel_import_sheets (
  id                      uuid primary key default gen_random_uuid(),
  import_id               uuid not null references public.excel_imports (id) on delete cascade,
  sheet_name              text not null,
  sheet_index             integer not null,
  map_code                text check (map_code is null or map_code ~ '^L(10|[1-9])$'),
  detected_columns        text[] not null default '{}',
  skip_reason             text,
  status                  public.excel_sheet_status not null default 'pendiente',
  -- Clasificación (Dirección)
  company_id              uuid references public.companies (id),
  agreement_id            uuid,
  modality_rule           public.excel_modality_rule not null default 'segun_cuotas',
  historical_stage        public.historical_stage not null default 'entregada',
  balance_rule            public.excel_balance_rule not null default 'total_pendiente',
  collection_responsible  public.collection_responsible not null default 'empresa',
  installment_periodicity public.payroll_frequency,
  first_due_date          date,
  loaded_at               timestamptz,
  loaded_by               uuid references public.users_profiles (id),
  updated_at              timestamptz not null default now(),
  constraint excel_import_sheets_unique unique (import_id, sheet_index),
  constraint excel_import_sheets_agreement_same_company
    foreign key (agreement_id, company_id) references public.agreements_convenios (id, company_id)
);

create index excel_import_sheets_company_id_idx on public.excel_import_sheets (company_id);
create index excel_import_sheets_agreement_id_idx on public.excel_import_sheets (agreement_id, company_id);
create index excel_import_sheets_loaded_by_idx on public.excel_import_sheets (loaded_by);

create trigger excel_import_sheets_set_updated_at
  before update on public.excel_import_sheets
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Filas: solo campos no clínicos ya interpretados
-- ---------------------------------------------------------------------
create table public.excel_import_rows (
  id                 uuid primary key default gen_random_uuid(),
  import_id          uuid not null references public.excel_imports (id) on delete cascade,
  sheet_id           uuid not null references public.excel_import_sheets (id) on delete cascade,
  row_number         integer not null check (row_number > 0),
  block_number       integer not null default 1,
  fingerprint        text not null check (fingerprint ~ '^[0-9a-f]{64}$'),
  -- Datos leídos
  event_date         date,
  company_name       text,
  full_name          text,
  document_type      public.buyer_document_type not null default 'cc',
  document_id        text,
  phone              text,
  sale_value         numeric(14,0),
  installments       integer,
  lab_reference      text,
  lab_name           text,
  frame              text,
  lens_type          text,
  cost_lens          numeric(14,0),
  cost_frame         numeric(14,0),
  cost_kit           numeric(14,0),
  paid_declared      numeric(14,0),
  legacy_marks       jsonb not null default '{}'::jsonb,
  -- Revisión
  company_id         uuid references public.companies (id),
  omit               boolean not null default false,
  omit_reason        text,
  status             public.excel_row_status not null default 'con_error',
  errors             text[] not null default '{}',
  -- Resultado de la carga
  buyer_id           uuid references public.buyers (id),
  order_id           uuid references public.orders (id),
  loaded_at          timestamptz,
  updated_at         timestamptz not null default now(),
  constraint excel_import_rows_unique unique (sheet_id, row_number),
  constraint excel_import_rows_omit_reason
    check (not omit or (omit_reason is not null and length(trim(omit_reason)) > 0)),
  constraint excel_import_rows_values
    check ((sale_value is null or sale_value >= 0) and (paid_declared is null or paid_declared >= 0)
           and (cost_lens is null or cost_lens >= 0) and (cost_frame is null or cost_frame >= 0)
           and (cost_kit is null or cost_kit >= 0))
);

create index excel_import_rows_import_id_idx on public.excel_import_rows (import_id);
create index excel_import_rows_fingerprint_idx on public.excel_import_rows (fingerprint);
create index excel_import_rows_company_id_idx on public.excel_import_rows (company_id);
create index excel_import_rows_buyer_id_idx on public.excel_import_rows (buyer_id);
create index excel_import_rows_order_id_idx on public.excel_import_rows (order_id);
-- Una fila (por su huella) se carga una sola vez, aunque venga en otra copia del archivo
create unique index excel_import_rows_loaded_fingerprint_key
  on public.excel_import_rows (fingerprint) where status = 'cargada';

create trigger excel_import_rows_set_updated_at
  before update on public.excel_import_rows
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Auditoría y privilegios: solo Dirección
-- ---------------------------------------------------------------------
create trigger excel_imports_audit
  after insert or update or delete on public.excel_imports
  for each row execute function private.audit_row_change();
create trigger excel_import_sheets_audit
  after update on public.excel_import_sheets
  for each row execute function private.audit_row_change();

alter table public.excel_imports enable row level security;
alter table public.excel_import_sheets enable row level security;
alter table public.excel_import_rows enable row level security;

revoke all on public.excel_imports, public.excel_import_sheets, public.excel_import_rows from anon, authenticated;
grant select on public.excel_imports, public.excel_import_sheets, public.excel_import_rows to authenticated;
grant update (notes, status) on public.excel_imports to authenticated;
grant update (company_id, agreement_id, modality_rule, historical_stage, balance_rule, collection_responsible,
              installment_periodicity, first_due_date, status)
  on public.excel_import_sheets to authenticated;
grant update (full_name, document_type, document_id, company_id, omit, omit_reason)
  on public.excel_import_rows to authenticated;

create policy excel_imports_select on public.excel_imports
  for select to authenticated using ((select private.has_role('direccion')));
create policy excel_imports_update on public.excel_imports
  for update to authenticated
  using ((select private.has_role('direccion'))) with check ((select private.has_role('direccion')));
create policy excel_import_sheets_select on public.excel_import_sheets
  for select to authenticated using ((select private.has_role('direccion')));
create policy excel_import_sheets_update on public.excel_import_sheets
  for update to authenticated
  using ((select private.has_role('direccion'))) with check ((select private.has_role('direccion')));
create policy excel_import_rows_select on public.excel_import_rows
  for select to authenticated using ((select private.has_role('direccion')));
create policy excel_import_rows_update on public.excel_import_rows
  for update to authenticated
  using ((select private.has_role('direccion'))) with check ((select private.has_role('direccion')));

-- Hojas y filas cargadas no se tocan; descartar no aplica si algo se cargó
create function private.excel_import_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user <> 'authenticated' then
    return new;
  end if;

  if tg_table_name = 'excel_imports' then
    if old.status <> 'en_revision' then
      raise exception 'La importación ya está %', old.status;
    end if;
    if new.status = 'cargada' then
      raise exception 'Una importación queda cargada al cargar sus hojas';
    end if;
    if new.status = 'descartada'
       and exists (select 1 from public.excel_import_sheets s where s.import_id = old.id and s.status = 'cargada') then
      raise exception 'No se descarta una importación con hojas ya cargadas';
    end if;
  elsif tg_table_name = 'excel_import_sheets' then
    if old.status = 'cargada' then
      raise exception 'La hoja ya se cargó; no se modifica';
    end if;
    if new.status = 'cargada' then
      raise exception 'Use la acción de carga para cargar la hoja';
    end if;
    if old.skip_reason is not null and new.status <> 'omitida' then
      raise exception 'Esta hoja no se puede importar: %', old.skip_reason;
    end if;
  else
    if old.status = 'cargada' then
      raise exception 'La fila ya se cargó; no se modifica';
    end if;
    if new.document_id is not null then
      new.document_id := upper(regexp_replace(new.document_id, '[^0-9A-Za-z]', '', 'g'));
    end if;
    if not new.omit then
      new.omit_reason := null;
    end if;
  end if;
  return new;
end;
$$;

create trigger excel_imports_guard before update on public.excel_imports
  for each row execute function private.excel_import_guard();
create trigger excel_import_sheets_guard before update on public.excel_import_sheets
  for each row execute function private.excel_import_guard();
create trigger excel_import_rows_guard before update on public.excel_import_rows
  for each row execute function private.excel_import_guard();

-- ---------------------------------------------------------------------
-- Registro de una importación leída por la aplicación (atómico)
-- p_sheets: [{sheet_name, sheet_index, map_code, detected_columns[], skip_reason,
--   rows: [{row_number, block_number, fingerprint, event_date, company_name, full_name,
--           document_id, phone, sale_value, installments, lab_reference, lab_name, frame,
--           lens_type, cost_lens, cost_frame, cost_kit, paid_declared, legacy_marks}]}]
-- ---------------------------------------------------------------------
create function public.excel_import_create(p_file_name text, p_file_sha256 text, p_sheets jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_import uuid;
  v_sheet jsonb;
  v_sheet_id uuid;
begin
  if not private.has_role('direccion') then
    raise exception 'Solo Dirección importa el Excel histórico' using errcode = '42501';
  end if;
  if jsonb_typeof(p_sheets) is distinct from 'array' or jsonb_array_length(p_sheets) = 0 then
    raise exception 'El archivo no tiene hojas';
  end if;
  if exists (select 1 from public.excel_imports i where i.file_sha256 = lower(p_file_sha256) and i.status <> 'descartada') then
    raise exception 'Este archivo ya se importó; abra la importación existente o descártela primero';
  end if;

  insert into public.excel_imports (file_name, file_sha256)
  values (trim(p_file_name), lower(p_file_sha256))
  returning id into v_import;

  for v_sheet in select * from jsonb_array_elements(p_sheets) loop
    insert into public.excel_import_sheets (import_id, sheet_name, sheet_index, map_code, detected_columns, skip_reason, status)
    values (
      v_import, v_sheet ->> 'sheet_name', (v_sheet ->> 'sheet_index')::int, v_sheet ->> 'map_code',
      coalesce(array(select jsonb_array_elements_text(v_sheet -> 'detected_columns')), '{}'),
      nullif(v_sheet ->> 'skip_reason', ''),
      case when nullif(v_sheet ->> 'skip_reason', '') is null then 'pendiente' else 'omitida' end::public.excel_sheet_status
    )
    returning id into v_sheet_id;

    insert into public.excel_import_rows (
      import_id, sheet_id, row_number, block_number, fingerprint, event_date, company_name, full_name,
      document_type, document_id, phone, sale_value, installments, lab_reference, lab_name, frame, lens_type,
      cost_lens, cost_frame, cost_kit, paid_declared, legacy_marks
    )
    select
      v_import, v_sheet_id, r.row_number, coalesce(r.block_number, 1), lower(r.fingerprint), r.event_date,
      nullif(trim(r.company_name), ''), nullif(trim(r.full_name), ''),
      case when upper(regexp_replace(coalesce(r.document_id, ''), '[^0-9A-Za-z]', '', 'g')) ~ '[A-Z]'
           then 'otro' else 'cc' end::public.buyer_document_type,
      nullif(upper(regexp_replace(coalesce(r.document_id, ''), '[^0-9A-Za-z]', '', 'g')), ''),
      nullif(trim(r.phone), ''), r.sale_value, r.installments,
      nullif(trim(r.lab_reference), ''), nullif(trim(r.lab_name), ''), nullif(trim(r.frame), ''),
      nullif(trim(r.lens_type), ''), r.cost_lens, r.cost_frame, r.cost_kit, r.paid_declared,
      coalesce(r.legacy_marks, '{}'::jsonb)
    from jsonb_to_recordset(coalesce(v_sheet -> 'rows', '[]'::jsonb)) as r (
      row_number int, block_number int, fingerprint text, event_date date, company_name text, full_name text,
      document_id text, phone text, sale_value numeric, installments int, lab_reference text, lab_name text,
      frame text, lens_type text, cost_lens numeric, cost_frame numeric, cost_kit numeric, paid_declared numeric,
      legacy_marks jsonb
    );

    perform public.excel_import_validate_sheet(v_sheet_id);
  end loop;

  return v_import;
end;
$$;

-- ---------------------------------------------------------------------
-- Validación de una hoja: estado y errores de cada fila
-- ---------------------------------------------------------------------
create function private.excel_row_modality(p_rule public.excel_modality_rule, p_company uuid, p_installments int)
returns public.payment_modality
language sql
immutable
as $$
  select case
    when p_rule = 'contado' then 'contado'
    when p_rule = 'nomina' then 'nomina_empresa'
    when p_company is not null and coalesce(p_installments, 0) > 1 then 'nomina_empresa'
    else 'contado'
  end::public.payment_modality;
$$;

create function private.excel_row_balance(p_rule public.excel_balance_rule, p_sale numeric, p_paid numeric)
returns numeric
language sql
immutable
as $$
  select case
    when p_paid is not null then greatest(p_sale - p_paid, 0)
    when p_rule = 'pagado' then 0
    else p_sale
  end;
$$;

create function public.excel_import_validate_sheet(p_sheet_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet public.excel_import_sheets%rowtype;
  r public.excel_import_rows%rowtype;
  v_errors text[];
  v_company uuid;
  v_modality public.payment_modality;
  v_balance numeric;
begin
  if not private.has_role('direccion') then
    raise exception 'Solo Dirección revisa la importación' using errcode = '42501';
  end if;
  select * into v_sheet from public.excel_import_sheets s where s.id = p_sheet_id;
  if not found then
    raise exception 'Hoja no encontrada';
  end if;
  if v_sheet.status = 'cargada' then
    return;
  end if;

  for r in select * from public.excel_import_rows x where x.sheet_id = p_sheet_id and x.status <> 'cargada' for update loop
    v_errors := '{}';

    -- Empresa: la de la fila (L9 trae EMPRESA), si no la de la hoja
    v_company := r.company_id;
    if v_company is null and r.company_name is not null then
      select c.id into v_company from public.companies c
      where c.name_normalized = private.normalize_company_name(r.company_name);
      if v_company is null then
        v_errors := v_errors || format('Empresa «%s» no está en el CRM: créela o elija otra', r.company_name);
      end if;
    end if;
    v_company := coalesce(v_company, v_sheet.company_id);

    if r.full_name is null then
      v_errors := v_errors || 'Sin nombre'::text;
    end if;
    if r.document_id is null then
      v_errors := v_errors || 'Sin documento'::text;
    elsif r.document_id !~ '^[0-9A-Z]{4,15}$' then
      v_errors := v_errors || 'Documento inválido (4 a 15 letras o números)'::text;
    end if;
    if r.sale_value is null or r.sale_value <= 0 then
      v_errors := v_errors || 'Sin valor de venta'::text;
    elsif r.paid_declared is not null and r.paid_declared > r.sale_value then
      v_errors := v_errors || 'El abono supera el valor de venta'::text;
    end if;

    v_modality := private.excel_row_modality(v_sheet.modality_rule, v_company, r.installments);
    if r.sale_value > 0 then
      v_balance := private.excel_row_balance(v_sheet.balance_rule, r.sale_value, r.paid_declared);
      if v_modality = 'nomina_empresa' then
        if v_company is null then
          v_errors := v_errors || 'Nómina sin empresa: asigne la empresa a la hoja'::text;
        end if;
        if v_balance > 0 then
          if coalesce(r.installments, 0) not between 1 and 24 then
            v_errors := v_errors || 'Nómina con saldo: faltan las cuotas (1 a 24)'::text;
          end if;
          if v_sheet.installment_periodicity is null or v_sheet.first_due_date is null then
            v_errors := v_errors || 'Nómina con saldo: indique en la hoja la periodicidad y la próxima cuota'::text;
          end if;
        end if;
      end if;
    end if;

    update public.excel_import_rows x
    set errors = v_errors,
        status = case
          when r.omit then 'omitida'
          when exists (select 1 from public.excel_import_rows d
                       where d.fingerprint = r.fingerprint and d.status = 'cargada') then 'duplicada'
          -- La misma venta en otra hoja o fila de esta importación (p. ej. la vista
          -- «Contado» repite órdenes de otras pestañas): se carga una sola vez
          when exists (select 1 from public.excel_import_rows d
                       join public.excel_import_sheets ds on ds.id = d.sheet_id
                       where d.import_id = r.import_id and d.fingerprint = r.fingerprint and d.id <> r.id
                         and not d.omit and ds.status <> 'omitida'
                         and (ds.sheet_index, d.row_number) < (v_sheet.sheet_index, r.row_number)) then 'duplicada'
          when cardinality(v_errors) > 0 then 'con_error'
          else 'lista'
        end::public.excel_row_status
    where x.id = r.id;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- Carga de una hoja: compradores + órdenes históricas + costos (atómico)
-- ---------------------------------------------------------------------
create function public.excel_import_load_sheet(p_sheet_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet public.excel_import_sheets%rowtype;
  v_file text;
  r public.excel_import_rows%rowtype;
  v_pending int;
  v_company uuid;
  v_agreement uuid;
  v_modality public.payment_modality;
  v_balance numeric;
  v_buyer uuid;
  v_order uuid;
  v_source text;
  v_notes text;
  v_loaded int := 0;
  v_stage public.historical_stage;
begin
  if not private.has_role('direccion') then
    raise exception 'Solo Dirección carga la importación' using errcode = '42501';
  end if;

  select * into v_sheet from public.excel_import_sheets s where s.id = p_sheet_id for update;
  if not found then
    raise exception 'Hoja no encontrada';
  end if;
  if v_sheet.status <> 'pendiente' then
    raise exception 'La hoja está %', v_sheet.status;
  end if;
  select i.file_name into v_file from public.excel_imports i where i.id = v_sheet.import_id and i.status = 'en_revision';
  if not found then
    raise exception 'La importación no está en revisión';
  end if;

  perform public.excel_import_validate_sheet(p_sheet_id);

  select count(*) into v_pending
  from public.excel_import_rows x where x.sheet_id = p_sheet_id and x.status = 'con_error';
  if v_pending > 0 then
    raise exception 'Hay % fila(s) con error: corríjalas u omítalas antes de cargar', v_pending;
  end if;

  v_stage := v_sheet.historical_stage;

  for r in select * from public.excel_import_rows x
           where x.sheet_id = p_sheet_id and x.status = 'lista' order by x.row_number loop
    -- Empresa de la fila o de la hoja; el convenio solo si es la misma empresa
    v_company := coalesce(
      r.company_id,
      (select c.id from public.companies c where r.company_name is not null
         and c.name_normalized = private.normalize_company_name(r.company_name)),
      v_sheet.company_id);
    v_agreement := case when v_company = v_sheet.company_id then v_sheet.agreement_id end;
    v_modality := private.excel_row_modality(v_sheet.modality_rule, v_company, r.installments);
    v_balance := private.excel_row_balance(v_sheet.balance_rule, r.sale_value, r.paid_declared);
    v_source := left(format('Excel «%s» · hoja «%s» · fila %s', v_file, v_sheet.sheet_name, r.row_number), 300);

    -- Comprador por documento (no se fusiona por nombre ni teléfono)
    select b.id into v_buyer from public.buyers b
    where b.document_type = r.document_type and b.document_id = r.document_id;
    if v_buyer is null then
      insert into public.buyers (document_type, document_id, full_name, phone, current_company_id, created_by)
      values (r.document_type, r.document_id, r.full_name,
              case when r.phone ~ '^\+?[0-9 ()-]{7,20}$' then r.phone end,
              v_company, (select auth.uid()))
      returning id into v_buyer;
    end if;

    v_notes := concat_ws(' · ',
      v_source,
      case when r.event_date is not null then 'Fecha: ' || to_char(r.event_date, 'DD/MM/YYYY') end,
      case when r.frame is not null then 'Montura: ' || r.frame end,
      case when r.lens_type is not null then 'Lente: ' || r.lens_type end,
      case when r.lab_name is not null then 'Laboratorio: ' || r.lab_name end,
      case when r.lab_reference is not null then 'Ref. laboratorio: ' || r.lab_reference end,
      case when r.installments is not null then 'Cuotas pactadas: ' || r.installments end);

    insert into public.orders (
      company_id, agreement_id, buyer_id, payment_modality, collection_responsible,
      installments_count, installment_periodicity, first_due_date, total_amount,
      is_historical_migration, historical_stage, historical_collected_before_migration, historical_reference,
      requirements_verified, requirements_verified_by, requirements_verified_at,
      ops_status, notes, created_by
    ) values (
      v_company, v_agreement, v_buyer, v_modality,
      case when v_modality = 'nomina_empresa' then v_sheet.collection_responsible else 'empleado' end,
      case when v_modality = 'nomina_empresa' and v_balance > 0 then r.installments end,
      case when v_modality = 'nomina_empresa' and v_balance > 0 then v_sheet.installment_periodicity end,
      case when v_modality = 'nomina_empresa' and v_balance > 0 then v_sheet.first_due_date end,
      r.sale_value,
      true, v_stage, r.sale_value - v_balance, 'XLS-' || left(r.fingerprint, 24),
      v_stage <> 'venta',
      case when v_stage <> 'venta' then (select auth.uid()) end,
      case when v_stage <> 'venta' then now() end,
      case v_stage when 'venta' then 'pendiente_liberar' when 'produccion' then 'en_produccion' else 'entrega_completa' end::public.order_ops_status,
      left(v_notes, 2000), (select auth.uid())
    )
    returning id into v_order;

    -- Venta pendiente de producir: un ítem para seguir el flujo normal
    if v_stage = 'venta' then
      insert into public.order_items (order_id, item_type, frame_description, lens_type, description, quantity, unit_price)
      values (v_order, 'gafas_completas', r.frame, r.lens_type,
              case when r.frame is null and r.lens_type is null then 'Importado del Excel' end, 1, r.sale_value);
    end if;

    -- Costos del bloque económico como estimados (UTILIDAD se recalcula)
    insert into public.order_costs (order_id, component, amount, basis, source, created_by)
    select v_order, c.component, c.amount, 'estimado', v_source, (select auth.uid())
    from (values ('lente'::public.cost_component, r.cost_lens),
                 ('montura'::public.cost_component, r.cost_frame),
                 ('kit'::public.cost_component, r.cost_kit)) c (component, amount)
    where c.amount is not null and c.amount > 0;

    update public.excel_import_rows x
    set status = 'cargada', buyer_id = v_buyer, order_id = v_order, loaded_at = now()
    where x.id = r.id;
    v_loaded := v_loaded + 1;
  end loop;

  update public.excel_import_sheets s
  set status = 'cargada', loaded_at = now(), loaded_by = (select auth.uid())
  where s.id = p_sheet_id;

  -- La importación queda cargada cuando no le quedan hojas pendientes
  update public.excel_imports i set status = 'cargada'
  where i.id = v_sheet.import_id
    and not exists (select 1 from public.excel_import_sheets s where s.import_id = i.id and s.status = 'pendiente');

  return v_loaded;
end;
$$;

revoke execute on function public.excel_import_create(text, text, jsonb) from public, anon;
revoke execute on function public.excel_import_validate_sheet(uuid) from public, anon;
revoke execute on function public.excel_import_load_sheet(uuid) from public, anon;
revoke execute on function private.excel_row_modality(public.excel_modality_rule, uuid, int) from public, anon;
revoke execute on function private.excel_row_balance(public.excel_balance_rule, numeric, numeric) from public, anon;
grant execute on function public.excel_import_create(text, text, jsonb) to authenticated;
grant execute on function public.excel_import_validate_sheet(uuid) to authenticated;
grant execute on function public.excel_import_load_sheet(uuid) to authenticated;
