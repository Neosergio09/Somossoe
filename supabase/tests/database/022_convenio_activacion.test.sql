-- SRS 1.6 · RF-M01-01 y RF-M01-03: activación de convenio sin aprobación
-- previa, control posterior de Dirección, prórroga, versiones del PDF y
-- NIT en firme por Comercial.
begin;
create extension if not exists pgtap with schema extensions;
select plan(30);

-- ---------------- Preparación (como postgres) ----------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'direccion@test.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'comercial@test.co'),
  ('00000000-0000-0000-0000-0000000000c2', 'comercial2@test.co'),
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.co');
update public.users_profiles set role = 'direccion', active = true where email = 'direccion@test.co';
update public.users_profiles set role = 'comercial', active = true where email in ('comercial@test.co', 'comercial2@test.co');
update public.users_profiles set role = 'administracion_cartera', active = true where email = 'admin@test.co';

-- Empresa de c1 con NIT provisional; empresa de c2
insert into public.companies (id, name, nit, nit_dv, sector, payroll_frequency, assigned_user_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Marisol SAS', '900123456', private.nit_check_digit('900123456'),
   'Manufactura', 'mensual', '00000000-0000-0000-0000-0000000000c1'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'Andina SAS', '800197268', private.nit_check_digit('800197268'),
   'Retail', 'mensual', '00000000-0000-0000-0000-0000000000c2');

insert into public.agreements_convenios (id, company_id, payroll_frequency, max_installments, valid_from, valid_until) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'mensual', 4,
   current_date - 1, current_date + 365),
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', 'mensual', 4,
   current_date - 1, current_date + 365);

insert into storage.objects (bucket_id, name, owner_id) values
  ('soportes', 'convenios/00000000-0000-0000-0000-0000000000c1/v1.pdf', '00000000-0000-0000-0000-0000000000c1'),
  ('soportes', 'convenios/00000000-0000-0000-0000-0000000000c1/v2.pdf', '00000000-0000-0000-0000-0000000000c1'),
  ('soportes', 'convenios/00000000-0000-0000-0000-0000000000c1/v3.pdf', '00000000-0000-0000-0000-0000000000c1'),
  ('soportes', 'convenios/00000000-0000-0000-0000-0000000000c2/andina.pdf', '00000000-0000-0000-0000-0000000000c2');
insert into public.agreement_documents (id, agreement_id, document_name, document_type, file_path) values
  ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 'Convenio v1', 'convenio_firmado',
   'convenios/00000000-0000-0000-0000-0000000000c1/v1.pdf'),
  ('dddddddd-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000002', 'Convenio Andina', 'convenio_firmado',
   'convenios/00000000-0000-0000-0000-0000000000c2/andina.pdf');

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.a1() returns public.agreements_convenios language sql as $$
  select * from public.agreements_convenios where id = 'cccccccc-0000-0000-0000-000000000001';
$$;

do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = pg_my_temp_schema() loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

set local role authenticated;

-- ---------------- Requisitos de activación ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  update public.agreements_convenios set status = 'aprobado' where id = 'cccccccc-0000-0000-0000-000000000001'
$$, 'P0001', 'Faltan requisitos para activar el convenio: NIT de la empresa en firme',
  'sin NIT en firme no se activa');

select lives_ok($$
  update public.companies set is_nit_provisional = false where id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, 'comercial confirma el NIT de su empresa');

select lives_ok($$
  update public.agreements_convenios set valid_until = null where id = 'cccccccc-0000-0000-0000-000000000001'
$$, 'en borrador la vigencia se edita');
select throws_ok($$
  update public.agreements_convenios set status = 'aprobado' where id = 'cccccccc-0000-0000-0000-000000000001'
$$, 'P0001', 'Faltan requisitos para activar el convenio: vigencia completa (desde y hasta)',
  'sin vigencia completa no se activa');
update public.agreements_convenios set valid_from = private.today_co() - 30, valid_until = private.today_co() - 1
where id = 'cccccccc-0000-0000-0000-000000000001';
select throws_ok($$
  update public.agreements_convenios set status = 'aprobado' where id = 'cccccccc-0000-0000-0000-000000000001'
$$, 'P0001', 'Faltan requisitos para activar el convenio: vigencia no vencida',
  'con la vigencia vencida no se activa');
update public.agreements_convenios set valid_from = private.today_co() - 1, valid_until = private.today_co() + 180
where id = 'cccccccc-0000-0000-0000-000000000001';

-- Comercial de otra empresa: la RLS no le deja tocar el convenio
select pg_temp.login('00000000-0000-0000-0000-0000000000c2');
update public.agreements_convenios set status = 'aprobado' where id = 'cccccccc-0000-0000-0000-000000000001';
select is((pg_temp.a1()).status::text, 'borrador', 'comercial de otra empresa no activa el convenio');
update public.companies set is_nit_provisional = true where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select is((select is_nit_provisional from public.companies where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  false, 'comercial de otra empresa no cambia el NIT');

-- ---------------- Versiones en borrador ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$
  insert into public.agreement_documents (agreement_id, document_name, document_type, file_path, replaces_id)
  values ('cccccccc-0000-0000-0000-000000000001', 'Convenio v2', 'convenio_firmado',
          'convenios/00000000-0000-0000-0000-0000000000c1/v2.pdf', 'dddddddd-0000-0000-0000-000000000001')
$$, '23514', null, 'reemplazar exige motivo');
insert into public.agreement_documents (agreement_id, document_name, document_type, file_path, replaces_id, replace_reason)
values ('cccccccc-0000-0000-0000-000000000001', 'Convenio v2', 'convenio_firmado',
        'convenios/00000000-0000-0000-0000-0000000000c1/v2.pdf', 'dddddddd-0000-0000-0000-000000000001', 'Escaneo legible');
select isnt((select superseded_at from public.agreement_documents where id = 'dddddddd-0000-0000-0000-000000000001'),
  null, 'la versión anterior queda reemplazada');
delete from public.agreement_documents where document_name = 'Convenio v2';
select is((select superseded_at from public.agreement_documents where id = 'dddddddd-0000-0000-0000-000000000001'),
  null, 'al borrar la versión nueva en borrador, la anterior vuelve a estar vigente');

-- ---------------- Activación ----------------
select lives_ok($$
  update public.agreements_convenios set status = 'aprobado' where id = 'cccccccc-0000-0000-0000-000000000001'
$$, 'comercial activa el convenio que cumple los requisitos');
select is((pg_temp.a1()).approved_by, '00000000-0000-0000-0000-0000000000c1'::uuid, 'queda quién lo activó');

reset role;
select is((public.circuit_summary() ->> 'convenios_por_revisar')::int, 1, 'el convenio queda por revisar en el circuito');
set local role authenticated;

-- NIT bloqueado para Comercial con convenio activo
select throws_ok($$
  update public.companies set is_nit_provisional = true where id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, '42501', null, 'con convenio activo comercial no cambia el NIT');

-- Condiciones congeladas y prórroga
select throws_ok($$
  update public.agreements_convenios set hr_approval_required = false where id = 'cccccccc-0000-0000-0000-000000000001'
$$, 'P0001', null, 'las condiciones de un convenio activo no cambian');
select throws_ok($$
  update public.agreements_convenios set valid_until = private.today_co() + 400,
    validity_extension_reason = 'Renovación' where id = 'cccccccc-0000-0000-0000-000000000001'
$$, '42501', null, 'comercial no prorroga la vigencia');

-- Versión nueva del convenio firmado en un convenio activo
select throws_ok($$
  insert into public.agreement_documents (agreement_id, document_name, document_type, file_path)
  values ('cccccccc-0000-0000-0000-000000000001', 'Otro convenio', 'convenio_firmado',
          'convenios/00000000-0000-0000-0000-0000000000c1/v3.pdf')
$$, 'P0001', null, 'en un convenio activo el convenio firmado solo entra como versión nueva');
select lives_ok($$
  insert into public.agreement_documents (agreement_id, document_name, document_type, file_path, replaces_id, replace_reason)
  values ('cccccccc-0000-0000-0000-000000000001', 'Convenio v3 (otrosí)', 'convenio_firmado',
          'convenios/00000000-0000-0000-0000-0000000000c1/v3.pdf', 'dddddddd-0000-0000-0000-000000000001', 'Otrosí firmado')
$$, 'se carga la versión nueva con motivo');
select is((select count(*)::int from public.agreement_documents
           where agreement_id = 'cccccccc-0000-0000-0000-000000000001'), 2, 'la versión anterior se conserva');
select is((select has_signed_file from public.v_agreements where id = 'cccccccc-0000-0000-0000-000000000001'),
  true, 'sigue habiendo un convenio firmado vigente con archivo');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$
  update public.agreements_convenios set valid_until = private.today_co() + 400 where id = 'cccccccc-0000-0000-0000-000000000001'
$$, 'P0001', 'Indique el motivo de la prórroga', 'la prórroga exige motivo');
select throws_ok($$
  update public.agreements_convenios set valid_until = private.today_co() + 10,
    validity_extension_reason = 'Recorte' where id = 'cccccccc-0000-0000-0000-000000000001'
$$, 'P0001', null, 'la prórroga no acorta la vigencia');
select lives_ok($$
  update public.agreements_convenios set valid_until = private.today_co() + 400,
    validity_extension_reason = 'Renovación anual' where id = 'cccccccc-0000-0000-0000-000000000001'
$$, 'Administración prorroga la vigencia con motivo');
select is((pg_temp.a1()).validity_extended_by, '00000000-0000-0000-0000-0000000000a1'::uuid, 'queda quién prorrogó');

-- ---------------- Control posterior de Dirección ----------------
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select throws_ok($$
  update public.agreements_convenios set status = 'cancelado' where id = 'cccccccc-0000-0000-0000-000000000001'
$$, 'P0001', 'Indique el motivo de la cancelación', 'cancelar exige motivo');
select lives_ok($$
  update public.agreements_convenios set reviewed_at = now() where id = 'cccccccc-0000-0000-0000-000000000001'
$$, 'Dirección revisa');
select throws_ok($$
  update public.agreements_convenios set reviewed_at = now() + interval '1 day' where id = 'cccccccc-0000-0000-0000-000000000001'
$$, 'P0001', 'El convenio ya fue revisado', 'la revisión se registra una sola vez');
select lives_ok($$
  update public.agreements_convenios set status = 'cancelado', cancel_reason = 'Empresa en liquidación'
  where id = 'cccccccc-0000-0000-0000-000000000001'
$$, 'Dirección cancela con motivo');
select throws_ok($$
  update public.agreements_convenios set status = 'aprobado' where id = 'cccccccc-0000-0000-0000-000000000001'
$$, 'P0001', null, 'un convenio cancelado no se reactiva');

-- Dirección activa directamente: queda revisado
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
reset role;
update public.companies set is_nit_provisional = false where id = 'aaaaaaaa-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
update public.agreements_convenios set status = 'aprobado' where id = 'cccccccc-0000-0000-0000-000000000002';
select is((select reviewed_by from public.agreements_convenios where id = 'cccccccc-0000-0000-0000-000000000002'),
  '00000000-0000-0000-0000-0000000000d1'::uuid, 'si lo activa Dirección queda revisado');

select * from finish();
rollback;
