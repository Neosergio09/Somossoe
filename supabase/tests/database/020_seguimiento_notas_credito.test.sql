-- Seguimiento de asistentes que no compraron y nota crédito del
-- laboratorio en las garantías.
begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

-- ---------------- Preparación (como postgres) ----------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'direccion@test.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'comercial@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'operacion@test.co');
update public.users_profiles set role = 'direccion', active = true where email = 'direccion@test.co';
update public.users_profiles set role = 'comercial', active = true where email = 'comercial@test.co';
update public.users_profiles set role = 'operacion', active = true where email = 'operacion@test.co';

insert into public.lab_providers (id, name, active) values
  ('11111111-0000-0000-0000-000000000001', 'Servilentes', true),
  ('11111111-0000-0000-0000-000000000002', 'CCL', true);

insert into public.companies (id, name, nit, nit_dv, is_nit_provisional, sector, payroll_frequency, assigned_user_id)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Magnetron SAS', '900123456',
        private.nit_check_digit('900123456'), false, 'Manufactura', 'mensual', '00000000-0000-0000-0000-0000000000c1');
insert into public.deals_opportunities (id, company_id, city_id, assigned_user_id, deal_name_branch, origin_code,
  stage, target_employees_n, estimated_close_date, tentative_campaign_date)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        (select id from public.cities where name = 'Pereira'), '00000000-0000-0000-0000-0000000000c1',
        'Magnetron - Pereira', 'referido', 'convenio_firmado', 50, private.today_co() + 10, private.today_co() + 5);
insert into public.agreements_convenios (id, company_id, payroll_frequency, max_installments, hr_approval_required, status, approved_at)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'mensual', 4, false, 'aprobado', now());
insert into public.campaigns_jornadas (id, deal_id, agreement_id, responsible_user_id, logistics_confirmed, status)
values ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', true, 'en_ejecucion');
insert into public.campaign_sessions (id, campaign_id, session_date, start_time, end_time, responsible_user_id)
values ('55555555-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000001', private.today_co(),
        '08:00', '12:00', '00000000-0000-0000-0000-0000000000b1');
insert into public.campaign_attendance (campaign_id, session_id, full_name, document_id, status) values
  ('eeeeeeee-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000001', 'Ana Pérez', '1088123456', 'atendido'),
  ('eeeeeeee-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000001', 'Carlos Ruiz', '1088654321', 'atendido'),
  ('eeeeeeee-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000001', 'Luis Mora', '1088777777', 'atendido'),
  ('eeeeeeee-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000001', 'Eva Gil', '1088999999', 'presente');
insert into public.buyers (id, document_type, document_id, full_name, phone, data_consent_at) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'cc', '1088123456', 'Ana Pérez', '3001234567', now()),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'cc', '1088654321', 'Carlos Ruiz', null, now());

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.att(p_doc text) returns uuid language sql as $$
  select id from public.campaign_attendance where document_id = p_doc;
$$;
create function pg_temp.w() returns uuid language sql as $$
  select id from public.post_sale_warranties limit 1;
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

-- ================= Seguimiento de asistentes =================
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
-- Carlos compra en la jornada: su asistencia queda vinculada
select public.create_order(
  jsonb_build_object('campaign_id', 'eeeeeeee-0000-0000-0000-000000000001', 'buyer_id', 'bbbbbbbb-0000-0000-0000-000000000002',
    'payment_modality', 'nomina_empresa', 'installments_count', 2,
    'first_due_date', (private.today_co() + 35)::text, 'employee_auth_received', true, 'notes', 'Carlos'),
  '[{"item_type": "montura", "frame_description": "Metálica", "quantity": 1, "unit_price": 200000}]');

select lives_ok($$
  update public.campaign_attendance
  set followup_status = 'pendiente_cierre', followup_date = private.today_co() + 10, followup_note = '  Abona en la quincena  '
  where id = pg_temp.att('1088123456')
$$, 'Comercial deja a un atendido como pendiente de cierre');
select is(
  (select followup_note || '/' || followup_updated_by from public.campaign_attendance where id = pg_temp.att('1088123456')),
  'Abona en la quincena/00000000-0000-0000-0000-0000000000c1', 'se guarda la nota y quién hizo el seguimiento');
select throws_ok($$
  update public.campaign_attendance set followup_status = 'pendiente_cierre' where id = pg_temp.att('1088777777')
$$, 'P0001', 'Indique la fecha para volver a contactar al asistente', 'pendiente de cierre exige fecha');
select throws_ok($$
  update public.campaign_attendance set followup_status = 'desistio' where id = pg_temp.att('1088999999')
$$, 'P0001', 'Solo se hace seguimiento a asistentes atendidos', 'solo atendidos');
select throws_ok($$
  update public.campaign_attendance set followup_status = 'desistio' where id = pg_temp.att('1088654321')
$$, 'P0001', 'Este asistente ya compró en la jornada', 'quien compró en la jornada no lleva seguimiento');

select lives_ok($$
  update public.campaign_attendance set followup_status = 'desistio', followup_date = private.today_co() + 3
  where id = pg_temp.att('1088777777')
$$, 'se registra que desistió');
select is((select followup_date from public.campaign_attendance where id = pg_temp.att('1088777777')), null::date,
  'desistió no guarda fecha de contacto');
update public.campaign_attendance set status = 'presente' where id = pg_temp.att('1088777777');
select is((select followup_status::text from public.campaign_attendance where id = pg_temp.att('1088777777')), null,
  'si deja de estar atendido, el seguimiento se borra');

-- Con la captura cerrada el seguimiento sigue, la asistencia no
reset role;
update public.campaigns_jornadas set status = 'captura_cerrada' where id = 'eeeeeeee-0000-0000-0000-000000000001';
set local role authenticated;
select lives_ok($$
  update public.campaign_attendance set followup_note = 'Llamar el 15' where id = pg_temp.att('1088123456')
$$, 'con la captura cerrada se actualiza el seguimiento');
select throws_ok($$
  update public.campaign_attendance set status = 'no_asistio' where id = pg_temp.att('1088123456')
$$, 'P0001', null, 'con la captura cerrada la asistencia sigue congelada');

select is(
  (select purchased || '/' || is_overdue || '/' || phone || '/' || company_name from public.v_attendance_followups
   where id = pg_temp.att('1088123456')),
  'false/false/3001234567/Magnetron SAS', 'la lista de seguimiento trae teléfono y empresa');
reset role;
update public.campaign_attendance set followup_date = private.today_co() - 1 where id = pg_temp.att('1088123456');
set local role authenticated;
select is((select is_overdue from public.v_attendance_followups where id = pg_temp.att('1088123456')), true,
  'pendiente con fecha vencida');

-- Compra después de la jornada (venta directa)
select public.create_order(
  jsonb_build_object('buyer_id', 'bbbbbbbb-0000-0000-0000-000000000001', 'payment_modality', 'contado', 'notes', 'Ana después'),
  '[{"item_type": "montura", "frame_description": "Acetato", "quantity": 1, "unit_price": 300000}]');
select is(
  (select purchased || '/' || is_overdue || '/' || (purchase_order_id = (select id from public.orders where notes = 'Ana después'))
   from public.v_attendance_followups where id = pg_temp.att('1088123456')),
  'true/false/true', 'si compra después, la lista lo muestra como compra y deja de estar vencido');
select is((select count(*) from public.v_orders where notes = 'Ana después' and campaign_id is null), 1::bigint,
  'el seguimiento nunca crea ventas: la venta es la orden');

-- ================= Nota crédito en garantías =================
reset role;
insert into public.post_sale_warranties (order_id, incident_type, description, responsible_user_id)
values ((select id from public.orders where notes = 'Carlos'), 'garantia', 'Ve borroso de lejos',
        '00000000-0000-0000-0000-0000000000b1');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');

select is((select credit_note_status::text from public.post_sale_warranties where id = pg_temp.w()), 'no_aplica',
  'por defecto la nota crédito no aplica');
select throws_ok($$
  update public.post_sale_warranties set credit_note_status = 'por_solicitar' where id = pg_temp.w()
$$, '23514', null, 'una nota crédito exige el laboratorio al que se cobra');
select lives_ok($$
  update public.post_sale_warranties
  set credit_note_status = 'por_solicitar', credit_note_lab_provider_id = '11111111-0000-0000-0000-000000000001'
  where id = pg_temp.w()
$$, 'Operación registra la nota crédito por solicitar');
select throws_ok($$
  update public.post_sale_warranties set credit_note_status = 'recibida' where id = pg_temp.w()
$$, '23514', null, 'recibida exige número y valor');

reset role;
update public.post_sale_warranties
set status = 'cerrada', resolution = 'Nueva orden a CCL', evidence_received = true, closed_at = now()
where id = pg_temp.w();
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select lives_ok($$
  update public.post_sale_warranties
  set credit_note_status = 'recibida', credit_note_amount = 45000, credit_note_reference = ' NC-778 '
  where id = pg_temp.w()
$$, 'la nota crédito se actualiza con la garantía cerrada');
select throws_ok($$
  update public.post_sale_warranties set description = 'otra' where id = pg_temp.w()
$$, 'P0001', 'Una garantía cerrada no se modifica', 'el resto de la garantía cerrada sigue bloqueado');
select is(
  (select credit_note_status || '/' || credit_note_lab_name || '/' || credit_note_amount || '/' || credit_note_reference
          || '/' || (credit_note_updated_at is not null)
   from public.v_warranties where id = pg_temp.w()),
  'recibida/Servilentes/45000/NC-778/true', 'la vista de garantías muestra la nota crédito');

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
update public.post_sale_warranties set credit_note_status = 'no_aplica' where id = pg_temp.w();

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
update public.post_sale_warranties set credit_note_status = 'no_aplica' where id = pg_temp.w();
select is(
  (select credit_note_status || '/' || coalesce(credit_note_lab_provider_id::text, '-') || '/' || coalesce(credit_note_reference, '-')
   from public.post_sale_warranties where id = pg_temp.w()),
  'no_aplica/-/-', '«no aplica» borra los datos de la nota');

select * from finish();
rollback;
