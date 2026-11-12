-- Pruebas de M07: referencia del laboratorio, cuotas por vencer y línea
-- de tiempo de la empresa.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

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
  ('bbbbbbbb-0000-0000-0000-000000000001', 'cc', '1088123456', 'Ana Pérez', now());
insert into public.lab_providers (id, name) values ('11111111-0000-0000-0000-000000000001', 'Lab Demo');

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.ord() returns uuid language sql as $$
  select id from public.orders where notes = 'Ana';
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select public.create_order(
  jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001', 'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001',
    'payment_modality', 'nomina_empresa', 'installments_count', 3, 'first_due_date', current_date - 5,
    'employee_auth_received', true, 'notes', 'Ana'),
  jsonb_build_array(jsonb_build_object('item_type', 'gafas_completas', 'frame_description', 'A', 'lens_type', 'Monofocal',
    'quantity', 1, 'unit_price', 300000)));
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
update public.orders set requirements_verified = true where notes = 'Ana';

-- ---------------- Referencia del pedido en el laboratorio ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date, lab_order_reference)
  values (pg_temp.ord(), '11111111-0000-0000-0000-000000000001', current_date + 7, repeat('x', 61))
$$, '23514', null, 'la referencia del laboratorio tiene máximo 60 caracteres');
select lives_ok($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date, lab_order_reference)
  values (pg_temp.ord(), '11111111-0000-0000-0000-000000000001', current_date + 7, 'LAB-77812')
$$, 'Operación libera con la referencia del pedido del laboratorio');
select is((select lab_order_reference from public.v_productions where order_id = pg_temp.ord()), 'LAB-77812',
  'la referencia se ve en el tablero de producción');
update public.order_productions set lab_order_reference = 'LAB-77812-B' where order_id = pg_temp.ord();
select is((select lab_order_reference from public.order_productions where order_id = pg_temp.ord()), 'LAB-77812-B',
  'Operación corrige la referencia');

-- ---------------- Cuotas por vencer ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select is((select count(*) from public.v_installments_due where order_id = pg_temp.ord()), 3::bigint,
  'las tres cuotas pendientes aparecen');
select is(
  (select is_overdue::text || '/' || pending_amount || '/' || collection_responsible
   from public.v_installments_due where order_id = pg_temp.ord() and installment_number = 1),
  'true/100000/empresa', 'la primera cuota vencida con su responsable de cobro');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
insert into public.collections_payments (company_id, payment_date, total_received_bank, bank_reference, support_received)
values ('aaaaaaaa-0000-0000-0000-000000000001', current_date, 100000, 'T-1', true);
select public.apply_payment((select id from public.collections_payments where bank_reference = 'T-1'), pg_temp.ord(), 100000);
select is((select count(*) from public.v_installments_due where order_id = pg_temp.ord()), 2::bigint,
  'una cuota pagada sale de la lista');
insert into public.portfolio_reclassifications (order_id, reason, new_installments_count, new_periodicity, new_first_due_date)
values (pg_temp.ord(), 'retiro', 1, 'mensual', current_date + 3);
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
update public.portfolio_reclassifications set status = 'autorizada' where order_id = pg_temp.ord();
select is(
  (select count(*) || '/' || min(collection_responsible::text) from public.v_installments_due where order_id = pg_temp.ord()),
  '1/empleado', 'las cuotas reemplazadas salen y queda la del plan nuevo');

-- ---------------- Resumen financiero ----------------
select is(
  (select total_sold || '/' || collected_bank || '/' || balance_due from public.v_company_finance
   where company_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  '300000/100000/200000', 'el resumen de la empresa suma venta, recaudo en bancos y saldo');
select is(
  (select active_orders || '/' || balance_due from public.v_buyer_finance where buyer_id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  '1/200000', 'el resumen del comprador coincide');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select is(
  (select collected_bank from public.v_company_finance where company_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  0::numeric, 'Operación no suma el recaudo (no lo ve)');
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');

-- ---------------- Línea de tiempo de la empresa ----------------
insert into public.order_costs (order_id, component, amount, basis, source)
values (pg_temp.ord(), 'lente', 90000, 'estimado', 'Cotización');
select cmp_ok((select count(*) from public.company_timeline('aaaaaaaa-0000-0000-0000-000000000001')), '>=', 6::bigint,
  'Dirección ve la línea de tiempo de la empresa');
select ok(
  exists (select 1 from public.company_timeline('aaaaaaaa-0000-0000-0000-000000000001')
          where table_name = 'portfolio_reclassifications' and action = 'UPDATE' and 'status' = any (changed_fields)),
  'muestra qué campos cambiaron');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select is(
  (select count(*) from public.company_timeline('aaaaaaaa-0000-0000-0000-000000000001') where table_name = 'order_costs'),
  0::bigint, 'la línea de tiempo no expone la auditoría de costos a Administración');
select cmp_ok((select count(*) from public.company_timeline('aaaaaaaa-0000-0000-0000-000000000001')), '>', 0::bigint,
  'Administración ve el resto de la línea de tiempo');
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select is((select count(*) from public.company_timeline('aaaaaaaa-0000-0000-0000-000000000001')), 0::bigint,
  'Comercial no accede a la auditoría');

select * from finish();
rollback;
