-- =====================================================================
-- Ficha de fabricación (RF-M04-07): el Super administrador (Luis) la
-- consulta en SOLO LECTURA (decisión del usuario, 27-nov-2026).
--
-- * Nueva finalidad 'consulta', exclusiva del superadmin (rol principal
--   real, private.is_superadmin()). Cada lectura queda en
--   fabrication_spec_access_logs como las demás.
-- * No captura, no valida, no corrige ni anula: save/validate/void no
--   cambian (siguen con los roles reales, sin el comodín del superadmin).
-- * Dirección, Socio, Administración y Costos siguen sin acceso.
-- =====================================================================

alter table public.fabrication_spec_access_logs drop constraint fabrication_spec_access_logs_purpose_check;
alter table public.fabrication_spec_access_logs add constraint fabrication_spec_access_logs_purpose_check
  check (purpose in ('captura', 'validacion', 'envio_laboratorio', 'correccion', 'consulta'));

create or replace function public.get_fabrication_spec(p_order_item_id uuid, p_purpose text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx record;
  v_spec public.order_fabrication_specs;
  v_comercial boolean;
  v_operacion boolean := private.fabrication_role('operacion');
  v_superadmin boolean := private.is_superadmin();
begin
  select * into v_ctx from private.fabrication_context(p_order_item_id);
  v_comercial := private.fabrication_role('comercial') and (v_ctx.o).created_by = (select auth.uid())
                 and not v_ctx.released;

  if not (v_operacion or v_comercial or v_superadmin) then
    raise exception 'La ficha de fabricación solo la consultan quien registró la orden (antes de liberarla), Operación y el Super administrador'
      using errcode = '42501';
  end if;
  if p_purpose not in ('captura', 'validacion', 'envio_laboratorio', 'correccion', 'consulta') then
    raise exception 'Finalidad de consulta no válida';
  end if;
  if p_purpose in ('validacion', 'envio_laboratorio') and not v_operacion then
    raise exception 'Esa finalidad corresponde a Operación' using errcode = '42501';
  end if;
  if p_purpose = 'consulta' and not v_superadmin then
    raise exception 'Esa finalidad corresponde al Super administrador' using errcode = '42501';
  end if;
  if p_purpose in ('captura', 'correccion') and not (v_operacion or v_comercial) then
    raise exception 'El Super administrador solo consulta la ficha' using errcode = '42501';
  end if;

  select * into v_spec from public.order_fabrication_specs s
  where s.order_item_id = p_order_item_id and s.superseded_at is null and not s.is_voided;
  if v_spec.id is null then
    return null;
  end if;
  if v_spec.values_purged_at is not null then
    raise exception 'Los valores de esta ficha se suprimieron por el plazo de conservación';
  end if;

  insert into public.fabrication_spec_access_logs (spec_id, order_id, user_id, purpose)
  values (v_spec.id, v_spec.order_id, (select auth.uid()), p_purpose);

  return jsonb_build_object(
    'spec_id', v_spec.id, 'version', v_spec.version,
    'od_sphere', v_spec.od_sphere, 'od_cylinder', v_spec.od_cylinder, 'od_axis', v_spec.od_axis,
    'od_add', v_spec.od_add, 'od_pd_mm', v_spec.od_pd_mm, 'od_height_mm', v_spec.od_height_mm,
    'os_sphere', v_spec.os_sphere, 'os_cylinder', v_spec.os_cylinder, 'os_axis', v_spec.os_axis,
    'os_add', v_spec.os_add, 'os_pd_mm', v_spec.os_pd_mm, 'os_height_mm', v_spec.os_height_mm,
    'pd_total_mm', v_spec.pd_total_mm, 'technical_notes', v_spec.technical_notes,
    'prescription_date', v_spec.prescription_date, 'source', v_spec.source,
    'validated_at', v_spec.validated_at, 'change_reason', v_spec.change_reason);
end;
$$;
