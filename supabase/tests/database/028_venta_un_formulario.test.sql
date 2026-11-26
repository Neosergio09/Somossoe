-- «Registrar venta» en un solo paso: asistencia + comprador + orden + RX.
-- Todos los valores son ficticios.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000c1', 'comercial@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co');
update public.users_profiles set role = 'comercial', active = true where email = 'comercial@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';

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
insert into public.campaign_sessions (id, campaign_id, session_date, start_time, end_time, responsible_user_id)
values ('5e550000-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000001', private.today_co(), '08:00', '12:00', '00000000-0000-0000-0000-0000000000b1');
-- Una persona ya agendada y un comprador ya existente
insert into public.campaign_attendance (campaign_id, session_id, full_name, document_id, status)
values ('eeeeeeee-0000-0000-0000-000000000001', '5e550000-0000-0000-0000-000000000001', 'Luz Gómez', '1088000002', 'agendado');
insert into public.buyers (id, document_type, document_id, full_name, data_consent_at) values
  ('bbbbbbbb-0000-0000-0000-000000000002', 'cc', '1088000002', 'Luz Gómez', now());

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.sale(p_doc text, p_name text, p_extra jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object('session_id', '5e550000-0000-0000-0000-000000000001', 'document_type', 'cc',
    'document_id', p_doc, 'full_name', p_name, 'phone', '3001234567', 'data_consent', true,
    'payment_modality', 'nomina_empresa', 'installments_count', 2,
    'first_due_date', (private.today_co() + 35)::text, 'employee_auth_received', true,
    'planned_lab_provider_id', '11111111-0000-0000-0000-000000000001') || p_extra;
$$;
create function pg_temp.items() returns jsonb language sql as $$
  select '[{"item_type": "gafas_completas", "frame_description": "Acetato", "lens_type": "Progresivo", "quantity": 1, "unit_price": 450000}]'::jsonb;
$$;
create function pg_temp.rx(p_od_sphere numeric default -1.25) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('od_sphere', p_od_sphere, 'od_cylinder', -0.50, 'od_axis', 90, 'od_add', 1.50,
    'os_sphere', -1.00, 'os_add', 1.50));
$$;
create function pg_temp.n(p_doc text) returns text language sql as $$
  select (select count(*) from public.buyers where document_id = p_doc) || '/' ||
         (select count(*) from public.campaign_attendance where document_id = p_doc) || '/' ||
         (select count(*) from public.orders o join public.buyers b on b.id = o.buyer_id where b.document_id = p_doc);
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');

-- 1. Persona nueva: todo en un paso
select lives_ok($$
  select public.register_campaign_sale('eeeeeeee-0000-0000-0000-000000000001', pg_temp.sale('1088000001', 'Ana Pérez'),
    pg_temp.items(), pg_temp.rx(), true)
$$, 'venta nueva con RX en un solo paso');
select is(pg_temp.n('1088000001'), '1/1/1', 'crea comprador, asistencia y orden');
select is((select status::text from public.campaign_attendance where document_id = '1088000001'), 'atendido', 'la asistencia queda atendida');
select ok((select a.buyer_id is not null from public.campaign_attendance a where a.document_id = '1088000001'),
  'la asistencia queda vinculada al comprador');
select is((select planned_lab_provider_id::text from public.orders o join public.buyers b on b.id = o.buyer_id where b.document_id = '1088000001'),
  '11111111-0000-0000-0000-000000000001', 'guarda el laboratorio previsto');
select is((select version::int from public.fabrication_spec_status(
            (select o.id from public.orders o join public.buyers b on b.id = o.buyer_id where b.document_id = '1088000001'))),
  1, 'el RX queda como ficha v1');
select ok((select sensitive_data_consent_at is not null from public.buyers where document_id = '1088000001'),
  'registra la autorización de datos sensibles');

-- 2. Persona agendada y comprador existente: no se duplica
select lives_ok($$
  select public.register_campaign_sale('eeeeeeee-0000-0000-0000-000000000001',
    pg_temp.sale('1088000002', 'Luz Gómez', '{"phone": "3109876543"}'), pg_temp.items())
$$, 'venta sin RX a una persona agendada');
select is(pg_temp.n('1088000002'), '1/1/1', 'reutiliza comprador y asistencia');
select is((select status::text || ' ' || (select phone from public.buyers where document_id = '1088000002')
           from public.campaign_attendance where document_id = '1088000002'),
  'atendido 3109876543', 'la agendada pasa a atendida y se actualiza el teléfono');

-- 3. Errores: no queda nada a medias
select throws_ok($$
  select public.register_campaign_sale('eeeeeeee-0000-0000-0000-000000000001',
    pg_temp.sale('1088000003', 'Sin Autorización', '{"data_consent": false}'), pg_temp.items())
$$, 'P0001', 'El comprador debe autorizar el tratamiento de sus datos personales', 'sin autorización de datos no se vende');
select throws_ok($$
  select public.register_campaign_sale('eeeeeeee-0000-0000-0000-000000000001', pg_temp.sale('1088000004', 'RX Malo'),
    pg_temp.items(), pg_temp.rx(-1.13), true)
$$, 'P0001', null, 'RX inválido se rechaza');
select is(pg_temp.n('1088000004'), '0/0/0', 'ni comprador, ni asistencia, ni orden a medias');
select throws_ok($$
  select public.register_campaign_sale('eeeeeeee-0000-0000-0000-000000000001',
    pg_temp.sale('1088000005', 'Otra', '{"session_id": "5e550000-0000-0000-0000-000000000099"}'), pg_temp.items())
$$, 'P0001', 'Elija la fecha (sesión) de la jornada', 'la sesión debe ser de la jornada');
select throws_ok($$
  select public.register_campaign_sale('eeeeeeee-0000-0000-0000-000000000001', pg_temp.sale('12#', 'Corta'), pg_temp.items())
$$, 'P0001', 'Cédula inválida: entre 4 y 15 letras o números, sin puntos', 'cédula inválida');

-- 4. Solo Comercial registra la venta
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  select public.register_campaign_sale('eeeeeeee-0000-0000-0000-000000000001', pg_temp.sale('1088000006', 'Operación'), pg_temp.items())
$$, null, null, 'Operación no registra ventas');

select * from finish();
rollback;
