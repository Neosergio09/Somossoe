-- Pruebas de producción, entregas y posventa (Etapas 08, 09 y 12).
begin;
create extension if not exists pgtap with schema extensions;
select plan(37);

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

insert into public.lab_providers (id, name, active) values
  ('11111111-0000-0000-0000-000000000001', 'Lab Activo', true),
  ('11111111-0000-0000-0000-000000000002', 'Lab Inactivo', false);

insert into public.companies (id, name, nit, nit_dv, is_nit_provisional, sector, payroll_frequency, assigned_user_id)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Marisol SAS', '900123456',
        private.nit_check_digit('900123456'), false, 'Manufactura', 'mensual', '00000000-0000-0000-0000-0000000000c1');
insert into public.deals_opportunities (id, company_id, city_id, assigned_user_id, deal_name_branch, origin_code,
  stage, target_employees_n, estimated_close_date, tentative_campaign_date)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        (select id from public.cities where name = 'Pereira'), '00000000-0000-0000-0000-0000000000c1',
        'Marisol - Pereira', 'referido', 'convenio_firmado', 50, current_date + 10, current_date + 5);
insert into public.agreements_convenios (id, company_id, payroll_frequency, max_installments, hr_approval_required, status, approved_at)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'mensual', 4, false, 'aprobado', now());
insert into public.campaigns_jornadas (id, deal_id, agreement_id, responsible_user_id, logistics_confirmed, status)
values ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', true, 'en_ejecucion');
insert into public.buyers (id, document_type, document_id, full_name, data_consent_at) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'cc', '1088123456', 'Ana Pérez', now()),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'cc', '1088654321', 'Carlos Ruiz', now());

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.ord(p_notes text) returns uuid language sql as $$
  select id from public.orders where notes = p_notes;
$$;
create function pg_temp.item(p_notes text, p_type text) returns uuid language sql as $$
  select i.id from public.order_items i join public.orders o on o.id = i.order_id
  where o.notes = p_notes and i.item_type::text = p_type;
$$;
create function pg_temp.ops(p_notes text) returns text language sql as $$
  select ops_status::text from public.orders where notes = p_notes;
$$;
create function pg_temp.warranty() returns uuid language sql as $$
  select id from public.post_sale_warranties limit 1;
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

-- ---------------- Órdenes (Comercial y Administración) ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select public.create_order(
  jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001', 'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001',
    'payment_modality', 'nomina_empresa', 'installments_count', 2, 'first_due_date', '2026-12-30',
    'employee_auth_received', true, 'notes', 'Nómina'),
  jsonb_build_array(
    jsonb_build_object('item_type', 'gafas_completas', 'frame_description', 'Acetato', 'lens_type', 'Progresivo', 'quantity', 1, 'unit_price', 400000),
    jsonb_build_object('item_type', 'montura', 'frame_description', 'Repuesto', 'quantity', 1, 'unit_price', 100000),
    jsonb_build_object('item_type', 'otro', 'description', 'Estuche', 'quantity', 2, 'unit_price', 10000)));
select public.create_order(
  jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001', 'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000002',
    'payment_modality', 'contado', 'notes', 'Contado'),
  jsonb_build_array(jsonb_build_object('item_type', 'lentes', 'lens_type', 'Monofocal', 'quantity', 1, 'unit_price', 150000)));

-- ---------------- Candado de liberación ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date)
  values (pg_temp.ord('Nómina'), '11111111-0000-0000-0000-000000000001', current_date + 7)
$$, 'P0001', null, 'no se libera sin requisitos verificados');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
update public.orders set requirements_verified = true where notes in ('Nómina', 'Contado');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date)
  values (pg_temp.ord('Nómina'), '11111111-0000-0000-0000-000000000001', current_date + 7)
$$, '42501', null, 'Comercial no libera a producción');

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select lives_ok($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date)
  values (pg_temp.ord('Nómina'), '11111111-0000-0000-0000-000000000001', current_date + 7)
$$, 'Operación libera la orden de nómina verificada');
select is(pg_temp.ops('Nómina'), 'en_produccion', 'la orden pasa a En producción');
select throws_ok($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date)
  values (pg_temp.ord('Nómina'), '11111111-0000-0000-0000-000000000001', current_date + 7)
$$, 'P0001', null, 'una orden no se libera dos veces');

select throws_ok($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date)
  values (pg_temp.ord('Contado'), '11111111-0000-0000-0000-000000000001', current_date + 7)
$$, 'P0001', null, 'contado sin pago verificado ni excepción no se libera');
select is(
  (select cardinality(release_blockers) from public.v_orders where notes = 'Contado'), 1,
  'la vista muestra el bloqueo de anticipo');

select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
update public.orders set prepayment_exception_reason = 'Cliente frecuente' where notes = 'Contado';

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date)
  values (pg_temp.ord('Contado'), '11111111-0000-0000-0000-000000000002', current_date + 7)
$$, 'P0001', null, 'no se envía a un laboratorio inactivo');
select lives_ok($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date)
  values (pg_temp.ord('Contado'), '11111111-0000-0000-0000-000000000001', current_date + 7)
$$, 'con excepción de Dirección, contado se libera');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  update public.order_items set unit_price = 1 where id = pg_temp.item('Nómina', 'montura')
$$, 'P0001', null, 'una orden liberada no cambia sus ítems');

-- ---------------- Entregas ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  select public.register_delivery(
    jsonb_build_object('order_id', pg_temp.ord('Nómina'), 'receiver_name', 'Ana', 'evidence_received', true),
    jsonb_build_array(jsonb_build_object('order_item_id', pg_temp.item('Nómina', 'gafas_completas'), 'quantity', 1)))
$$, 'P0001', null, 'las gafas no se entregan antes de que la producción esté lista');
select throws_ok($$
  select public.register_delivery(
    jsonb_build_object('order_id', pg_temp.ord('Nómina'), 'receiver_name', 'Ana'),
    jsonb_build_array(jsonb_build_object('order_item_id', pg_temp.item('Nómina', 'montura'), 'quantity', 1)))
$$, 'P0001', null, 'la entrega exige evidencia');
select lives_ok($$
  select public.register_delivery(
    jsonb_build_object('order_id', pg_temp.ord('Nómina'), 'receiver_name', 'Ana Pérez', 'evidence_received', true),
    jsonb_build_array(jsonb_build_object('order_item_id', pg_temp.item('Nómina', 'montura'), 'quantity', 1)))
$$, 'la montura se entrega desde que la orden se libera');
select is(pg_temp.ops('Nómina'), 'entrega_parcial', 'la orden queda con entrega parcial');
select is(
  (select accounting_status::text || '/' || collection_status::text || '/' || balance_due from public.orders where notes = 'Nómina'),
  'pendiente_vincular/con_saldo/520000',
  'entregado no significa cobrado: contable y cartera no cambian');

select throws_ok($$
  update public.order_productions set status = 'cancelada', cancel_reason = 'x' where order_id = pg_temp.ord('Nómina')
$$, 'P0001', null, 'no se cancela la producción de una orden con entregas');

select lives_ok($$
  update public.order_productions set status = 'listo_para_entregar' where order_id = pg_temp.ord('Nómina')
$$, 'Operación marca la producción lista');
select is(
  (select ready_at from public.order_productions where order_id = pg_temp.ord('Nómina')),
  private.today_co(), 'se registra la fecha real de listo');

select throws_ok($$
  select public.register_delivery(
    jsonb_build_object('order_id', pg_temp.ord('Nómina'), 'receiver_name', 'Ana', 'evidence_received', true),
    jsonb_build_array(jsonb_build_object('order_item_id', pg_temp.item('Nómina', 'otro'), 'quantity', 3)))
$$, 'P0001', null, 'no se entregan más unidades de las vendidas');
select lives_ok($$
  select public.register_delivery(
    jsonb_build_object('order_id', pg_temp.ord('Nómina'), 'receiver_name', 'Ana Pérez', 'evidence_received', true),
    jsonb_build_array(
      jsonb_build_object('order_item_id', pg_temp.item('Nómina', 'gafas_completas'), 'quantity', 1),
      jsonb_build_object('order_item_id', pg_temp.item('Nómina', 'otro'), 'quantity', 2)))
$$, 'se entrega el resto');
select is(pg_temp.ops('Nómina'), 'entrega_completa', 'la orden queda con entrega completa');
select is(
  (select sum(pending_quantity)::int from public.v_order_item_delivery where order_id = pg_temp.ord('Nómina')), 0,
  'no queda nada pendiente por entregar');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  update public.orders set is_cancelled = true, cancel_reason = 'x' where notes = 'Nómina'
$$, 'P0001', null, 'una orden con entregas no se anula');

-- ---------------- Posventa ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  insert into public.post_sale_warranties (order_id, incident_type, description, responsible_user_id)
  values (pg_temp.ord('Contado'), 'garantia', 'x', '00000000-0000-0000-0000-0000000000b1')
$$, 'P0001', null, 'no hay posventa sin productos entregados');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  insert into public.post_sale_warranties (order_id, incident_type, description, responsible_user_id)
  values (pg_temp.ord('Nómina'), 'garantia', 'x', '00000000-0000-0000-0000-0000000000b1')
$$, '42501', null, 'Comercial no registra garantías');

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select lives_ok($$
  insert into public.post_sale_warranties (order_id, incident_type, description, responsible_user_id)
  values (pg_temp.ord('Nómina'), 'garantia', 'Lente rayado de fábrica', '00000000-0000-0000-0000-0000000000b1')
$$, 'Operación registra la garantía');
select lives_ok($$
  insert into public.order_productions (order_id, warranty_id, lab_provider_id, promised_date)
  values (pg_temp.ord('Nómina'), pg_temp.warranty(), '11111111-0000-0000-0000-000000000001', current_date + 5)
$$, 'se envía la reposición al laboratorio');
select is((select status::text from public.post_sale_warranties), 'en_reposicion', 'la garantía pasa a En reposición');
select is(
  (select ops_status::text || '/' || total_amount from public.orders where notes = 'Nómina'),
  'entrega_completa/520000', 'la reposición no cambia el estado operativo ni el valor de la orden');

select throws_ok($$
  update public.post_sale_warranties set status = 'cerrada', resolution = 'x', evidence_received = true
$$, '42501', null, 'Operación no cierra garantías');

select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select throws_ok($$
  update public.post_sale_warranties set status = 'cerrada', resolution = 'Reposición', evidence_received = true
$$, 'P0001', null, 'no se cierra antes de entregar la reposición');

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
update public.order_productions set status = 'listo_para_entregar' where warranty_id = pg_temp.warranty();
select lives_ok($$
  select public.register_delivery(
    jsonb_build_object('order_id', pg_temp.ord('Nómina'), 'warranty_id', pg_temp.warranty(),
      'receiver_name', 'Ana Pérez', 'evidence_received', true),
    jsonb_build_array(jsonb_build_object('order_item_id', pg_temp.item('Nómina', 'gafas_completas'), 'quantity', 1)))
$$, 'se entrega la reposición (no cuenta como entrega de la venta)');

select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select throws_ok($$
  update public.post_sale_warranties set status = 'cerrada', resolution = 'Reposición entregada'
$$, 'P0001', null, 'el cierre exige evidencia');
select lives_ok($$
  update public.post_sale_warranties set status = 'cerrada', resolution = 'Reposición entregada', evidence_received = true
$$, 'Dirección cierra la garantía');
select throws_ok($$
  update public.post_sale_warranties set resolution = 'otra'
$$, 'P0001', null, 'una garantía cerrada no se modifica');

-- ---------------- Anulación con producción en curso ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select lives_ok($$
  update public.orders set is_cancelled = true, cancel_reason = 'Desistió' where notes = 'Contado'
$$, 'se anula una orden en producción sin entregas');
select is(
  (select status::text || '/' || pg_temp.ops('Contado') from public.order_productions where order_id = pg_temp.ord('Contado')),
  'cancelada/pendiente_liberar', 'al anular la orden se cancela su producción');

select * from finish();
rollback;
