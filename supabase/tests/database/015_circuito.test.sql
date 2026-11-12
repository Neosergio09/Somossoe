-- Resumen del circuito (inicio y contadores de la barra lateral).
begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co');
update public.users_profiles set role = 'administracion_cartera', active = true where email = 'admin@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';
insert into public.companies (id, name, nit, nit_dv, is_nit_provisional, sector, payroll_frequency)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Marisol SAS', '900123456', private.nit_check_digit('900123456'), false, 'Manufactura', 'mensual');
insert into public.buyers (id, document_type, document_id, full_name, data_consent_at)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'cc', '1088123456', 'Ana Pérez', now());

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.login(uuid) to authenticated;

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select public.create_historical_order(
  jsonb_build_object('buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001', 'company_id', 'aaaaaaaa-0000-0000-0000-000000000001',
    'payment_modality', 'nomina_empresa', 'collection_responsible', 'empresa', 'total_amount', 300000, 'balance_due', 200000,
    'historical_stage', 'entregada', 'historical_reference', 'Prueba circuito', 'installments_count', 2,
    'installment_periodicity', 'mensual', 'first_due_date', current_date));

select is((public.circuit_summary() -> 'cobrar' ->> 'saldo')::numeric, 200000::numeric, 'Cartera ve el saldo por cobrar');
select is((public.circuit_summary() -> 'cobrar' ->> 'vencidas')::int, 1, 'cuenta la cuota que vence hoy');
select is((public.circuit_summary() -> 'facturar' ->> 'sin_factura')::int, 1, 'cuenta la orden verificada sin factura');

insert into public.collections_payments (company_id, payment_date, total_received_bank, bank_reference, support_received)
values ('aaaaaaaa-0000-0000-0000-000000000001', current_date, 50000, 'C-1', true);
select is((public.circuit_summary() -> 'cobrar' ->> 'pagos_sin_asignar')::int, 1, 'Cartera ve el pago sin asignar');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select is((public.circuit_summary() -> 'cobrar' ->> 'pagos_sin_asignar')::int, 0, 'Operación no cuenta los pagos (no los ve)');

select * from finish();
rollback;
