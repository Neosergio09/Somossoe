-- =====================================================================
-- Datos de prueba SOLO para el entorno local (supabase db reset).
-- No se suben al proyecto remoto.
-- Contraseña de todos los usuarios: Somossoe2026!
-- =====================================================================

do $$
declare
  u record;
begin
  for u in
    select * from (values
      ('11111111-1111-1111-1111-111111111111'::uuid, 'direccion@somossoe.test', 'Fabián (Dirección)', 'direccion'::public.app_role),
      ('22222222-2222-2222-2222-222222222222'::uuid, 'comercial@somossoe.test', 'Laura (Comercial)', 'comercial'::public.app_role),
      ('33333333-3333-3333-3333-333333333333'::uuid, 'operacion@somossoe.test', 'Andrés (Operación)', 'operacion'::public.app_role),
      ('44444444-4444-4444-4444-444444444444'::uuid, 'cartera@somossoe.test', 'Marta (Cartera)', 'administracion_cartera'::public.app_role),
      ('55555555-5555-5555-5555-555555555555'::uuid, 'nuevo@somossoe.test', 'Usuario sin activar', null)
    ) as t (id, email, full_name, role)
  loop
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, email_change, email_change_token_new, recovery_token
    ) values (
      '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
      extensions.crypt('Somossoe2026!', extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', u.full_name),
      now(), now(), '', '', '', ''
    );

    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (
      gen_random_uuid(), u.id, u.id::text,
      jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
      'email', now(), now(), now()
    );

    if u.role is not null then
      update public.users_profiles set role = u.role, active = true where id = u.id;
    end if;
  end loop;
end;
$$;

-- Empresa de ejemplo con sede y contacto
insert into public.companies (id, name, nit, nit_dv, is_nit_provisional, sector, total_employees, payroll_frequency, assigned_user_id)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Andina Ejemplo SAS', '900123456',
        private.nit_check_digit('900123456'), false, 'Manufactura', 250, 'quincenal',
        '22222222-2222-2222-2222-222222222222');

insert into public.company_branches (company_id, name, city_id, address, is_main)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Planta Pereira',
        (select id from public.cities where name = 'Pereira'), 'Zona Industrial', true);

insert into public.contacts (company_id, full_name, role_title, area, is_coordinator, is_decision_maker, phone_whatsapp, email)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Carolina Ríos', 'Jefe de Talento Humano', 'rrhh',
        true, true, '+57 300 000 0000', 'carolina@andina.test');
