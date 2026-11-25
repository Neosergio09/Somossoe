-- =====================================================================
-- Importador: plantilla 2026 del Excel de Jornadas («SOE - JORNADAS
-- (nuevo)», mapa L11). La lectura por encabezados la hace la aplicación;
-- aquí se agrega lo que cambia la revisión y la carga:
--   * Estado del lente por fila (Por pedir / En laboratorio / Llegó - por
--     entregar / Entregado) → etapa histórica de cada orden. Sin estado, se
--     usa la etapa de la hoja, como antes.
--   * Filas que no son ventas (secciones «pendientes por llamar» y
--     «desistieron» de MAGNETRON): no crean órdenes; pasan a Seguimiento de
--     la jornada del CRM que Dirección asigne a la hoja.
--   * Avisos que no bloquean la carga: contado sin abono registrado (entra
--     con saldo total; puede ser una deuda o un pago no anotado).
-- =====================================================================

create type public.excel_row_kind as enum ('venta', 'pendiente_cierre', 'desistio');
create type public.excel_lens_status as enum ('por_pedir', 'en_laboratorio', 'por_entregar', 'entregado');

alter table public.excel_import_rows
  add column row_kind      public.excel_row_kind not null default 'venta',
  add column section_label text check (section_label is null or length(section_label) <= 200),
  add column lens_status   public.excel_lens_status,
  add column warnings      text[] not null default '{}';

-- Jornada del CRM a la que pasan como seguimiento quienes no compraron
alter table public.excel_import_sheets
  add column campaign_id uuid references public.campaigns_jornadas (id),
  drop constraint excel_import_sheets_map_code_check,
  add constraint excel_import_sheets_map_code_check check (map_code is null or map_code ~ '^L(1[01]|[1-9])$');

create index excel_import_sheets_campaign_id_idx on public.excel_import_sheets (campaign_id);

grant update (campaign_id) on public.excel_import_sheets to authenticated;

-- ---------------------------------------------------------------------
-- Registro de la importación: campos nuevos de cada fila
-- ---------------------------------------------------------------------
create or replace function public.excel_import_create(p_file_name text, p_file_sha256 text, p_sheets jsonb)
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
      cost_lens, cost_frame, cost_kit, paid_declared, legacy_marks, row_kind, section_label, lens_status
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
      coalesce(r.legacy_marks, '{}'::jsonb),
      coalesce(nullif(r.row_kind, ''), 'venta')::public.excel_row_kind,
      left(nullif(trim(r.section_label), ''), 200),
      nullif(r.lens_status, '')::public.excel_lens_status
    from jsonb_to_recordset(coalesce(v_sheet -> 'rows', '[]'::jsonb)) as r (
      row_number int, block_number int, fingerprint text, event_date date, company_name text, full_name text,
      document_id text, phone text, sale_value numeric, installments int, lab_reference text, lab_name text,
      frame text, lens_type text, cost_lens numeric, cost_frame numeric, cost_kit numeric, paid_declared numeric,
      legacy_marks jsonb, row_kind text, section_label text, lens_status text
    );

    perform public.excel_import_validate_sheet(v_sheet_id);
  end loop;

  return v_import;
end;
$$;

-- Etapa histórica de una fila: la del Excel si la trae, si no la de la hoja
create function private.excel_row_stage(p_status public.excel_lens_status, p_sheet_stage public.historical_stage)
returns public.historical_stage
language sql
immutable
as $$
  select case p_status
    when 'por_pedir' then 'venta'
    when 'en_laboratorio' then 'produccion'
    when 'por_entregar' then 'produccion'
    when 'entregado' then 'entregada'
    else p_sheet_stage
  end::public.historical_stage;
$$;

revoke execute on function private.excel_row_stage(public.excel_lens_status, public.historical_stage) from public, anon;

-- ---------------------------------------------------------------------
-- Validación: ventas como antes; quienes no compraron solo necesitan
-- persona y la jornada de la hoja
-- ---------------------------------------------------------------------
create or replace function public.excel_import_validate_sheet(p_sheet_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet public.excel_import_sheets%rowtype;
  r public.excel_import_rows%rowtype;
  v_errors text[];
  v_warnings text[];
  v_company uuid;
  v_modality public.payment_modality;
  v_balance numeric;
  v_has_session boolean;
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
  v_has_session := exists (select 1 from public.campaign_sessions cs where cs.campaign_id = v_sheet.campaign_id);

  for r in select * from public.excel_import_rows x where x.sheet_id = p_sheet_id and x.status <> 'cargada' for update loop
    v_errors := '{}';
    v_warnings := '{}';

    if r.full_name is null then
      v_errors := v_errors || 'Sin nombre'::text;
    end if;
    if r.document_id is null then
      v_errors := v_errors || 'Sin documento'::text;
    elsif r.document_id !~ '^[0-9A-Z]{4,15}$' then
      v_errors := v_errors || 'Documento inválido (4 a 15 letras o números)'::text;
    end if;

    if r.row_kind <> 'venta' then
      -- No compró: no es una venta, va a Seguimiento de la jornada
      if v_sheet.campaign_id is null then
        v_errors := v_errors || 'No compró: asigne la jornada del CRM a la hoja para pasarlo a Seguimiento, u omita la fila'::text;
      elsif not v_has_session then
        v_errors := v_errors || 'La jornada asignada no tiene sesiones'::text;
      end if;
      if coalesce(r.paid_declared, 0) > 0 then
        v_warnings := v_warnings || format('Figura como «no compró» pero tiene un abono de $%s: queda en la nota del seguimiento',
                                           replace(to_char(r.paid_declared, 'FM999,999,999,999'), ',', '.'));
      end if;
    else
      -- Empresa: la de la fila (EMPRESA o grupo de la hoja), si no la de la hoja
      v_company := r.company_id;
      if v_company is null and r.company_name is not null then
        select c.id into v_company from public.companies c
        where c.name_normalized = private.normalize_company_name(r.company_name);
        if v_company is null then
          v_errors := v_errors || format('Empresa «%s» no está en el CRM: créela o elija otra', r.company_name);
        end if;
      end if;
      v_company := coalesce(v_company, v_sheet.company_id);

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
        elsif r.paid_declared is null and v_sheet.balance_rule = 'total_pendiente' then
          v_warnings := v_warnings || 'Contado sin abono registrado: entra con el saldo total. Verifique si ya pagó.'::text;
        end if;
      end if;
    end if;

    update public.excel_import_rows x
    set errors = v_errors,
        warnings = v_warnings,
        status = case
          when r.omit then 'omitida'
          when exists (select 1 from public.excel_import_rows d
                       where d.fingerprint = r.fingerprint and d.status = 'cargada') then 'duplicada'
          -- La misma venta en otra hoja o fila de esta importación: se carga una sola vez
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
-- Carga: ventas → órdenes históricas (etapa por fila); quienes no
-- compraron → asistencia atendida con seguimiento en la jornada
-- ---------------------------------------------------------------------
create or replace function public.excel_import_load_sheet(p_sheet_id uuid)
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
  v_session uuid;
  v_attendance public.campaign_attendance%rowtype;
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

  select cs.id into v_session from public.campaign_sessions cs
  where cs.campaign_id = v_sheet.campaign_id
  order by cs.session_date, cs.start_time
  limit 1;

  for r in select * from public.excel_import_rows x
           where x.sheet_id = p_sheet_id and x.status = 'lista' order by x.row_number loop
    v_source := left(format('Excel «%s» · hoja «%s» · fila %s', v_file, v_sheet.sheet_name, r.row_number), 300);

    -- ---------------- No compró: seguimiento en la jornada ----------------
    if r.row_kind <> 'venta' then
      v_notes := left(concat_ws(' · ',
        'Excel: ' || coalesce(r.section_label, v_sheet.sheet_name),
        case when coalesce(r.paid_declared, 0) > 0 then 'Abonó $' || replace(to_char(r.paid_declared, 'FM999,999,999,999'), ',', '.') end,
        case when r.sale_value > 0 then 'Valor ofrecido $' || replace(to_char(r.sale_value, 'FM999,999,999,999'), ',', '.') end,
        case when r.lens_type is not null then 'Lente: ' || r.lens_type end,
        case when r.phone is not null then 'Tel. ' || r.phone end), 500);

      select a.* into v_attendance from public.campaign_attendance a
      where a.campaign_id = v_sheet.campaign_id and a.document_id = r.document_id
      order by (a.status = 'atendido') desc, a.created_at
      limit 1;

      if found then
        -- Si ya compró en la jornada, la compra manda: no se le pone seguimiento
        if v_attendance.buyer_id is null then
          update public.campaign_attendance a
          set status = 'atendido',
              followup_status = r.row_kind::text::public.attendance_followup,
              followup_date = case when r.row_kind = 'pendiente_cierre' then private.today_co() end,
              followup_note = v_notes,
              followup_updated_by = (select auth.uid()),
              followup_updated_at = now()
          where a.id = v_attendance.id;
        end if;
      else
        insert into public.campaign_attendance (
          campaign_id, session_id, full_name, document_id, status, attended_at, registered_by,
          followup_status, followup_date, followup_note, followup_updated_by, followup_updated_at
        ) values (
          v_sheet.campaign_id, v_session, r.full_name, r.document_id, 'atendido',
          coalesce(r.event_date::timestamp at time zone 'America/Bogota', now()), (select auth.uid()),
          r.row_kind::text::public.attendance_followup,
          case when r.row_kind = 'pendiente_cierre' then private.today_co() end,
          v_notes, (select auth.uid()), now()
        );
      end if;

      update public.excel_import_rows x
      set status = 'cargada', loaded_at = now()
      where x.id = r.id;
      v_loaded := v_loaded + 1;
      continue;
    end if;

    -- ---------------- Venta: orden histórica ----------------
    v_stage := private.excel_row_stage(r.lens_status, v_sheet.historical_stage);
    -- Empresa de la fila o de la hoja; el convenio solo si es la misma empresa
    v_company := coalesce(
      r.company_id,
      (select c.id from public.companies c where r.company_name is not null
         and c.name_normalized = private.normalize_company_name(r.company_name)),
      v_sheet.company_id);
    v_agreement := case when v_company = v_sheet.company_id then v_sheet.agreement_id end;
    v_modality := private.excel_row_modality(v_sheet.modality_rule, v_company, r.installments);
    v_balance := private.excel_row_balance(v_sheet.balance_rule, r.sale_value, r.paid_declared);

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
      case when r.installments is not null then 'Cuotas pactadas: ' || r.installments end,
      case r.lens_status
        when 'por_pedir' then 'Estado en el Excel: por pedir'
        when 'en_laboratorio' then 'Estado en el Excel: en laboratorio'
        when 'por_entregar' then 'Estado en el Excel: llegó, por entregar'
        when 'entregado' then 'Estado en el Excel: entregado'
      end,
      case when r.legacy_marks ? 'MEDIO DE PAGO' then 'Medio de pago: ' || (r.legacy_marks ->> 'MEDIO DE PAGO') end,
      case when r.paid_declared is null and v_modality = 'contado' and v_sheet.balance_rule = 'total_pendiente'
           then 'Abono no registrado en el Excel: verificar si ya pagó' end);

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
      case
        when v_stage = 'venta' then 'pendiente_liberar'
        when v_stage = 'produccion' and r.lens_status = 'por_entregar' then 'listo_para_entregar'
        when v_stage = 'produccion' then 'en_produccion'
        else 'entrega_completa'
      end::public.order_ops_status,
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
