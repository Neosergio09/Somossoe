-- Pruebas de carga de históricos con contexto mínimo (RF-M06-05).
begin;
create extension if not exists pgtap with schema extensions;
select plan(32);

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

-- Empresa sin convenio en el CRM
insert into public.companies (id, name, nit, nit_dv, is_nit_provisional, sector, payroll_frequency)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Energía Demo SA', '900123456', private.nit_check_digit('900123456'),
        false, 'Servicios', 'quincenal');
insert into public.buyers (id, document_type, document_id, full_name, data_consent_at) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'cc', '1088123456', 'Ana Pérez', now()),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'cc', '1088654321', 'Carlos Ruiz', now()),
  ('bbbbbbbb-0000-0000-0000-000000000003', 'cc', '10001000', 'Pedro Gómez', now());
insert into public.buyers (id, document_type, document_id, full_name) values
  ('bbbbbbbb-0000-0000-0000-000000000009', 'cc', '10009999', 'Sin Autorización');

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.ref(p_ref text) returns uuid language sql as $$
  select id from public.orders where historical_reference = p_ref;
$$;
create function pg_temp.hist(p jsonb, p_items jsonb default '[]') returns uuid language sql as $$
  select public.create_historical_order(
    jsonb_build_object('buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001', 'company_id', 'aaaaaaaa-0000-0000-0000-000000000001',
      'payment_modality', 'nomina_empresa', 'collection_responsible', 'empresa', 'total_amount', 400000,
      'balance_due', 250000, 'historical_stage', 'entregada', 'historical_reference', 'Excel ENERGIA fila 12',
      'installments_count', 2, 'installment_periodicity', 'quincenal', 'first_due_date', current_date + 10) || p,
    p_items);
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

-- ---------------- Permisos y validaciones ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$ select pg_temp.hist('{}') $$, '42501', null, 'Comercial no carga históricos');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select pg_temp.hist('{}') $$, '42501', null, 'Operación no carga históricos');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$ select pg_temp.hist('{"buyer_id": "bbbbbbbb-0000-0000-0000-000000000009"}') $$,
  'P0001', null, 'exige la autorización de datos del comprador');
select throws_ok($$ select pg_temp.hist('{"company_id": null}') $$, 'P0001', null, 'nómina exige empresa');
select throws_ok($$ select pg_temp.hist('{"payment_modality": "contado", "company_id": null}') $$,
  'P0001', null, 'contado se cobra al comprador');
select throws_ok($$ select pg_temp.hist('{"balance_due": 500000}') $$, 'P0001', null, 'el saldo vivo no supera el valor');
select throws_ok($$ select pg_temp.hist('{"installments_count": null}') $$,
  'P0001', null, 'nómina con saldo exige el plan restante');
select throws_ok($$ select pg_temp.hist('{"historical_stage": "venta"}') $$,
  'P0001', null, 'una venta pendiente de producir exige ítems');
select throws_ok($$
  select pg_temp.hist('{}', '[{"item_type": "montura", "frame_description": "X", "quantity": 1, "unit_price": 100000}]')
$$, 'P0001', null, 'los ítems deben sumar el valor total');
select throws_ok($$ select pg_temp.hist('{"historical_reference": " "}') $$, '23514', null, 'exige la referencia de origen');

-- ---------------- Histórico por nómina sin convenio, entregado ----------------
select lives_ok($$ select pg_temp.hist('{}') $$, 'Administración carga un histórico por nómina sin convenio');
select is(
  (select historical_collected_before_migration || '/' || balance_due || '/' || collection_status
   from public.orders where id = pg_temp.ref('Excel ENERGIA fila 12')),
  '150000/250000/parcialmente_recaudado', 'lo recaudado antes de migrar = valor − saldo vivo');
select is(
  (select doc_status || '/' || ops_status || '/' || collection_responsible || '/' || accounting_status
   from public.orders where id = pg_temp.ref('Excel ENERGIA fila 12')),
  'requisitos_verificados/entrega_completa/empresa/pendiente_vincular',
  'entra en la etapa declarada sin inventar las previas');
select results_eq($$
  select installment_number::int, expected_amount from public.order_installments
  where order_id = pg_temp.ref('Excel ENERGIA fila 12') order by installment_number
$$, $$ values (1, 125000::numeric), (2, 125000::numeric) $$, 'el plan restante reparte solo el saldo vivo');
select is(
  (select installment_periodicity::text from public.orders where id = pg_temp.ref('Excel ENERGIA fila 12')),
  'quincenal', 'conserva la periodicidad declarada');
select throws_ok($$ select pg_temp.hist('{"historical_reference": "excel energia FILA 12 "}') $$,
  '23505', null, 'la misma referencia no se carga dos veces');

-- Pagos posteriores siguen la Regla de Oro
insert into public.collections_payments (company_id, payment_date, total_received_bank, bank_reference, support_received)
values ('aaaaaaaa-0000-0000-0000-000000000001', current_date, 125000, 'EN-1', true);
select is(
  (select public.apply_payment((select id from public.collections_payments where bank_reference = 'EN-1'),
                               pg_temp.ref('Excel ENERGIA fila 12'), 125000)),
  1, 'el giro de la empresa abona la primera cuota restante');
select is((select balance_due from public.orders where id = pg_temp.ref('Excel ENERGIA fila 12')), 125000::numeric,
  'el saldo baja con el pago verificado');
select throws_ok($$
  select public.apply_payment((select id from public.collections_payments where bank_reference = 'EN-1'),
                              pg_temp.ref('Excel ENERGIA fila 12'), 1)
$$, 'P0001', null, 'no se asigna más de lo recibido');
select lives_ok($$
  insert into public.portfolio_reclassifications (order_id, reason, new_installments_count, new_periodicity, new_first_due_date)
  values (pg_temp.ref('Excel ENERGIA fila 12'), 'retiro', 1, 'mensual', current_date + 5)
$$, 'un histórico por nómina se puede reclasificar');

select throws_ok($$
  update public.orders set first_due_date = current_date + 40 where id = pg_temp.ref('Excel ENERGIA fila 12')
$$, 'P0001', null, 'el plan de un histórico no se cambia');
select lives_ok($$
  update public.orders set notes = 'Revisado con Fabián' where id = pg_temp.ref('Excel ENERGIA fila 12')
$$, 'las notas de un histórico se pueden editar');

-- ---------------- Contado en producción, ya pagado ----------------
select lives_ok($$
  select pg_temp.hist('{"buyer_id": "bbbbbbbb-0000-0000-0000-000000000002", "company_id": null, "payment_modality": "contado",
    "collection_responsible": "empleado", "total_amount": 300000, "balance_due": 0, "historical_stage": "produccion",
    "historical_reference": "Excel PARTICULAR OCTUBRE fila 4"}')
$$, 'contado particular en producción, sin ítems ni plan');
select is(
  (select ops_status || '/' || collection_status || '/' || coalesce(installments_count::text, 'sin plan')
   from public.orders where id = pg_temp.ref('Excel PARTICULAR OCTUBRE fila 4')),
  'en_produccion/recaudado_total/sin plan', 'queda en producción y recaudado');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  select public.register_historical_delivery(pg_temp.ref('Excel PARTICULAR OCTUBRE fila 4'), current_date, 'Carlos')
$$, '42501', null, 'Comercial no registra entregas');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  select public.register_historical_delivery(pg_temp.ref('Excel ENERGIA fila 12'), current_date, 'Ana')
$$, 'P0001', null, 'la entrega histórica solo aplica a órdenes cargadas en producción');
select throws_ok($$
  select public.register_historical_delivery(pg_temp.ref('Excel PARTICULAR OCTUBRE fila 4'), current_date + 1, 'Carlos')
$$, 'P0001', null, 'la entrega no puede ser futura');
select lives_ok($$
  select public.register_historical_delivery(pg_temp.ref('Excel PARTICULAR OCTUBRE fila 4'), current_date, 'Carlos Ruiz')
$$, 'Operación registra la entrega del histórico');
select is(
  (select ops_status || '/' || historical_delivery_receiver from public.orders where id = pg_temp.ref('Excel PARTICULAR OCTUBRE fila 4')),
  'entrega_completa/Carlos Ruiz', 'queda con entrega completa y receptor');

-- ---------------- Venta pendiente de producir: sigue el flujo normal ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select lives_ok($$
  select pg_temp.hist('{"buyer_id": "bbbbbbbb-0000-0000-0000-000000000003", "company_id": null, "payment_modality": "contado",
    "collection_responsible": "empleado", "total_amount": 200000, "balance_due": 200000, "historical_stage": "venta",
    "historical_reference": "Excel PARTICULAR NOVIEMBRE fila 9"}',
    '[{"item_type": "gafas_completas", "frame_description": "Montura demo", "lens_type": "Monofocal", "quantity": 1, "unit_price": 200000}]')
$$, 'una venta pendiente de producir se carga con sus ítems');
select is(
  (select doc_status || '/' || ops_status || '/' || items_count || '/' || cardinality(release_blockers)
   from public.v_orders where historical_reference = 'Excel PARTICULAR NOVIEMBRE fila 9'),
  'pendiente_soportes/pendiente_liberar/1/2', 'queda en Etapa 07: verificar requisitos y anticipo como cualquier venta');

select is(
  (select count(*) from public.orders where not is_historical_migration and historical_collected_before_migration <> 0),
  0::bigint, 'las órdenes normales no llevan datos de histórico');

select * from finish();
rollback;
