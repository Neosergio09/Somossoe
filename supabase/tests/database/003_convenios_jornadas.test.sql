-- Pruebas de convenios (Etapa 05) y jornadas (Etapa 06).
begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

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

insert into public.companies (name, nit, nit_dv, is_nit_provisional, sector, total_employees, payroll_frequency)
values ('Marisol SAS', '900123456', private.nit_check_digit('900123456'), false, 'Manufactura', 120, 'quincenal'),
       ('Andina Ejemplo', null, null, true, 'Retail', null, 'mensual');

insert into public.deals_opportunities (company_id, city_id, assigned_user_id, deal_name_branch, origin_code,
  stage, target_employees_n, estimated_close_date, next_action, next_action_due_date, next_action_owner_id)
values
  ((select id from public.companies where name = 'Marisol SAS'),
   (select id from public.cities where name = 'Medellín'),
   '00000000-0000-0000-0000-0000000000c1', 'Marisol - Medellín', 'referido', 'negociacion', 100,
   current_date + 10, 'Cerrar convenio', current_date + 5, '00000000-0000-0000-0000-0000000000c1'),
  ((select id from public.companies where name = 'Andina Ejemplo'),
   (select id from public.cities where name = 'Pereira'),
   '00000000-0000-0000-0000-0000000000c1', 'Andina - Pereira', 'referido', 'negociacion', 50,
   current_date + 10, 'Cerrar convenio', current_date + 5, '00000000-0000-0000-0000-0000000000c1');

insert into public.deal_interaction_logs (deal_id, user_id, interaction_type, interaction_note)
select id, '00000000-0000-0000-0000-0000000000c1', 'reunion', 'Reunión con RRHH'
from public.deals_opportunities;

-- Convenio aprobado de otra empresa (Andina) para probar el cruce
insert into public.agreements_convenios (company_id, payroll_frequency, max_installments, status, approved_at)
values ((select id from public.companies where name = 'Andina Ejemplo'), 'mensual', 4, 'aprobado', now());

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.marisol_deal() returns uuid language sql as $$
  select id from public.deals_opportunities where deal_name_branch = 'Marisol - Medellín';
$$;
create function pg_temp.marisol_agreement() returns uuid language sql as $$
  select a.id from public.agreements_convenios a
  join public.companies c on c.id = a.company_id where c.name = 'Marisol SAS';
$$;

-- Desde la revisión de RLS las funciones nuevas no son ejecutables por PUBLIC
do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

-- ---------------- Convenio: Comercial ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');

select throws_ok($$
  insert into public.agreements_convenios (company_id, deal_id, payroll_frequency, max_installments)
  values ((select id from public.companies where name = 'Marisol SAS'), pg_temp.marisol_deal(), 'mensual', 6)
$$, 'P0001', null, 'con nómina mensual el máximo es 4 cuotas');

select lives_ok($$
  insert into public.agreements_convenios (company_id, deal_id, payroll_frequency, max_installments,
    valid_from, valid_until)
  values ((select id from public.companies where name = 'Marisol SAS'), pg_temp.marisol_deal(),
          'quincenal', 8, current_date - 1, current_date + 365)
$$, 'comercial crea el convenio en Borrador');

select throws_ok($$
  update public.agreements_convenios set status = 'pendiente_aprobacion' where id = pg_temp.marisol_agreement()
$$, 'P0001', null, 'no se envía a aprobación sin el convenio firmado');

select lives_ok($$
  insert into public.agreement_documents (agreement_id, document_name, document_type)
  values (pg_temp.marisol_agreement(), 'Convenio firmado Marisol', 'convenio_firmado')
$$, 'se registra el convenio firmado sin archivo (R2 pendiente)');

select lives_ok($$
  update public.agreements_convenios set status = 'pendiente_aprobacion' where id = pg_temp.marisol_agreement()
$$, 'comercial envía el convenio a aprobación');

select throws_ok($$
  update public.agreements_convenios set status = 'aprobado' where id = pg_temp.marisol_agreement()
$$, '42501', null, 'comercial no aprueba convenios');
select throws_ok($$
  update public.agreements_convenios set documents_verified = true where id = pg_temp.marisol_agreement()
$$, '42501', null, 'comercial no verifica la documentación');

-- ---------------- Convenio: Dirección y Administración ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select throws_ok($$
  update public.agreements_convenios set status = 'aprobado' where id = pg_temp.marisol_agreement()
$$, 'P0001', null, 'Dirección no aprueba sin documentación verificada');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select lives_ok($$
  update public.agreements_convenios set documents_verified = true where id = pg_temp.marisol_agreement()
$$, 'Administración verifica la documentación');

select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select lives_ok($$
  update public.agreements_convenios set status = 'aprobado' where id = pg_temp.marisol_agreement()
$$, 'Dirección aprueba el convenio');
select is(
  (select approved_by from public.agreements_convenios where id = pg_temp.marisol_agreement()),
  '00000000-0000-0000-0000-0000000000d1'::uuid,
  'queda registrado quién aprobó'
);

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  update public.agreements_convenios set max_installments = 6 where id = pg_temp.marisol_agreement()
$$, 'P0001', null, 'un convenio aprobado no se modifica');
select throws_ok($$
  delete from public.agreement_documents where agreement_id = pg_temp.marisol_agreement()
$$, 'P0001', null, 'los documentos de un convenio aprobado no se eliminan');
reset role;
insert into storage.objects (bucket_id, name, owner_id)
values ('soportes', 'convenios/00000000-0000-0000-0000-0000000000c1/marisol.pdf', '00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select lives_ok($$
  update public.agreement_documents set file_path = 'convenios/00000000-0000-0000-0000-0000000000c1/marisol.pdf'
  where agreement_id = pg_temp.marisol_agreement()
$$, 'se puede completar el archivo pendiente de un convenio aprobado');

-- ---------------- Oportunidad → Convenio Firmado ----------------
select throws_ok($$
  update public.deals_opportunities set stage = 'convenio_firmado'
  where id = pg_temp.marisol_deal()
$$, '23514', null, 'Convenio Firmado exige fecha tentativa de jornada');
select lives_ok($$
  update public.deals_opportunities set stage = 'convenio_firmado', tentative_campaign_date = current_date + 7
  where id = pg_temp.marisol_deal()
$$, 'con convenio aprobado la oportunidad pasa a Convenio Firmado');

-- ---------------- Jornadas ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  insert into public.campaigns_jornadas (deal_id, agreement_id, responsible_user_id)
  values (pg_temp.marisol_deal(), pg_temp.marisol_agreement(), '00000000-0000-0000-0000-0000000000b1')
$$, '42501', null, 'comercial no crea jornadas');

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  insert into public.campaigns_jornadas (deal_id, agreement_id, responsible_user_id)
  values (pg_temp.marisol_deal(),
          (select a.id from public.agreements_convenios a join public.companies c on c.id = a.company_id
           where c.name = 'Andina Ejemplo'),
          '00000000-0000-0000-0000-0000000000b1')
$$, 'P0001', null, 'la jornada no puede usar el convenio de otra empresa');

select lives_ok($$
  insert into public.campaigns_jornadas (deal_id, agreement_id, responsible_user_id, notes)
  values (pg_temp.marisol_deal(), pg_temp.marisol_agreement(), '00000000-0000-0000-0000-0000000000b1', 'Jornada 1')
$$, 'operación programa la jornada');
select is(
  (select c.name || ' / ' || ci.name from public.campaigns_jornadas j
   join public.companies c on c.id = j.company_id join public.cities ci on ci.id = j.city_id
   where j.notes = 'Jornada 1'),
  'Marisol SAS / Medellín',
  'la jornada hereda empresa y ciudad de la oportunidad'
);

select throws_ok($$
  insert into public.campaign_sessions (campaign_id, session_date, start_time, end_time, responsible_user_id)
  values ((select id from public.campaigns_jornadas where notes = 'Jornada 1'),
          current_date + 7, '10:00', '08:00', '00000000-0000-0000-0000-0000000000b1')
$$, '23514', null, 'la sesión debe terminar después de empezar');
select throws_ok($$
  insert into public.campaign_sessions (campaign_id, session_date, start_time, end_time, responsible_user_id)
  values ((select id from public.campaigns_jornadas where notes = 'Jornada 1'),
          current_date + 400, '08:00', '12:00', '00000000-0000-0000-0000-0000000000b1')
$$, 'P0001', null, 'la sesión no puede quedar fuera de la vigencia del convenio');

select is((select status::text from public.campaigns_jornadas where notes = 'Jornada 1'), 'borrador',
  'la jornada nace en borrador');
select throws_ok($$
  update public.campaigns_jornadas set status = 'programada' where notes = 'Jornada 1'
$$, 'P0001', null, 'no se programa una jornada sin sesiones');

insert into public.campaign_sessions (campaign_id, session_date, start_time, end_time, location_detail, responsible_user_id)
values ((select id from public.campaigns_jornadas where notes = 'Jornada 1'),
        current_date + 7, '08:00', '12:00', 'Auditorio piso 2', '00000000-0000-0000-0000-0000000000b1');
update public.campaigns_jornadas set status = 'programada' where notes = 'Jornada 1';

select throws_ok($$
  update public.campaigns_jornadas set status = 'en_ejecucion' where notes = 'Jornada 1'
$$, 'P0001', null, 'no se inicia una jornada sin logística confirmada');
select lives_ok($$
  update public.campaigns_jornadas set logistics_confirmed = true, status = 'en_ejecucion'
  where notes = 'Jornada 1'
$$, 'con sesión y logística confirmada la jornada inicia');
select is(
  (select stage from public.deals_opportunities where id = pg_temp.marisol_deal()),
  'jornada_en_ejecucion'::public.deal_stage,
  'la oportunidad pasa sola a Jornada en Ejecución'
);

-- ---------------- Asistencia ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
insert into public.campaign_attendance (campaign_id, session_id, full_name, document_id, area, status)
select j.id, s.id, x.full_name, x.document_id, 'Planta', 'atendido'
from public.campaigns_jornadas j
join public.campaign_sessions s on s.campaign_id = j.id
cross join (values ('Ana Pérez', '1088123456'), ('Carlos Ruiz', '1088654321')) as x (full_name, document_id)
where j.notes = 'Jornada 1';

select throws_ok($$
  insert into public.campaign_attendance (campaign_id, session_id, full_name, document_id)
  select j.id, s.id, 'Ana Pérez', '1088123456'
  from public.campaigns_jornadas j join public.campaign_sessions s on s.campaign_id = j.id
  where j.notes = 'Jornada 1'
$$, '23505', null, 'una persona no se registra dos veces en la misma sesión');
select is(
  (select attended_headcount from public.v_campaigns where notes = 'Jornada 1'),
  2::bigint,
  'el conteo de asistencia se calcula del listado'
);

-- ---------------- Calendario: cruce del mismo responsable ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
insert into public.campaigns_jornadas (deal_id, agreement_id, responsible_user_id, notes)
values (pg_temp.marisol_deal(), pg_temp.marisol_agreement(), '00000000-0000-0000-0000-0000000000b1', 'Jornada 2');
insert into public.campaign_sessions (campaign_id, session_date, start_time, end_time, responsible_user_id)
values ((select id from public.campaigns_jornadas where notes = 'Jornada 2'),
        current_date + 7, '11:00', '14:00', '00000000-0000-0000-0000-0000000000b1');
select is(
  (select count(*) from public.v_campaign_calendar where has_conflict),
  2::bigint,
  'el calendario marca el cruce de sesiones del mismo responsable'
);

-- ---------------- Cierre ----------------
update public.campaigns_jornadas set status = 'captura_cerrada' where notes = 'Jornada 1';
select throws_ok($$
  insert into public.campaign_attendance (campaign_id, session_id, full_name, document_id)
  select j.id, s.id, 'Luis Gómez', '1088000000'
  from public.campaigns_jornadas j join public.campaign_sessions s on s.campaign_id = j.id
  where j.notes = 'Jornada 1'
$$, 'P0001', null, 'no se registra asistencia con la captura cerrada');
select throws_ok($$
  update public.campaigns_jornadas set status = 'en_ejecucion' where notes = 'Jornada 1'
$$, 'P0001', null, 'la captura no se reabre sin motivo');

-- ---------------- Archivo obligatorio cuando R2 esté activo ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
update public.system_settings set value = 1 where key = 'require_document_files';
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
insert into public.agreements_convenios (company_id, payroll_frequency, max_installments)
values ((select id from public.companies where name = 'Andina Ejemplo'), 'mensual', 4);
insert into public.agreement_documents (agreement_id, document_name, document_type)
select id, 'Convenio Andina', 'convenio_firmado' from public.agreements_convenios where status = 'borrador';
select throws_ok($$
  update public.agreements_convenios set status = 'pendiente_aprobacion' where status = 'borrador'
$$, 'P0001', null, 'con require_document_files = 1 se exige el archivo del convenio firmado');

select * from finish();
rollback;
