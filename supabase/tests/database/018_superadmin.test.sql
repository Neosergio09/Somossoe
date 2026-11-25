-- Super administrador: pasa todas las guardas de rol y de propiedad comercial.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000f1', 'super@test.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'laura@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co'),
  ('00000000-0000-0000-0000-0000000000e1', 'socio@test.co');
update public.users_profiles set role = 'superadmin', active = true where email = 'super@test.co';
update public.users_profiles set role = 'comercial', active = true where email = 'laura@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';
update public.users_profiles set role = 'socio', active = true where email = 'socio@test.co';

-- Empresa, oportunidad y jornada de Laura
insert into public.companies (id, name, sector, payroll_frequency, assigned_user_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Empresa de Laura', 'Retail', 'mensual', '00000000-0000-0000-0000-0000000000c1');
insert into public.deals_opportunities (id, company_id, city_id, assigned_user_id, deal_name_branch, origin_code,
  stage, next_action, next_action_due_date, next_action_owner_id)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        (select id from public.cities where name = 'Pereira'), '00000000-0000-0000-0000-0000000000c1',
        'Laura - Pereira', 'referido', 'prospecto', 'Llamar', private.today_co() + 3, '00000000-0000-0000-0000-0000000000c1');
insert into public.agreements_convenios (id, company_id, payroll_frequency, max_installments, status, approved_at)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'mensual', 4, 'aprobado', now());
insert into public.campaigns_jornadas (id, deal_id, agreement_id, responsible_user_id, status) values
  ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', 'programada');

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.luis_company() returns uuid language sql as $$
  select id from public.companies where name = 'Cliente de Luis';
$$;
grant execute on function pg_temp.login(uuid) to authenticated;
grant execute on function pg_temp.luis_company() to authenticated;

set local role authenticated;

-- ---------------- Socio sigue siendo solo consulta ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000e1');
select throws_ok($$
  insert into public.companies (name, sector) values ('Del socio', 'Retail')
$$, '42501', null, 'Socio no crea empresas');

-- ---------------- Superadmin ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000f1');
select ok(private.has_role('comercial') and private.has_role('administracion_cartera', 'operacion'),
  'has_role es verdadero para cualquier rol');
select ok(private.is_internal_user(), 'Cuenta como usuario interno');

select lives_ok($$
  insert into public.companies (name, sector, payroll_frequency, assigned_user_id)
  values ('Cliente de Luis', 'Retail', 'mensual',
          '00000000-0000-0000-0000-0000000000f1')
$$, 'Crea una empresa asignada a sí mismo');
select lives_ok($$
  insert into public.company_branches (company_id, name, city_id)
  values (pg_temp.luis_company(), 'Sede principal', (select id from public.cities where name = 'Pereira'))
$$, 'Crea una sede');
select lives_ok($$
  insert into public.contacts (company_id, full_name, role_title, area, email)
  values (pg_temp.luis_company(), 'Ana RRHH', 'Jefe', 'rrhh', 'ana@cliente.co')
$$, 'Crea un contacto');
select lives_ok($$
  insert into public.deals_opportunities (company_id, city_id, assigned_user_id, deal_name_branch, origin_code,
    stage, next_action, next_action_due_date, next_action_owner_id)
  values (pg_temp.luis_company(),
          (select id from public.cities where name = 'Pereira'), '00000000-0000-0000-0000-0000000000f1',
          'Luis - Pereira', 'referido', 'prospecto', 'Llamar', private.today_co() + 3, '00000000-0000-0000-0000-0000000000f1')
$$, 'Crea una oportunidad y queda como ejecutivo');
select lives_ok($$
  insert into public.deal_interaction_logs (deal_id, interaction_type, interaction_note)
  values ((select id from public.deals_opportunities where deal_name_branch = 'Luis - Pereira'), 'llamada', 'Primer contacto')
$$, 'Registra en la bitácora de su oportunidad');

select isnt_empty($$
  update public.companies set sector = 'Salud' where id = 'aaaaaaaa-0000-0000-0000-000000000001' returning id
$$, 'Edita la empresa de otro ejecutivo');
select isnt_empty($$
  update public.deals_opportunities set next_action = 'Visitar'
  where id = 'dddddddd-0000-0000-0000-000000000001' returning id
$$, 'Edita la oportunidad de otro ejecutivo');
select lives_ok($$
  update public.campaigns_jornadas set notes = 'Llevar autorrefractómetro'
  where id = 'eeeeeeee-0000-0000-0000-000000000001'
$$, 'Edita una jornada (la guarda de Dirección no lo limita)');

-- ---------------- Laura sigue limitada a lo suyo ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select is_empty($$
  update public.companies set sector = 'Otro' where id = pg_temp.luis_company() returning id
$$, 'Laura no edita la empresa de Luis');

select * from finish();
rollback;
