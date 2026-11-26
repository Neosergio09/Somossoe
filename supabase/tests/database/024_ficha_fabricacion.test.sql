-- SRS 1.6 · RF-M04-07 y RNF-06: ficha de fabricación (RX/ADD) restringida.
-- Todos los valores son ficticios.
begin;
create extension if not exists pgtap with schema extensions;
select plan(37);

-- ---------------- Preparación (como postgres) ----------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'direccion@test.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'comercial@test.co'),
  ('00000000-0000-0000-0000-0000000000c2', 'comercial2@test.co'),
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co'),
  ('00000000-0000-0000-0000-0000000000e1', 'socio@test.co'),
  ('00000000-0000-0000-0000-0000000000f1', 'super@test.co');
update public.users_profiles set role = 'direccion', active = true where email = 'direccion@test.co';
update public.users_profiles set role = 'comercial', active = true where email in ('comercial@test.co', 'comercial2@test.co');
update public.users_profiles set role = 'administracion_cartera', active = true where email = 'admin@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';
update public.users_profiles set role = 'socio', active = true where email = 'socio@test.co';
update public.users_profiles set role = 'superadmin', active = true where email = 'super@test.co';

insert into public.lab_providers (id, name, active) values ('11111111-0000-0000-0000-000000000001', 'Panoram', true);
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
  ('bbbbbbbb-0000-0000-0000-000000000001', 'cc', '1088123456', 'Ana Pérez', now());

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.ord() returns uuid language sql as $$
  select id from public.orders where notes = 'Ana';
$$;
create function pg_temp.lens() returns uuid language sql as $$
  select i.id from public.order_items i join public.orders o on o.id = i.order_id
  where o.notes = 'Ana' and i.item_type = 'gafas_completas';
$$;
create function pg_temp.frame() returns uuid language sql as $$
  select i.id from public.order_items i join public.orders o on o.id = i.order_id
  where o.notes = 'Ana' and i.item_type = 'montura';
$$;
create function pg_temp.spec() returns uuid language sql as $$
  select spec_id from public.fabrication_spec_status(pg_temp.ord()) where order_item_id = pg_temp.lens();
$$;
-- Fórmula ficticia válida para un progresivo
create function pg_temp.rx(p_od_sphere numeric default -1.25) returns jsonb language sql as $$
  select jsonb_build_object('od_sphere', p_od_sphere, 'od_cylinder', -0.50, 'od_axis', 90, 'od_add', 1.50,
    'os_sphere', -1.00, 'os_add', 1.50, 'pd_total_mm', 62, 'prescription_date', private.today_co() - 2);
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
    'payment_modality', 'nomina_empresa', 'installments_count', 2,
    'first_due_date', (private.today_co() + 35)::text, 'employee_auth_received', true, 'notes', 'Ana'),
  '[{"item_type": "gafas_completas", "frame_description": "Acetato", "lens_type": "Progresivo", "quantity": 1, "unit_price": 500000},
    {"item_type": "montura", "frame_description": "Repuesto", "quantity": 1, "unit_price": 100000}]');

-- ================= 1. Sin acceso directo =================
select throws_ok($$ select * from public.order_fabrication_specs $$, '42501', null,
  'nadie consulta la tabla de fichas directamente');
select throws_ok($$
  insert into public.order_fabrication_specs (order_id, order_item_id, version, source, created_by, od_sphere, os_sphere)
  values (pg_temp.ord(), pg_temp.lens(), 1, 'formula_externa', '00000000-0000-0000-0000-0000000000c1', 0, 0)
$$, '42501', null, 'nadie escribe la tabla de fichas directamente');

-- ================= 2. Captura por Comercial =================
select throws_ok($$ select public.save_fabrication_spec(pg_temp.lens(), pg_temp.rx()) $$, 'P0001',
  'El comprador no ha autorizado el tratamiento de sus datos sensibles: regístrelo antes de guardar la ficha',
  'sin autorización de datos sensibles no se guarda');
select lives_ok($$
  update public.buyers set sensitive_data_consent_at = now() where id = 'bbbbbbbb-0000-0000-0000-000000000001'
$$, 'Comercial registra la autorización de datos sensibles');

select throws_ok($$ select public.save_fabrication_spec(pg_temp.frame(), pg_temp.rx()) $$, 'P0001',
  'Solo los ítems con lente llevan ficha de fabricación', 'una montura no lleva ficha');
select throws_ok($$ select public.save_fabrication_spec(pg_temp.lens(), pg_temp.rx() - 'od_add') $$, 'P0001', null,
  'un progresivo exige ADD en ambos ojos');
select throws_ok($$ select public.save_fabrication_spec(pg_temp.lens(), pg_temp.rx(-1.13)) $$, '23514', null,
  'la esfera va en pasos de 0.25');
select throws_ok($$ select public.save_fabrication_spec(pg_temp.lens(), pg_temp.rx() - 'od_cylinder') $$, '23514', null,
  'eje sin cilindro se rechaza');
select throws_ok($$
  select public.save_fabrication_spec(pg_temp.lens(), pg_temp.rx() || jsonb_build_object('prescription_date', private.today_co() + 1))
$$, 'P0001', 'La fecha de la fórmula no puede ser futura', 'la fecha de la fórmula no es futura');

select pg_temp.login('00000000-0000-0000-0000-0000000000c2');
select throws_ok($$ select public.save_fabrication_spec(pg_temp.lens(), pg_temp.rx()) $$, '42501', null,
  'otro Comercial no registra la ficha');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select lives_ok($$ select public.save_fabrication_spec(pg_temp.lens(), pg_temp.rx()) $$, 'quien registró la orden guarda la ficha');
select is((select version::int || '/' || (validated_at is null) from public.fabrication_spec_status(pg_temp.ord())
           where order_item_id = pg_temp.lens()), '1/true', 'versión 1 pendiente de validar');
select throws_ok($$ select public.save_fabrication_spec(pg_temp.lens(), pg_temp.rx()) $$, 'P0001',
  'Indique el motivo de la corrección', 'corregir exige motivo');

-- ================= 3. Candado de liberación =================
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
update public.orders set requirements_verified = true where id = pg_temp.ord();
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_like($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date)
  values (pg_temp.ord(), '11111111-0000-0000-0000-000000000001', private.today_co() + 7)
$$, '%Ficha de fabricación validada por Operación (1 ítem con lente sin ficha validada)%',
  'sin ficha validada no se libera');

-- ================= 4. Quién lee =================
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$ select public.get_fabrication_spec(pg_temp.lens(), 'validacion') $$, '42501', null,
  'Comercial no consulta con finalidad de validación');
select is((public.get_fabrication_spec(pg_temp.lens(), 'captura') ->> 'od_sphere')::numeric, -1.25,
  'quien registró la orden la consulta para capturar');
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select throws_ok($$ select public.get_fabrication_spec(pg_temp.lens(), 'captura') $$, '42501', null, 'Dirección no la consulta');
select pg_temp.login('00000000-0000-0000-0000-0000000000e1');
select throws_ok($$ select public.get_fabrication_spec(pg_temp.lens(), 'captura') $$, '42501', null, 'Socio no la consulta');
select pg_temp.login('00000000-0000-0000-0000-0000000000f1');
select throws_ok($$ select public.get_fabrication_spec(pg_temp.lens(), 'captura') $$, '42501', null, 'el Super administrador no la consulta');
select throws_ok($$ select public.save_fabrication_spec(pg_temp.lens(), pg_temp.rx(), 'x') $$, '42501', null, 'el Super administrador no la registra');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$ select public.get_fabrication_spec(pg_temp.lens(), 'captura') $$, '42501', null, 'Administración no la consulta');

-- ================= 5. Validación por Operación =================
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$ select public.validate_fabrication_spec(pg_temp.spec()) $$, '42501', null, 'Comercial no valida');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select is((public.get_fabrication_spec(pg_temp.lens(), 'validacion') ->> 'od_add')::numeric, 1.50, 'Operación la consulta para validar');
select lives_ok($$ select public.validate_fabrication_spec(pg_temp.spec()) $$, 'Operación valida');

-- Una versión nueva antes de liberar anula la validación
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select lives_ok($$ select public.save_fabrication_spec(pg_temp.lens(), pg_temp.rx(-1.50), 'Error de transcripción') $$,
  'Comercial corrige con motivo antes de liberar');
select is((select version::int || '/' || (validated_at is null) from public.fabrication_spec_status(pg_temp.ord())
           where order_item_id = pg_temp.lens()), '2/true', 'la versión 2 exige validar de nuevo');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select public.validate_fabrication_spec(pg_temp.spec());
select lives_ok($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date)
  values (pg_temp.ord(), '11111111-0000-0000-0000-000000000001', private.today_co() + 7)
$$, 'con la ficha validada se libera');

-- ================= 6. Después de liberar =================
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$ select public.get_fabrication_spec(pg_temp.lens(), 'captura') $$, '42501', null,
  'liberada la orden, Comercial ya no la consulta');
select throws_ok($$ select public.save_fabrication_spec(pg_temp.lens(), pg_temp.rx(), 'x') $$, '42501', null,
  'liberada la orden, Comercial ya no la corrige');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select lives_ok($$ select public.save_fabrication_spec(pg_temp.lens(), pg_temp.rx(-1.75), 'El laboratorio detectó un error') $$,
  'Operación corrige con motivo tras liberar');
select isnt((select validated_at from public.fabrication_spec_status(pg_temp.ord()) where order_item_id = pg_temp.lens()),
  null, 'la corrección de Operación queda validada');

-- ================= 7. Bitácoras y exclusiones =================
select is((select count(*)::int from public.fabrication_spec_events where order_id = pg_temp.ord()), 6,
  'Operación ve los 6 cambios (3 versiones y 3 validaciones)');
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select is((select count(*)::int from public.fabrication_spec_access_logs where order_id = pg_temp.ord()), 2,
  'Dirección ve las 2 lecturas registradas');
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select is((select count(*)::int from public.fabrication_spec_access_logs), 0, 'Comercial no ve la bitácora de lecturas');
update public.buyers set sensitive_data_consent_at = null where id = 'bbbbbbbb-0000-0000-0000-000000000001';
select isnt((select sensitive_data_consent_at from public.buyers where id = 'bbbbbbbb-0000-0000-0000-000000000001'), null,
  'la autorización de datos sensibles no se retira desde la aplicación');

reset role;
select is((select count(*)::int from public.audit_logs where table_name = 'order_fabrication_specs'), 0,
  'la ficha no pasa por la auditoría general');
select is((select count(*)::int from public.order_fabrication_specs where order_item_id = pg_temp.lens()), 3,
  'las tres versiones se conservan');

select * from finish();
rollback;
