-- Acceso total (27-nov-2026): Comercial y Super administrador hacen todo;
-- solo Super administrador y Dirección gestionan usuarios.
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000f1', 'luis@test.co'),
  ('00000000-0000-0000-0000-0000000000d1', 'fabian@test.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'laura@test.co'),
  ('00000000-0000-0000-0000-0000000000c2', 'pablo@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co'),
  ('00000000-0000-0000-0000-0000000000e1', 'socio@test.co');
update public.users_profiles set role = 'superadmin', active = true where email = 'luis@test.co';
update public.users_profiles set role = 'direccion', active = true where email = 'fabian@test.co';
update public.users_profiles set role = 'comercial', active = true where email in ('laura@test.co', 'pablo@test.co');
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';
update public.users_profiles set role = 'socio', active = true where email = 'socio@test.co';

insert into public.companies (id, name, sector, payroll_frequency, assigned_user_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Empresa de Laura', 'Retail', 'mensual', '00000000-0000-0000-0000-0000000000c1');

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.login(uuid) to authenticated;

set local role authenticated;

-- ---------------- Comercial: acceso total ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c2');
select ok(private.has_full_access(), 'Comercial tiene acceso total');
select ok(private.has_role('direccion') and private.has_role('costos', 'operacion'), 'has_role es verdadero para cualquier rol');
select ok(private.fabrication_role('operacion'), 'en la ficha RX actúa como Operación');
select ok(private.can_view_costs(), 've costos');
select isnt_empty($$
  update public.companies set sector = 'Otro' where id = 'aaaaaaaa-0000-0000-0000-000000000001' returning id
$$, 'edita la empresa de otro Comercial');
select lives_ok($$
  update public.system_settings set value = 0.65 where key = 'conversion_rate_c'
$$, 'cambia parámetros');
select is((select value from public.system_settings where key = 'conversion_rate_c'), 0.65, 'el parámetro cambió');
select ok(not private.can_manage_users(), 'no gestiona usuarios');
select is_empty($$
  update public.users_profiles set full_name = 'Otro nombre' where id = '00000000-0000-0000-0000-0000000000c1' returning id
$$, 'no edita a otros usuarios');
select is_empty($$
  update public.users_profiles set role = 'superadmin' where id = '00000000-0000-0000-0000-0000000000c2' returning id
$$, 'no se cambia el rol a sí mismo');

-- ---------------- Otros roles no cambian ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000e1');
select ok(not private.has_full_access() and not private.has_role('direccion'), 'Socio sigue sin acceso total');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select ok(not private.has_full_access() and not private.can_manage_users(), 'Operación sigue sin acceso total');

-- ---------------- Usuarios: Dirección y Super administrador ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select ok(not private.has_full_access(), 'Dirección no tiene acceso total');
select isnt_empty($$
  update public.users_profiles set full_name = 'Laura G.' where id = '00000000-0000-0000-0000-0000000000c1' returning id
$$, 'Dirección gestiona usuarios');
select pg_temp.login('00000000-0000-0000-0000-0000000000f1');
select ok(private.has_full_access() and private.can_manage_users(), 'el Super administrador tiene acceso total y gestiona usuarios');
select lives_ok($$
  update public.users_profiles set active = false where id = '00000000-0000-0000-0000-0000000000d1'
$$, 'con un Super administrador activo se puede desactivar la última Dirección');
select throws_like($$
  update public.users_profiles set active = false where id = '00000000-0000-0000-0000-0000000000f1'
$$, '%al menos un usuario de Dirección o Super administrador activo%',
  'no queda el sistema sin quien gestione usuarios');
select isnt_empty($$
  update public.users_profiles set role = 'comercial' where id = '00000000-0000-0000-0000-0000000000b1' returning id
$$, 'el Super administrador cambia el rol de otro usuario');

select * from finish();
rollback;
