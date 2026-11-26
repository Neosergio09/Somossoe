-- Reglas aprobadas tras revisar el Excel nuevo de Jornadas: margen solo con
-- costos completos, pedido del laboratorio obligatorio para marcar recibido,
-- pedido sin repetir por laboratorio y días en laboratorio.
begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

-- ---------------- Preparación (como postgres) ----------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'direccion@test.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'comercial@test.co'),
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co');
update public.users_profiles set role = 'direccion', active = true where email = 'direccion@test.co';
update public.users_profiles set role = 'comercial', active = true where email = 'comercial@test.co';
update public.users_profiles set role = 'administracion_cartera', active = true where email = 'admin@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';
-- Estas pruebas no cubren la ficha de fabricación (ver 024): sin candado de RX
update public.system_settings set value = 0 where key = 'require_fabrication_spec';

insert into public.lab_providers (id, name, active) values
  ('11111111-0000-0000-0000-000000000001', 'Panoram', true),
  ('11111111-0000-0000-0000-000000000002', 'CCL', true);

insert into public.companies (id, name, nit, nit_dv, is_nit_provisional, sector, payroll_frequency, assigned_user_id)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Marisol SAS', '900123456',
        private.nit_check_digit('900123456'), false, 'Manufactura', 'mensual', '00000000-0000-0000-0000-0000000000c1');
insert into public.deals_opportunities (id, company_id, city_id, assigned_user_id, deal_name_branch, origin_code,
  stage, target_employees_n, estimated_close_date, tentative_campaign_date)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        (select id from public.cities where name = 'Pereira'), '00000000-0000-0000-0000-0000000000c1',
        'Marisol - Pereira', 'referido', 'convenio_firmado', 50, private.today_co() + 10, private.today_co() + 5);
insert into public.agreements_convenios (id, company_id, payroll_frequency, max_installments, hr_approval_required, status, approved_at)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'mensual', 4, false, 'aprobado', now());
insert into public.campaigns_jornadas (id, deal_id, agreement_id, responsible_user_id, logistics_confirmed, status)
values ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', true, 'en_ejecucion');
insert into public.buyers (id, document_type, document_id, full_name, data_consent_at) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'cc', '1088123456', 'Ana Pérez', now()),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'cc', '1088654321', 'Carlos Ruiz', now()),
  ('bbbbbbbb-0000-0000-0000-000000000003', 'cc', '1088777777', 'Laura Díaz', now());

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.ord(p_notes text) returns uuid language sql as $$
  select id from public.orders where notes = p_notes;
$$;
create function pg_temp.prod(p_notes text) returns uuid language sql as $$
  select p.id from public.order_productions p join public.orders o on o.id = p.order_id
  where o.notes = p_notes and p.status <> 'cancelada';
$$;
create function pg_temp.new_order(p_buyer uuid, p_notes text, p_items jsonb) returns uuid language sql as $$
  select public.create_order(
    jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001', 'buyer_id', p_buyer,
      'payment_modality', 'nomina_empresa', 'installments_count', 2,
      'first_due_date', (private.today_co() + 35)::text, 'employee_auth_received', true, 'notes', p_notes),
    p_items);
$$;
create function pg_temp.margin(p_notes text) returns text language sql as $$
  select cost_basis || '/' || costs_complete || '/' || missing_cost_components::text || '/'
         || coalesce(margin_amount::text, '-')
  from public.v_order_margins where order_id = pg_temp.ord(p_notes);
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select pg_temp.new_order('bbbbbbbb-0000-0000-0000-000000000001', 'Ana',
  '[{"item_type": "lentes", "lens_type": "Monofocal", "quantity": 1, "unit_price": 300000}]');
select pg_temp.new_order('bbbbbbbb-0000-0000-0000-000000000002', 'Carlos',
  '[{"item_type": "montura", "frame_description": "Metálica", "quantity": 1, "unit_price": 200000}]');
select pg_temp.new_order('bbbbbbbb-0000-0000-0000-000000000003', 'Laura',
  '[{"item_type": "gafas_completas", "frame_description": "Acetato", "lens_type": "Progresivo", "quantity": 1, "unit_price": 500000},
    {"item_type": "otro", "description": "Lente de contacto", "quantity": 1, "unit_price": 50000}]');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
update public.orders set requirements_verified = true where notes in ('Ana', 'Carlos', 'Laura');

-- ================= 1. Margen solo con costos completos =================
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select is(pg_temp.margin('Ana'), 'sin_costos/false/{lente,kit}/-', 'sin costos: faltan lente y kit');
select is(pg_temp.margin('Laura'), 'sin_costos/false/{lente,montura,kit,otro}/-',
  'gafas completas + otro exigen lente, montura, kit y otro');

insert into public.order_costs (order_id, component, amount, basis, source)
values (pg_temp.ord('Ana'), 'lente', 60000, 'verificado', 'Factura lab');
select is(pg_temp.margin('Ana'), 'incompleto/false/{kit}/-', 'con el lente pero sin kit: margen no disponible');
select is((select cost_total from public.v_order_margins where order_id = pg_temp.ord('Ana')), 60000::numeric,
  'el costo parcial se sigue mostrando');

insert into public.order_costs (order_id, component, amount, basis, source)
values (pg_temp.ord('Ana'), 'kit', 3000, 'estimado', 'Kit estándar');
select is(pg_temp.margin('Ana'), 'estimado/true/{}/237000', 'con todos los costos el margen aparece');

insert into public.order_costs (order_id, component, amount, basis, source)
values (pg_temp.ord('Carlos'), 'montura', 35000, 'verificado', 'Factura monturas');
select is(pg_temp.margin('Carlos'), 'verificado/true/{}/165000', 'solo montura exige solo el costo de montura');

select is(
  (select orders_incomplete_costs || '/' || coalesce(margin_amount::text, '-') from public.v_campaign_margins
   where campaign_id = 'eeeeeeee-0000-0000-0000-000000000001'),
  '1/-', 'con una orden incompleta la jornada no muestra margen');

insert into public.order_costs (order_id, component, amount, basis, source) values
  (pg_temp.ord('Laura'), 'lente', 150000, 'verificado', 'Factura lab'),
  (pg_temp.ord('Laura'), 'montura', 35000, 'verificado', 'Factura monturas'),
  (pg_temp.ord('Laura'), 'kit', 3000, 'verificado', 'Kit'),
  (pg_temp.ord('Laura'), 'otro', 20000, 'verificado', 'Lente de contacto');
select is(
  (select orders_incomplete_costs || '/' || margin_amount from public.v_campaign_margins
   where campaign_id = 'eeeeeeee-0000-0000-0000-000000000001'),
  '0/744000', 'con todas las órdenes completas la jornada muestra margen');

-- ================= 2 y 4. Pedido del laboratorio =================
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select lives_ok($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date, lab_order_reference)
  values (pg_temp.ord('Ana'), '11111111-0000-0000-0000-000000000001', private.today_co() + 7, ' 053 ')
$$, 'se libera con pedido del laboratorio');
select is((select lab_order_reference from public.order_productions where id = pg_temp.prod('Ana')), '053',
  'el pedido se guarda sin espacios');
select throws_ok($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date, lab_order_reference)
  values (pg_temp.ord('Carlos'), '11111111-0000-0000-0000-000000000001', private.today_co() + 7, '053')
$$, 'P0001', 'El pedido 053 ya está registrado en este laboratorio para otra orden',
  'el mismo pedido no se repite en el mismo laboratorio');
select lives_ok($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date, lab_order_reference, sent_to_lab_at)
  values (pg_temp.ord('Carlos'), '11111111-0000-0000-0000-000000000002', private.today_co() + 7, '053', private.today_co() - 3)
$$, 'el mismo número en otro laboratorio sí se permite');
select lives_ok($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date, sent_to_lab_at)
  values (pg_temp.ord('Laura'), '11111111-0000-0000-0000-000000000001', private.today_co() + 7, private.today_co() - 6)
$$, 'se puede liberar sin pedido y completarlo después');

select throws_ok($$
  update public.order_productions set status = 'listo_para_entregar' where id = pg_temp.prod('Laura')
$$, 'P0001', 'Para marcar el lente como recibido en SOE registre el n.º de pedido del laboratorio',
  'sin pedido del laboratorio no se marca recibido');
select throws_ok($$
  update public.order_productions set status = 'listo_para_entregar', lab_order_reference = '   ' where id = pg_temp.prod('Laura')
$$, 'P0001', null, 'un pedido en blanco no cuenta');
select throws_ok($$
  update public.order_productions set lab_order_reference = '053' where id = pg_temp.prod('Laura')
$$, 'P0001', null, 'tampoco se repite al editar');

select lives_ok($$
  update public.order_productions set lab_order_reference = '198' where id = pg_temp.prod('Laura')
$$, 'se registra el pedido');
select lives_ok($$
  update public.order_productions set status = 'listo_para_entregar', ready_at = private.today_co() - 1
  where id = pg_temp.prod('Laura')
$$, 'con pedido se marca recibido en SOE');
select throws_ok($$
  update public.order_productions set lab_order_reference = null where id = pg_temp.prod('Laura')
$$, 'P0001', null, 'un lente recibido no se queda sin pedido');

update public.order_productions set status = 'cancelada', cancel_reason = 'Error del laboratorio'
where id = pg_temp.prod('Ana');
select lives_ok($$
  update public.order_productions set lab_order_reference = '053' where id = pg_temp.prod('Laura')
$$, 'una producción cancelada libera su número de pedido');

-- ================= 3. Días en laboratorio =================
select is(
  (select days_in_lab || '/' || days_since_received from public.v_productions where id = pg_temp.prod('Laura')),
  '5/1', 'recibido: días desde la orden hasta recibir en SOE y días esperando entrega');
select is(
  (select days_in_lab || '/' || coalesce(days_since_received::text, '-') from public.v_productions where id = pg_temp.prod('Carlos')),
  '3/-', 'en laboratorio: días corridos desde la orden');

-- ================= Datos heredados =================
reset role;
select lives_ok($$
  update public.order_productions set status = 'listo_para_entregar', ready_at = private.today_co(), lab_order_reference = null
  where id = pg_temp.prod('Carlos')
$$, 'cargas heredadas (no API) no exigen el pedido');

select * from finish();
rollback;
