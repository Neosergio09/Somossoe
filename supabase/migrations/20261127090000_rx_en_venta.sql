-- RX al registrar la venta (SRS 1.6 · RF-M04-07, backlog V0.2 SOE-12)
--
-- La orden de jornada (o venta directa) se registra con la ficha de
-- fabricación de cada ítem con lente en el mismo paso y en la misma
-- transacción: si la ficha no es válida no queda la orden a medias.
--
-- * p_specs: arreglo alineado con p_items; null u objeto vacío = sin RX.
-- * p_sensitive_consent: el comprador autorizó en ese momento sus datos
--   sensibles (se registra en buyers con fecha y usuario de la base).
-- * Las reglas de quién captura, rangos, ADD y consentimiento son las de
--   public.save_fabrication_spec (Comercial que registra la orden).
-- * Sin RX la venta se guarda igual y la ficha queda «Sin ficha».

drop function public.create_order(jsonb, jsonb);

create function public.create_order(
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
    employee_auth_file_path, hr_approval_file_path, notes
  )
  select
    r.campaign_id, r.company_id, r.branch_id, r.agreement_id, r.buyer_id, r.payment_modality,
    r.installments_count, r.first_due_date,
    coalesce(r.employee_auth_received, false), coalesce(r.hr_approval_received, false),
    r.employee_auth_file_path, r.hr_approval_file_path, r.notes
  from jsonb_populate_record(null::public.orders, p_order) r
  returning id into v_id;

  -- Autorización de datos sensibles dada al momento de la venta
  if p_sensitive_consent then
    update public.buyers
    set sensitive_data_consent_at = now()
    where id = (p_order ->> 'buyer_id')::uuid and sensitive_data_consent_at is null;
  end if;

  -- Ítems uno a uno para saber el id de cada posición
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

revoke execute on function public.create_order(jsonb, jsonb, jsonb, boolean) from public, anon;
grant execute on function public.create_order(jsonb, jsonb, jsonb, boolean) to authenticated;
