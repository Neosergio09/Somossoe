-- Pruebas de estados de jornada y asistencia, rol Socio y costos directos
-- (Especificación Módulo de Jornadas V01).
begin;
create extension if not exists pgtap with schema extensions;
select plan(53);

-- ---------------- Preparación (como postgres) ----------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'direccion@test.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'comercial@test.co'),
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co'),
  ('00000000-0000-0000-0000-0000000000e1', 'socio@test.co');
update public.users_profiles set role = 'direccion', active = true where email = 'direccion@test.co';
update public.users_profiles set role = 'comercial', active = true where email = 'comercial@test.co';
update public.users_profiles set role = 'administracion_cartera', active = true where email = 'admin@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';
update public.users_profiles set role = 'socio', active = true where email = 'socio@test.co';

insert into public.companies (id, name, nit, nit_dv, is_nit_provisional, sector, payroll_frequency, assigned_user_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Marisol SAS', '900123456', private.nit_check_digit('900123456'),
   false, 'Manufactura', 'mensual', '00000000-0000-0000-0000-0000000000c1');
insert into public.deals_opportunities (id, company_id, city_id, assigned_user_id, deal_name_branch, origin_code,
  stage, target_employees_n, estimated_close_date, tentative_campaign_date)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        (select id from public.cities where name = 'Pereira'), '00000000-0000-0000-0000-0000000000c1',
        'Marisol - Pereira', 'referido', 'convenio_firmado', 50, current_date + 10, current_date + 5);
insert into public.agreements_convenios (id, company_id, payroll_frequency, max_installments, hr_approval_required, status, approved_at)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'mensual', 4, false, 'aprobado', now());
insert into public.buyers (id, document_type, document_id, full_name, data_consent_at) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'cc', '1088123456', 'Ana Pérez', now()),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'cc', '1088654321', 'Carlos Ruiz', now()),
  ('bbbbbbbb-0000-0000-0000-000000000003', 'cc', '10001000', 'Pedro Gómez', now());
insert into public.lab_providers (id, name) values ('11111111-0000-0000-0000-000000000001', 'Lab Demo');

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.jid() returns uuid language sql as $$
  select id from public.campaigns_jornadas where notes = 'J1';
$$;
create function pg_temp.jstatus() returns text language sql as $$
  select status::text from public.campaigns_jornadas where notes = 'J1';
$$;
create function pg_temp.ord(p_notes text) returns uuid language sql as $$
  select id from public.orders where notes = p_notes;
$$;
create function pg_temp.cost(p_source text) returns uuid language sql as $$
  select id from public.order_costs where source = p_source;
$$;
create function pg_temp.new_order(p_buyer uuid, p_notes text, p_price numeric) returns uuid language sql as $$
  select public.create_order(
    jsonb_build_object('campaign_id', pg_temp.jid(), 'buyer_id', p_buyer, 'payment_modality', 'contado', 'notes', p_notes),
    jsonb_build_array(jsonb_build_object('item_type', 'gafas_completas', 'frame_description', 'X', 'lens_type', 'Monofocal',
      'quantity', 1, 'unit_price', p_price)));
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

-- ================= Jornada: borrador → programada =================
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
insert into public.campaigns_jornadas (deal_id, agreement_id, responsible_user_id, notes)
values ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-0000000000b1', 'J1');
select is(pg_temp.jstatus(), 'borrador', 'la jornada nace en borrador');
select throws_ok($$
  update public.campaigns_jornadas set logistics_confirmed = true, status = 'en_ejecucion' where notes = 'J1'
$$, 'P0001', null, 'desde borrador no se inicia la jornada');
select throws_ok($$
  update public.campaigns_jornadas set status = 'programada' where notes = 'J1'
$$, 'P0001', null, 'sin sesiones no se programa');

insert into public.campaign_sessions (campaign_id, session_date, start_time, end_time, responsible_user_id)
values (pg_temp.jid(), current_date, '08:00', '12:00', '00000000-0000-0000-0000-0000000000b1');

-- Asistencia agendada antes de ejecutar
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  insert into public.campaign_attendance (campaign_id, session_id, full_name, document_id, status)
  select pg_temp.jid(), s.id, 'Ana Pérez', '1088123456', 'atendido'
  from public.campaign_sessions s where s.campaign_id = pg_temp.jid()
$$, 'P0001', null, 'antes de ejecutar no se marca atendido');
select lives_ok($$
  insert into public.campaign_attendance (campaign_id, session_id, full_name, document_id)
  select pg_temp.jid(), s.id, 'Ana Pérez', '1088123456'
  from public.campaign_sessions s where s.campaign_id = pg_temp.jid()
$$, 'en borrador se agenda la asistencia');
select is((select status::text from public.campaign_attendance where document_id = '1088123456'), 'agendado',
  'la asistencia nace agendada');

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
update public.campaigns_jornadas set status = 'programada' where notes = 'J1';
select is(pg_temp.jstatus(), 'programada', 'con sesión la jornada se programa');
select isnt((select scheduled_at from public.campaigns_jornadas where notes = 'J1'), null, 'se guarda la fecha de programación');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$ select pg_temp.new_order('bbbbbbbb-0000-0000-0000-000000000001', 'Ana', 300000) $$,
  'P0001', null, 'con la jornada programada no se registran órdenes');

-- ================= En ejecución: asistencia =================
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
update public.campaigns_jornadas set logistics_confirmed = true, status = 'en_ejecucion' where notes = 'J1';
select is(pg_temp.jstatus(), 'en_ejecucion', 'la jornada inicia');
insert into public.campaign_sessions (campaign_id, session_date, start_time, end_time, responsible_user_id)
values (pg_temp.jid(), current_date, '13:00', '17:00', '00000000-0000-0000-0000-0000000000b1');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
update public.campaign_attendance set status = 'atendido' where document_id = '1088123456';
select isnt((select attended_at from public.campaign_attendance where document_id = '1088123456'), null,
  'al marcar atendido se registra la hora');
select throws_ok($$
  insert into public.campaign_attendance (campaign_id, session_id, full_name, document_id, status)
  select pg_temp.jid(), s.id, 'Ana Pérez', '1088123456', 'atendido'
  from public.campaign_sessions s where s.campaign_id = pg_temp.jid() and s.start_time = '13:00'
$$, '23505', null, 'una persona tiene un solo atendido por jornada');
insert into public.campaign_attendance (campaign_id, session_id, full_name, document_id, status)
select pg_temp.jid(), s.id, x.n, x.d, x.st::public.attendance_status
from public.campaign_sessions s
cross join (values ('Carlos Ruiz', '1088654321', 'atendido'), ('Laura Díaz', '1088777777', 'no_asistio')) x (n, d, st)
where s.campaign_id = pg_temp.jid() and s.start_time = '08:00';
select is(
  (select attended_headcount || '/' || no_show_count from public.v_campaigns where notes = 'J1'),
  '2/1', 'la asistencia cuenta atendidos únicos y aparte las inasistencias');

-- ================= Órdenes y cierre de captura =================
select lives_ok($$ select pg_temp.new_order('bbbbbbbb-0000-0000-0000-000000000001', 'Ana', 300000) $$,
  'con la jornada en ejecución se registran órdenes');
select pg_temp.new_order('bbbbbbbb-0000-0000-0000-000000000002', 'Carlos', 200000);

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
update public.campaigns_jornadas set status = 'captura_cerrada' where notes = 'J1';
select isnt((select capture_closed_at from public.campaigns_jornadas where notes = 'J1'), null,
  'se registra el cierre de captura');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$ select pg_temp.new_order('bbbbbbbb-0000-0000-0000-000000000003', 'Pedro', 150000) $$,
  'P0001', null, 'con la captura cerrada no se registran órdenes');
select throws_ok($$
  update public.campaign_attendance set status = 'presente' where document_id = '1088654321'
$$, 'P0001', null, 'con la captura cerrada no cambia la asistencia');

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  update public.campaigns_jornadas set status = 'en_ejecucion' where notes = 'J1'
$$, 'P0001', null, 'la captura no se reabre sin motivo');
select throws_ok($$
  update public.campaigns_jornadas set reopen_reason = 'x' where notes = 'J1'
$$, 'P0001', null, 'el motivo de reapertura solo se registra al reabrir');
update public.campaigns_jornadas set status = 'en_ejecucion', reopen_reason = 'Venta tardía de Pedro' where notes = 'J1';
select is(
  (select status::text || '/' || (capture_reopened_at is not null) || '/' || (capture_closed_at is null)
   from public.campaigns_jornadas where notes = 'J1'),
  'en_ejecucion/true/true', 'con motivo la captura se reabre y queda el rastro');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select lives_ok($$ select pg_temp.new_order('bbbbbbbb-0000-0000-0000-000000000003', 'Pedro', 150000) $$,
  'con la captura reabierta se registra la venta tardía');

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
update public.campaigns_jornadas set status = 'captura_cerrada' where notes = 'J1';
select throws_ok($$
  update public.campaigns_jornadas set status = 'en_ejecucion', reopen_reason = 'Venta tardía de Pedro' where notes = 'J1'
$$, 'P0001', null, 'una segunda reapertura exige un motivo nuevo');

-- ================= Cierre operativo =================
select throws_ok($$
  update public.campaigns_jornadas set status = 'operacion_cerrada' where notes = 'J1'
$$, 'P0001', null, 'no se cierra la operación con órdenes sin entregar');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
update public.orders set is_cancelled = true, cancel_reason = 'Desistió' where notes = 'Pedro';
-- Las entregas se prueban en 007; aquí se simulan como postgres
reset role;
update public.orders set ops_status = 'entrega_completa' where notes in ('Ana', 'Carlos');
insert into public.post_sale_warranties (order_id, incident_type, description, responsible_user_id)
values (pg_temp.ord('Ana'), 'garantia', 'Tornillo flojo', '00000000-0000-0000-0000-0000000000b1');
set local role authenticated;

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  update public.campaigns_jornadas set status = 'operacion_cerrada' where notes = 'J1'
$$, 'P0001', null, 'no se cierra la operación con posventa abierta');
reset role;
update public.post_sale_warranties set status = 'cerrada', resolution = 'Ajuste en sitio', evidence_received = true;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select lives_ok($$
  update public.campaigns_jornadas set status = 'operacion_cerrada' where notes = 'J1'
$$, 'entregado todo y sin posventa abierta, la operación se cierra');
select throws_ok($$
  update public.campaigns_jornadas set notes = 'J1 editada' where notes = 'J1'
$$, 'P0001', null, 'una jornada con la operación cerrada no se modifica');

-- Cancelación desde borrador
insert into public.campaigns_jornadas (deal_id, agreement_id, responsible_user_id, notes)
values ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-0000000000b1', 'J2');
select lives_ok($$
  update public.campaigns_jornadas set status = 'cancelada', cancel_reason = 'Empresa pospuso' where notes = 'J2'
$$, 'un borrador se puede cancelar');

-- ================= Rol Socio =================
select pg_temp.login('00000000-0000-0000-0000-0000000000e1');
select is((select count(*) from public.v_campaigns), 2::bigint, 'el socio consulta las jornadas');
select is((select count(*) from public.orders), 3::bigint, 'el socio consulta las órdenes');
update public.campaigns_jornadas set notes = 'J2 socio' where notes = 'J2';
select is((select count(*) from public.campaigns_jornadas where notes = 'J2'), 1::bigint,
  'el socio no modifica jornadas');
select throws_ok($$
  insert into public.campaigns_jornadas (deal_id, agreement_id, responsible_user_id)
  values ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1')
$$, '42501', null, 'el socio no crea jornadas');

-- ================= Costos =================
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  insert into public.order_costs (order_id, component, amount, basis, source)
  values (pg_temp.ord('Ana'), 'lente', 100000, 'estimado', 'Cotización')
$$, '42501', null, 'Comercial no registra costos');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  insert into public.order_costs (order_id, component, amount, basis, source)
  values (pg_temp.ord('Ana'), 'lente', 100000, 'estimado', 'Cotización')
$$, '42501', null, 'Administración no registra costos');
select pg_temp.login('00000000-0000-0000-0000-0000000000e1');
select throws_ok($$
  insert into public.order_costs (order_id, component, amount, basis, source)
  values (pg_temp.ord('Ana'), 'lente', 100000, 'estimado', 'Cotización')
$$, '42501', null, 'el socio no registra costos');

select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select lives_ok($$
  insert into public.order_costs (order_id, component, amount, basis, source, lab_provider_id)
  values (pg_temp.ord('Ana'), 'lente', 120000, 'estimado', 'Cotización lab', '11111111-0000-0000-0000-000000000001')
$$, 'Dirección registra un costo estimado');
insert into public.order_costs (order_id, component, amount, basis, source)
values (pg_temp.ord('Ana'), 'montura', 80000, 'verificado', 'Factura proveedor monturas');
select is(
  (select cost_basis || '/' || cost_total || '/' || margin_amount from public.v_order_margins where order_id = pg_temp.ord('Ana')),
  'estimado/200000/100000', 'con un costo estimado el margen se marca estimado');
select is(
  (select cost_basis || '/' || coalesce(margin_amount::text, 'null') from public.v_order_margins where order_id = pg_temp.ord('Carlos')),
  'sin_costos/null', 'sin costos el margen no está disponible (no es cero)');

select lives_ok($$
  insert into public.order_costs (order_id, component, amount, basis, source, replaces_id)
  values (pg_temp.ord('Ana'), 'lente', 110000, 'verificado', 'Factura lab 77', pg_temp.cost('Cotización lab'))
$$, 'una corrección es una versión nueva');
select isnt((select superseded_at from public.order_costs where id = pg_temp.cost('Cotización lab')), null,
  'la versión anterior queda reemplazada');
select throws_ok($$
  insert into public.order_costs (order_id, component, amount, basis, source, replaces_id)
  values (pg_temp.ord('Ana'), 'lente', 100000, 'verificado', 'Otra', pg_temp.cost('Cotización lab'))
$$, 'P0001', null, 'solo se reemplaza la versión vigente');
select throws_ok($$
  insert into public.order_costs (order_id, component, amount, basis, source, replaces_id)
  values (pg_temp.ord('Carlos'), 'lente', 100000, 'verificado', 'Otra', pg_temp.cost('Factura lab 77'))
$$, 'P0001', null, 'no se reemplaza un costo de otra orden');
select throws_ok($$
  insert into public.order_costs (order_id, order_item_id, component, amount, basis, source)
  values (pg_temp.ord('Carlos'), (select id from public.order_items where order_id = pg_temp.ord('Ana')),
          'lente', 1, 'estimado', 'Ítem ajeno')
$$, '23503', null, 'el ítem del costo debe ser de la misma orden');
select throws_ok($$
  update public.order_costs set amount = 1 where source = 'Factura lab 77'
$$, '42501', null, 'un costo no se edita');
select is(
  (select cost_basis || '/' || cost_total || '/' || margin_amount || '/' || margin_ratio
   from public.v_order_margins where order_id = pg_temp.ord('Ana')),
  'verificado/190000/110000/0.3667', 'el margen usa solo las versiones vigentes');

select throws_ok($$
  update public.order_costs set is_voided = true where source = 'Factura proveedor monturas'
$$, '23514', null, 'anular exige motivo');
update public.order_costs set is_voided = true, void_reason = 'Montura de exhibición, sin costo'
where source = 'Factura proveedor monturas';
select throws_ok($$
  update public.order_costs set is_voided = true, void_reason = 'otra vez' where source = 'Factura proveedor monturas'
$$, 'P0001', null, 'un costo anulado no se vuelve a anular');
select is((select cost_total from public.v_order_margins where order_id = pg_temp.ord('Ana')), 110000::numeric,
  'el costo anulado sale del margen');
select is(
  (select sold_amount || '/' || cost_total || '/' || orders_without_costs from public.v_campaign_margins where campaign_id = pg_temp.jid()),
  '500000/110000/1', 'margen de la jornada: venta sin anuladas, costos vigentes y órdenes sin costo');
select cmp_ok((select count(*) from public.audit_logs where table_name = 'order_costs'), '>', 0::bigint,
  'Dirección ve la auditoría de costos');

-- Nadie más recibe costos
select pg_temp.login('00000000-0000-0000-0000-0000000000e1');
select is((select count(*) from public.v_order_costs), 3::bigint, 'el socio consulta los costos y su historial');
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select is(
  (select count(*) from public.order_costs) + (select count(*) from public.v_order_margins)
    + (select count(*) from public.v_campaign_margins),
  0::bigint, 'Comercial no recibe costos ni márgenes');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select is(
  (select count(*) from public.order_costs) + (select count(*) from public.v_order_margins),
  0::bigint, 'Operación no recibe costos ni márgenes');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select is(
  (select count(*) from public.order_costs) + (select count(*) from public.v_order_costs)
    + (select count(*) from public.audit_logs where table_name = 'order_costs'),
  0::bigint, 'Administración no recibe costos ni su auditoría');

select * from finish();
rollback;
