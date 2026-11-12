-- Pruebas de reclasificación de cartera por novedad de nómina (RF-M06-04).
begin;
create extension if not exists pgtap with schema extensions;
select plan(30);

-- ---------------- Preparación (como postgres) ----------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'direccion@test.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'comercial@test.co'),
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co'),
  ('00000000-0000-0000-0000-0000000000e1', 'socio@test.co');
update public.users_profiles set role = 'direccion', active = true where email = 'direccion@test.co';
update public.users_profiles set role = 'comercial', active = true where email = 'comercial@test.co';
update public.users_profiles set role = 'administracion_cartera', active = true where email = 'admin@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';
update public.users_profiles set role = 'socio', active = true where email = 'socio@test.co';

insert into public.companies (id, name, nit, nit_dv, is_nit_provisional, sector, payroll_frequency, assigned_user_id)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Marisol SAS', '900123456', private.nit_check_digit('900123456'),
        false, 'Manufactura', 'mensual', '00000000-0000-0000-0000-0000000000c1');
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
  ('bbbbbbbb-0000-0000-0000-000000000002', 'cc', '1088654321', 'Carlos Ruiz', now()),
  ('bbbbbbbb-0000-0000-0000-000000000003', 'cc', '10001000', 'Pedro Gómez', now());

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.ord(p_notes text) returns uuid language sql as $$
  select id from public.orders where notes = p_notes;
$$;
create function pg_temp.pay(p_ref text) returns uuid language sql as $$
  select id from public.collections_payments where bank_reference = p_ref;
$$;
create function pg_temp.req(p_order text, p_status text) returns uuid language sql as $$
  select r.id from public.portfolio_reclassifications r
  where r.order_id = pg_temp.ord(p_order) and r.status::text = p_status
  order by r.requested_at desc limit 1;
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

-- ---------------- Órdenes y un primer giro de la empresa ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select public.create_order(
  jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001', 'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001',
    'payment_modality', 'nomina_empresa', 'installments_count', 3, 'first_due_date', current_date + 20, 'notes', 'Ana'),
  jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'A', 'quantity', 1, 'unit_price', 300000)));
select public.create_order(
  jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001', 'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000002',
    'payment_modality', 'nomina_empresa', 'installments_count', 2, 'first_due_date', current_date + 20, 'notes', 'Carlos'),
  jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'B', 'quantity', 1, 'unit_price', 200000)));
select public.create_order(
  jsonb_build_object('buyer_id', 'bbbbbbbb-0000-0000-0000-000000000003', 'payment_modality', 'contado', 'notes', 'Pedro'),
  jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'C', 'quantity', 1, 'unit_price', 150000)));

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
insert into public.collections_payments (company_id, payment_date, total_received_bank, bank_reference, support_received)
values ('aaaaaaaa-0000-0000-0000-000000000001', current_date, 150000, 'EMP-1', true);
select public.apply_payment(pg_temp.pay('EMP-1'), pg_temp.ord('Ana'), 150000);

-- ---------------- Solicitud (Administración / Cartera) ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  insert into public.portfolio_reclassifications (order_id, reason, new_installments_count, new_periodicity, new_first_due_date)
  values (pg_temp.ord('Ana'), 'retiro', 2, 'mensual', current_date + 10)
$$, '42501', null, 'Comercial no solicita reclasificaciones');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  insert into public.portfolio_reclassifications (order_id, reason, new_installments_count, new_periodicity, new_first_due_date)
  values (pg_temp.ord('Pedro'), 'retiro', 1, 'mensual', current_date + 10)
$$, 'P0001', null, 'una orden de contado no se reclasifica');
select throws_ok($$
  insert into public.portfolio_reclassifications (order_id, reason, new_installments_count, new_periodicity, new_first_due_date)
  values (pg_temp.ord('Ana'), 'retiro', 2, 'mensual', current_date - 1)
$$, 'P0001', null, 'el plan nuevo no vence en el pasado');
select throws_ok($$
  insert into public.portfolio_reclassifications (order_id, reason, new_installments_count, new_periodicity, new_first_due_date)
  values (pg_temp.ord('Ana'), 'otro', 2, 'mensual', current_date + 10)
$$, '23514', null, 'motivo "otro" exige notas');
select lives_ok($$
  insert into public.portfolio_reclassifications (order_id, reason, notes, new_installments_count, new_periodicity, new_first_due_date)
  values (pg_temp.ord('Ana'), 'retiro', 'Renunció el 10/11', 2, 'mensual', current_date + 10)
$$, 'Administración solicita la reclasificación');
select is(
  (select status::text || '/' || balance_at_request from public.portfolio_reclassifications where order_id = pg_temp.ord('Ana')),
  'pendiente/150000', 'la solicitud queda pendiente con el saldo del momento');
select throws_ok($$
  insert into public.portfolio_reclassifications (order_id, reason, new_installments_count, new_periodicity, new_first_due_date)
  values (pg_temp.ord('Ana'), 'retiro', 1, 'mensual', current_date + 10)
$$, '23505', null, 'una sola solicitud pendiente por orden');
select is(
  (select collection_responsible::text || '/' || (select count(*) from public.order_installments i where i.order_id = o.id)
   from public.orders o where o.notes = 'Ana'),
  'empresa/3', 'mientras está pendiente nada cambia en la orden');

-- ---------------- Decisión (Dirección) ----------------
select throws_ok($$
  update public.portfolio_reclassifications set status = 'autorizada' where id = pg_temp.req('Ana', 'pendiente')
$$, '42501', null, 'Administración no autoriza');

select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select lives_ok($$
  update public.portfolio_reclassifications set status = 'autorizada', decision_notes = 'Confirmado con RRHH'
  where id = pg_temp.req('Ana', 'pendiente')
$$, 'Dirección autoriza');
select is(
  (select payment_modality::text || '/' || collection_responsible::text from public.orders where notes = 'Ana'),
  'nomina_empresa/empleado', 'cambia el responsable de cobro; la modalidad original se conserva');
select is(
  (select balance_transferred || '/' || (decided_by is not null) from public.portfolio_reclassifications
   where id = pg_temp.req('Ana', 'autorizada')),
  '150000/true', 'se registra el saldo trasladado y quién autorizó');
select results_eq($$
  select installment_number::int, expected_amount, paid_amount, superseded_by_reclassification_id is not null
  from public.order_installments where order_id = pg_temp.ord('Ana') order by installment_number
$$, $$ values (1, 100000::numeric, 100000::numeric, false), (2, 100000::numeric, 50000::numeric, true),
              (3, 100000::numeric, 0::numeric, true), (4, 75000::numeric, 0::numeric, false),
              (5, 75000::numeric, 0::numeric, false) $$,
  'las cuotas pendientes quedan reemplazadas y el saldo se reparte en el plan nuevo');
select is(
  (select due_date from public.order_installments where order_id = pg_temp.ord('Ana') and installment_number = 5),
  (current_date + 10 + interval '1 month')::date, 'el plan nuevo usa su propia periodicidad');
select throws_ok($$
  update public.portfolio_reclassifications set status = 'rechazada', decision_notes = 'x'
  where id = pg_temp.req('Ana', 'autorizada')
$$, 'P0001', null, 'una decisión no se cambia');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  insert into public.portfolio_reclassifications (order_id, reason, new_installments_count, new_periodicity, new_first_due_date)
  values (pg_temp.ord('Ana'), 'retiro', 1, 'mensual', current_date + 10)
$$, 'P0001', null, 'una orden ya reclasificada no se vuelve a reclasificar');

-- ---------------- Pagos después de reclasificar ----------------
insert into public.collections_payments (buyer_id, payment_date, total_received_bank, bank_reference, support_received)
values ('bbbbbbbb-0000-0000-0000-000000000001', current_date, 75000, 'ANA-1', true);
select is((select public.apply_payment(pg_temp.pay('ANA-1'), pg_temp.ord('Ana'), 75000)), 1,
  'el empleado paga y el abono va a la primera cuota del plan nuevo');
select is((select paid_amount from public.order_installments where order_id = pg_temp.ord('Ana') and installment_number = 4),
  75000::numeric, 'la cuota 4 queda pagada');
insert into public.collections_payments (company_id, payment_date, total_received_bank, bank_reference, support_received)
values ('aaaaaaaa-0000-0000-0000-000000000001', current_date, 75000, 'EMP-LIQ', true);
select lives_ok($$ select public.apply_payment(pg_temp.pay('EMP-LIQ'), pg_temp.ord('Ana'), 75000) $$,
  'la empresa todavía puede abonar (liquidación final)');
select is((select collection_status::text || '/' || balance_due from public.orders where notes = 'Ana'),
  'recaudado_total/0', 'con ambos pagos la orden queda recaudada');
select throws_ok($$
  update public.collections_payments set is_voided = true, void_reason = 'Rebotado' where bank_reference = 'EMP-1'
$$, 'P0001', null, 'no se anula un pago aplicado a cuotas reemplazadas');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  update public.orders set installments_count = 2 where notes = 'Ana'
$$, 'P0001', null, 'el plan original de una orden reclasificada no se cambia');

-- ---------------- Rechazo y anulación ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
insert into public.portfolio_reclassifications (order_id, reason, new_installments_count, new_periodicity, new_first_due_date)
values (pg_temp.ord('Carlos'), 'incapacidad', 1, 'quincenal', current_date + 5);
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  update public.orders set installments_count = 1 where notes = 'Carlos'
$$, 'P0001', null, 'con una solicitud pendiente el plan no se cambia');
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select throws_ok($$
  update public.portfolio_reclassifications set status = 'rechazada' where id = pg_temp.req('Carlos', 'pendiente')
$$, '23514', null, 'rechazar exige motivo');
select lives_ok($$
  update public.portfolio_reclassifications set status = 'rechazada', decision_notes = 'La empresa sí descontará'
  where id = pg_temp.req('Carlos', 'pendiente')
$$, 'Dirección rechaza con motivo');
select is((select collection_responsible::text from public.orders where notes = 'Carlos'), 'empresa',
  'al rechazar la orden sigue a cargo de la empresa');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
insert into public.portfolio_reclassifications (order_id, reason, new_installments_count, new_periodicity, new_first_due_date)
values (pg_temp.ord('Carlos'), 'retiro', 1, 'mensual', current_date + 5);
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select throws_ok($$
  update public.portfolio_reclassifications set status = 'anulada', decision_notes = 'x'
  where id = pg_temp.req('Carlos', 'pendiente')
$$, '42501', null, 'Dirección no anula solicitudes (las anula quien las gestiona)');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select lives_ok($$
  update public.portfolio_reclassifications set status = 'anulada', decision_notes = 'Error de digitación'
  where id = pg_temp.req('Carlos', 'pendiente')
$$, 'Administración anula su solicitud');

-- ---------------- Visibilidad ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000e1');
select is((select count(*) from public.v_portfolio_reclassifications), 3::bigint, 'el socio consulta las reclasificaciones');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select is((select count(*) from public.portfolio_reclassifications), 0::bigint, 'Operación no ve reclasificaciones');

select * from finish();
rollback;
