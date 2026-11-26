-- «Registrar venta» en un solo formulario (campos del Excel «SOE - JORNADAS
-- (nuevo)»): asistencia + comprador + orden + RX en una transacción.
--
-- * Fecha → sesión de la jornada; Nombre, Cédula, Teléfono → asistencia y
--   comprador; Valor venta, Tipo de lente, Montura → ítem; Medio de pago y
--   Cuotas → modalidad y plan; RX OD/OI y ADD → ficha de fabricación;
--   Laboratorio → laboratorio previsto (Operación lo confirma al liberar).
-- * Sin abono: la empresa responde por el comprador; los pagos los registra
--   Cartera en Recaudo.
-- * SECURITY INVOKER: aplican las mismas reglas y permisos que cada paso por
--   separado (RLS, guardas de jornada, create_order, save_fabrication_spec).

-- ---------------------------------------------------------------------
-- Laboratorio previsto en la orden
-- ---------------------------------------------------------------------
alter table public.orders
  add column planned_lab_provider_id uuid references public.lab_providers (id);

create index orders_planned_lab_provider_id_idx on public.orders (planned_lab_provider_id);

grant insert (planned_lab_provider_id) on public.orders to authenticated;
grant update (planned_lab_provider_id) on public.orders to authenticated;

-- create_order guarda también el laboratorio previsto
create or replace function public.create_order(
  p_order jsonb,
  p_items jsonb,
  p_specs jsonb default null,
  p_sensitive_consent boolean default false
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
  v_item_id uuid;
  v_item jsonb;
  v_spec jsonb;
  v_n bigint;
begin
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La orden necesita al menos un ítem';
  end if;
  if p_specs is not null and jsonb_typeof(p_specs) is distinct from 'array' then
    raise exception 'Fichas de fabricación inválidas';
  end if;

  insert into public.orders (
    campaign_id, company_id, branch_id, agreement_id, buyer_id, payment_modality,
    installments_count, first_due_date, employee_auth_received, hr_approval_received,
    employee_auth_file_path, hr_approval_file_path, notes, planned_lab_provider_id
  )
  select
    r.campaign_id, r.company_id, r.branch_id, r.agreement_id, r.buyer_id, r.payment_modality,
    r.installments_count, r.first_due_date,
    coalesce(r.employee_auth_received, false), coalesce(r.hr_approval_received, false),
    r.employee_auth_file_path, r.hr_approval_file_path, r.notes, r.planned_lab_provider_id
  from jsonb_populate_record(null::public.orders, p_order) r
  returning id into v_id;

  if p_sensitive_consent then
    update public.buyers
    set sensitive_data_consent_at = now()
    where id = (p_order ->> 'buyer_id')::uuid and sensitive_data_consent_at is null;
  end if;

  for v_item, v_n in select e.value, e.ordinality from jsonb_array_elements(p_items) with ordinality e loop
    insert into public.order_items (
      order_id, item_type, frame_description, lens_type, lens_filter, description, quantity, unit_price,
      discount_amount, discount_reason
    )
    select
      v_id, r.item_type, r.frame_description, r.lens_type, r.lens_filter, r.description, r.quantity, r.unit_price,
      coalesce(r.discount_amount, 0), nullif(trim(r.discount_reason), '')
    from jsonb_populate_record(null::public.order_items, v_item) r
    returning id into v_item_id;

    v_spec := case when p_specs is null then null else p_specs -> (v_n::int - 1) end;
    if v_spec is not null and jsonb_typeof(v_spec) = 'object' and v_spec <> '{}'::jsonb then
      begin
        perform public.save_fabrication_spec(v_item_id, v_spec);
      exception when check_violation or not_null_violation or invalid_text_representation then
        raise exception 'Ítem %: el RX no cumple las reglas (esfera obligatoria en ambos ojos, pasos de 0.25, eje 0–180 solo con cilindro, ADD 0.50–4.00, DP y altura en mm)', v_n;
      end;
    end if;
  end loop;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Venta de jornada en un solo paso
-- ---------------------------------------------------------------------
-- p_sale: session_id, document_type, document_id, full_name, phone,
--         data_consent (bool), payment_modality, installments_count,
--         first_due_date, employee_auth_received, hr_approval_received,
--         planned_lab_provider_id, notes
create function public.register_campaign_sale(
  p_campaign_id uuid,
  p_sale jsonb,
  p_items jsonb,
  p_specs jsonb default null,
  p_sensitive_consent boolean default false
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_session_id uuid := (p_sale ->> 'session_id')::uuid;
  v_doc_type public.buyer_document_type := coalesce(nullif(p_sale ->> 'document_type', ''), 'cc')::public.buyer_document_type;
  v_doc text := upper(regexp_replace(coalesce(p_sale ->> 'document_id', ''), '[\s.-]', '', 'g'));
  v_name text := nullif(trim(coalesce(p_sale ->> 'full_name', '')), '');
  v_phone text := nullif(trim(coalesce(p_sale ->> 'phone', '')), '');
  v_buyer public.buyers;
  v_att public.campaign_attendance;
begin
  if v_name is null then
    raise exception 'Escriba el nombre del comprador';
  end if;
  if v_doc !~ '^[0-9A-Z]{4,15}$' then
    raise exception 'Cédula inválida: entre 4 y 15 letras o números, sin puntos';
  end if;
  if not exists (select 1 from public.campaign_sessions s where s.id = v_session_id and s.campaign_id = p_campaign_id) then
    raise exception 'Elija la fecha (sesión) de la jornada';
  end if;

  -- 1. Comprador: se reutiliza si ya existe la cédula
  select * into v_buyer from public.buyers b where b.document_type = v_doc_type and b.document_id = v_doc;
  if v_buyer.id is null then
    if not coalesce((p_sale ->> 'data_consent')::boolean, false) then
      raise exception 'El comprador debe autorizar el tratamiento de sus datos personales';
    end if;
    insert into public.buyers (document_type, document_id, full_name, phone, data_consent_at)
    values (v_doc_type, v_doc, v_name, v_phone, now())
    returning * into v_buyer;
  else
    if v_buyer.data_consent_at is null and not coalesce((p_sale ->> 'data_consent')::boolean, false) then
      raise exception 'El comprador debe autorizar el tratamiento de sus datos personales';
    end if;
    update public.buyers b
    set data_consent_at = coalesce(b.data_consent_at, now()),
        phone = coalesce(v_phone, b.phone)
    where b.id = v_buyer.id
      and (b.data_consent_at is null or v_phone is distinct from b.phone and v_phone is not null);
  end if;

  -- 2. Asistencia: queda «atendido» (una sola vez por persona y jornada)
  select * into v_att from public.campaign_attendance a
  where a.campaign_id = p_campaign_id and a.document_id = v_doc and a.status = 'atendido';
  if v_att.id is null then
    select * into v_att from public.campaign_attendance a
    where a.session_id = v_session_id and a.document_id = v_doc;
    if v_att.id is null then
      insert into public.campaign_attendance (campaign_id, session_id, full_name, document_id, status)
      values (p_campaign_id, v_session_id, v_name, v_doc, 'atendido');
    else
      update public.campaign_attendance set status = 'atendido' where id = v_att.id;
    end if;
  end if;

  -- 3. Orden con su ítem y RX (hereda empresa, sede y convenio de la jornada)
  return public.create_order(
    jsonb_strip_nulls(jsonb_build_object(
      'campaign_id', p_campaign_id,
      'buyer_id', v_buyer.id,
      'payment_modality', p_sale ->> 'payment_modality',
      'installments_count', p_sale -> 'installments_count',
      'first_due_date', p_sale ->> 'first_due_date',
      'employee_auth_received', coalesce((p_sale ->> 'employee_auth_received')::boolean, false),
      'hr_approval_received', coalesce((p_sale ->> 'hr_approval_received')::boolean, false),
      'planned_lab_provider_id', nullif(p_sale ->> 'planned_lab_provider_id', ''),
      'notes', nullif(trim(coalesce(p_sale ->> 'notes', '')), '')
    )),
    p_items, p_specs, p_sensitive_consent);
end;
$$;

revoke execute on function public.register_campaign_sale(uuid, jsonb, jsonb, jsonb, boolean) from public, anon;
grant execute on function public.register_campaign_sale(uuid, jsonb, jsonb, jsonb, boolean) to authenticated;
