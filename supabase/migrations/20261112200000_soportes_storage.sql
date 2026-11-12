-- =====================================================================
-- Soportes documentales en Supabase Storage (RNF-02, RNF-05)
-- Decisión técnica del 2026-11-12: Supabase Storage reemplaza a
-- Cloudflare R2. Los permisos usan las mismas reglas (RLS) y roles.
--
-- * Bucket privado "soportes": sin URL pública; se consulta con enlaces
--   firmados de pocos minutos. PDF, JPG, PNG o WEBP de hasta 10 MB.
-- * Ruta: {tipo}/{usuario}/{uuid}.{ext}. Se sube primero (con enlace de
--   subida firmado) y luego el registro guarda la ruta.
-- * Ver un archivo = poder ver el registro que lo referencia (RLS de esa
--   tabla). Subir = rol con escritura sobre ese tipo de soporte.
-- * Los archivos no se modifican ni se borran desde la app.
-- * Las columnas *_r2_key pasan a *_file_path.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Columnas
-- ---------------------------------------------------------------------
alter table public.agreement_documents   rename column file_r2_key to file_path;
alter table public.buyers                rename column data_consent_r2_key to data_consent_file_path;
alter table public.collections_payments  rename column support_file_r2_key to support_file_path;
alter table public.order_deliveries      rename column delivery_evidence_r2_key to evidence_file_path;
alter table public.orders                rename column employee_auth_file_r2_key to employee_auth_file_path;
alter table public.orders                rename column hr_approval_r2_key to hr_approval_file_path;
alter table public.payment_allocations   rename column withholding_certificate_r2_key to withholding_certificate_file_path;
alter table public.post_sale_warranties  rename column evidence_r2_key to evidence_file_path;

-- Funciones que usaban los nombres anteriores (mismo código, nombres nuevos)
create or replace function private.assert_signed_agreement_document(p_agreement_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $$
declare
  v_files_required boolean := private.get_setting('require_document_files') = 1;
begin
  if not exists (
    select 1 from public.agreement_documents d
    where d.agreement_id = p_agreement_id
      and d.document_type = 'convenio_firmado'
      and (not v_files_required or d.file_path is not null)
  ) then
    raise exception '%', case when v_files_required
      then 'Falta cargar el archivo del convenio firmado por el cliente'
      else 'Falta registrar el documento de convenio firmado por el cliente' end;
  end if;
end;
$$

;
create or replace function private.agreement_documents_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $$
declare
  v_status public.agreement_status;
begin
  if current_user <> 'authenticated' then
    return coalesce(new, old);
  end if;

  select a.status into v_status
  from public.agreements_convenios a
  where a.id = coalesce(new.agreement_id, old.agreement_id);

  if tg_op = 'INSERT' then
    if v_status = 'cancelado' then
      raise exception 'No se agregan documentos a un convenio cancelado';
    end if;
    return new;
  end if;

  if v_status in ('borrador', 'pendiente_aprobacion') then
    return coalesce(new, old);
  end if;

  if tg_op = 'UPDATE'
     and (new.document_name, new.document_type) is not distinct from (old.document_name, old.document_type)
     and old.file_path is null then
    return new;
  end if;

  raise exception 'Los documentos de un convenio % no se modifican ni se eliminan', v_status;
end;
$$

;
create or replace function private.buyers_before_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $$
begin
  new.document_id := upper(regexp_replace(coalesce(new.document_id, ''), '[\s.-]', '', 'g'));
  new.full_name := trim(new.full_name);

  if current_user <> 'authenticated' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if (new.document_type, new.document_id) is distinct from (old.document_type, old.document_id)
       and exists (select 1 from public.orders o where o.buyer_id = old.id) then
      raise exception 'El documento de un comprador con órdenes no se cambia';
    end if;

    -- La autorización de tratamiento de datos se registra una vez y no se retira
    -- desde la aplicación (las solicitudes de supresión siguen el procedimiento RNF-05)
    if old.data_consent_at is not null then
      new.data_consent_at := old.data_consent_at;
      new.data_consent_by := old.data_consent_by;
      if old.data_consent_file_path is not null then
        new.data_consent_file_path := old.data_consent_file_path;
      end if;
      return new;
    end if;
  end if;

  if new.data_consent_at is not null then
    new.data_consent_at := now();
    new.data_consent_by := (select auth.uid());
  else
    new.data_consent_by := null;
  end if;
  return new;
end;
$$

;
create or replace function private.order_missing_requirements(o orders)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $$
declare
  v_missing text[] := '{}';
  v_files boolean := private.get_setting('require_document_files') = 1;
  v_agreement record;
begin
  if o.total_amount <= 0 or not exists (select 1 from public.order_items i where i.order_id = o.id) then
    v_missing := v_missing || 'Al menos un ítem con valor'::text;
  end if;

  if not exists (
    select 1 from public.buyers b
    where b.id = o.buyer_id and b.data_consent_at is not null
      and (not v_files or b.data_consent_file_path is not null)
  ) then
    v_missing := v_missing || 'Autorización de tratamiento de datos del comprador'::text;
  end if;

  if o.payment_modality = 'nomina_empresa' then
    select a.status, a.hr_approval_required into v_agreement
    from public.agreements_convenios a where a.id = o.agreement_id;

    if v_agreement.status is distinct from 'aprobado' then
      v_missing := v_missing || 'Convenio de nómina aprobado'::text;
    end if;
    if not o.employee_auth_received or (v_files and o.employee_auth_file_path is null) then
      v_missing := v_missing || 'Autorización de descuento firmada por el empleado'::text;
    end if;
    if coalesce(v_agreement.hr_approval_required, true)
       and (not o.hr_approval_received or (v_files and o.hr_approval_file_path is null)) then
      v_missing := v_missing || 'Aval de RRHH'::text;
    end if;
  end if;

  return v_missing;
end;
$$

;
create or replace function private.orders_before_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $$
declare
  v_is_api boolean := current_user = 'authenticated';
  v_campaign record;
  v_agreement record;
  v_max numeric;
  v_missing text[];
  v_plan_changed boolean;
begin
  if tg_op = 'INSERT' then
    if v_is_api then
      new.total_amount := 0;
      new.balance_due := 0;
      new.requirements_verified := false;
      new.requirements_verified_by := null;
      new.requirements_verified_at := null;
      new.prepayment_exception_reason := null;
      new.prepayment_exception_by := null;
      new.prepayment_exception_at := null;
      new.ops_status := 'pendiente_liberar';
      new.accounting_status := 'pendiente_vincular';
      new.collection_status := 'con_saldo';
      new.is_cancelled := false;
      new.cancelled_by := null;
      new.cancelled_at := null;
      new.cancel_reason := null;
    end if;

    -- Herencia de contexto (RF-M04-01)
    if new.campaign_id is not null then
      select c.company_id, c.branch_id, c.city_id, c.agreement_id, c.status
        into v_campaign
      from public.campaigns_jornadas c
      where c.id = new.campaign_id;
      if not found then
        raise exception 'Jornada no encontrada';
      end if;
      if v_is_api and v_campaign.status <> 'en_ejecucion' then
        raise exception 'Las órdenes de jornada se registran con la jornada en_ejecucion (está %). Para una venta tardía, reabra la captura',
          v_campaign.status;
      end if;
      new.company_id := v_campaign.company_id;
      new.branch_id := v_campaign.branch_id;
      new.city_id := v_campaign.city_id;
      new.agreement_id := v_campaign.agreement_id;
    elsif new.company_id is null then
      new.branch_id := null;
      new.agreement_id := null;
    end if;

    if v_is_api and not exists (
      select 1 from public.buyers b where b.id = new.buyer_id and b.data_consent_at is not null
    ) then
      raise exception 'Registre la autorización de tratamiento de datos del comprador antes de crear la orden';
    end if;

    -- Un histórico declara su responsable de cobro actual (RF-M06-05)
    if not new.is_historical_migration then
      new.collection_responsible := case when new.payment_modality = 'nomina_empresa' then 'empresa' else 'empleado' end;
    end if;

  elsif v_is_api then
    if old.is_cancelled then
      raise exception 'Una orden anulada no se modifica';
    end if;

    if (new.campaign_id, new.company_id, new.buyer_id)
       is distinct from (old.campaign_id, old.company_id, old.buyer_id) then
      raise exception 'La jornada, la empresa y el comprador de una orden no se cambian; anule y registre una nueva';
    end if;

    if new.campaign_id is not null and new.agreement_id is distinct from old.agreement_id then
      raise exception 'Una orden de jornada usa el convenio de la jornada';
    end if;
    if new.campaign_id is not null and new.branch_id is distinct from old.branch_id then
      raise exception 'Una orden de jornada usa la sede de la jornada';
    end if;

    -- Datos de la venta: Comercial hasta la verificación; después, Administración
    if (new.branch_id, new.agreement_id, new.payment_modality, new.installments_count, new.first_due_date,
        new.employee_auth_received, new.employee_auth_file_path, new.hr_approval_received,
        new.hr_approval_file_path, new.notes)
       is distinct from
       (old.branch_id, old.agreement_id, old.payment_modality, old.installments_count, old.first_due_date,
        old.employee_auth_received, old.employee_auth_file_path, old.hr_approval_received,
        old.hr_approval_file_path, old.notes) then
      if old.doc_status = 'pendiente_soportes' then
        if not private.has_role('comercial', 'administracion_cartera') then
          raise exception 'Solo Comercial o Administración / Cartera modifican la orden' using errcode = '42501';
        end if;
      elsif not private.has_role('administracion_cartera') then
        raise exception 'Con los requisitos verificados, solo Administración / Cartera modifica la orden'
          using errcode = '42501';
      end if;

      if old.ops_status <> 'pendiente_liberar'
         and (new.agreement_id, new.payment_modality, new.installments_count, new.first_due_date)
             is distinct from
             (old.agreement_id, old.payment_modality, old.installments_count, old.first_due_date) then
        raise exception 'La orden ya fue liberada a producción; su modalidad y plan de pagos no se cambian';
      end if;
    end if;

    -- Excepción de anticipo en contado (RF-M04-03): solo Dirección
    if new.prepayment_exception_reason is distinct from old.prepayment_exception_reason then
      if not private.has_role('direccion') then
        raise exception 'Solo Dirección autoriza la excepción de anticipo' using errcode = '42501';
      end if;
      if old.ops_status <> 'pendiente_liberar' then
        raise exception 'La orden ya fue liberada a producción';
      end if;
      if new.prepayment_exception_reason is null then
        new.prepayment_exception_by := null;
        new.prepayment_exception_at := null;
      else
        new.prepayment_exception_by := (select auth.uid());
        new.prepayment_exception_at := now();
      end if;
    end if;

    -- Verificación de requisitos (Etapa 07 → 08): Administración / Cartera
    if new.requirements_verified is distinct from old.requirements_verified then
      if not private.has_role('administracion_cartera') then
        raise exception 'Solo Administración / Cartera verifica los requisitos de la orden' using errcode = '42501';
      end if;
      if new.requirements_verified then
        new.requirements_verified_by := (select auth.uid());
        new.requirements_verified_at := now();
      else
        if old.ops_status <> 'pendiente_liberar' then
          raise exception 'La orden ya fue liberada a producción; la verificación no se revierte';
        end if;
        new.requirements_verified_by := null;
        new.requirements_verified_at := null;
      end if;
    end if;

    -- Anulación (RF-M04-05)
    if new.is_cancelled and not old.is_cancelled then
      if not (private.has_role('administracion_cartera')
              or (private.has_role('comercial') and old.doc_status = 'pendiente_soportes')) then
        raise exception 'Con los requisitos verificados, solo Administración / Cartera anula la orden'
          using errcode = '42501';
      end if;
      if old.accounting_status <> 'pendiente_vincular'
         or old.collection_status <> 'con_saldo'
         or old.balance_due < old.total_amount then
        raise exception 'La orden tiene pagos aplicados o factura vinculada: gestiónela como posventa o nota crédito en Alegra';
      end if;
      new.cancelled_by := (select auth.uid());
      new.cancelled_at := now();
    end if;
  end if;

  -- Ciudad de la Venta Directa: la de la sede elegida
  if new.campaign_id is null then
    new.city_id := (select b.city_id from public.company_branches b where b.id = new.branch_id);
  end if;

  v_plan_changed := tg_op = 'INSERT'
    or (new.payment_modality, new.agreement_id, new.installments_count)
       is distinct from (old.payment_modality, old.agreement_id, old.installments_count);

  -- Convenio de una Venta Directa: aprobado y vigente
  if v_is_api and new.campaign_id is null and new.agreement_id is not null
     and (tg_op = 'INSERT' or new.agreement_id is distinct from old.agreement_id
          or new.payment_modality is distinct from old.payment_modality)
     and not exists (
       select 1 from public.agreements_convenios a
       where a.id = new.agreement_id
         and a.company_id = new.company_id
         and a.status = 'aprobado'
         and (a.valid_until is null or a.valid_until >= private.today_co())
     ) then
    raise exception 'El convenio de la orden debe estar aprobado y vigente';
  end if;

  -- Descuento de nómina: periodicidad y tope de cuotas del convenio
  if new.payment_modality = 'nomina_empresa' then
    if new.agreement_id is null and not new.is_historical_migration then
      raise exception 'El descuento de nómina requiere una empresa con convenio aprobado';
    end if;
    select a.status, a.payroll_frequency, a.max_installments
      into v_agreement
    from public.agreements_convenios a
    where a.id = new.agreement_id;

    -- Un histórico conserva la periodicidad de su plan restante
    if not new.is_historical_migration then
      new.installment_periodicity := v_agreement.payroll_frequency;
    end if;

    if v_is_api and v_plan_changed then
      if v_agreement.status <> 'aprobado' then
        raise exception 'El descuento de nómina requiere un convenio aprobado (el de esta orden está %)',
          v_agreement.status;
      end if;
      v_max := least(
        v_agreement.max_installments,
        private.get_setting(case v_agreement.payroll_frequency
          when 'mensual' then 'max_installments_monthly'
          else 'max_installments_biweekly' end)
      );
      if new.installments_count > v_max then
        raise exception 'El convenio permite hasta % cuotas con nómina %', v_max, v_agreement.payroll_frequency;
      end if;
    end if;
  else
    new.installments_count := null;
    new.installment_periodicity := null;
    new.first_due_date := null;
    new.employee_auth_received := false;
    new.employee_auth_file_path := null;
    new.hr_approval_received := false;
    new.hr_approval_file_path := null;
  end if;

  if tg_op = 'UPDATE' and new.payment_modality is distinct from old.payment_modality then
    new.collection_responsible := case when new.payment_modality = 'nomina_empresa' then 'empresa' else 'empleado' end;
    if new.payment_modality <> 'contado' then
      new.prepayment_exception_reason := null;
      new.prepayment_exception_by := null;
      new.prepayment_exception_at := null;
    end if;
  end if;

  -- Una orden verificada debe seguir cumpliendo sus requisitos
  -- Se valida al verificar y cuando cambia algo que afecta los requisitos;
  -- no en cada recálculo (p. ej., el saldo al aplicar un pago), para que
  -- activar require_document_files no bloquee órdenes ya verificadas
  if new.requirements_verified and not new.is_cancelled and not new.is_historical_migration
     and (tg_op = 'INSERT' or not old.requirements_verified
          or (new.payment_modality, new.agreement_id, new.total_amount, new.employee_auth_received,
              new.employee_auth_file_path, new.hr_approval_received, new.hr_approval_file_path)
             is distinct from
             (old.payment_modality, old.agreement_id, old.total_amount, old.employee_auth_received,
              old.employee_auth_file_path, old.hr_approval_received, old.hr_approval_file_path)) then
    v_missing := private.order_missing_requirements(new);
    if cardinality(v_missing) > 0 then
      raise exception 'Faltan requisitos: %', array_to_string(v_missing, '; ');
    end if;
  end if;

  -- Estados derivados (RF-M04-04). Saldo = valor total hasta que M06
  -- registre pagos; los demás estados los derivan M05 y M06.
  new.doc_status := case when new.requirements_verified then 'requisitos_verificados' else 'pendiente_soportes' end;
  new.balance_due := new.total_amount;

  return new;
end;
$$

;
create or replace function private.order_deliveries_before_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $$
declare
  v_is_api boolean := current_user = 'authenticated';
  v_order record;
  v_production record;
  v_files boolean := private.get_setting('require_document_files') = 1;
begin
  if not v_is_api then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    if exists (
      select 1 from public.post_sale_warranties w
      where w.order_id = old.order_id and old.warranty_id is null
    ) and not exists (
      select 1 from public.order_deliveries d
      where d.order_id = old.order_id and d.warranty_id is null and d.id <> old.id
    ) then
      raise exception 'La orden tiene garantías registradas; no se puede borrar su única entrega';
    end if;
    if old.warranty_id is not null and exists (
      select 1 from public.post_sale_warranties w where w.id = old.warranty_id and w.status = 'cerrada'
    ) then
      raise exception 'La garantía está cerrada; su entrega no se borra';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' then
    if (new.order_id, new.production_id, new.warranty_id, new.delivered_at)
       is distinct from (old.order_id, old.production_id, old.warranty_id, old.delivered_at) then
      raise exception 'Solo se corrigen el receptor, la evidencia y las notas; para lo demás borre y registre la entrega';
    end if;
  else
    new.delivered_by := (select auth.uid());

    select o.is_cancelled, o.ops_status into v_order from public.orders o where o.id = new.order_id;
    if v_order.is_cancelled then
      raise exception 'Una orden anulada no se entrega';
    end if;
    if new.delivered_at > private.today_co() then
      raise exception 'La fecha de entrega no puede ser futura';
    end if;

    if new.warranty_id is null then
      select p.id, p.status into v_production
      from public.order_productions p
      where p.order_id = new.order_id and p.warranty_id is null and p.status <> 'cancelada';
      if v_production.id is null then
        raise exception 'La orden aún no se ha liberado a producción';
      end if;
    else
      if exists (select 1 from public.post_sale_warranties w where w.id = new.warranty_id and w.status = 'cerrada') then
        raise exception 'La garantía está cerrada';
      end if;
      select p.id, p.status into v_production
      from public.order_productions p
      where p.warranty_id = new.warranty_id and p.status <> 'cancelada';
      if v_production.status is distinct from 'listo_para_entregar' then
        raise exception 'La reposición de la garantía aún no está lista para entregar';
      end if;
    end if;
    new.production_id := v_production.id;
  end if;

  if not new.evidence_received or (v_files and new.evidence_file_path is null) then
    raise exception 'Registre la evidencia de la entrega (foto o acta firmada)';
  end if;

  return new;
end;
$$

;
create or replace function public.register_delivery(p_delivery jsonb, p_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $$
declare
  v_id uuid;
  v_order_id uuid;
begin
  if jsonb_typeof(p_items) is distinct from 'array'
     or not exists (
       select 1 from jsonb_to_recordset(p_items) as x (order_item_id uuid, quantity int) where x.quantity > 0
     ) then
    raise exception 'Indique al menos un ítem con cantidad a entregar';
  end if;

  insert into public.order_deliveries (
    order_id, warranty_id, delivered_at, receiver_name, evidence_received, evidence_file_path, notes
  )
  select r.order_id, r.warranty_id, coalesce(r.delivered_at, private.today_co()), r.receiver_name,
         coalesce(r.evidence_received, false), r.evidence_file_path, r.notes
  from jsonb_populate_record(null::public.order_deliveries, p_delivery) r
  returning id, order_id into v_id, v_order_id;

  insert into public.order_delivery_items (delivery_id, order_id, order_item_id, quantity)
  select v_id, v_order_id, x.order_item_id, x.quantity
  from jsonb_to_recordset(p_items) as x (order_item_id uuid, quantity int)
  where x.quantity > 0;

  return v_id;
end;
$$

;
create or replace function private.post_sale_warranties_before_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $$
declare
  v_is_api boolean := current_user = 'authenticated';
  v_files boolean := private.get_setting('require_document_files') = 1;
begin
  if not v_is_api then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.status := 'abierta';
    new.opened_by := (select auth.uid());
    new.closed_by := null;
    new.closed_at := null;
    if exists (select 1 from public.orders o where o.id = new.order_id and o.is_cancelled) then
      raise exception 'Una orden anulada no tiene posventa';
    end if;
    if not exists (
      select 1 from public.order_deliveries d where d.order_id = new.order_id and d.warranty_id is null
    ) then
      raise exception 'La posventa se registra sobre productos ya entregados';
    end if;
  else
    if new.order_id is distinct from old.order_id then
      raise exception 'La orden de una garantía no se cambia';
    end if;
    if old.status = 'cerrada' then
      raise exception 'Una garantía cerrada no se modifica';
    end if;

    if new.status is distinct from old.status then
      if new.status <> 'cerrada' then
        raise exception 'El estado En reposición lo fija la producción de reposición';
      end if;
      if not private.has_role('direccion') then
        raise exception 'Solo Dirección cierra garantías' using errcode = '42501';
      end if;
      if not new.evidence_received or (v_files and new.evidence_file_path is null) then
        raise exception 'Registre la evidencia de cierre de la garantía';
      end if;
      if exists (
        select 1 from public.order_productions p
        where p.warranty_id = old.id and p.status <> 'cancelada'
      ) and not exists (
        select 1 from public.order_deliveries d where d.warranty_id = old.id
      ) then
        raise exception 'Entregue la reposición antes de cerrar la garantía';
      end if;
      new.closed_by := (select auth.uid());
      new.closed_at := now();
    end if;
  end if;

  if (tg_op = 'INSERT' or new.responsible_user_id is distinct from old.responsible_user_id)
     and not exists (
       select 1 from public.users_profiles p
       where p.id = new.responsible_user_id and p.active and p.role in ('operacion', 'direccion')
     ) then
    raise exception 'El responsable debe ser un usuario activo de Operación o Dirección';
  end if;

  return new;
end;
$$

;
create or replace function private.collections_payments_before_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $$
declare
  v_files boolean := private.get_setting('require_document_files') = 1;
  v_allocated numeric;
begin
  new.bank_reference := trim(new.bank_reference);

  if current_user <> 'authenticated' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.verified_by := (select auth.uid());
    new.verified_at := now();
    new.is_voided := false;
    new.void_reason := null;
  else
    if old.is_voided then
      raise exception 'Un pago anulado no se modifica';
    end if;
    if (new.company_id, new.buyer_id) is distinct from (old.company_id, old.buyer_id) then
      raise exception 'El pagador no se cambia; anule el pago y regístrelo de nuevo';
    end if;
    select coalesce(sum(a.amount_applied), 0) into v_allocated
    from public.payment_allocations a where a.payment_id = old.id and not a.is_voided;
    if not new.is_voided and new.total_received_bank < v_allocated then
      raise exception 'El valor recibido no puede ser menor que lo ya asignado (%)', v_allocated;
    end if;
    if new.is_voided then
      new.voided_by := (select auth.uid());
      new.voided_at := now();
    end if;
  end if;

  if new.payment_date > private.today_co() then
    raise exception 'La fecha del pago no puede ser futura';
  end if;
  if not new.support_received or (v_files and new.support_file_path is null) then
    raise exception 'Registre el soporte bancario del pago';
  end if;

  return new;
end;
$$

;
create or replace function private.payment_allocations_before_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $$
declare
  v_files boolean := private.get_setting('require_document_files') = 1;
  v_payment public.collections_payments;
  v_order public.orders;
  v_allocated numeric;
  v_installment record;
begin
  if current_user <> 'authenticated' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.is_voided then
      raise exception 'Una asignación anulada no se modifica';
    end if;
    if (new.payment_id, new.order_id, new.installment_id, new.amount_applied, new.withholding_applied,
        new.withholding_certificate_received)
       is distinct from
       (old.payment_id, old.order_id, old.installment_id, old.amount_applied, old.withholding_applied,
        old.withholding_certificate_received) then
      raise exception 'Una asignación no se edita: anúlela y registre una nueva';
    end if;
    if new.is_voided then
      new.voided_by := (select auth.uid());
      new.voided_at := now();
    end if;
    return new;
  end if;

  new.created_by := (select auth.uid());
  new.is_voided := false;

  select * into v_payment from public.collections_payments p where p.id = new.payment_id;
  if v_payment.is_voided then
    raise exception 'El pago está anulado';
  end if;

  select * into v_order from public.orders o where o.id = new.order_id;
  if v_order.is_cancelled then
    raise exception 'No se aplican pagos a una orden anulada';
  end if;
  if v_payment.company_id is not null and v_order.company_id is distinct from v_payment.company_id then
    raise exception 'La orden no es de la empresa que hizo el pago';
  end if;
  if v_payment.buyer_id is not null and v_order.buyer_id is distinct from v_payment.buyer_id then
    raise exception 'La orden no es del comprador que hizo el pago';
  end if;

  -- Lo asignado en dinero no supera lo recibido en bancos
  select coalesce(sum(a.amount_applied), 0) into v_allocated
  from public.payment_allocations a where a.payment_id = new.payment_id and not a.is_voided;
  if v_allocated + new.amount_applied > v_payment.total_received_bank then
    raise exception 'Se asignarían % de un pago por %', v_allocated + new.amount_applied, v_payment.total_received_bank;
  end if;

  -- No se abona más del saldo de la orden
  if new.amount_applied + new.withholding_applied > v_order.balance_due then
    raise exception 'El abono (%) supera el saldo de la orden (%)',
      new.amount_applied + new.withholding_applied, v_order.balance_due;
  end if;

  if new.withholding_applied > 0
     and (not new.withholding_certificate_received or (v_files and new.withholding_certificate_file_path is null)) then
    raise exception 'La retención requiere el certificado de retención';
  end if;

  if new.installment_id is not null then
    select i.order_id, i.expected_amount, i.paid_amount, i.superseded_by_reclassification_id
      into v_installment
    from public.order_installments i where i.id = new.installment_id;
    if v_installment.order_id is distinct from new.order_id then
      raise exception 'La cuota no pertenece a la orden';
    end if;
    if v_installment.superseded_by_reclassification_id is not null then
      raise exception 'La cuota fue reemplazada por una reprogramación';
    end if;
    if new.amount_applied + new.withholding_applied > v_installment.expected_amount - v_installment.paid_amount then
      raise exception 'El abono supera lo pendiente de la cuota';
    end if;
  end if;

  return new;
end;
$$

;

-- ---------------------------------------------------------------------
-- 2. Bucket privado
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('soportes', 'soportes', false, 10485760,
        array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------
-- 3. Quién sube y quién ve cada tipo de soporte
-- ---------------------------------------------------------------------
create function private.can_upload_support(p_kind text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_kind
    when 'convenios'   then private.has_role('comercial', 'administracion_cartera')
    when 'compradores' then private.has_role('comercial', 'administracion_cartera')
    when 'ordenes'     then private.has_role('comercial', 'administracion_cartera')
    when 'entregas'    then private.has_role('operacion')
    when 'garantias'   then private.has_role('operacion', 'direccion')
    when 'pagos'       then private.has_role('administracion_cartera')
    when 'retenciones' then private.has_role('administracion_cartera')
    else false
  end;
$$;

-- SECURITY INVOKER: la RLS de la tabla que referencia el archivo decide
create function private.support_visible(p_path text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return case split_part(p_path, '/', 1)
    when 'convenios' then exists (select 1 from public.agreement_documents x where x.file_path = p_path)
    when 'compradores' then exists (select 1 from public.buyers x where x.data_consent_file_path = p_path)
    when 'ordenes' then exists (
      select 1 from public.orders x where x.employee_auth_file_path = p_path or x.hr_approval_file_path = p_path)
    when 'entregas' then exists (select 1 from public.order_deliveries x where x.evidence_file_path = p_path)
    when 'garantias' then exists (select 1 from public.post_sale_warranties x where x.evidence_file_path = p_path)
    when 'pagos' then exists (select 1 from public.collections_payments x where x.support_file_path = p_path)
    when 'retenciones' then exists (
      select 1 from public.payment_allocations x where x.withholding_certificate_file_path = p_path)
    else false
  end;
end;
$$;

revoke execute on function private.can_upload_support(text) from public, anon;
revoke execute on function private.support_visible(text) from public, anon;
grant execute on function private.can_upload_support(text) to authenticated;
grant execute on function private.support_visible(text) to authenticated;

create policy soportes_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'soportes'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and private.can_upload_support((storage.foldername(name))[1])
  );

create policy soportes_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'soportes'
    and ((storage.foldername(name))[2] = (select auth.uid())::text or private.support_visible(name))
  );

-- ---------------------------------------------------------------------
-- 4. Un registro solo referencia un archivo existente, del tipo correcto
--    y subido por quien lo vincula. Adjuntar marca el soporte recibido.
-- TG_ARGV[0] = tipo; los demás = "columna" o "columna:bandera_recibido"
-- ---------------------------------------------------------------------
create function private.support_files_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text := tg_argv[0];
  v_new jsonb := to_jsonb(new);
  v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  v_spec text;
  v_col text;
  v_flag text;
  v_path text;
  v_patch jsonb := '{}'::jsonb;
begin
  for i in 1 .. tg_nargs - 1 loop
    v_spec := tg_argv[i];
    v_col := split_part(v_spec, ':', 1);
    v_flag := nullif(split_part(v_spec, ':', 2), '');
    v_path := v_new ->> v_col;

    if v_path is not null and v_path is distinct from (v_old ->> v_col) then
      if split_part(v_path, '/', 1) <> v_kind then
        raise exception 'El archivo no corresponde a este tipo de soporte';
      end if;
      if not exists (select 1 from storage.objects o where o.bucket_id = 'soportes' and o.name = v_path) then
        raise exception 'El archivo no se encontró; súbalo de nuevo';
      end if;
      if (select auth.uid()) is not null and split_part(v_path, '/', 2) <> (select auth.uid())::text then
        raise exception 'Solo se vinculan archivos subidos por el mismo usuario';
      end if;
      if v_flag is not null then
        v_patch := v_patch || jsonb_build_object(v_flag, true);
      end if;
    end if;
  end loop;

  if v_patch <> '{}'::jsonb then
    new := jsonb_populate_record(new, v_patch);
  end if;
  return new;
end;
$$;

revoke execute on function private.support_files_guard() from public, anon, authenticated;

-- Se nombran "a_..." para ejecutarse antes que las reglas de cada tabla
-- (los triggers BEFORE corren en orden alfabético)
create trigger a_support_files before insert or update on public.agreement_documents
  for each row execute function private.support_files_guard('convenios', 'file_path');
create trigger a_support_files before insert or update on public.buyers
  for each row execute function private.support_files_guard('compradores', 'data_consent_file_path');
create trigger a_support_files before insert or update on public.orders
  for each row execute function private.support_files_guard('ordenes',
    'employee_auth_file_path:employee_auth_received', 'hr_approval_file_path:hr_approval_received');
create trigger a_support_files before insert or update on public.order_deliveries
  for each row execute function private.support_files_guard('entregas', 'evidence_file_path:evidence_received');
create trigger a_support_files before insert or update on public.post_sale_warranties
  for each row execute function private.support_files_guard('garantias', 'evidence_file_path:evidence_received');
create trigger a_support_files before insert or update on public.collections_payments
  for each row execute function private.support_files_guard('pagos', 'support_file_path:support_received');
create trigger a_support_files before insert or update on public.payment_allocations
  for each row execute function private.support_files_guard('retenciones',
    'withholding_certificate_file_path:withholding_certificate_received');

-- Permisos de columna que faltaban para adjuntar después del registro
grant update (data_consent_file_path) on public.buyers to authenticated;
grant update (evidence_file_path) on public.order_deliveries to authenticated;

-- ---------------------------------------------------------------------
-- 5. Aplicación de pagos con el certificado de retención adjunto
-- ---------------------------------------------------------------------
drop function public.apply_payment_batch(uuid, jsonb);
drop function public.apply_payment(uuid, uuid, numeric, numeric, boolean);

create function public.apply_payment(
  p_payment_id uuid,
  p_order_id uuid,
  p_amount numeric,
  p_withholding numeric default 0,
  p_certificate_received boolean default false,
  p_certificate_path text default null
)
returns int
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_money numeric := coalesce(p_amount, 0);
  v_withholding numeric := coalesce(p_withholding, 0);
  v_rows int := 0;
  v_take numeric;
  v_take_money numeric;
  v_inst record;
  v_cert_ok boolean := coalesce(p_certificate_received, false) or p_certificate_path is not null;
begin
  if v_money < 0 or v_withholding < 0 or v_money + v_withholding <= 0 then
    raise exception 'Indique un valor de dinero recibido o de retención mayor que cero';
  end if;

  if not exists (
    select 1 from public.order_installments i
    where i.order_id = p_order_id and i.superseded_by_reclassification_id is null
  ) then
    insert into public.payment_allocations (payment_id, order_id, amount_applied, withholding_applied,
      withholding_certificate_received, withholding_certificate_file_path)
    values (p_payment_id, p_order_id, v_money, v_withholding, v_cert_ok,
      case when v_withholding > 0 then p_certificate_path end);
    return 1;
  end if;

  for v_inst in
    select i.id, i.expected_amount - i.paid_amount as pending
    from public.order_installments i
    where i.order_id = p_order_id
      and i.superseded_by_reclassification_id is null
      and i.paid_amount < i.expected_amount
    order by i.due_date, i.installment_number
  loop
    exit when v_money + v_withholding <= 0;
    v_take := least(v_inst.pending, v_money + v_withholding);
    v_take_money := least(v_take, v_money);
    insert into public.payment_allocations (payment_id, order_id, installment_id, amount_applied,
      withholding_applied, withholding_certificate_received, withholding_certificate_file_path)
    values (p_payment_id, p_order_id, v_inst.id, v_take_money, v_take - v_take_money, v_cert_ok,
      case when v_take - v_take_money > 0 then p_certificate_path end);
    v_money := v_money - v_take_money;
    v_withholding := v_withholding - (v_take - v_take_money);
    v_rows := v_rows + 1;
  end loop;

  if v_money + v_withholding > 0 then
    raise exception 'El abono supera lo pendiente de las cuotas de la orden';
  end if;
  return v_rows;
end;
$$;

-- p_items: [{order_id, amount, withholding, certificate_received, certificate_path}]
create function public.apply_payment_batch(p_payment_id uuid, p_items jsonb)
returns int
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_item record;
  v_rows int := 0;
begin
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'Asignaciones inválidas';
  end if;
  for v_item in
    select x.order_id, coalesce(x.amount, 0) as amount, coalesce(x.withholding, 0) as withholding,
           coalesce(x.certificate_received, false) as certificate_received, x.certificate_path
    from jsonb_to_recordset(p_items)
      as x (order_id uuid, amount numeric, withholding numeric, certificate_received boolean, certificate_path text)
    where coalesce(x.amount, 0) + coalesce(x.withholding, 0) > 0
  loop
    v_rows := v_rows + public.apply_payment(p_payment_id, v_item.order_id, v_item.amount, v_item.withholding,
                                            v_item.certificate_received, v_item.certificate_path);
  end loop;
  if v_rows = 0 then
    raise exception 'Indique al menos una orden con valor a aplicar';
  end if;
  return v_rows;
end;
$$;

revoke execute on function public.apply_payment(uuid, uuid, numeric, numeric, boolean, text) from public, anon;
revoke execute on function public.apply_payment_batch(uuid, jsonb) from public, anon;
grant execute on function public.apply_payment(uuid, uuid, numeric, numeric, boolean, text) to authenticated;
grant execute on function public.apply_payment_batch(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- 6. Registro de consultas de soportes (RNF-05)
-- ---------------------------------------------------------------------
create table public.support_access_logs (
  id          bigint generated always as identity primary key,
  file_path   text not null,
  accessed_by uuid not null default auth.uid() references public.users_profiles (id),
  accessed_at timestamptz not null default now()
);

create index support_access_logs_path_idx on public.support_access_logs (file_path, accessed_at desc);
create index support_access_logs_accessed_by_idx on public.support_access_logs (accessed_by);

alter table public.support_access_logs enable row level security;
revoke all on public.support_access_logs from anon, authenticated;
grant select on public.support_access_logs to authenticated;

create policy support_access_logs_select on public.support_access_logs
  for select to authenticated
  using ((select private.has_role('direccion', 'administracion_cartera', 'socio')));

-- Lo llama la app después de generar el enlace firmado (que ya validó el
-- permiso de lectura); solo registra si el usuario ve el archivo
create function public.log_support_access(p_path text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not private.support_visible(p_path) then
    raise exception 'Sin acceso al soporte' using errcode = '42501';
  end if;
  perform private.insert_support_access(p_path);
end;
$$;

create function private.insert_support_access(p_path text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.support_access_logs (file_path, accessed_by) values (p_path, (select auth.uid()));
$$;

revoke execute on function public.log_support_access(text) from public, anon;
revoke execute on function private.insert_support_access(text) from public, anon;
grant execute on function public.log_support_access(text) to authenticated;
grant execute on function private.insert_support_access(text) to authenticated;

-- ---------------------------------------------------------------------
-- 7. create_order acepta los soportes de nómina ya subidos
-- ---------------------------------------------------------------------
create or replace function public.create_order(p_order jsonb, p_items jsonb)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La orden necesita al menos un ítem';
  end if;

  insert into public.orders (
    campaign_id, company_id, branch_id, agreement_id, buyer_id, payment_modality,
    installments_count, first_due_date, employee_auth_received, hr_approval_received,
    employee_auth_file_path, hr_approval_file_path, notes
  )
  select
    r.campaign_id, r.company_id, r.branch_id, r.agreement_id, r.buyer_id, r.payment_modality,
    r.installments_count, r.first_due_date,
    coalesce(r.employee_auth_received, false), coalesce(r.hr_approval_received, false),
    r.employee_auth_file_path, r.hr_approval_file_path, r.notes
  from jsonb_populate_record(null::public.orders, p_order) r
  returning id into v_id;

  insert into public.order_items (
    order_id, item_type, frame_description, lens_type, lens_filter, description, quantity, unit_price
  )
  select
    v_id, r.item_type, r.frame_description, r.lens_type, r.lens_filter, r.description, r.quantity, r.unit_price
  from jsonb_populate_recordset(null::public.order_items, p_items) r;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. v_orders: rutas de los soportes de nómina (columnas nuevas al final)
-- ---------------------------------------------------------------------
create or replace view public.v_orders
with (security_invoker = true)
as
 SELECT o.id,
    o.order_number,
    o.campaign_id,
    j.deal_id,
    d.deal_name_branch,
    j.status AS campaign_status,
    o.company_id,
    c.name AS company_name,
    o.branch_id,
    br.name AS branch_name,
    o.city_id,
    ci.name AS city_name,
    o.agreement_id,
    o.buyer_id,
    b.full_name AS buyer_name,
    b.document_type AS buyer_document_type,
    b.document_id AS buyer_document_id,
    o.total_amount,
    o.balance_due,
    o.payment_modality,
    o.collection_responsible,
    o.installments_count,
    o.installment_periodicity,
    o.first_due_date,
    o.employee_auth_received,
    o.hr_approval_received,
    a.hr_approval_required,
    o.prepayment_exception_reason,
    o.prepayment_exception_by,
    o.prepayment_exception_at,
    o.requirements_verified,
    o.requirements_verified_by,
    o.requirements_verified_at,
    o.doc_status,
    o.ops_status,
    o.accounting_status,
    o.collection_status,
    o.is_cancelled,
    o.cancelled_by,
    o.cancelled_at,
    o.cancel_reason,
    o.notes,
    ( SELECT count(*) AS count
           FROM order_items i
          WHERE (i.order_id = o.id)) AS items_count,
    private.order_missing_requirements(o.*) AS missing_requirements,
    o.created_by,
    u.full_name AS created_by_name,
    o.created_at,
    o.updated_at,
    private.order_release_blockers(o.*) AS release_blockers,
    o.is_historical_migration,
    o.historical_stage,
    o.historical_collected_before_migration,
    o.historical_reference,
    o.historical_delivered_at,
    o.historical_delivery_receiver,
    o.employee_auth_file_path,
    o.hr_approval_file_path
   FROM ((((((((orders o
     JOIN buyers b ON ((b.id = o.buyer_id)))
     LEFT JOIN companies c ON ((c.id = o.company_id)))
     LEFT JOIN company_branches br ON ((br.id = o.branch_id)))
     LEFT JOIN cities ci ON ((ci.id = o.city_id)))
     LEFT JOIN campaigns_jornadas j ON ((j.id = o.campaign_id)))
     LEFT JOIN deals_opportunities d ON ((d.id = j.deal_id)))
     LEFT JOIN agreements_convenios a ON ((a.id = o.agreement_id)))
     LEFT JOIN users_profiles u ON ((u.id = o.created_by)));
