-- Pruebas de compradores, órdenes, ítems y plan de cuotas (Etapa 07).
begin;
create extension if not exists pgtap with schema extensions;
select plan(39);

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

insert into public.companies (id, name, nit, nit_dv, is_nit_provisional, sector, total_employees, payroll_frequency)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Marisol SAS', '900123456',
        private.nit_check_digit('900123456'), false, 'Manufactura', 120, 'quincenal');

insert into public.deals_opportunities (id, company_id, city_id, assigned_user_id, deal_name_branch, origin_code,
  stage, target_employees_n, estimated_close_date, tentative_campaign_date)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        (select id from public.cities where name = 'Medellín'),
        '00000000-0000-0000-0000-0000000000c1', 'Marisol - Medellín', 'referido', 'convenio_firmado', 100,
        current_date + 10, current_date + 5);

insert into public.agreements_convenios (id, company_id, payroll_frequency, max_installments,
  hr_approval_required, valid_from, valid_until, status, approved_at)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        'quincenal', 6, true, current_date - 30, current_date + 365, 'aprobado', now());

insert into public.campaigns_jornadas (id, deal_id, agreement_id, responsible_user_id, logistics_confirmed, status)
values
  ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', true, 'en_ejecucion'),
  ('eeeeeeee-0000-0000-0000-000000000002', 'dddddddd-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', false, 'programada');

insert into public.campaign_sessions (id, campaign_id, session_date, start_time, end_time, responsible_user_id)
values ('ffffffff-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000001',
        current_date, '08:00', '12:00', '00000000-0000-0000-0000-0000000000b1');

insert into public.campaign_attendance (campaign_id, session_id, full_name, document_id)
values ('eeeeeeee-0000-0000-0000-000000000001', 'ffffffff-0000-0000-0000-000000000001',
        'Ana Pérez', '1088123456');

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.buyer(p_doc text) returns uuid language sql as $$
  select id from public.buyers where document_id = p_doc;
$$;

create function pg_temp.payroll_order() returns uuid language sql as $$
  select id from public.orders where notes = 'Nómina Ana';
$$;

create function pg_temp.cash_order() returns uuid language sql as $$
  select id from public.orders where notes = 'Contado particular';
$$;


set local role authenticated;

-- ---------------- Comprador ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  insert into public.buyers (document_type, document_id, full_name) values ('cc', '999999', 'X')
$$, '42501', null, 'operación no registra compradores');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select lives_ok($$
  insert into public.buyers (document_type, document_id, full_name, phone)
  values ('cc', '1.088.123.456', 'Ana Pérez', '3001234567')
$$, 'comercial registra al comprador');
select is(pg_temp.buyer('1088123456') is not null, true, 'el documento se guarda sin puntos');

select throws_ok($$
  select public.create_order(
    jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001',
      'buyer_id', pg_temp.buyer('1088123456'), 'payment_modality', 'contado'),
    jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'Ray-Ban',
      'quantity', 1, 'unit_price', 100000)))
$$, 'P0001', null, 'sin autorización de datos no se crea la orden');

update public.buyers set data_consent_at = now() where document_id = '1088123456';
select is(
  (select data_consent_by from public.buyers where document_id = '1088123456'),
  '00000000-0000-0000-0000-0000000000c1'::uuid,
  'la autorización de datos registra quién la tomó'
);

-- ---------------- Creación de la orden de jornada ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  select public.create_order(
    jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001',
      'buyer_id', pg_temp.buyer('1088123456'), 'payment_modality', 'contado'),
    jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'X',
      'quantity', 1, 'unit_price', 1)))
$$, '42501', null, 'operación no crea órdenes');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  select public.create_order(
    jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000002',
      'buyer_id', pg_temp.buyer('1088123456'), 'payment_modality', 'contado'),
    jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'X',
      'quantity', 1, 'unit_price', 1)))
$$, 'P0001', null, 'no se crean órdenes en una jornada Programada');

select throws_ok($$
  select public.create_order(
    jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001',
      'buyer_id', pg_temp.buyer('1088123456'), 'payment_modality', 'nomina_empresa',
      'installments_count', 7, 'first_due_date', '2026-12-15'),
    jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'X',
      'quantity', 1, 'unit_price', 1)))
$$, 'P0001', null, 'no se superan las cuotas del convenio');

select throws_ok($$
  select public.create_order(
    jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001',
      'buyer_id', pg_temp.buyer('1088123456'), 'payment_modality', 'contado'),
    '[]'::jsonb)
$$, 'P0001', null, 'la orden necesita al menos un ítem');

select lives_ok($$
  select public.create_order(
    jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001',
      'buyer_id', pg_temp.buyer('1088123456'), 'payment_modality', 'nomina_empresa',
      'installments_count', 3, 'first_due_date', '2026-12-15', 'notes', 'Nómina Ana',
      -- intento de inyectar contexto y estados: la BD los ignora
      'company_id', null, 'requirements_verified', true),
    jsonb_build_array(
      jsonb_build_object('item_type', 'gafas_completas', 'frame_description', 'Montura acetato',
        'lens_type', 'Progresivo', 'lens_filter', 'Antirreflejo', 'quantity', 1, 'unit_price', 350000),
      jsonb_build_object('item_type', 'montura', 'frame_description', 'Montura de repuesto',
        'quantity', 1, 'unit_price', 250001)))
$$, 'comercial crea la orden por nómina con sus ítems');

select results_eq($$
  select company_id, agreement_id, installment_periodicity::text, collection_responsible::text,
         total_amount, balance_due, doc_status::text
  from public.orders where id = pg_temp.payroll_order()
$$, $$
  values ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, 'cccccccc-0000-0000-0000-000000000001'::uuid,
          'quincenal', 'empresa', 600001::numeric, 600001::numeric, 'pendiente_soportes')
$$, 'la orden hereda empresa, convenio y periodicidad; el total es la suma de los ítems');

select results_eq($$
  select installment_number::int, due_date, expected_amount
  from public.order_installments where order_id = pg_temp.payroll_order() order by installment_number
$$, $$
  values (1, '2026-12-15'::date, 200001::numeric),
         (2, '2026-12-30'::date, 200000::numeric),
         (3, '2027-01-15'::date, 200000::numeric)
$$, 'el plan quincenal alterna 15 y fin de mes y reparte el residuo en la primera cuota');

select is(
  (select buyer_id from public.campaign_attendance where document_id = '1088123456'),
  pg_temp.buyer('1088123456'),
  'la asistencia queda vinculada al comprador'
);
select is(
  (select current_company_id from public.buyers where document_id = '1088123456'),
  'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
  'el comprador queda asociado a la empresa'
);

-- ---------------- Verificación de requisitos ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  update public.orders set requirements_verified = true where id = pg_temp.payroll_order()
$$, 'P0001', null, 'no se verifica sin autorización del empleado ni aval de RRHH');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  update public.orders set requirements_verified = true where id = pg_temp.payroll_order()
$$, '42501', null, 'comercial no verifica requisitos');
select lives_ok($$
  update public.orders set employee_auth_received = true, hr_approval_received = true
  where id = pg_temp.payroll_order()
$$, 'comercial registra la autorización del empleado y el aval de RRHH');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select lives_ok($$
  update public.orders set requirements_verified = true where id = pg_temp.payroll_order()
$$, 'Administración verifica los requisitos');
select results_eq($$
  select doc_status::text, requirements_verified_by from public.orders where id = pg_temp.payroll_order()
$$, $$ values ('requisitos_verificados', '00000000-0000-0000-0000-0000000000a1'::uuid) $$,
  'el estado documental se deriva de la verificación');

-- ---------------- Después de verificar ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  update public.orders set notes = 'cambio' where id = pg_temp.payroll_order()
$$, '42501', null, 'comercial ya no edita la orden verificada');
select throws_ok($$
  insert into public.order_items (order_id, item_type, description, quantity, unit_price)
  values (pg_temp.payroll_order(), 'otro', 'Estuche', 1, 30000)
$$, '42501', null, 'comercial ya no agrega ítems a la orden verificada');
select throws_ok($$
  update public.orders set is_cancelled = true, cancel_reason = 'x' where id = pg_temp.payroll_order()
$$, '42501', null, 'comercial ya no anula la orden verificada');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select lives_ok($$
  insert into public.order_items (order_id, item_type, description, quantity, unit_price)
  values (pg_temp.payroll_order(), 'otro', 'Estuche', 2, 15000)
$$, 'Administración agrega un ítem a la orden verificada');
select results_eq($$
  select (select total_amount from public.orders where id = pg_temp.payroll_order()),
         (select sum(expected_amount) from public.order_installments where order_id = pg_temp.payroll_order())
$$, $$ values (630001::numeric, 630001::numeric) $$,
  'el total y el plan de cuotas se recalculan');
select throws_ok($$
  update public.orders set employee_auth_received = false where id = pg_temp.payroll_order()
$$, 'P0001', null, 'una orden verificada no puede quedar sin sus requisitos');

select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select throws_ok($$
  update public.orders set prepayment_exception_reason = 'Cliente frecuente' where id = pg_temp.payroll_order()
$$, '23514', null, 'la excepción de anticipo solo aplica a contado');

-- ---------------- Venta Directa de contado sin empresa ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
insert into public.buyers (document_type, document_id, full_name, email, data_consent_at)
values ('ce', 'E123456', 'Pedro Gómez', 'pedro@correo.co', now());

select lives_ok($$
  select public.create_order(
    jsonb_build_object('buyer_id', pg_temp.buyer('E123456'), 'payment_modality', 'contado',
      'installments_count', 4, 'notes', 'Contado particular'),
    jsonb_build_array(jsonb_build_object('item_type', 'lentes', 'lens_type', 'Monofocal',
      'quantity', 2, 'unit_price', 90000)))
$$, 'venta directa de contado a un particular');
select results_eq($$
  select company_id, collection_responsible::text, installments_count::int, total_amount,
         (select count(*) from public.order_installments i where i.order_id = o.id)::int
  from public.orders o where id = pg_temp.cash_order()
$$, $$ values (null::uuid, 'empleado', null::int, 180000::numeric, 0) $$,
  'contado: sin empresa, cobro al comprador y sin plan de cuotas');

select throws_ok($$
  update public.orders set payment_modality = 'nomina_empresa', installments_count = 2,
    first_due_date = '2026-12-31' where id = pg_temp.cash_order()
$$, 'P0001', null, 'sin empresa no hay descuento de nómina');

select throws_ok($$
  update public.orders set prepayment_exception_reason = 'Urgente' where id = pg_temp.cash_order()
$$, '42501', null, 'comercial no autoriza excepción de anticipo');
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select lives_ok($$
  update public.orders set prepayment_exception_reason = 'Urgente' where id = pg_temp.cash_order()
$$, 'Dirección autoriza la excepción de anticipo');
select is(
  (select prepayment_exception_by from public.orders where id = pg_temp.cash_order()),
  '00000000-0000-0000-0000-0000000000d1'::uuid,
  'la excepción registra quién la autorizó'
);

-- ---------------- Venta Directa por nómina con convenio ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select lives_ok($$
  select public.create_order(
    jsonb_build_object('company_id', 'aaaaaaaa-0000-0000-0000-000000000001',
      'agreement_id', 'cccccccc-0000-0000-0000-000000000001',
      'buyer_id', pg_temp.buyer('1088123456'), 'payment_modality', 'nomina_empresa',
      'installments_count', 2, 'first_due_date', '2027-01-31', 'notes', 'Directa nómina'),
    jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'Metálica',
      'quantity', 1, 'unit_price', 100000)))
$$, 'venta directa por nómina con convenio aprobado y vigente');
select results_eq($$
  select due_date from public.order_installments i join public.orders o on o.id = i.order_id
  where o.notes = 'Directa nómina' order by installment_number
$$, $$ values ('2027-01-31'::date), ('2027-02-15'::date) $$,
  'quincenal desde fin de mes: la siguiente cuota es el 15');

-- ---------------- Anulación ----------------
select throws_ok($$
  update public.orders set is_cancelled = true where id = pg_temp.cash_order()
$$, '23514', null, 'la anulación exige motivo');
select lives_ok($$
  update public.orders set is_cancelled = true, cancel_reason = 'Cliente desistió' where id = pg_temp.cash_order()
$$, 'comercial anula una orden sin verificar ni pagos');
select throws_ok($$
  update public.orders set notes = 'otra' where id = pg_temp.cash_order()
$$, 'P0001', null, 'una orden anulada no se modifica');
select throws_ok($$
  delete from public.orders where id = pg_temp.cash_order()
$$, '42501', null, 'las órdenes no se borran');

select throws_ok($$
  update public.buyers set document_id = '1088000000' where document_id = '1088123456'
$$, 'P0001', null, 'el documento de un comprador con órdenes no se cambia');

select * from finish();
rollback;
