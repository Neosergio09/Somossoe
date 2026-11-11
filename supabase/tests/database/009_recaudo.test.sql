-- Pruebas de recaudo verificado, retenciones y recibo corporativo (Etapa 11).
begin;
create extension if not exists pgtap with schema extensions;
select plan(31);

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
create function pg_temp.coll(p_notes text) returns text language sql as $$
  select collection_status::text || '/' || balance_due from public.orders where notes = p_notes;
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

-- ---------------- Órdenes ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select public.create_order(
  jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001', 'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001',
    'payment_modality', 'nomina_empresa', 'installments_count', 3, 'first_due_date', '2026-01-31', 'notes', 'Ana'),
  jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'A', 'quantity', 1, 'unit_price', 300000)));
select public.create_order(
  jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001', 'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000002',
    'payment_modality', 'nomina_empresa', 'installments_count', 2, 'first_due_date', '2026-12-30', 'notes', 'Carlos'),
  jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'B', 'quantity', 1, 'unit_price', 200000)));
select public.create_order(
  jsonb_build_object('buyer_id', 'bbbbbbbb-0000-0000-0000-000000000003', 'payment_modality', 'contado', 'notes', 'Pedro'),
  jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'C', 'quantity', 1, 'unit_price', 150000)));

-- ---------------- Registro del pago ----------------
select throws_ok($$
  insert into public.collections_payments (company_id, payment_date, total_received_bank, bank_reference, support_received)
  values ('aaaaaaaa-0000-0000-0000-000000000001', current_date, 450000, 'TRX-1', true)
$$, '42501', null, 'Comercial no registra pagos');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  insert into public.collections_payments (company_id, payment_date, total_received_bank, bank_reference)
  values ('aaaaaaaa-0000-0000-0000-000000000001', current_date, 450000, 'TRX-1')
$$, 'P0001', null, 'el pago exige soporte bancario');
select lives_ok($$
  insert into public.collections_payments (company_id, payment_date, total_received_bank, bank_reference, support_received)
  values ('aaaaaaaa-0000-0000-0000-000000000001', current_date, 450000, 'TRX-1', true)
$$, 'Administración registra el giro corporativo');
select throws_ok($$
  insert into public.collections_payments (company_id, payment_date, total_received_bank, bank_reference, support_received)
  values ('aaaaaaaa-0000-0000-0000-000000000001', current_date, 450000, 'trx-1', true)
$$, '23505', null, 'no se registra dos veces el mismo movimiento bancario');

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select is((select count(*) from public.collections_payments), 0::bigint, 'Operación no ve el recaudo');

-- ---------------- Asignación (recibo corporativo) ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  select public.apply_payment(pg_temp.pay('TRX-1'), pg_temp.ord('Pedro'), 10000)
$$, 'P0001', null, 'no se aplica a una orden de otro pagador');
select is(
  (select public.apply_payment(pg_temp.pay('TRX-1'), pg_temp.ord('Ana'), 250000)), 3,
  'el abono de Ana se reparte en 3 cuotas');
select results_eq($$
  select installment_number::int, paid_amount from public.order_installments
  where order_id = pg_temp.ord('Ana') order by installment_number
$$, $$ values (1, 100000::numeric), (2, 100000::numeric), (3, 50000::numeric) $$,
  'se aplica a las cuotas en orden de vencimiento');
select is(pg_temp.coll('Ana'), 'parcialmente_recaudado/50000', 'Ana queda con recaudo parcial');
select is(
  (select status from public.v_order_installments where order_id = pg_temp.ord('Ana') and installment_number = 1),
  'pagada', 'la cuota cubierta queda pagada');

select throws_ok($$
  select public.apply_payment(pg_temp.pay('TRX-1'), pg_temp.ord('Carlos'), 150000, 50000, false)
$$, 'P0001', null, 'la retención exige certificado');
select lives_ok($$
  select public.apply_payment(pg_temp.pay('TRX-1'), pg_temp.ord('Carlos'), 150000, 50000, true)
$$, 'se aplica dinero y retención con certificado');
select is(pg_temp.coll('Carlos'), 'recaudado_total/0', 'la retención extingue su parte del saldo');
select results_eq($$
  select allocated_amount, withholding_amount, unassigned_amount from public.v_payments where bank_reference = 'TRX-1'
$$, $$ values (400000::numeric, 50000::numeric, 50000::numeric) $$,
  'retención no es pago: el recaudo en bancos solo cuenta dinero y lo no asignado queda visible');

select throws_ok($$
  select public.apply_payment(pg_temp.pay('TRX-1'), pg_temp.ord('Ana'), 60000)
$$, 'P0001', null, 'no se abona más del saldo de la orden');
select lives_ok($$
  select public.apply_payment(pg_temp.pay('TRX-1'), pg_temp.ord('Ana'), 50000)
$$, 'se completa el saldo de Ana');
select is(pg_temp.coll('Ana'), 'recaudado_total/0', 'Ana queda recaudada');

-- ---------------- Pago de un particular y anticipo en contado ----------------
insert into public.collections_payments (buyer_id, payment_date, total_received_bank, bank_reference, support_received)
values ('bbbbbbbb-0000-0000-0000-000000000003', current_date, 100000, 'TRX-2', true);
select throws_ok($$
  select public.apply_payment(pg_temp.pay('TRX-2'), pg_temp.ord('Pedro'), 120000)
$$, 'P0001', null, 'no se asigna más de lo recibido en el pago');
select lives_ok($$
  select public.apply_payment(pg_temp.pay('TRX-2'), pg_temp.ord('Pedro'), 100000)
$$, 'se aplica el anticipo de Pedro');
update public.orders set requirements_verified = true where notes = 'Pedro';
select is(
  (select cardinality(release_blockers) from public.v_orders where notes = 'Pedro'), 1,
  'con anticipo parcial y política del 100% la orden de contado sigue bloqueada');
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
update public.system_settings set value = 0.5 where key = 'cash_min_prepayment_pct';
select is(
  (select cardinality(release_blockers) from public.v_orders where notes = 'Pedro'), 0,
  'con política del 50% el pago verificado libera la orden');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  update public.orders set is_cancelled = true, cancel_reason = 'x' where notes = 'Pedro'
$$, 'P0001', null, 'una orden con pagos no se anula');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  update public.orders set installments_count = 2 where notes = 'Ana'
$$, 'P0001', null, 'con pagos aplicados no cambia el plan de la orden');

-- ---------------- Anulaciones ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  update public.payment_allocations set amount_applied = 1 where order_id = pg_temp.ord('Pedro')
$$, '42501', null, 'una asignación no se edita');
select lives_ok($$
  update public.payment_allocations set is_voided = true, void_reason = 'Aplicado a la orden equivocada'
  where order_id = pg_temp.ord('Pedro')
$$, 'se anula la asignación con motivo');
select is(pg_temp.coll('Pedro'), 'con_saldo/150000', 'el saldo vuelve a su valor');

select lives_ok($$
  update public.collections_payments set is_voided = true, void_reason = 'Consignación devuelta'
  where bank_reference = 'TRX-1'
$$, 'se anula el giro corporativo');
select is(pg_temp.coll('Ana') || ' ' || pg_temp.coll('Carlos'), 'con_saldo/300000 con_saldo/200000',
  'anular el pago anula sus asignaciones');
select is(
  (select sum(paid_amount) from public.order_installments where order_id = pg_temp.ord('Ana')), 0::numeric,
  'las cuotas vuelven a quedar sin pago');
select throws_ok($$
  update public.collections_payments set notes = 'x' where bank_reference = 'TRX-1'
$$, 'P0001', null, 'un pago anulado no se modifica');
select is((select count(*) from public.v_receivables), 3::bigint, 'las tres órdenes quedan en cartera por cobrar');

select * from finish();
rollback;
