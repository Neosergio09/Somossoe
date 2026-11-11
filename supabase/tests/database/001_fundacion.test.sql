-- Pruebas de la migración de fundación: perfiles, RLS por rol,
-- parámetros y auditoría.
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

-- Usuarios de prueba (el trigger crea sus perfiles)
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000d1', 'direccion@test.co', '{"full_name":"Dirección Test"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'comercial@test.co', '{}'),
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.co',     '{}'),
  ('00000000-0000-0000-0000-0000000000e1', 'nuevo@test.co',     '{}');

select is(
  (select count(*) from public.users_profiles where not active and role is null),
  4::bigint,
  'los perfiles nacen inactivos y sin rol'
);
select is(
  (select full_name from public.users_profiles where id = '00000000-0000-0000-0000-0000000000d1'),
  'Dirección Test',
  'full_name se toma de user_metadata'
);
select throws_ok(
  $$ update public.users_profiles set active = true where id = '00000000-0000-0000-0000-0000000000e1' $$,
  '23514', null,
  'no se puede activar un perfil sin rol'
);

update public.users_profiles set role = 'direccion', active = true
  where id = '00000000-0000-0000-0000-0000000000d1';
update public.users_profiles set role = 'comercial', active = true
  where id = '00000000-0000-0000-0000-0000000000c1';
update public.users_profiles set role = 'administracion_cartera', active = true
  where id = '00000000-0000-0000-0000-0000000000a1';

-- ---------------- Comercial ----------------
-- Desde la revisión de RLS las funciones nuevas no son ejecutables por PUBLIC
do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);

select is((select count(*) from public.cities), 2::bigint, 'comercial ve las ciudades');
select ok((select count(*) from public.system_settings) >= 6, 'comercial ve los parámetros');
select is(private.get_setting('conversion_rate_c'), 0.70, 'get_setting devuelve C = 0.70');

update public.system_settings set value = 0.5 where key = 'conversion_rate_c';
select is(
  (select value from public.system_settings where key = 'conversion_rate_c'),
  0.70,
  'comercial no puede cambiar parámetros'
);
select throws_ok(
  $$ insert into public.cities (name) values ('Cali') $$,
  '42501', null,
  'comercial no puede crear ciudades'
);
update public.users_profiles set role = 'direccion' where id = '00000000-0000-0000-0000-0000000000c1';
select is(
  private.current_app_role(),
  'comercial'::public.app_role,
  'comercial no puede cambiarse el rol'
);

-- ---------------- Usuario sin activar ----------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
select is((select count(*) from public.cities), 0::bigint, 'usuario inactivo no ve catálogos');
select is((select count(*) from public.users_profiles), 1::bigint, 'usuario inactivo solo ve su perfil');

-- ---------------- Dirección ----------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);

update public.system_settings set value = 0.65 where key = 'conversion_rate_c';
select is(
  (select value from public.system_settings where key = 'conversion_rate_c'),
  0.65,
  'dirección cambia parámetros'
);
select throws_ok(
  $$ update public.system_settings set value = 1.5 where key = 'conversion_rate_c' $$,
  '23514', null,
  'C fuera de rango (0, 1] se rechaza'
);
select lives_ok(
  $$ insert into public.cities (name, is_operational) values ('Cali', false) $$,
  'dirección crea ciudades'
);

-- ---------------- Auditoría ----------------
select ok(
  exists (
    select 1 from public.audit_logs
    where table_name = 'system_settings'
      and record_id = 'conversion_rate_c'
      and changed_by = '00000000-0000-0000-0000-0000000000d1'
      and (old_data ->> 'value')::numeric = 0.70
      and (new_data ->> 'value')::numeric = 0.65
  ),
  'el cambio de parámetro queda auditado con autor, valor anterior y nuevo'
);
select throws_ok(
  $$ delete from public.audit_logs $$,
  '42501', null,
  'la auditoría no se puede borrar'
);

-- ---------------- Anónimo ----------------
reset role;
set local role anon;
select throws_ok(
  $$ select * from public.cities $$,
  '42501', null,
  'anon no tiene acceso a las tablas'
);

select * from finish();
rollback;
