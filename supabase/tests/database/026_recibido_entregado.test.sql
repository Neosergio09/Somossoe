-- Backlog V0.2 · SOE-14/18: lente recibido en SOE con responsable e
-- historial del n.º de pedido del laboratorio.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'direccion@test.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'comercial@test.co'),
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co');
update public.users_profiles set role = 'direccion', active = true where email = 'direccion@test.co';
update public.users_profiles set role = 'comercial', active = true where email = 'comercial@test.co';
update public.users_profiles set role = 'administracion_cartera', active = true where email = 'admin@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';
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
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'mensual', 4, false, 'aprobado', now());
insert into public.campaigns_jornadas (id, deal_id, agreement_id, responsible_user_id, logistics_confirmed, status)
values ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', true, 'en_ejecucion');
insert into public.buyers (id, document_type, document_id, full_name, data_consent_at) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'cc', '1088000001', 'Ana Pérez', now());

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.prod() returns public.order_productions language sql as $$
  select p.* from public.order_productions p join public.orders o on o.id = p.order_id where o.notes = 'Ana';
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
  '[{"item_type": "montura", "frame_description": "Acetato", "quantity": 1, "unit_price": 200000}]');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
update public.orders set requirements_verified = true where notes = 'Ana';
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
insert into public.order_productions (order_id, lab_provider_id, promised_date, lab_order_reference)
select id, '11111111-0000-0000-0000-000000000001', private.today_co() + 7, 'P-100' from public.orders where notes = 'Ana';

-- Envío al laboratorio
select is((pg_temp.prod()).released_by, '00000000-0000-0000-0000-0000000000b1'::uuid, 'el envío queda con quién liberó');
select is((pg_temp.prod()).received_by, null, 'aún no hay recepción');

-- Corrección del pedido
select throws_ok($$
  update public.order_productions set lab_order_reference = 'P-101' where id = (pg_temp.prod()).id
$$, 'P0001', 'Indique el motivo del cambio del n.º de pedido del laboratorio', 'cambiar el pedido exige motivo');
select lives_ok($$
  update public.order_productions set lab_order_reference = 'P-101', lab_reference_change_reason = 'El laboratorio reemitió el pedido'
  where id = (pg_temp.prod()).id
$$, 'Operación corrige el pedido con motivo');
select is((select old_reference || '→' || new_reference || ' · ' || reason from public.production_reference_history),
  'P-100→P-101 · El laboratorio reemitió el pedido', 'el pedido anterior se conserva en el historial');
select is((pg_temp.prod()).lab_reference_change_reason, null, 'el motivo no queda en la producción');

-- Recepción en SOE
select throws_ok($$
  update public.order_productions set received_by = '00000000-0000-0000-0000-0000000000d1' where id = (pg_temp.prod()).id
$$, '42501', null, 'quién recibió no se escribe a mano');
update public.order_productions set status = 'listo_para_entregar', ready_at = private.today_co() where id = (pg_temp.prod()).id;
select is((pg_temp.prod()).received_by, '00000000-0000-0000-0000-0000000000b1'::uuid, 'la recepción queda con quién la registró');
select is((select received_by_name from public.v_productions where id = (pg_temp.prod()).id), (select full_name from public.users_profiles where email = 'operacion@test.co'),
  'la vista muestra quién recibió');
select is((select reference_changes::int from public.v_productions where id = (pg_temp.prod()).id), 1, 'la vista cuenta los cambios del pedido');
update public.order_productions set status = 'en_produccion', ready_at = null where id = (pg_temp.prod()).id;
select is((pg_temp.prod()).received_by, null, 'al devolver a En producción se borra la recepción');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select is((select count(*)::int from public.production_reference_history), 1, 'los usuarios internos ven el historial del pedido');

select * from finish();
rollback;
