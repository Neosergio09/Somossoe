-- Pruebas de soportes en Supabase Storage: subida, vínculo, lectura por
-- rol, archivos obligatorios y registro de consultas.
begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

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

insert into public.companies (id, name, nit, nit_dv, is_nit_provisional, sector, payroll_frequency, assigned_user_id)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Marisol SAS', '900123456', private.nit_check_digit('900123456'),
        false, 'Manufactura', 'mensual', '00000000-0000-0000-0000-0000000000c1');
insert into public.deals_opportunities (id, company_id, city_id, assigned_user_id, deal_name_branch, origin_code,
  stage, target_employees_n, estimated_close_date, tentative_campaign_date)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        (select id from public.cities where name = 'Pereira'), '00000000-0000-0000-0000-0000000000c1',
        'Marisol - Pereira', 'referido', 'convenio_firmado', 50, current_date + 10, current_date + 5);
insert into public.agreements_convenios (id, company_id, payroll_frequency, max_installments, hr_approval_required, status, approved_at)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'mensual', 4, false, 'aprobado', now());
insert into public.campaigns_jornadas (id, deal_id, agreement_id, responsible_user_id, logistics_confirmed, status)
values ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', true, 'en_ejecucion');
insert into public.buyers (id, document_type, document_id, full_name, data_consent_at) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'cc', '1088123456', 'Ana Pérez', now());

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.up(p_name text) returns void language sql as $$
  insert into storage.objects (bucket_id, name, owner_id)
  values ('soportes', p_name, split_part(p_name, '/', 2));
$$;
create function pg_temp.sees(p_name text) returns bigint language sql as $$
  select count(*) from storage.objects where bucket_id = 'soportes' and name = p_name;
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

select is((select public from storage.buckets where id = 'soportes'), false, 'el bucket de soportes es privado');

set local role authenticated;

-- ---------------- Subida ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select lives_ok($$ select pg_temp.up('ordenes/00000000-0000-0000-0000-0000000000c1/auth.pdf') $$,
  'Comercial sube un soporte de orden en su carpeta');
select throws_ok($$ select pg_temp.up('ordenes/00000000-0000-0000-0000-0000000000a1/ajeno.pdf') $$,
  '42501', null, 'nadie sube en la carpeta de otro usuario');
select throws_ok($$ select pg_temp.up('pagos/00000000-0000-0000-0000-0000000000c1/soporte.pdf') $$,
  '42501', null, 'Comercial no sube soportes de pagos');
select pg_temp.up('ordenes/00000000-0000-0000-0000-0000000000c1/otro.pdf');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select lives_ok($$ select pg_temp.up('pagos/00000000-0000-0000-0000-0000000000a1/banco.pdf') $$,
  'Administración sube el soporte bancario');
select pg_temp.up('retenciones/00000000-0000-0000-0000-0000000000a1/cert.pdf');
select pg_temp.up('ordenes/00000000-0000-0000-0000-0000000000a1/admin.pdf');

-- ---------------- Vínculo con el registro ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  select public.create_order(
    jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001', 'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001',
      'payment_modality', 'nomina_empresa', 'installments_count', 2, 'first_due_date', current_date + 20,
      'employee_auth_file_path', 'ordenes/00000000-0000-0000-0000-0000000000c1/no-existe.pdf', 'notes', 'X'),
    '[{"item_type": "montura", "frame_description": "A", "quantity": 1, "unit_price": 200000}]')
$$, 'P0001', null, 'no se vincula un archivo inexistente');
select throws_ok($$
  select public.create_order(
    jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001', 'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001',
      'payment_modality', 'nomina_empresa', 'installments_count', 2, 'first_due_date', current_date + 20,
      'employee_auth_file_path', 'ordenes/00000000-0000-0000-0000-0000000000a1/admin.pdf', 'notes', 'X'),
    '[{"item_type": "montura", "frame_description": "A", "quantity": 1, "unit_price": 200000}]')
$$, 'P0001', null, 'no se vincula un archivo subido por otro usuario');
select lives_ok($$
  select public.create_order(
    jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001', 'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001',
      'payment_modality', 'nomina_empresa', 'installments_count', 2, 'first_due_date', current_date + 20,
      'employee_auth_file_path', 'ordenes/00000000-0000-0000-0000-0000000000c1/auth.pdf', 'notes', 'Ana'),
    '[{"item_type": "montura", "frame_description": "A", "quantity": 1, "unit_price": 200000}]')
$$, 'la orden se crea con la autorización escaneada');
select is((select employee_auth_received from public.orders where notes = 'Ana'), true,
  'adjuntar el archivo marca el soporte como recibido');
select throws_ok($$
  update public.orders set hr_approval_file_path = 'ordenes/00000000-0000-0000-0000-0000000000c1/../../pagos/x.pdf'
  where notes = 'Ana'
$$, 'P0001', null, 'una ruta inventada no se acepta');

-- ---------------- Archivos obligatorios ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
update public.orders set requirements_verified = true where notes = 'Ana';
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
update public.system_settings set value = 1 where key = 'require_document_files';

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  insert into public.collections_payments (company_id, payment_date, total_received_bank, bank_reference, support_received)
  values ('aaaaaaaa-0000-0000-0000-000000000001', current_date, 200000, 'T-1', true)
$$, 'P0001', null, 'con archivos obligatorios, marcar "recibido" no basta');
select lives_ok($$
  insert into public.collections_payments (company_id, payment_date, total_received_bank, bank_reference, support_file_path)
  values ('aaaaaaaa-0000-0000-0000-000000000001', current_date, 200000, 'T-1',
          'pagos/00000000-0000-0000-0000-0000000000a1/banco.pdf')
$$, 'con el soporte bancario adjunto el pago se registra');
select is((select support_received from public.collections_payments where bank_reference = 'T-1'), true,
  'el soporte queda marcado como recibido');
select throws_ok($$
  select public.apply_payment((select id from public.collections_payments where bank_reference = 'T-1'),
    (select id from public.orders where notes = 'Ana'), 50000, 10000, true)
$$, 'P0001', null, 'la retención exige el certificado adjunto');
select lives_ok($$
  select public.apply_payment((select id from public.collections_payments where bank_reference = 'T-1'),
    (select id from public.orders where notes = 'Ana'), 50000, 10000, false,
    'retenciones/00000000-0000-0000-0000-0000000000a1/cert.pdf')
$$, 'con el certificado adjunto se aplica la retención');
select is(
  (select withholding_certificate_file_path from public.payment_allocations where withholding_applied > 0),
  'retenciones/00000000-0000-0000-0000-0000000000a1/cert.pdf', 'la asignación con retención guarda el certificado');

-- ---------------- Lectura según el registro ----------------
select is(pg_temp.sees('pagos/00000000-0000-0000-0000-0000000000a1/banco.pdf'), 1::bigint, 'Administración ve el soporte bancario');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select is(pg_temp.sees('pagos/00000000-0000-0000-0000-0000000000a1/banco.pdf'), 0::bigint,
  'Operación no ve el soporte bancario aunque conozca la ruta');
select is(pg_temp.sees('ordenes/00000000-0000-0000-0000-0000000000c1/auth.pdf'), 1::bigint,
  'Operación ve la autorización de una orden que puede consultar');
select is(pg_temp.sees('ordenes/00000000-0000-0000-0000-0000000000c1/otro.pdf'), 0::bigint,
  'un archivo sin vincular solo lo ve quien lo subió');
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select is(pg_temp.sees('ordenes/00000000-0000-0000-0000-0000000000c1/otro.pdf'), 1::bigint, 'quien lo subió sí lo ve');
select throws_ok($$ delete from storage.objects where name = 'ordenes/00000000-0000-0000-0000-0000000000c1/auth.pdf' $$,
  '42501', null, 'los soportes no se borran desde la app');
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select is(pg_temp.sees('ordenes/00000000-0000-0000-0000-0000000000c1/auth.pdf'), 1::bigint,
  'el soporte sigue disponible');

-- ---------------- Registro de consultas ----------------
select lives_ok($$ select public.log_support_access('ordenes/00000000-0000-0000-0000-0000000000c1/auth.pdf') $$,
  'se registra la consulta de un soporte visible');
select is((select count(*) from public.support_access_logs where accessed_by = '00000000-0000-0000-0000-0000000000d1'),
  1::bigint, 'Dirección ve el registro de consultas');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select public.log_support_access('pagos/00000000-0000-0000-0000-0000000000a1/banco.pdf') $$,
  '42501', null, 'no se registra (ni se permite) la consulta de un soporte no visible');

select * from finish();
rollback;
