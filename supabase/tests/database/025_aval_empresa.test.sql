-- Backlog V0.2 · SOE-17: aval de la empresa por orden de nómina, con
-- historial, rechazo, registro por listado y anulación.
begin;
create extension if not exists pgtap with schema extensions;
select plan(28);

-- ---------------- Preparación (como postgres) ----------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'direccion@test.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'comercial@test.co'),
  ('00000000-0000-0000-0000-0000000000c2', 'comercial2@test.co'),
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co');
update public.users_profiles set role = 'direccion', active = true where email = 'direccion@test.co';
update public.users_profiles set role = 'comercial', active = true where email in ('comercial@test.co', 'comercial2@test.co');
update public.users_profiles set role = 'administracion_cartera', active = true where email = 'admin@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';
-- Esta prueba no cubre la ficha de fabricación
update public.system_settings set value = 0 where key = 'require_fabrication_spec';

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
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'mensual', 4, true, 'aprobado', now());
insert into public.campaigns_jornadas (id, deal_id, agreement_id, responsible_user_id, logistics_confirmed, status)
values ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', true, 'en_ejecucion');
insert into public.buyers (id, document_type, document_id, full_name, data_consent_at) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'cc', '1088000001', 'Ana Pérez', now()),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'cc', '1088000002', 'Carlos Ruiz', now()),
  ('bbbbbbbb-0000-0000-0000-000000000003', 'cc', '1088000003', 'Laura Díaz', now()),
  ('bbbbbbbb-0000-0000-0000-000000000004', 'cc', '1088000004', 'Pedro Gil', now()),
  ('bbbbbbbb-0000-0000-0000-000000000005', 'cc', '1088000005', 'Sara Mesa', now());

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.ord(p_notes text) returns uuid language sql as $$
  select id from public.orders where notes = p_notes;
$$;
create function pg_temp.new_order(p_buyer uuid, p_notes text, p_modality text default 'nomina_empresa', p_extra jsonb default '{}')
returns uuid language sql as $$
  select public.create_order(
    jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001', 'buyer_id', p_buyer,
      'payment_modality', p_modality, 'notes', p_notes)
    || case when p_modality = 'nomina_empresa'
         then jsonb_build_object('installments_count', 2, 'first_due_date', (private.today_co() + 35)::text,
                                 'employee_auth_received', true)
         else '{}'::jsonb end
    || p_extra,
    '[{"item_type": "montura", "frame_description": "Acetato", "quantity": 1, "unit_price": 200000}]');
$$;
create function pg_temp.decision(p_notes text) returns text language sql as $$
  select coalesce(company_approval_decision, '-') || '/' || hr_approval_received || '/' || doc_status
  from public.orders where notes = p_notes;
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select pg_temp.new_order('bbbbbbbb-0000-0000-0000-000000000001', 'Ana');
select pg_temp.new_order('bbbbbbbb-0000-0000-0000-000000000002', 'Carlos');
select pg_temp.new_order('bbbbbbbb-0000-0000-0000-000000000004', 'Contado', 'contado');
select pg_temp.new_order('bbbbbbbb-0000-0000-0000-000000000005', 'Con aval', 'nomina_empresa',
  '{"hr_approval_received": true}');
select pg_temp.login('00000000-0000-0000-0000-0000000000c2');
select pg_temp.new_order('bbbbbbbb-0000-0000-0000-000000000003', 'Laura');

-- ================= 1. Registro por listado =================
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select is(pg_temp.decision('Ana'), '-/false/pendiente_soportes', 'la venta de nómina nace pendiente del aval');
select throws_ok($$
  update public.orders set hr_approval_received = true where id = pg_temp.ord('Ana')
$$, 'P0001', null, 'el aval ya no se marca directamente en la orden');
select throws_ok($$
  select public.record_company_approval(array[pg_temp.ord('Ana'), pg_temp.ord('Laura')], 'aprobada', private.today_co(), 'Listado')
$$, '42501', null, 'Comercial no registra el aval de órdenes de otro Comercial');
select is(pg_temp.decision('Ana'), '-/false/pendiente_soportes', 'el listado rechazado no deja nada a medias');
select throws_ok($$
  select public.record_company_approval(array[pg_temp.ord('Ana')], 'aprobada', private.today_co() + 1, 'Listado')
$$, 'P0001', null, 'la fecha de la decisión no es futura');
select throws_ok($$
  select public.record_company_approval(array[pg_temp.ord('Contado')], 'aprobada', private.today_co(), 'Listado')
$$, 'P0001', null, 'una venta de contado no requiere aval');
select lives_ok($$
  select public.record_company_approval(array[pg_temp.ord('Ana'), pg_temp.ord('Carlos')], 'aprobada',
    private.today_co() - 1, 'Listado RRHH 20-nov')
$$, 'Comercial registra el aval de sus órdenes con un solo listado');
select is(pg_temp.decision('Carlos'), 'aprobada/true/pendiente_soportes', 'la orden queda con el aval aprobado');
select is((select count(distinct batch_id)::int from public.order_company_approvals
           where order_id in (pg_temp.ord('Ana'), pg_temp.ord('Carlos'))), 1, 'las dos decisiones son del mismo listado');
select throws_ok($$
  select public.record_company_approval(array[pg_temp.ord('Ana')], 'aprobada', private.today_co(), 'Otra vez')
$$, 'P0001', null, 'no se repite la misma decisión');
select is((select reference from public.order_company_approvals where order_id = pg_temp.ord('Con aval')),
  'Registrado al crear la orden', 'el aval marcado al crear la orden queda como decisión');

-- ================= 2. Rechazo sobre una orden verificada =================
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select lives_ok($$ update public.orders set requirements_verified = true where id = pg_temp.ord('Ana') $$,
  'Administración verifica la orden con aval');
select throws_ok($$
  select public.record_company_approval(array[pg_temp.ord('Ana')], 'rechazada', private.today_co(), 'Correo RRHH')
$$, 'P0001', 'Indique el motivo del rechazo', 'rechazar exige motivo');
select lives_ok($$
  select public.record_company_approval(array[pg_temp.ord('Ana')], 'rechazada', private.today_co(), 'Correo RRHH',
    null, 'Empleada en periodo de prueba')
$$, 'Administración registra el rechazo de la empresa');
select is(pg_temp.decision('Ana'), 'rechazada/false/pendiente_soportes', 'el rechazo retira la verificación');
select ok((select 'Aval de RRHH' = any (missing_requirements) from public.v_orders where id = pg_temp.ord('Ana')),
  'el aval vuelve a faltar en los requisitos');
select throws_ok($$ update public.orders set requirements_verified = true where id = pg_temp.ord('Ana') $$,
  'P0001', null, 'una orden rechazada no se verifica');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  select public.record_company_approval(array[pg_temp.ord('Ana')], 'aprobada', private.today_co(), 'Listado')
$$, '42501', null, 'Operación no registra el aval');

-- ================= 3. La empresa aprueba después; anulación =================
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select lives_ok($$
  select public.record_company_approval(array[pg_temp.ord('Ana')], 'aprobada', private.today_co(), 'Listado corregido')
$$, 'la empresa aprueba después del rechazo');
select is((select count(*)::int from public.order_company_approvals where order_id = pg_temp.ord('Ana')), 3,
  'el historial conserva aprobación, rechazo y nueva aprobación');
select throws_ok($$
  select public.void_company_approval(
    (select id from public.order_company_approvals where order_id = pg_temp.ord('Ana') and decision = 'rechazada'), 'x')
$$, '42501', null, 'Comercial no anula una decisión que registró otra persona');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  select public.void_company_approval(
    (select id from public.order_company_approvals where order_id = pg_temp.ord('Ana') and decision = 'rechazada'), 'x')
$$, 'P0001', 'Solo se anula la última decisión vigente', 'solo se anula la última decisión');
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select lives_ok($$
  select public.void_company_approval(
    (select id from public.order_company_approvals where order_id = pg_temp.ord('Ana') and reference = 'Listado corregido'),
    'Se registró en la orden equivocada')
$$, 'quien la registró anula su decisión');
select is(pg_temp.decision('Ana'), 'rechazada/false/pendiente_soportes', 'al anular, vuelve a regir la decisión anterior');

-- ================= 4. Orden liberada =================
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
update public.orders set requirements_verified = true where id = pg_temp.ord('Carlos');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select lives_ok($$
  insert into public.order_productions (order_id, lab_provider_id, promised_date)
  values (pg_temp.ord('Carlos'), '11111111-0000-0000-0000-000000000001', private.today_co() + 7)
$$, 'con aval y requisitos verificados se libera');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  select public.record_company_approval(array[pg_temp.ord('Carlos')], 'rechazada', private.today_co(), 'Correo', null, 'Tarde')
$$, 'P0001', null, 'una orden liberada no admite rechazo');

-- ================= 5. Lectura y auditoría =================
select pg_temp.login('00000000-0000-0000-0000-0000000000c2');
select ok((select count(*) from public.order_company_approvals) > 0, 'los usuarios internos ven el historial de avales');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select ok((select count(*) from public.audit_logs where table_name = 'order_company_approvals') > 0,
  'las decisiones quedan en la auditoría');

select * from finish();
rollback;
