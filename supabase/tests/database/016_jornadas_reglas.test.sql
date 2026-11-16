-- Reglas del doc «Módulo Jornadas V01»: descuento por línea, checklist,
-- capacidad y reprogramación de sesiones con historial.
begin;
create extension if not exists pgtap with schema extensions;
select plan(34);

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

insert into public.companies (id, name, nit, nit_dv, is_nit_provisional, sector, payroll_frequency, assigned_user_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Marisol SAS', '900123456', private.nit_check_digit('900123456'),
   false, 'Manufactura', 'mensual', '00000000-0000-0000-0000-0000000000c1');
insert into public.deals_opportunities (id, company_id, city_id, assigned_user_id, deal_name_branch, origin_code,
  stage, target_employees_n, estimated_close_date, tentative_campaign_date)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        (select id from public.cities where name = 'Pereira'), '00000000-0000-0000-0000-0000000000c1',
        'Marisol - Pereira', 'referido', 'convenio_firmado', 50, current_date + 10, current_date + 5);
insert into public.agreements_convenios (id, company_id, payroll_frequency, max_installments, hr_approval_required,
  status, approved_at, valid_from, valid_until)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'mensual', 4, false,
        'aprobado', now(), current_date - 30, current_date + 60);
insert into public.buyers (id, document_type, document_id, full_name, data_consent_at) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'cc', '1088123456', 'Ana Pérez', now());

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.jid() returns uuid language sql as $$
  select id from public.campaigns_jornadas where notes = 'J1';
$$;
create function pg_temp.sid() returns uuid language sql as $$
  select id from public.campaign_sessions where campaign_id = pg_temp.jid() order by created_at limit 1;
$$;
create function pg_temp.oid_() returns uuid language sql as $$
  select id from public.orders where notes = 'Ana';
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

-- ================= Capacidad y reprogramación =================
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
insert into public.campaigns_jornadas (deal_id, agreement_id, responsible_user_id, notes)
values ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-0000000000b1', 'J1');

select throws_ok($$
  insert into public.campaign_sessions (campaign_id, session_date, start_time, end_time, responsible_user_id, capacity)
  values (pg_temp.jid(), current_date + 3, '08:00', '12:00', '00000000-0000-0000-0000-0000000000b1', 0)
$$, '23514', null, 'la capacidad debe ser positiva');
select lives_ok($$
  insert into public.campaign_sessions (campaign_id, session_date, start_time, end_time, responsible_user_id, capacity, location_detail)
  values (pg_temp.jid(), current_date + 3, '08:00', '12:00', '00000000-0000-0000-0000-0000000000b1', 30, 'Sala A')
$$, 'la sesión admite capacidad');
select lives_ok($$
  update public.campaign_sessions set capacity = 40 where id = pg_temp.sid()
$$, 'Operación cambia la capacidad');
select throws_ok($$
  update public.campaign_sessions set session_date = current_date + 4 where id = pg_temp.sid()
$$, '42501', null, 'la fecha no se cambia directamente: se reprograma');

select throws_ok($$
  select public.reschedule_campaign_session(pg_temp.sid(), current_date + 4, '08:00', '12:00', 'Sala A', '  ')
$$, 'P0001', 'Indique el motivo de la reprogramación', 'reprogramar exige motivo');
select throws_ok($$
  select public.reschedule_campaign_session(pg_temp.sid(), current_date + 90, '08:00', '12:00', 'Sala A', 'Lluvia')
$$, 'P0001', null, 'la nueva fecha respeta la vigencia del convenio');
select throws_ok($$
  select public.reschedule_campaign_session(pg_temp.sid(), current_date + 3, '08:00', '12:00', 'Sala A', 'Nada')
$$, 'P0001', 'La nueva fecha, horario y lugar son iguales a los actuales', 'reprogramar exige un cambio');
select throws_ok($$
  select public.reschedule_campaign_session(pg_temp.sid(), current_date + 4, '08:00', '12:00', 'Sala A', 'Lluvia',
    '2000-01-01 00:00:00+00')
$$, 'P0001', 'Otra persona modificó esta sesión mientras la editaba. Recargue la página y vuelva a intentarlo.',
  'una versión vieja de la sesión se rechaza');

select lives_ok($$
  select public.reschedule_campaign_session(pg_temp.sid(), current_date + 4, '09:00', '13:00', 'Sala B',
    'La empresa movió el turno', (select updated_at from public.campaign_sessions where id = pg_temp.sid()))
$$, 'Operación reprograma la sesión con motivo');
select is(
  (select session_date || ' ' || start_time || ' ' || location_detail from public.campaign_sessions where id = pg_temp.sid()),
  (current_date + 4) || ' 09:00:00 Sala B', 'la sesión queda con la nueva fecha, hora y lugar');
select is(
  (select previous_date || ' ' || previous_start_time || ' ' || previous_location || ' · ' || reason
   from public.campaign_session_reschedules where session_id = pg_temp.sid()),
  (current_date + 3) || ' 08:00:00 Sala A · La empresa movió el turno', 'el historial guarda la fecha anterior y el motivo');
select is(
  (select rescheduled_by from public.campaign_session_reschedules where session_id = pg_temp.sid()),
  '00000000-0000-0000-0000-0000000000b1'::uuid, 'el historial guarda quién reprogramó');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  select public.reschedule_campaign_session(pg_temp.sid(), current_date + 5, '09:00', '13:00', 'Sala B', 'x')
$$, '42501', null, 'Comercial no reprograma');
select is((select count(*)::int from public.campaign_session_reschedules), 1, 'Comercial consulta el historial');

select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select lives_ok($$
  select public.reschedule_campaign_session(pg_temp.sid(), current_date + 5, '09:00', '13:00', 'Sala B', 'Pidió Gerencia')
$$, 'Dirección reprograma');
select throws_ok($$
  insert into public.campaign_session_reschedules (session_id, campaign_id, previous_date, previous_start_time,
    previous_end_time, new_date, new_start_time, new_end_time, reason)
  values (pg_temp.sid(), pg_temp.jid(), current_date, '08:00', '09:00', current_date, '08:00', '09:00', 'falso')
$$, '42501', null, 'el historial no se escribe directamente');

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  delete from public.campaign_sessions where id = pg_temp.sid()
$$, 'P0001', null, 'una sesión reprogramada no se elimina');

-- ================= Checklist =================
update public.campaigns_jornadas set status = 'programada' where notes = 'J1';
update public.campaigns_jornadas set logistics_confirmed = true, checklist_staff = true where notes = 'J1';
select is((select checklist_complete from public.v_campaigns where notes = 'J1'), false, 'checklist incompleto');
select throws_ok($$
  update public.campaigns_jornadas set status = 'en_ejecucion' where notes = 'J1'
$$, 'P0001', 'No se puede iniciar la jornada con el checklist incompleto', 'sin checklist completo no se inicia');

select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select throws_ok($$
  update public.campaigns_jornadas set checklist_equipment = true where notes = 'J1'
$$, '42501', null, 'Dirección no marca el checklist');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
update public.campaigns_jornadas
set checklist_equipment = true, checklist_materials = true, checklist_notice = true where notes = 'J1';
select is((select checklist_complete from public.v_campaigns where notes = 'J1'), true, 'checklist completo');
select lives_ok($$
  update public.campaigns_jornadas set status = 'en_ejecucion' where notes = 'J1'
$$, 'con el checklist completo la jornada inicia');

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$
  select public.reschedule_campaign_session(pg_temp.sid(), current_date + 6, '09:00', '13:00', 'Sala B', 'Tarde')
$$, 'P0001', null, 'en ejecución ya no se reprograma');

-- ================= Descuento por línea =================
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  select public.create_order(
    jsonb_build_object('campaign_id', pg_temp.jid(), 'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001',
      'payment_modality', 'contado', 'notes', 'X'),
    jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'Metal',
      'quantity', 1, 'unit_price', 100000, 'discount_amount', 10000)))
$$, '23514', null, 'un descuento sin motivo se rechaza');
select throws_ok($$
  select public.create_order(
    jsonb_build_object('campaign_id', pg_temp.jid(), 'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001',
      'payment_modality', 'contado', 'notes', 'X'),
    jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'Metal',
      'quantity', 1, 'unit_price', 100000, 'discount_amount', 150000, 'discount_reason', 'Promo')))
$$, '23514', null, 'el descuento no supera la base de la línea');

select lives_ok($$
  select public.create_order(
    jsonb_build_object('campaign_id', pg_temp.jid(), 'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001',
      'payment_modality', 'contado', 'notes', 'Ana'),
    jsonb_build_array(
      jsonb_build_object('item_type', 'montura', 'frame_description', 'Metal',
        'quantity', 2, 'unit_price', 100000, 'discount_amount', 30000, 'discount_reason', 'Segunda montura'),
      jsonb_build_object('item_type', 'lentes', 'lens_type', 'Monofocal', 'quantity', 1, 'unit_price', 50000)))
$$, 'la orden se crea con descuento por línea');
select is((select line_total from public.order_items where order_id = pg_temp.oid_() and item_type = 'montura'),
  170000::numeric, 'neto de línea = cantidad × precio − descuento');
select is((select total_amount from public.orders where id = pg_temp.oid_()), 220000::numeric,
  'el total de la orden suma los netos');

select lives_ok($$
  update public.order_items set discount_amount = 0, discount_reason = null
  where order_id = pg_temp.oid_() and item_type = 'montura'
$$, 'Comercial retira el descuento antes de liberar');
select is((select total_amount from public.orders where id = pg_temp.oid_()), 250000::numeric,
  'el total se recalcula al cambiar el descuento');
select throws_ok($$
  update public.order_items set discount_amount = 5000
  where order_id = pg_temp.oid_() and item_type = 'lentes'
$$, '23514', null, 'al editar, el descuento también exige motivo');
select lives_ok($$
  update public.order_items set discount_amount = 5000, discount_reason = 'Cliente frecuente'
  where order_id = pg_temp.oid_() and item_type = 'lentes'
$$, 'descuento con motivo al editar');
reset role;
select is(
  (select count(*)::int from public.audit_logs where table_name = 'order_items' and action = 'UPDATE'
     and new_data ->> 'discount_reason' = 'Cliente frecuente'),
  1, 'el cambio de descuento queda auditado');

-- Histórica: los ítems suman su neto
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select lives_ok($$
  select public.create_historical_order(
    jsonb_build_object('buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001', 'payment_modality', 'contado',
      'collection_responsible', 'empleado', 'total_amount', 90000, 'balance_due', 0,
      'historical_stage', 'entregada', 'historical_reference', 'H-DESC-1'),
    jsonb_build_array(jsonb_build_object('item_type', 'montura', 'frame_description', 'Acetato',
      'quantity', 1, 'unit_price', 100000, 'discount_amount', 10000, 'discount_reason', 'Promo')))
$$, 'la orden histórica cuadra con el neto de sus ítems');

select * from finish();
rollback;
