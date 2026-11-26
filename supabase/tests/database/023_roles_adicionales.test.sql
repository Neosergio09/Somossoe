-- SRS 1.6 · §3.3: roles adicionales por usuario (unión de permisos),
-- perfil Gestión y rol Costos (auxiliar contable).
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

-- ---------------- Preparación (como postgres) ----------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'direccion@test.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'comercial@test.co'),
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co'),
  ('00000000-0000-0000-0000-0000000000f1', 'gestion@test.co'),
  ('00000000-0000-0000-0000-0000000000f2', 'auxiliar@test.co');
update public.users_profiles set role = 'direccion', active = true where email = 'direccion@test.co';
update public.users_profiles set role = 'comercial', active = true where email = 'comercial@test.co';
update public.users_profiles set role = 'administracion_cartera', active = true where email = 'admin@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'gestion@test.co';
update public.users_profiles set role = 'costos', active = true where email = 'auxiliar@test.co';

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
create function pg_temp.cost(p_order uuid, p_source text) returns void language sql as $$
  insert into public.order_costs (order_id, component, amount, basis, source)
  values (p_order, 'lente', 100000, 'verificado', p_source);
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
  '[{"item_type": "lentes", "lens_type": "Monofocal", "quantity": 1, "unit_price": 300000}]');

-- ---------------- Asignar roles adicionales (Dirección) ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000f1');
select throws_ok($$ select pg_temp.cost(pg_temp.ord(), 'Factura 1') $$, '42501', null,
  'Operación sin rol adicional no registra costos');
select is((select count(*)::int from public.v_order_margins), 0, 'Operación sin rol adicional no ve márgenes');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
update public.users_profiles set extra_roles = '{costos}' where email = 'gestion@test.co';
select is((select extra_roles from public.users_profiles where email = 'gestion@test.co'), '{}'::public.app_role[],
  'Administración no asigna roles');

select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select throws_ok($$
  update public.users_profiles set extra_roles = '{direccion}' where email = 'gestion@test.co'
$$, '23514', null, 'Dirección no se asigna como rol adicional');
select throws_ok($$
  update public.users_profiles set extra_roles = '{socio}' where email = 'gestion@test.co'
$$, '23514', null, 'Socio no se asigna como rol adicional');
select throws_ok($$
  update public.users_profiles set extra_roles = '{operacion}' where email = 'gestion@test.co'
$$, '23514', null, 'el rol principal no se repite como adicional');
select lives_ok($$
  update public.users_profiles set extra_roles = '{costos,administracion_cartera,costos}' where email = 'gestion@test.co'
$$, 'Dirección asigna el perfil Gestión (Administración + Costos sobre Operación)');
select is((select extra_roles from public.users_profiles where email = 'gestion@test.co'),
  '{administracion_cartera,costos}'::public.app_role[], 'los roles adicionales se guardan sin repetir y ordenados');
select throws_ok($$
  update public.users_profiles set role = null where email = 'gestion@test.co'
$$, '23514', null, 'sin rol principal no hay roles adicionales');

-- ---------------- Unión de permisos (usuario Gestión) ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000f1');
select is(private.has_role('operacion'), true, 'Gestión conserva su rol principal');
select is(private.has_role('administracion_cartera'), true, 'Gestión tiene el rol adicional de Administración');
select is(private.has_role('direccion'), false, 'Gestión no es Dirección');
select is(private.can_view_costs(), true, 'Gestión ve costos por su rol Costos');
select lives_ok($$ select pg_temp.cost(pg_temp.ord(), 'Factura 1') $$, 'Gestión registra un costo');
select is((select count(*)::int from public.v_order_margins), 1, 'Gestión ve el margen de la orden');
select lives_ok($$
  update public.orders set requirements_verified = true where id = pg_temp.ord()
$$, 'Gestión verifica requisitos como Administración');
select is((select doc_status::text from public.orders where id = pg_temp.ord()), 'requisitos_verificados',
  'la verificación quedó aplicada');
select is((select count(*)::int from public.audit_logs where table_name = 'order_costs') > 0, true,
  'Gestión ve la auditoría de costos');

-- ---------------- Rol Costos como principal ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000f2');
select is(private.is_internal_user(), true, 'el rol Costos es un usuario interno');
select is((select count(*)::int from public.orders), 1, 'Costos consulta las órdenes');
select lives_ok($$ select pg_temp.cost(pg_temp.ord(), 'Factura 2') $$, 'Costos registra un costo');
update public.orders set requirements_verified = false where id = pg_temp.ord();
select is((select doc_status::text from public.orders where id = pg_temp.ord()), 'requisitos_verificados',
  'Costos no modifica la orden');

-- ---------------- Otros roles siguen sin costos ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select is((select count(*)::int from public.order_costs), 0, 'Administración sola no ve costos');
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select is((select count(*)::int from public.order_costs), 0, 'Comercial no ve costos');

select * from finish();
rollback;
