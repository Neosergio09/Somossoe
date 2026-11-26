-- RX al registrar la venta: create_order con fichas y autorización sensible.
-- Todos los valores son ficticios.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000c1', 'comercial@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co'),
  ('00000000-0000-0000-0000-0000000000f1', 'super@test.co');
update public.users_profiles set role = 'comercial', active = true where email = 'comercial@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';
update public.users_profiles set role = 'superadmin', active = true where email = 'super@test.co';

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
  ('bbbbbbbb-0000-0000-0000-000000000001', 'cc', '1088123456', 'Ana Pérez', now()),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'cc', '1088123457', 'Luz Gómez', now());

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.ord(p_buyer text, p_note text) returns jsonb language sql as $$
  select jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001',
    'buyer_id', 'bbbbbbbb-0000-0000-0000-00000000000' || p_buyer, 'payment_modality', 'contado', 'notes', p_note);
$$;
create function pg_temp.items() returns jsonb language sql as $$
  select '[{"item_type": "montura", "frame_description": "Repuesto", "quantity": 1, "unit_price": 100000},
           {"item_type": "gafas_completas", "frame_description": "Acetato", "lens_type": "Progresivo", "quantity": 1, "unit_price": 500000}]'::jsonb;
$$;
create function pg_temp.rx(p_od_sphere numeric default -1.25) returns jsonb language sql as $$
  select jsonb_build_object('od_sphere', p_od_sphere, 'od_cylinder', -0.50, 'od_axis', 90, 'od_add', 1.50,
    'os_sphere', -1.00, 'os_add', 1.50, 'pd_total_mm', 62, 'prescription_date', private.today_co() - 2);
$$;
create function pg_temp.status(p_note text) returns text language sql as $$
  select string_agg(s.item_type::text || ':' || coalesce(s.version::text, '-'), ',' order by s.item_type)
  from public.fabrication_spec_status((select id from public.orders where notes = p_note)) s;
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');

-- 1. Sin RX funciona como antes (dos argumentos)
select lives_ok($$ select public.create_order(pg_temp.ord('1', 'sin-rx'), pg_temp.items()) $$,
  'la venta sin RX se registra igual');
select is(pg_temp.status('sin-rx'), 'gafas_completas:-', 'el ítem con lente queda sin ficha');

-- 2. RX sin autorización: no queda nada
select throws_ok($$
  select public.create_order(pg_temp.ord('1', 'rx-sin-aut'), pg_temp.items(), jsonb_build_array(null, pg_temp.rx()))
$$, 'P0001', 'El comprador no ha autorizado el tratamiento de sus datos sensibles: regístrelo antes de guardar la ficha',
  'RX sin autorización de datos sensibles se rechaza');
select is((select count(*)::int from public.orders where notes = 'rx-sin-aut'), 0, 'y la orden no queda a medias');

-- 3. RX inválido: tampoco queda la orden
select throws_ok($$
  select public.create_order(pg_temp.ord('1', 'rx-malo'), pg_temp.items(), jsonb_build_array(null, pg_temp.rx(-1.13)), true)
$$, 'P0001', 'Ítem 2: el RX no cumple las reglas (esfera obligatoria en ambos ojos, pasos de 0.25, eje 0–180 solo con cilindro, ADD 0.50–4.00, DP y altura en mm)',
  'esfera fuera de los pasos de 0.25 se rechaza con el número de ítem');
select is((select count(*)::int from public.orders where notes = 'rx-malo'), 0, 'sin orden a medias');
select ok((select sensitive_data_consent_at is null from public.buyers where id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  'ni autorización registrada');

-- 4. RX con autorización en el mismo paso
select lives_ok($$
  select public.create_order(pg_temp.ord('1', 'rx-ok'), pg_temp.items(), jsonb_build_array(null, pg_temp.rx()), true)
$$, 'orden, autorización y RX en un solo paso');
select is(pg_temp.status('rx-ok'), 'gafas_completas:1', 'el ítem con lente queda con la ficha v1');
select ok((select sensitive_data_consent_at is not null and sensitive_data_consent_by = '00000000-0000-0000-0000-0000000000c1'
           from public.buyers where id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  'la autorización queda con fecha y usuario');

-- 5. RX en un ítem sin lente se rechaza
select throws_ok($$
  select public.create_order(pg_temp.ord('1', 'rx-montura'), pg_temp.items(), jsonb_build_array(pg_temp.rx(), null))
$$, 'P0001', 'Solo los ítems con lente llevan ficha de fabricación', 'una montura no lleva RX');

-- 6. El Super administrador no captura RX
select pg_temp.login('00000000-0000-0000-0000-0000000000f1');
select throws_ok($$
  select public.create_order(pg_temp.ord('2', 'rx-super'), pg_temp.items(), jsonb_build_array(null, pg_temp.rx()), true)
$$, '42501', null, 'el Super administrador no registra RX');

select * from finish();
rollback;
