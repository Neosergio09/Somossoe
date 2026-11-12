-- Pruebas de facturas de Alegra, estado contable y etapa 7 (Etapa 10).
begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

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

insert into public.companies (id, name, nit, nit_dv, is_nit_provisional, sector, payroll_frequency, assigned_user_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Marisol SAS', '900123456', private.nit_check_digit('900123456'),
   false, 'Manufactura', 'mensual', '00000000-0000-0000-0000-0000000000c1'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'Andina Provisional', null, null, true, 'Retail', 'mensual', null);
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
insert into public.campaign_sessions (campaign_id, session_date, start_time, end_time, responsible_user_id)
values ('eeeeeeee-0000-0000-0000-000000000001', current_date, '08:00', '12:00', '00000000-0000-0000-0000-0000000000b1');
update public.deals_opportunities set stage = 'jornada_en_ejecucion' where id = 'dddddddd-0000-0000-0000-000000000001';
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
create function pg_temp.inv(p_number text) returns uuid language sql as $$
  select id from public.alegra_invoices where alegra_invoice_number = p_number;
$$;
create function pg_temp.acc(p_notes text) returns text language sql as $$
  select accounting_status::text from public.orders where notes = p_notes;
$$;
create function pg_temp.stage() returns text language sql as $$
  select stage::text from public.deals_opportunities where id = 'dddddddd-0000-0000-0000-000000000001';
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
    'payment_modality', 'nomina_empresa', 'installments_count', 2, 'first_due_date', '2026-12-30', 'notes', 'Ana'),
  jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'A', 'quantity', 1, 'unit_price', 300000)));
select public.create_order(
  jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001', 'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000002',
    'payment_modality', 'nomina_empresa', 'installments_count', 2, 'first_due_date', '2026-12-30', 'notes', 'Carlos'),
  jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'B', 'quantity', 1, 'unit_price', 200000)));
select public.create_order(
  jsonb_build_object('buyer_id', 'bbbbbbbb-0000-0000-0000-000000000003', 'payment_modality', 'contado', 'notes', 'Pedro'),
  jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'C', 'quantity', 1, 'unit_price', 150000)));

-- ---------------- Registro de facturas ----------------
select throws_ok($$
  insert into public.alegra_invoices (alegra_invoice_number, invoice_date, invoiced_amount, company_id)
  values ('FE-1', current_date, 1000, 'aaaaaaaa-0000-0000-0000-000000000001')
$$, '42501', null, 'Comercial no registra facturas');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  insert into public.alegra_invoices (alegra_invoice_number, invoice_date, invoiced_amount, company_id)
  values ('FE-1', current_date, 1000, 'aaaaaaaa-0000-0000-0000-000000000002')
$$, 'P0001', null, 'no se factura a una empresa con NIT provisional');
select throws_ok($$
  insert into public.alegra_invoices (alegra_invoice_number, invoice_date, invoiced_amount, company_id)
  values ('FE-1', current_date + 1, 1000, 'aaaaaaaa-0000-0000-0000-000000000001')
$$, 'P0001', null, 'la fecha de la factura no puede ser futura');
select throws_ok($$
  insert into public.alegra_invoices (alegra_invoice_number, invoice_date, invoiced_amount,
    company_id, buyer_id)
  values ('FE-1', current_date, 1000, 'aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001')
$$, '23514', null, 'la factura tiene un solo sujeto: empresa o comprador');
select lives_ok($$
  insert into public.alegra_invoices (alegra_invoice_number, invoice_date, invoiced_amount, company_id)
  values (' fe-100 ', current_date, 500000, 'aaaaaaaa-0000-0000-0000-000000000001')
$$, 'Administración registra la factura de la empresa');
select throws_ok($$
  insert into public.alegra_invoices (alegra_invoice_number, invoice_date, invoiced_amount, company_id)
  values ('FE-100', current_date, 1000, 'aaaaaaaa-0000-0000-0000-000000000001')
$$, '23505', null, 'el número de factura no se repite');

-- ---------------- Vínculo con órdenes ----------------
select throws_ok($$
  insert into public.alegra_invoice_orders (invoice_id, order_id, amount_assigned)
  values (pg_temp.inv('FE-100'), pg_temp.ord('Pedro'), 150000)
$$, 'P0001', null, 'no se vincula una orden de otro sujeto');
select lives_ok($$
  insert into public.alegra_invoice_orders (invoice_id, order_id, amount_assigned)
  values (pg_temp.inv('FE-100'), pg_temp.ord('Ana'), 300000)
$$, 'se vincula la orden de Ana por su valor');
select is(pg_temp.acc('Ana'), 'factura_vinculada', 'la orden queda con factura vinculada');
select lives_ok($$
  insert into public.alegra_invoice_orders (invoice_id, order_id, amount_assigned)
  values (pg_temp.inv('FE-100'), pg_temp.ord('Carlos'), 150000)
$$, 'se vincula la orden de Carlos por menos de su valor');
select is(pg_temp.acc('Carlos'), 'factura_con_diferencia', 'Diferencia Visible: factura con diferencia');
select is(
  (select discrepancy_amount from public.v_invoice_orders where order_id = pg_temp.ord('Carlos')),
  -50000::numeric, 'la vista muestra la diferencia');
select throws_ok($$
  update public.alegra_invoice_orders set amount_assigned = 250000 where order_id = pg_temp.ord('Carlos')
$$, 'P0001', null, 'no se asigna más de lo facturado');
update public.alegra_invoice_orders set amount_assigned = 200000 where order_id = pg_temp.ord('Carlos');
select is(pg_temp.acc('Carlos'), 'factura_vinculada', 'al corregir el monto la diferencia desaparece');
select throws_ok($$
  update public.alegra_invoices set invoiced_amount = 400000 where id = pg_temp.inv('FE-100')
$$, 'P0001', null, 'el monto facturado no baja de lo ya asignado');
select throws_ok($$
  update public.orders set is_cancelled = true, cancel_reason = 'x' where notes = 'Ana'
$$, 'P0001', null, 'una orden con factura vinculada no se anula');

-- ---------------- Etapa 7 automática ----------------
select is(pg_temp.stage(), 'jornada_en_ejecucion', 'con la jornada abierta la oportunidad no se cierra');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
update public.campaigns_jornadas set status = 'captura_cerrada' where id = 'eeeeeeee-0000-0000-0000-000000000001';
select is(pg_temp.stage(), 'jornada_en_ejecucion', 'cerrar la captura no cierra la facturación');
select throws_ok($$
  update public.campaigns_jornadas set status = 'operacion_cerrada' where id = 'eeeeeeee-0000-0000-0000-000000000001'
$$, 'P0001', null, 'la operación no se cierra con órdenes sin entregar');
-- Las entregas se prueban en 007; aquí se cierra la operación sin pasar por ellas
reset role;
update public.campaigns_jornadas set status = 'operacion_cerrada' where id = 'eeeeeeee-0000-0000-0000-000000000001';
set local role authenticated;
select is(pg_temp.stage(), 'facturacion_cerrada', 'jornadas cerradas y órdenes facturadas: Facturación Cerrada');

-- ---------------- Anulación de la factura ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
update public.alegra_invoices set is_voided = true, void_reason = 'Emitida con error' where id = pg_temp.inv('FE-100');
select is(pg_temp.acc('Ana') || '/' || pg_temp.acc('Carlos'), 'pendiente_vincular/pendiente_vincular',
  'al anular la factura las órdenes vuelven a pendiente');
select is(pg_temp.stage(), 'jornada_en_ejecucion', 'y la oportunidad sale de Facturación Cerrada');
select throws_ok($$
  update public.alegra_invoices set notes = 'x' where id = pg_temp.inv('FE-100')
$$, 'P0001', null, 'una factura anulada no se modifica');

-- ---------------- Venta a particular ----------------
insert into public.alegra_invoices (alegra_invoice_number, invoice_date, invoiced_amount, buyer_id)
values ('FE-200', current_date, 150000, 'bbbbbbbb-0000-0000-0000-000000000003');
insert into public.alegra_invoice_orders (invoice_id, order_id, amount_assigned)
values (pg_temp.inv('FE-200'), pg_temp.ord('Pedro'), 150000);
select is(pg_temp.acc('Pedro'), 'factura_vinculada', 'factura al comprador particular');

-- ---------------- Campos de sincronización (solo servidor) ----------------
select throws_ok($$
  update public.alegra_invoices set alegra_total = 1 where id = pg_temp.inv('FE-200')
$$, '42501', null, 'la app no escribe los campos de sincronización con Alegra');
select is(
  (select count(*) from public.v_orders_to_invoice), 0::bigint,
  'las órdenes sin requisitos verificados no aparecen por facturar');

select * from finish();
rollback;
