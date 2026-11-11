-- Pruebas M01 + M02: empresas, NIT, anti-duplicados, sedes, contactos,
-- oportunidades, Facturación Estimada, bitácora y embudo.
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
insert into public.cities (name, is_operational) values ('Cali', false);

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- ---------------- Funciones de apoyo ----------------
select is(private.nit_check_digit('800197268'), 4::smallint, 'DV del NIT de la DIAN (800197268) = 4');
select is(private.normalize_company_name('Marisol S.A.S.'), 'marisol', 'normaliza "Marisol S.A.S."');
select is(private.normalize_company_name('ÓPTICA  Andina Ltda.'), 'optica andina', 'normaliza tildes, espacios y LTDA');

-- Desde la revisión de RLS las funciones nuevas no son ejecutables por PUBLIC
do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

-- ---------------- Empresas (Comercial) ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');

select lives_ok($$
  insert into public.companies (name, nit, nit_dv, is_nit_provisional, sector, total_employees, payroll_frequency)
  values ('Marisol SAS', '900123456', private.nit_check_digit('900123456'), false, 'Manufactura', 120, 'quincenal')
$$, 'comercial crea una empresa');
select is(
  (select is_nit_provisional from public.companies where name = 'Marisol SAS'),
  true,
  'la empresa creada por comercial queda con NIT provisional'
);
select throws_ok($$
  insert into public.companies (name, sector) values ('MARISOL S.A.S', 'Manufactura')
$$, '23505', null, 'razón social duplicada (normalizada) se rechaza');
select is(
  (select count(*) from public.find_company_duplicates('marisol', null)),
  1::bigint,
  'find_company_duplicates encuentra por nombre'
);
select is(
  (select match_reason from public.find_company_duplicates('Otra cosa', '900123456-8')),
  'nit',
  'find_company_duplicates encuentra por NIT con DV'
);
select throws_ok($$
  update public.companies set is_nit_provisional = false where name = 'Marisol SAS'
$$, '42501', null, 'comercial no puede confirmar el NIT');

-- ---------------- Empresas (Administración) ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  update public.companies set is_nit_provisional = false, nit_dv = (nit_dv + 1) % 10 where name = 'Marisol SAS'
$$, '23514', null, 'DV incorrecto se rechaza');
select lives_ok($$
  update public.companies set is_nit_provisional = false where name = 'Marisol SAS'
$$, 'administración confirma el NIT');
select is(
  (select nit_verified_by from public.companies where name = 'Marisol SAS'),
  '00000000-0000-0000-0000-0000000000a1'::uuid,
  'queda registrado quién verificó el NIT'
);

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  update public.companies set nit = '900123457' where name = 'Marisol SAS'
$$, '42501', null, 'comercial no puede cambiar un NIT en firme');

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  insert into public.companies (name, sector) values ('Empresa Operación', 'Servicios')
$$, '42501', null, 'operación no puede crear empresas');

-- ---------------- Sedes y contactos (Comercial) ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
insert into public.companies (name, sector) values ('Andina Ejemplo', 'Retail');

insert into public.company_branches (company_id, name, city_id, is_main)
values (
  (select id from public.companies where name = 'Marisol SAS'),
  'Sede Medellín',
  (select id from public.cities where name = 'Medellín'),
  true
);
insert into public.company_branches (company_id, name, city_other)
values ((select id from public.companies where name = 'Andina Ejemplo'), 'Sede Bogotá', 'Bogotá');

select throws_ok($$
  insert into public.company_branches (company_id, name, city_id, is_main)
  values ((select id from public.companies where name = 'Marisol SAS'), 'Sede Pereira',
          (select id from public.cities where name = 'Pereira'), true)
$$, '23505', null, 'solo una sede principal por empresa');
select throws_ok($$
  insert into public.company_branches (company_id, name, city_id, city_other)
  values ((select id from public.companies where name = 'Marisol SAS'), 'Sede X',
          (select id from public.cities where name = 'Pereira'), 'Pereira')
$$, '23514', null, 'la sede tiene ciudad de catálogo o ciudad en texto, no ambas');

select throws_ok($$
  insert into public.contacts (company_id, full_name, role_title, area)
  values ((select id from public.companies where name = 'Marisol SAS'), 'Laura Gómez', 'Jefe RRHH', 'rrhh')
$$, '23514', null, 'el contacto necesita teléfono o correo');
select throws_ok($$
  insert into public.contacts (company_id, branch_id, full_name, role_title, area, email)
  values ((select id from public.companies where name = 'Marisol SAS'),
          (select id from public.company_branches where name = 'Sede Bogotá'),
          'Laura Gómez', 'Jefe RRHH', 'rrhh', 'laura@marisol.co')
$$, '23503', null, 'el contacto no puede apuntar a una sede de otra empresa');

insert into public.contacts (company_id, full_name, role_title, area, is_coordinator, is_decision_maker, email)
values ((select id from public.companies where name = 'Marisol SAS'),
        'Laura Gómez', 'Jefe RRHH', 'rrhh', true, true, 'laura@marisol.co');

-- ---------------- Oportunidades (Comercial) ----------------
select throws_ok($$
  insert into public.deals_opportunities (company_id, city_id, assigned_user_id, deal_name_branch,
    origin_code, stage, next_action, next_action_due_date, next_action_owner_id)
  values ((select id from public.companies where name = 'Marisol SAS'),
          (select id from public.cities where name = 'Medellín'),
          '00000000-0000-0000-0000-0000000000c1', 'Marisol - Sede Medellín', 'referido',
          'negociacion', 'Llamar', current_date + 3, '00000000-0000-0000-0000-0000000000c1')
$$, 'P0001', null, 'una oportunidad no puede nacer en Negociación');

select throws_ok($$
  insert into public.deals_opportunities (company_id, city_id, assigned_user_id, deal_name_branch,
    origin_code, next_action, next_action_due_date, next_action_owner_id)
  values ((select id from public.companies where name = 'Marisol SAS'),
          (select id from public.cities where name = 'Cali'),
          '00000000-0000-0000-0000-0000000000c1', 'Marisol - Cali', 'referido',
          'Llamar', current_date + 3, '00000000-0000-0000-0000-0000000000c1')
$$, 'P0001', null, 'la ciudad debe ser operativa');

select lives_ok($$
  insert into public.deals_opportunities (company_id, branch_id, city_id, primary_contact_id,
    assigned_user_id, deal_name_branch, origin_code, target_employees_n,
    next_action, next_action_due_date, next_action_owner_id)
  values ((select id from public.companies where name = 'Marisol SAS'),
          (select id from public.company_branches where name = 'Sede Medellín'),
          (select id from public.cities where name = 'Medellín'),
          (select id from public.contacts where email = 'laura@marisol.co'),
          '00000000-0000-0000-0000-0000000000c1', 'Marisol SAS - Sede Medellín', 'referido', 100,
          'Agendar reunión', current_date + 2, '00000000-0000-0000-0000-0000000000c1')
$$, 'comercial crea una oportunidad en Prospecto');

select is(
  (select estimated_billing_amount from public.deals_opportunities where deal_name_branch = 'Marisol SAS - Sede Medellín'),
  21000000::numeric,
  'Facturación Estimada: 100 × 0,70 × 300.000 = 21.000.000'
);
select is(
  (select payroll_frequency from public.deals_opportunities where deal_name_branch = 'Marisol SAS - Sede Medellín'),
  'quincenal'::public.payroll_frequency,
  'la periodicidad de nómina se hereda de la empresa'
);

-- Embudo y bitácora
select throws_ok($$
  update public.deals_opportunities set stage = 'reunion_exploratoria'
  where deal_name_branch = 'Marisol SAS - Sede Medellín'
$$, 'P0001', null, 'Reunión Exploratoria exige una Reunión en bitácora');

insert into public.deal_interaction_logs (deal_id, interaction_type, interaction_note)
values ((select id from public.deals_opportunities where deal_name_branch = 'Marisol SAS - Sede Medellín'),
        'llamada', 'Primera llamada con Laura');
select is(
  (select last_interaction_type from public.deals_opportunities where deal_name_branch = 'Marisol SAS - Sede Medellín'),
  'llamada'::public.interaction_type,
  'la bitácora actualiza la última interacción del negocio'
);

insert into public.deal_interaction_logs (deal_id, interaction_type, interaction_note)
values ((select id from public.deals_opportunities where deal_name_branch = 'Marisol SAS - Sede Medellín'),
        'reunion', 'Reunión presencial con RRHH');
select lives_ok($$
  update public.deals_opportunities set stage = 'reunion_exploratoria'
  where deal_name_branch = 'Marisol SAS - Sede Medellín'
$$, 'con la Reunión registrada avanza a Reunión Exploratoria');

select throws_ok($$
  update public.deal_interaction_logs set interaction_note = 'editado'
$$, '42501', null, 'la bitácora no se puede editar');
select throws_ok($$
  insert into public.deal_interaction_logs (deal_id, user_id, interaction_type, interaction_note)
  values ((select id from public.deals_opportunities limit 1),
          '00000000-0000-0000-0000-0000000000d1', 'correo', 'suplantado')
$$, '42501', null, 'no se puede registrar bitácora a nombre de otro usuario');

select throws_ok($$
  update public.deals_opportunities set stage = 'convenio_firmado', tentative_campaign_date = current_date + 30,
    estimated_close_date = current_date + 10
  where deal_name_branch = 'Marisol SAS - Sede Medellín'
$$, 'P0001', null, 'Convenio Firmado bloqueado hasta tener convenio aprobado');
select throws_ok($$
  update public.deals_opportunities set stage = 'jornada_en_ejecucion'
  where deal_name_branch = 'Marisol SAS - Sede Medellín'
$$, 'P0001', null, 'Jornada en Ejecución no se asigna a mano');
select throws_ok($$
  update public.deals_opportunities set target_employees_n = 500
  where deal_name_branch = 'Marisol SAS - Sede Medellín'
$$, 'P0001', null, 'N no puede superar el total de empleados de la empresa');
select throws_ok($$
  select public.recalculate_deal_forecast((select id from public.deals_opportunities limit 1))
$$, '42501', null, 'comercial no puede recalcular la Facturación Estimada');

-- ---------------- Congelamiento de C y T (Dirección) ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
update public.system_settings set value = 0.65 where key = 'conversion_rate_c';
select is(
  (select estimated_billing_amount from public.deals_opportunities where deal_name_branch = 'Marisol SAS - Sede Medellín'),
  21000000::numeric,
  'cambiar C no altera las oportunidades existentes'
);
select is(
  public.recalculate_deal_forecast((select id from public.deals_opportunities where deal_name_branch = 'Marisol SAS - Sede Medellín')),
  19500000::numeric,
  'Dirección recalcula con C = 0,65: 19.500.000'
);

-- ---------------- Cierre perdido ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  update public.deals_opportunities set stage = 'cierre_perdido'
  where deal_name_branch = 'Marisol SAS - Sede Medellín'
$$, '23514', null, 'Cierre Perdido exige sub-estado');
select lives_ok($$
  update public.deals_opportunities set stage = 'cierre_perdido', lost_substatus = 'no_contactar'
  where deal_name_branch = 'Marisol SAS - Sede Medellín'
$$, 'Cierre Perdido con No Contactar');
select throws_ok($$
  update public.deals_opportunities set stage = 'prospecto'
  where deal_name_branch = 'Marisol SAS - Sede Medellín'
$$, 'P0001', null, 'una oportunidad No Contactar no se reabre');

-- ---------------- Tablero ----------------
select is(
  (select is_new_business and days_inactive = 0 and not inactivity_alert
   from public.v_deals_board where deal_name_branch = 'Marisol SAS - Sede Medellín'),
  true,
  'tablero: Nuevo Negocio, 0 días de inactividad y sin alerta'
);

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  insert into public.deals_opportunities (company_id, city_id, assigned_user_id, deal_name_branch,
    origin_code, next_action, next_action_due_date, next_action_owner_id)
  values ((select id from public.companies where name = 'Marisol SAS'),
          (select id from public.cities where name = 'Pereira'),
          '00000000-0000-0000-0000-0000000000c1', 'Marisol - Pereira', 'referido',
          'Llamar', current_date + 3, '00000000-0000-0000-0000-0000000000c1')
$$, '42501', null, 'administración no crea oportunidades');

select * from finish();
rollback;
