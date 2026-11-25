-- Importador con la plantilla 2026 (L11): etapa por estado del lente, filas
-- que no son ventas a Seguimiento de la jornada, avisos y margen de
-- históricos sin ítems.
begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'direccion@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co');
update public.users_profiles set role = 'direccion', active = true where email = 'direccion@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';

insert into public.companies (id, name, nit, nit_dv, is_nit_provisional, sector, payroll_frequency) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Magnetron SAS', '900123456', private.nit_check_digit('900123456'),
   false, 'Manufactura', 'quincenal');
insert into public.deals_opportunities (id, company_id, city_id, assigned_user_id, deal_name_branch, origin_code,
  stage, target_employees_n, estimated_close_date, tentative_campaign_date)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        (select id from public.cities where name = 'Pereira'), '00000000-0000-0000-0000-0000000000d1',
        'Magnetron - Pereira', 'referido', 'convenio_firmado', 50, private.today_co() + 10, private.today_co() + 5);
insert into public.agreements_convenios (id, company_id, payroll_frequency, max_installments, hr_approval_required, status, approved_at)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'quincenal', 4, false, 'aprobado', now());
insert into public.campaigns_jornadas (id, deal_id, agreement_id, responsible_user_id, logistics_confirmed, status)
values ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', true, 'captura_cerrada');
insert into public.campaign_sessions (campaign_id, session_date, start_time, end_time, responsible_user_id)
values ('eeeeeeee-0000-0000-0000-000000000001', private.today_co() - 40, '08:00', '12:00', '00000000-0000-0000-0000-0000000000b1');

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.fp(p text) returns text language sql as $$
  select encode(extensions.digest(p, 'sha256'), 'hex');
$$;
create function pg_temp.row_(p_row int) returns public.excel_import_rows language sql as $$
  select * from public.excel_import_rows where row_number = p_row;
$$;
create function pg_temp.sheet() returns uuid language sql as $$
  select id from public.excel_import_sheets where sheet_name = 'MAGNETRON';
$$;
create function pg_temp.ord(p_row int) returns public.orders language sql as $$
  select o.* from public.orders o join public.excel_import_rows r on r.order_id = o.id where r.row_number = p_row;
$$;
create function pg_temp.payload() returns jsonb language sql as $$
  select jsonb_build_array(
    jsonb_build_object('sheet_name', 'MAGNETRON', 'sheet_index', 1, 'map_code', 'L11',
      'detected_columns', jsonb_build_array('NOMBRE', 'CEDULA', 'VALOR VENTA', 'ESTADO DEL LENTE'),
      'rows', jsonb_build_array(
        jsonb_build_object('row_number', 6, 'fingerprint', pg_temp.fp('a'), 'full_name', 'Entregado Completo',
          'document_id', '1001', 'sale_value', 370000, 'paid_declared', 370000, 'lens_status', 'entregado',
          'lab_reference', '8757', 'cost_lens', 32000, 'cost_frame', 35000, 'cost_kit', 3000,
          'legacy_marks', jsonb_build_object('MEDIO DE PAGO', 'Banco'), 'row_kind', 'venta'),
        jsonb_build_object('row_number', 7, 'fingerprint', pg_temp.fp('b'), 'full_name', 'Llego Sin Costo',
          'document_id', '1002', 'sale_value', 450000, 'paid_declared', 100000, 'lens_status', 'por_entregar',
          'lab_reference', '053', 'cost_frame', 35000, 'cost_kit', 3000, 'row_kind', 'venta'),
        jsonb_build_object('row_number', 8, 'fingerprint', pg_temp.fp('c'), 'full_name', 'En Lab',
          'document_id', '1003', 'sale_value', 300000, 'paid_declared', 300000, 'lens_status', 'en_laboratorio',
          'row_kind', 'venta'),
        jsonb_build_object('row_number', 9, 'fingerprint', pg_temp.fp('d'), 'full_name', 'Por Pedir Sin Abono',
          'document_id', '1004', 'sale_value', 500000, 'lens_status', 'por_pedir', 'lens_type', 'CR FOTO BLUE',
          'row_kind', 'venta'),
        jsonb_build_object('row_number', 22, 'fingerprint', pg_temp.fp('e'), 'full_name', 'Pendiente Llamar',
          'document_id', '2001', 'phone', '3001234567', 'sale_value', 300000, 'paid_declared', 70000,
          'lens_status', 'por_pedir', 'row_kind', 'pendiente_cierre',
          'section_label', 'PENDIENTES POR LLAMAR · no contestan o no han abonado'),
        jsonb_build_object('row_number', 36, 'fingerprint', pg_temp.fp('f'), 'full_name', 'Ya No Quiso',
          'document_id', '2002', 'sale_value', 420000, 'row_kind', 'desistio', 'section_label', 'DESISTIERON'))));
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');

select lives_ok($$ select public.excel_import_create('SOE - JORNADAS (nuevo).xlsx', repeat('b', 64), pg_temp.payload()) $$,
  'se registra un archivo con la plantilla 2026 (mapa L11)');
select is((select row_kind::text || '/' || lens_status from public.excel_import_rows where row_number = 7),
  'venta/por_entregar', 'se guardan el tipo de fila y el estado del lente');
select is((pg_temp.row_(22)).errors,
  array['No compró: asigne la jornada del CRM a la hoja para pasarlo a Seguimiento, u omita la fila'],
  'sin jornada asignada, quien no compró queda con error (no se carga como venta)');

update public.excel_import_sheets
set company_id = 'aaaaaaaa-0000-0000-0000-000000000001', modality_rule = 'contado',
    campaign_id = 'eeeeeeee-0000-0000-0000-000000000001'
where id = pg_temp.sheet();
select public.excel_import_validate_sheet(pg_temp.sheet());
select is((select count(*) from public.excel_import_rows where status = 'lista'), 6::bigint,
  'con la jornada asignada todas las filas quedan listas');
select is((pg_temp.row_(9)).warnings,
  array['Contado sin abono registrado: entra con el saldo total. Verifique si ya pagó.'],
  'contado sin abono: aviso que no bloquea');
select is((pg_temp.row_(22)).warnings,
  array['Figura como «no compró» pero tiene un abono de $70.000: queda en la nota del seguimiento'],
  'un abono en quien no compró se avisa');

select is(public.excel_import_load_sheet(pg_temp.sheet()), 6, 'se cargan 4 ventas y 2 seguimientos');

-- Ventas: la etapa sale del estado del lente
select is((select historical_stage || '/' || ops_status from pg_temp.ord(6)), 'entregada/entrega_completa', 'entregado');
select is((select historical_stage || '/' || ops_status from pg_temp.ord(7)), 'produccion/listo_para_entregar', 'llegó, por entregar');
select is((select historical_stage || '/' || ops_status from pg_temp.ord(8)), 'produccion/en_produccion', 'en laboratorio');
select is(
  (select o.historical_stage || '/' || o.ops_status || '/' || count(i.id)
   from pg_temp.ord(9) o left join public.order_items i on i.order_id = o.id group by o.historical_stage, o.ops_status),
  'venta/pendiente_liberar/1', 'por pedir: venta con su ítem, pendiente de liberar');
select is((select balance_due from pg_temp.ord(9)), 500000::numeric, 'contado sin abono entra con el saldo total');
select ok((select notes like '%Medio de pago: Banco%' and notes like '%Estado en el Excel: entregado%' from pg_temp.ord(6)),
  'la nota de la orden conserva medio de pago y estado del Excel');

-- Margen: histórico sin ítems exige lente, montura y kit
select is((select cost_basis || '/' || coalesce(margin_amount::text, '-') from public.v_order_margins where order_id = (pg_temp.ord(6)).id),
  'estimado/300000', 'con lente, montura y kit el margen aparece');
select is((select cost_basis || '/' || missing_cost_components::text || '/' || coalesce(margin_amount::text, '-')
           from public.v_order_margins where order_id = (pg_temp.ord(7)).id),
  'incompleto/{lente}/-', 'sin costo de lente no hay margen');

-- No compraron: seguimiento en la jornada, sin órdenes
select is((select count(*) from public.excel_import_rows where row_number in (22, 36) and order_id is not null), 0::bigint,
  'quienes no compraron no crean órdenes');
select is(
  (select a.status || '/' || a.followup_status || '/' || a.followup_date from public.campaign_attendance a where a.document_id = '2001'),
  'atendido/pendiente_cierre/' || private.today_co(), 'pendiente por llamar queda en seguimiento para hoy');
select ok((select followup_note like 'Excel: PENDIENTES POR LLAMAR%Abonó $70.000%' from public.campaign_attendance where document_id = '2001'),
  'la nota trae la sección y el abono');
select is((select followup_status::text from public.v_attendance_followups where document_id = '2002'), 'desistio',
  'el desistido aparece en la lista de seguimiento');

select * from finish();
rollback;
