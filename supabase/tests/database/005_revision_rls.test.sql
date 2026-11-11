-- Pruebas de la revisión de RLS y privilegios.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

-- ---------------- Preparación (como postgres) ----------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'direccion@test.co'),
  ('00000000-0000-0000-0000-0000000000d2', 'direccion2@test.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'comercial@test.co'),
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co');
update public.users_profiles set role = 'direccion', active = true where email = 'direccion@test.co';
update public.users_profiles set role = 'comercial', active = true where email = 'comercial@test.co';
update public.users_profiles set role = 'administracion_cartera', active = true where email = 'admin@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';

insert into public.companies (id, name, nit, nit_dv, is_nit_provisional, sector, payroll_frequency)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Marisol SAS', '900123456',
        private.nit_check_digit('900123456'), false, 'Manufactura', 'mensual');

insert into public.agreements_convenios (id, company_id, payroll_frequency, max_installments, status)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'mensual', 2, 'borrador');
insert into public.agreement_documents (agreement_id, document_name, document_type)
values ('cccccccc-0000-0000-0000-000000000001', 'Convenio firmado', 'convenio_firmado');
update public.agreements_convenios set status = 'pendiente_aprobacion', documents_verified = true
where id = 'cccccccc-0000-0000-0000-000000000001';

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.verified() returns boolean language sql as $$
  select documents_verified from public.agreements_convenios where id = 'cccccccc-0000-0000-0000-000000000001';
$$;

-- Desde la revisión de RLS las funciones nuevas no son ejecutables por PUBLIC
do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

-- ---------------- 1. Convenio ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
update public.agreements_convenios set payroll_conditions = 'Solo personal de planta'
where id = 'cccccccc-0000-0000-0000-000000000001';
select is(pg_temp.verified(), false, 'cambiar condiciones de un convenio verificado anula la verificación');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
update public.agreements_convenios set documents_verified = true where id = 'cccccccc-0000-0000-0000-000000000001';
select is(pg_temp.verified(), true, 'Administración vuelve a verificar');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
insert into public.agreement_documents (agreement_id, document_name, document_type)
values ('cccccccc-0000-0000-0000-000000000001', 'RUT', 'rut');
select is(pg_temp.verified(), false, 'agregar un documento anula la verificación');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
update public.agreements_convenios set documents_verified = true where id = 'cccccccc-0000-0000-0000-000000000001';
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select lives_ok($$
  update public.agreements_convenios set status = 'aprobado' where id = 'cccccccc-0000-0000-0000-000000000001'
$$, 'Dirección aprueba lo que Administración verificó');

-- ---------------- 2. Dirección activa ----------------
select throws_ok($$
  update public.users_profiles set active = false where email = 'direccion@test.co'
$$, 'P0001', null, 'la única Dirección no se desactiva');
select throws_ok($$
  update public.users_profiles set role = 'comercial' where email = 'direccion@test.co'
$$, 'P0001', null, 'la única Dirección no se quita el rol');
select lives_ok($$
  update public.users_profiles set role = 'direccion', active = true where email = 'direccion2@test.co'
$$, 'Dirección activa a otro usuario de Dirección');
select lives_ok($$
  update public.users_profiles set active = false where email = 'direccion@test.co'
$$, 'con otra Dirección activa sí se puede desactivar');

-- ---------------- 3. Auditoría ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select is((select count(*) from public.audit_logs), 0::bigint, 'Operación no lee la auditoría');
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select is((select count(*) from public.audit_logs), 0::bigint, 'Comercial no lee la auditoría');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select ok((select count(*) from public.audit_logs) > 0, 'Administración / Cartera lee la auditoría');

-- ---------------- 4 y 5. Privilegios ----------------
reset role;
create table public.tmp_nueva (id int);
select is(has_table_privilege('anon', 'public.tmp_nueva', 'select'), false,
  'una tabla nueva no queda abierta a anon');
select is(has_table_privilege('authenticated', 'public.tmp_nueva', 'select'), false,
  'una tabla nueva no queda abierta a authenticated');
select is(has_column_privilege('authenticated', 'public.cities', 'id', 'update'), false,
  'el id de una ciudad no se puede modificar');

select * from finish();
rollback;
