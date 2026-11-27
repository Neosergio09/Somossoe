-- Paquete incremental N26 (V0.3, 26/11/2026): sede sin nombre, orígenes,
-- fecha real de la interacción, propuestas comerciales, catálogos y
-- columnas nuevas de órdenes y garantías.
begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

-- ---------------- Preparación (como postgres) ----------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'direccion@test.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'comercial@test.co'),
  ('00000000-0000-0000-0000-0000000000c2', 'comercial2@test.co'),
  ('00000000-0000-0000-0000-0000000000f1', 'costos@test.co');
update public.users_profiles set role = 'direccion', active = true where email = 'direccion@test.co';
update public.users_profiles set role = 'comercial', active = true where email in ('comercial@test.co', 'comercial2@test.co');
update public.users_profiles set role = 'costos', active = true where email = 'costos@test.co';

insert into public.companies (id, name, sector, payroll_frequency, assigned_user_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Marisol SAS', 'Manufactura', 'mensual', '00000000-0000-0000-0000-0000000000c1');

insert into public.deals_opportunities (id, company_id, city_id, assigned_user_id, deal_name_branch, origin_code,
  next_action, next_action_due_date, next_action_owner_id, target_employees_n, estimated_close_date) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   (select id from public.cities where name = 'Pereira'), '00000000-0000-0000-0000-0000000000c1',
   'Marisol Pereira', 'referido', 'Llamar', private.today_co() + 3, '00000000-0000-0000-0000-0000000000c1', 50, private.today_co() + 30);

insert into storage.objects (bucket_id, name, owner_id) values
  ('soportes', 'propuestas/00000000-0000-0000-0000-0000000000c1/p1.pdf', '00000000-0000-0000-0000-0000000000c1'),
  ('soportes', 'convenios/00000000-0000-0000-0000-0000000000c1/x.pdf', '00000000-0000-0000-0000-0000000000c1');

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.login(uuid) to authenticated;

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');

-- ---------------- N26-02/03 · Sedes ----------------
select lives_ok($$
  insert into public.company_branches (company_id, city_id, address)
  values ('aaaaaaaa-0000-0000-0000-000000000001',
          (select id from public.cities where name = 'Pereira'), 'Cra 7 # 20-15')
$$, 'una sede se crea solo con ciudad y dirección');
select is((select name from public.company_branches where company_id = 'aaaaaaaa-0000-0000-0000-000000000001' and city_id = (select id from public.cities where name = 'Pereira')),
  'Pereira · Cra 7 # 20-15', 'el nombre se arma con ciudad y dirección');
select lives_ok($$
  insert into public.company_branches (company_id, city_id, address)
  values ('aaaaaaaa-0000-0000-0000-000000000001', (select id from public.cities where name = 'Medellín'), 'Calle 10 # 5-20')
$$, 'la misma empresa admite otra sede en otra ciudad');
select throws_ok($$
  insert into public.company_branches (company_id, city_id)
  values ('aaaaaaaa-0000-0000-0000-000000000001', (select id from public.cities where name = 'Medellín'))
$$, 'P0001', 'Indique la dirección de la sede (o un nombre que la identifique)', 'sin nombre exige dirección');
update public.company_branches set address = 'Cra 8 # 21-30' where company_id = 'aaaaaaaa-0000-0000-0000-000000000001' and city_id = (select id from public.cities where name = 'Pereira');
select is((select name from public.company_branches where company_id = 'aaaaaaaa-0000-0000-0000-000000000001' and city_id = (select id from public.cities where name = 'Pereira')),
  'Pereira · Cra 8 # 21-30', 'el nombre automático sigue a la dirección');
update public.company_branches set name = 'Planta norte' where company_id = 'aaaaaaaa-0000-0000-0000-000000000001' and city_id = (select id from public.cities where name = 'Pereira');
update public.company_branches set address = 'Cra 9 # 1-1' where company_id = 'aaaaaaaa-0000-0000-0000-000000000001' and city_id = (select id from public.cities where name = 'Pereira');
select is((select name from public.company_branches where company_id = 'aaaaaaaa-0000-0000-0000-000000000001' and city_id = (select id from public.cities where name = 'Pereira')),
  'Planta norte', 'un nombre propio no se sobrescribe');

-- ---------------- N26-05 · Orígenes ----------------
select is((select label from public.deal_origins where code = 'llamada_saliente'), 'Outbound', 'Llamada saliente → Outbound');
select is((select label from public.deal_origins where code = 'inbound_web'), 'Inbound', 'Inbound web → Inbound');
select throws_ok($$
  update public.deals_opportunities set origin_code = 'cliente_recurrente' where id = 'bbbbbbbb-0000-0000-0000-000000000001'
$$, 'P0001', 'El origen elegido ya no está disponible; elija Referido, Outbound, Evento, Inbound u Otro',
  'Cliente recurrente ya no se asigna');
select lives_ok($$
  update public.deals_opportunities set payroll_frequency = 'quincenal',
    payroll_frequency_note = 'La planta de Pereira paga quincenal'
  where id = 'bbbbbbbb-0000-0000-0000-000000000001'
$$, 'la oportunidad registra una excepción de nómina con nota');
select is((select payroll_frequency::text from public.companies where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'mensual', 'la excepción no cambia la ficha de la empresa');

-- ---------------- N26-06 · Fecha real de la interacción ----------------
select lives_ok($$
  insert into public.deal_interaction_logs (deal_id, interaction_type, interaction_note, occurred_at)
  values ('bbbbbbbb-0000-0000-0000-000000000001', 'llamada', 'Llamada de ayer', now() - interval '1 day')
$$, 'se registra hoy una llamada de ayer');
select ok((select occurred_at < created_at - interval '23 hours' from public.deal_interaction_logs
           where interaction_note = 'Llamada de ayer'), 'ocurrió_el y registrado_el quedan separados');
select ok((select last_interaction_at < now() - interval '23 hours' from public.deals_opportunities
           where id = 'bbbbbbbb-0000-0000-0000-000000000001'), 'la inactividad cuenta desde la fecha real');
select throws_ok($$
  insert into public.deal_interaction_logs (deal_id, interaction_type, interaction_note, occurred_at)
  values ('bbbbbbbb-0000-0000-0000-000000000001', 'llamada', 'Futura', now() + interval '1 day')
$$, '23514', null, 'no se registra una interacción futura');
select throws_ok($$
  update public.deal_interaction_logs set occurred_at = now() - interval '3 days'
$$, '42501', null, 'la fecha real no se edita después');

-- ---------------- N26-07 · Propuestas ----------------
insert into public.deal_interaction_logs (deal_id, interaction_type, interaction_note)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'reunion', 'Reunión inicial');
select throws_ok($$
  update public.deals_opportunities set stage = 'propuesta_enviada' where id = 'bbbbbbbb-0000-0000-0000-000000000001'
$$, 'P0001', 'Para pasar a Propuesta Enviada registre la propuesta comercial: adjunte el archivo o justifique por qué no lo hay',
  'sin propuesta no pasa a Propuesta enviada');
select throws_ok($$
  insert into public.deal_proposals (deal_id, document_name)
  values ('bbbbbbbb-0000-0000-0000-000000000001', 'Sin nada')
$$, '23514', null, 'una propuesta lleva archivo o justificación');
select throws_ok($$
  insert into public.deal_proposals (deal_id, document_name, file_path)
  values ('bbbbbbbb-0000-0000-0000-000000000001', 'Errada', 'convenios/00000000-0000-0000-0000-0000000000c1/x.pdf')
$$, 'P0001', 'El archivo no corresponde a este tipo de soporte', 'el archivo debe ser del tipo propuestas');
select lives_ok($$
  insert into public.deal_proposals (deal_id, document_name, file_path)
  values ('bbbbbbbb-0000-0000-0000-000000000001', 'Propuesta v1', 'propuestas/00000000-0000-0000-0000-0000000000c1/p1.pdf')
$$, 'el comercial dueño adjunta la propuesta');
select lives_ok($$
  insert into public.deal_proposals (deal_id, document_name, no_file_reason)
  values ('bbbbbbbb-0000-0000-0000-000000000001', 'Ajuste de precios', 'Enviada por WhatsApp al gerente')
$$, 'o la registra con justificación');
select results_eq($$ select version from public.deal_proposals order by version $$, array[1, 2],
  'las versiones se numeran solas');
select lives_ok($$
  update public.deals_opportunities set stage = 'propuesta_enviada' where id = 'bbbbbbbb-0000-0000-0000-000000000001'
$$, 'con propuesta pasa a Propuesta enviada');
select throws_ok($$ delete from public.deal_proposals $$, '42501', null, 'las propuestas no se borran');

select pg_temp.login('00000000-0000-0000-0000-0000000000c2');

-- ---------------- Catálogos ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000f1');
select lives_ok($$
  insert into public.catalog_items (kind, name) values ('tipo_lente', 'Progresivo')
$$, 'la auxiliar de costos mantiene el catálogo de lentes');

select * from finish();
rollback;
