-- Pruebas de propiedad comercial y cancelación de jornadas.
begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

-- ---------------- Preparación (como postgres) ----------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'direccion@test.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'laura@test.co'),
  ('00000000-0000-0000-0000-0000000000c2', 'pablo@test.co'),
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co');
update public.users_profiles set role = 'direccion', active = true where email = 'direccion@test.co';
update public.users_profiles set role = 'comercial', active = true where email in ('laura@test.co', 'pablo@test.co');
update public.users_profiles set role = 'administracion_cartera', active = true where email = 'admin@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';

-- Empresa de Laura (c1) y empresa sin ejecutivo
insert into public.companies (id, name, sector, payroll_frequency, assigned_user_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Empresa de Laura', 'Retail', 'mensual', '00000000-0000-0000-0000-0000000000c1'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'Empresa libre', 'Retail', 'mensual', null);

insert into public.deals_opportunities (id, company_id, city_id, assigned_user_id, deal_name_branch, origin_code,
  stage, next_action, next_action_due_date, next_action_owner_id)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        (select id from public.cities where name = 'Pereira'), '00000000-0000-0000-0000-0000000000c1',
        'Laura - Pereira', 'referido', 'prospecto', 'Llamar', current_date + 3, '00000000-0000-0000-0000-0000000000c1');

insert into public.agreements_convenios (id, company_id, payroll_frequency, max_installments, status, approved_at)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'mensual', 4, 'aprobado', now());

insert into public.campaigns_jornadas (id, deal_id, agreement_id, responsible_user_id, status) values
  ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', 'programada'),
  ('eeeeeeee-0000-0000-0000-000000000002', 'dddddddd-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', 'programada');

insert into public.buyers (id, document_type, document_id, full_name, data_consent_at)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'cc', '1088123456', 'Ana Pérez', now());

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.laura_order() returns uuid language sql as $$
  select id from public.orders where notes = 'Orden de Laura';
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

-- ---------------- Empresas ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c2');
select is_empty($$
  update public.companies set sector = 'Otro' where id = 'aaaaaaaa-0000-0000-0000-000000000001' returning id
$$, 'Pablo no edita la empresa de Laura');
select throws_ok($$
  insert into public.contacts (company_id, full_name, role_title, area, email)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'X', 'Y', 'rrhh', 'x@y.co')
$$, '42501', null, 'Pablo no agrega contactos a la empresa de Laura');
select throws_ok($$
  insert into public.company_branches (company_id, name, city_id)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'Sede 2', (select id from public.cities where name = 'Pereira'))
$$, '42501', null, 'Pablo no agrega sedes a la empresa de Laura');
select throws_ok($$
  insert into public.companies (name, sector, assigned_user_id)
  values ('Para Laura', 'Retail', '00000000-0000-0000-0000-0000000000c1')
$$, '42501', null, 'Pablo no crea empresas asignadas a otro');
select lives_ok($$
  update public.companies set assigned_user_id = '00000000-0000-0000-0000-0000000000c2'
  where id = 'aaaaaaaa-0000-0000-0000-000000000002'
$$, 'Pablo se asigna una empresa sin ejecutivo');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select is_empty($$
  update public.companies set sector = 'Otro' where id = 'aaaaaaaa-0000-0000-0000-000000000002' returning id
$$, 'una vez asignada, Laura ya no la edita');
select throws_ok($$
  update public.companies set assigned_user_id = '00000000-0000-0000-0000-0000000000c2'
  where id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, '42501', null, 'Laura no le pasa su empresa a otro Comercial');
select lives_ok($$
  insert into public.contacts (company_id, full_name, role_title, area, email)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'Carolina', 'RRHH', 'rrhh', 'c@y.co')
$$, 'Laura agrega contactos a su empresa');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select isnt_empty($$
  update public.companies set sector = 'Servicios' where id = 'aaaaaaaa-0000-0000-0000-000000000001' returning id
$$, 'Administración edita cualquier empresa');

-- ---------------- Oportunidades ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c2');
select is_empty($$
  update public.deals_opportunities set next_action = 'Otra' where id = 'dddddddd-0000-0000-0000-000000000001' returning id
$$, 'Pablo no edita la oportunidad de Laura');
select throws_ok($$
  insert into public.deal_interaction_logs (deal_id, user_id, interaction_type, interaction_note)
  values ('dddddddd-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000c2', 'llamada', 'x')
$$, '42501', null, 'Pablo no escribe en la bitácora de Laura');
select throws_ok($$
  insert into public.deals_opportunities (company_id, city_id, assigned_user_id, deal_name_branch, origin_code,
    next_action, next_action_due_date, next_action_owner_id)
  values ('aaaaaaaa-0000-0000-0000-000000000001', (select id from public.cities where name = 'Pereira'),
          '00000000-0000-0000-0000-0000000000c2', 'Pablo en empresa de Laura', 'referido',
          'Llamar', current_date + 3, '00000000-0000-0000-0000-0000000000c2')
$$, '42501', null, 'Pablo no abre oportunidades en la empresa de Laura');

select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select isnt_empty($$
  update public.deals_opportunities set assigned_user_id = '00000000-0000-0000-0000-0000000000c2'
  where id = 'dddddddd-0000-0000-0000-000000000001' returning id
$$, 'Dirección reasigna la oportunidad');
select pg_temp.login('00000000-0000-0000-0000-0000000000c2');
select isnt_empty($$
  update public.deals_opportunities set next_action = 'Visitar' where id = 'dddddddd-0000-0000-0000-000000000001' returning id
$$, 'tras la reasignación, Pablo edita la oportunidad');

-- ---------------- Convenios ----------------
select throws_ok($$
  insert into public.agreements_convenios (company_id, payroll_frequency, max_installments)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'mensual', 2)
$$, '42501', null, 'Pablo no crea convenios en la empresa de Laura');

-- ---------------- Órdenes ----------------
reset role;
update public.campaigns_jornadas set status = 'en_ejecucion', logistics_confirmed = true
where id = 'eeeeeeee-0000-0000-0000-000000000001';
set local role authenticated;

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select public.create_order(
  jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001',
    'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001', 'payment_modality', 'contado', 'notes', 'Orden de Laura'),
  jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'Metal',
    'quantity', 1, 'unit_price', 100000)));

select pg_temp.login('00000000-0000-0000-0000-0000000000c2');
select is_empty($$
  update public.orders set notes = 'cambio' where id = pg_temp.laura_order() returning id
$$, 'Pablo no edita la orden de Laura');
select throws_ok($$
  insert into public.order_items (order_id, item_type, description, quantity, unit_price)
  values (pg_temp.laura_order(), 'otro', 'Estuche', 1, 1000)
$$, '42501', null, 'Pablo no agrega ítems a la orden de Laura');
select lives_ok($$
  select public.create_order(
    jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001',
      'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001', 'payment_modality', 'contado'),
    jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'Acetato',
      'quantity', 1, 'unit_price', 90000)))
$$, 'cualquier Comercial registra órdenes en la jornada');

-- ---------------- Cancelación de jornadas ----------------
select throws_ok($$
  update public.campaigns_jornadas set status = 'cancelada', cancel_reason = 'x'
  where id = 'eeeeeeee-0000-0000-0000-000000000002'
$$, '42501', null, 'Comercial no cancela jornadas');

select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select throws_ok($$
  update public.campaigns_jornadas set logistics_confirmed = true where id = 'eeeeeeee-0000-0000-0000-000000000002'
$$, '42501', null, 'Dirección no modifica otros datos de la jornada');
select lives_ok($$
  update public.campaigns_jornadas set status = 'cancelada', cancel_reason = 'Empresa aplazó'
  where id = 'eeeeeeee-0000-0000-0000-000000000002'
$$, 'Dirección cancela la jornada');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select isnt_empty($$
  update public.campaigns_jornadas set notes = 'Apoyo de Laura' where id = 'eeeeeeee-0000-0000-0000-000000000001' returning id
$$, 'cualquier Comercial sigue apoyando la jornada (aunque la oportunidad ya no sea suya)');

select * from finish();
rollback;
