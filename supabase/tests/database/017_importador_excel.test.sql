-- Importador del Excel histórico: revisión, validación, carga y no duplicación.
begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'direccion@test.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'comercial@test.co'),
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.co');
update public.users_profiles set role = 'direccion', active = true where email = 'direccion@test.co';
update public.users_profiles set role = 'comercial', active = true where email = 'comercial@test.co';
update public.users_profiles set role = 'administracion_cartera', active = true where email = 'admin@test.co';

insert into public.companies (id, name, nit, nit_dv, is_nit_provisional, sector, payroll_frequency) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Fácil Créditos SAS', '900123456', private.nit_check_digit('900123456'),
   false, 'Servicios', 'quincenal');
insert into public.buyers (id, document_type, document_id, full_name, data_consent_at)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'cc', '10203040', 'Ya Existente', now());

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.fp(p text) returns text language sql as $$
  select encode(extensions.digest(p, 'sha256'), 'hex');
$$;
create function pg_temp.row_(p_sheet text, p_row int) returns public.excel_import_rows language sql as $$
  select r.* from public.excel_import_rows r join public.excel_import_sheets s on s.id = r.sheet_id
  where s.sheet_name = p_sheet and r.row_number = p_row order by r.loaded_at nulls last limit 1;
$$;
create function pg_temp.sheet(p_name text) returns uuid language sql as $$
  select id from public.excel_import_sheets where sheet_name = p_name order by updated_at desc limit 1;
$$;
create function pg_temp.payload() returns jsonb language sql as $$
  select jsonb_build_array(
    jsonb_build_object('sheet_name', 'FACIL CREDITOS PEREIRA', 'sheet_index', 1, 'map_code', 'L1',
      'detected_columns', jsonb_build_array('NOMBRE', 'CEDULA', 'VALOR VENTA'),
      'rows', jsonb_build_array(
        jsonb_build_object('row_number', 2, 'fingerprint', pg_temp.fp('a'), 'full_name', 'Persona Uno',
          'document_id', '1.088.111', 'phone', '3001234567', 'sale_value', 500000, 'lab_reference', 'LAB-1',
          'lab_name', 'Lab Demo', 'frame', 'MONT-A', 'lens_type', 'Progresivo',
          'cost_lens', 120000, 'cost_frame', 50000, 'cost_kit', 10000,
          'legacy_marks', jsonb_build_object('PENDIENTE', 'x')),
        jsonb_build_object('row_number', 3, 'fingerprint', pg_temp.fp('b'), 'full_name', 'Persona Dos',
          'sale_value', 300000),
        jsonb_build_object('row_number', 4, 'fingerprint', pg_temp.fp('c'), 'full_name', 'Ya Existente',
          'document_id', '10203040', 'sale_value', 600000, 'installments', 4))),
    jsonb_build_object('sheet_name', 'ENEREGIA PARTICULAR', 'sheet_index', 2, 'map_code', 'L7',
      'detected_columns', jsonb_build_array('NOMBRE'),
      'rows', jsonb_build_array(
        jsonb_build_object('row_number', 2, 'fingerprint', pg_temp.fp('a'), 'full_name', 'Persona Uno',
          'document_id', '1088111', 'sale_value', 500000, 'paid_declared', 500000),
        jsonb_build_object('row_number', 3, 'fingerprint', pg_temp.fp('d'), 'full_name', 'Persona Cuatro',
          'document_id', '55555', 'sale_value', 400000, 'paid_declared', 100000))),
    jsonb_build_object('sheet_name', 'NOVIEMBRE- EMPRESAS CLIENTES', 'sheet_index', 3, 'map_code', 'L9',
      'detected_columns', jsonb_build_array('EMPRESA'),
      'rows', jsonb_build_array(
        jsonb_build_object('row_number', 2, 'fingerprint', pg_temp.fp('e'), 'company_name', 'FACIL CREDITOS S.A.S.',
          'full_name', 'Persona Cinco', 'document_id', '66666', 'sale_value', 350000),
        jsonb_build_object('row_number', 3, 'fingerprint', pg_temp.fp('f'), 'company_name', 'Empresa Fantasma',
          'full_name', 'Persona Seis', 'document_id', '77777', 'sale_value', 200000))),
    jsonb_build_object('sheet_name', 'GARANTIAS', 'sheet_index', 4, 'map_code', 'L10',
      'skip_reason', 'Bloques mixtos sin encabezado fiable (doc §3.2)', 'rows', '[]'::jsonb));
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

-- ================= Permisos =================
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$ select public.excel_import_create('x.xlsx', repeat('a', 64), pg_temp.payload()) $$,
  '42501', null, 'Cartera no importa el Excel');

select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select lives_ok($$ select public.excel_import_create('INFORME.xlsx', repeat('a', 64), pg_temp.payload()) $$,
  'Dirección registra la importación');
select throws_ok($$ select public.excel_import_create('copia.xlsx', repeat('a', 64), pg_temp.payload()) $$,
  'P0001', null, 'el mismo archivo no se importa dos veces');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select is_empty($$ select id from public.excel_import_rows $$, 'Comercial no ve las filas (traen costos)');

-- ================= Validación =================
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select is((pg_temp.row_('FACIL CREDITOS PEREIRA', 2)).document_id, '1088111', 'el documento se normaliza sin puntos');
select is((pg_temp.row_('FACIL CREDITOS PEREIRA', 2)).status::text, 'lista', 'una fila completa queda lista');
select ok('Sin documento' = any ((pg_temp.row_('FACIL CREDITOS PEREIRA', 3)).errors), 'una fila sin documento tiene error');
select is((pg_temp.row_('ENEREGIA PARTICULAR', 2)).status::text, 'duplicada',
  'la misma venta repetida en otra pestaña se marca duplicada');
select is((pg_temp.row_('NOVIEMBRE- EMPRESAS CLIENTES', 2)).status::text, 'lista',
  'la EMPRESA de la fila se reconoce aunque cambie la escritura');
select ok((pg_temp.row_('NOVIEMBRE- EMPRESAS CLIENTES', 3)).errors[1] like 'Empresa «Empresa Fantasma»%',
  'una empresa que no está en el CRM es un error');
select is((select status::text from public.excel_import_sheets where sheet_name = 'GARANTIAS'), 'omitida',
  'GARANTIAS queda omitida');
select throws_ok($$ update public.excel_import_sheets set status = 'pendiente' where sheet_name = 'GARANTIAS' $$,
  'P0001', null, 'una hoja no importable no se activa');

-- Nómina por cuotas: necesita empresa y plan
update public.excel_import_sheets set modality_rule = 'segun_cuotas', company_id = 'aaaaaaaa-0000-0000-0000-000000000001'
where sheet_name = 'FACIL CREDITOS PEREIRA';
select public.excel_import_validate_sheet(pg_temp.sheet('FACIL CREDITOS PEREIRA'));
select ok((pg_temp.row_('FACIL CREDITOS PEREIRA', 4)).errors[1] like 'Nómina con saldo: indique en la hoja%',
  'nómina con saldo exige periodicidad y próxima cuota');

select throws_ok($$ select public.excel_import_load_sheet(pg_temp.sheet('FACIL CREDITOS PEREIRA')) $$,
  'P0001', 'Hay 2 fila(s) con error: corríjalas u omítalas antes de cargar', 'con errores no se carga');

update public.excel_import_sheets set installment_periodicity = 'quincenal', first_due_date = current_date + 15
where sheet_name = 'FACIL CREDITOS PEREIRA';
update public.excel_import_rows set document_id = '20.304.050' where full_name = 'Persona Dos';
select public.excel_import_validate_sheet(pg_temp.sheet('FACIL CREDITOS PEREIRA'));
select is((pg_temp.row_('FACIL CREDITOS PEREIRA', 3)).status::text, 'lista', 'al corregir el documento la fila queda lista');

-- ================= Carga =================
select is(public.excel_import_load_sheet(pg_temp.sheet('FACIL CREDITOS PEREIRA')), 3, 'se cargan las 3 filas');
select is((select count(*)::int from public.orders where is_historical_migration), 3, 'se crean 3 órdenes históricas');
select is(
  (select payment_modality || '/' || ops_status || '/' || historical_collected_before_migration
   from public.orders where id = (pg_temp.row_('FACIL CREDITOS PEREIRA', 2)).order_id),
  'contado/entrega_completa/0', 'sin ABONO y regla «saldo pendiente»: contado entregado con todo el saldo');
select is((select count(*)::int from public.order_installments
           where order_id = (pg_temp.row_('FACIL CREDITOS PEREIRA', 4)).order_id), 4,
  'la venta por nómina genera su plan de cuotas');
select is((pg_temp.row_('FACIL CREDITOS PEREIRA', 4)).buyer_id, 'bbbbbbbb-0000-0000-0000-000000000001'::uuid,
  'el comprador existente se reutiliza por documento');
select is((select data_consent_at from public.buyers where document_id = '1088111'), null,
  'un comprador importado no recibe autorización de datos ficticia');
select is(
  (select string_agg(component || ':' || amount || ':' || basis, ',' order by component)
   from public.order_costs where order_id = (pg_temp.row_('FACIL CREDITOS PEREIRA', 2)).order_id),
  'lente:120000:estimado,montura:50000:estimado,kit:10000:estimado', 'los costos entran como estimados');
select ok((select notes from public.orders where id = (pg_temp.row_('FACIL CREDITOS PEREIRA', 2)).order_id)
  like '%Ref. laboratorio: LAB-1%', 'la referencia del laboratorio queda en la orden');
select ok((select notes from public.orders where id = (pg_temp.row_('FACIL CREDITOS PEREIRA', 2)).order_id)
  not like '%PENDIENTE%', 'las marcas legadas no pasan a la orden');
select is((select status::text from public.excel_import_sheets where sheet_name = 'FACIL CREDITOS PEREIRA'), 'cargada',
  'la hoja queda cargada');
select throws_ok($$ update public.excel_import_rows set full_name = 'Otro' where full_name = 'Persona Uno' and status = 'cargada' $$,
  'P0001', null, 'una fila cargada no se modifica');

-- Abono declarado y venta pendiente de producir
update public.excel_import_sheets set historical_stage = 'venta' where sheet_name = 'ENEREGIA PARTICULAR';
select is(public.excel_import_load_sheet(pg_temp.sheet('ENEREGIA PARTICULAR')), 1,
  'la hoja Contado carga solo la venta que no estaba repetida');
select is(
  (select total_amount || '/' || historical_collected_before_migration || '/' || ops_status
   from public.orders where id = (pg_temp.row_('ENEREGIA PARTICULAR', 3)).order_id),
  '400000/100000/pendiente_liberar', 'el ABONO declarado queda como recaudo previo');
select is((select count(*)::int from public.order_items where order_id = (pg_temp.row_('ENEREGIA PARTICULAR', 3)).order_id), 1,
  'una venta pendiente de producir lleva su ítem');

-- Reimportar otra copia del archivo no duplica lo cargado
select lives_ok($$ select public.excel_import_create('INFORME (2).xlsx', repeat('b', 64), pg_temp.payload()) $$,
  'otra copia del archivo se puede subir');
select is(
  (select r.status::text from public.excel_import_rows r join public.excel_imports i on i.id = r.import_id
   where i.file_name = 'INFORME (2).xlsx' and r.row_number = 2
     and r.sheet_id = (select id from public.excel_import_sheets s where s.import_id = i.id and s.sheet_index = 1)),
  'duplicada', 'una fila ya cargada desde otra copia queda duplicada');

select throws_ok($$ update public.excel_imports set status = 'descartada' where file_name = 'INFORME.xlsx' $$,
  'P0001', null, 'no se descarta una importación con hojas cargadas');
select lives_ok($$ update public.excel_imports set status = 'descartada' where file_name = 'INFORME (2).xlsx' $$,
  'una importación sin cargas se descarta');

select * from finish();
rollback;
