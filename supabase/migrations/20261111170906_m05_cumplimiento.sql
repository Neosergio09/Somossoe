-- =====================================================================
-- M05 Cumplimiento: producción, entrega y posventa (Etapas 08, 09 y 12)
-- Referencias SRS v1.4: RF-M05-01 a RF-M05-04, §5.6 (order_productions,
-- order_deliveries, order_delivery_items, post_sale_warranties), §3.2.
--
-- Decisiones (11-nov-2026):
-- * Una producción por orden (un laboratorio); las garantías con
--   reposición tienen su propia producción y entrega.
-- * Candado de liberación: requisitos verificados y, en contado, pago
--   verificado ≥ cash_min_prepayment_pct × valor o excepción de Dirección.
--   Hasta M06 el pago verificado es 0: contado se libera con excepción.
-- * Montura y otros ítems se pueden entregar desde que la orden se
--   libera; gafas completas y lentes esperan a que la producción esté lista.
-- * La evidencia de entrega y de cierre de garantía se registra sin
--   archivo mientras require_document_files = 0 (integración R2 pendiente).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------
create type public.production_status as enum ('en_produccion', 'listo_para_entregar', 'cancelada');
create type public.warranty_status as enum ('abierta', 'en_reposicion', 'cerrada');
create type public.warranty_incident_type as enum ('garantia', 'reclamo', 'ajuste', 'otro');

-- Para referencias compuestas (ítem y entrega de la misma orden)
alter table public.order_items add constraint order_items_id_order_key unique (id, order_id);

-- ---------------------------------------------------------------------
-- Pago verificado de una orden. M06 la reemplaza por la suma de las
-- asignaciones de pagos verificados en bancos (Regla de Oro de Cartera).
-- ---------------------------------------------------------------------
create function private.order_verified_paid(p_order_id uuid)
returns numeric
language sql
stable
set search_path = ''
as $$
  select 0::numeric;
$$;

-- Bloqueos para liberar a producción (RF-M05-01). Vacío = se puede liberar.
create function private.order_release_blockers(o public.orders)
returns text[]
language plpgsql
stable
set search_path = ''
as $$
declare
  v_blockers text[] := '{}';
  v_pct numeric;
  v_required numeric;
begin
  if o.is_cancelled then
    return array['La orden está anulada'];
  end if;
  if o.doc_status <> 'requisitos_verificados' then
    v_blockers := v_blockers || 'Requisitos sin verificar por Administración / Cartera'::text;
  end if;
  if o.payment_modality = 'contado' and o.prepayment_exception_reason is null then
    v_pct := private.get_setting('cash_min_prepayment_pct');
    v_required := ceil(o.total_amount * v_pct);
    if private.order_verified_paid(o.id) < v_required then
      v_blockers := v_blockers || format(
        'Pago verificado inferior al %s%% del valor (o excepción de anticipo de Dirección)',
        round(v_pct * 100))::text;
    end if;
  end if;
  return v_blockers;
end;
$$;

revoke execute on function private.order_verified_paid(uuid), private.order_release_blockers(public.orders)
  from public, anon;
grant execute on function private.order_verified_paid(uuid), private.order_release_blockers(public.orders)
  to authenticated;

-- ---------------------------------------------------------------------
-- Posventa y garantías (RF-M05-04, §5.6.21). Sin impacto en ingresos
-- ni cartera.
-- ---------------------------------------------------------------------
create table public.post_sale_warranties (
  id                  uuid primary key default gen_random_uuid(),
  order_id            uuid not null references public.orders (id),
  incident_type       public.warranty_incident_type not null,
  description         text not null check (length(trim(description)) > 0),
  responsible_user_id uuid not null references public.users_profiles (id),
  status              public.warranty_status not null default 'abierta',
  resolution          text,
  evidence_received   boolean not null default false,
  evidence_r2_key     text check (evidence_r2_key is null or length(trim(evidence_r2_key)) > 0),
  opened_by           uuid default auth.uid() references public.users_profiles (id),
  closed_by           uuid references public.users_profiles (id),
  closed_at           timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint post_sale_warranties_id_order_key unique (id, order_id),
  constraint post_sale_warranties_closed check (
    status <> 'cerrada' or (resolution is not null and length(trim(resolution)) > 0)
  )
);

create index post_sale_warranties_order_id_idx on public.post_sale_warranties (order_id);
create index post_sale_warranties_responsible_idx on public.post_sale_warranties (responsible_user_id);
create index post_sale_warranties_opened_by_idx on public.post_sale_warranties (opened_by);
create index post_sale_warranties_closed_by_idx on public.post_sale_warranties (closed_by);
create index post_sale_warranties_status_idx on public.post_sale_warranties (status) where status <> 'cerrada';

create trigger post_sale_warranties_set_updated_at
  before update on public.post_sale_warranties
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Producción con laboratorio (RF-M05-02, §5.6.18)
-- ---------------------------------------------------------------------
create table public.order_productions (
  id              uuid primary key default gen_random_uuid(),
  order_id        uuid not null references public.orders (id),
  warranty_id     uuid,
  lab_provider_id uuid not null references public.lab_providers (id),
  released_by     uuid default auth.uid() references public.users_profiles (id),
  released_at     timestamptz not null default now(),
  sent_to_lab_at  date not null default ((now() at time zone 'America/Bogota')::date),
  promised_date   date not null,
  ready_at        date,
  status          public.production_status not null default 'en_produccion',
  cancel_reason   text,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint order_productions_warranty_same_order
    foreign key (warranty_id, order_id) references public.post_sale_warranties (id, order_id),
  constraint order_productions_id_order_key unique (id, order_id),
  constraint order_productions_promised check (promised_date >= sent_to_lab_at),
  constraint order_productions_ready check (
    (status = 'listo_para_entregar') = (ready_at is not null) or status = 'cancelada'
  ),
  constraint order_productions_ready_after_sent check (ready_at is null or ready_at >= sent_to_lab_at),
  constraint order_productions_cancel_reason check (
    status <> 'cancelada' or (cancel_reason is not null and length(trim(cancel_reason)) > 0)
  )
);

-- Una sola producción vigente por orden y por garantía
create unique index order_productions_one_active_key
  on public.order_productions (order_id) where warranty_id is null and status <> 'cancelada';
create unique index order_productions_one_active_warranty_key
  on public.order_productions (warranty_id) where warranty_id is not null and status <> 'cancelada';
create index order_productions_order_id_idx on public.order_productions (order_id);
create index order_productions_warranty_id_idx on public.order_productions (warranty_id);
create index order_productions_lab_provider_id_idx on public.order_productions (lab_provider_id);
create index order_productions_released_by_idx on public.order_productions (released_by);
create index order_productions_status_idx on public.order_productions (status) where status <> 'cancelada';

create trigger order_productions_set_updated_at
  before update on public.order_productions
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------
-- Entregas (RF-M05-03, §5.6.19-20)
-- ---------------------------------------------------------------------
create table public.order_deliveries (
  id                       uuid primary key default gen_random_uuid(),
  order_id                 uuid not null references public.orders (id),
  production_id            uuid,
  warranty_id              uuid,
  delivered_at             date not null default ((now() at time zone 'America/Bogota')::date),
  receiver_name            text not null check (length(trim(receiver_name)) > 0),
  evidence_received        boolean not null default false,
  delivery_evidence_r2_key text check (delivery_evidence_r2_key is null or length(trim(delivery_evidence_r2_key)) > 0),
  notes                    text,
  delivered_by             uuid default auth.uid() references public.users_profiles (id),
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  constraint order_deliveries_production_same_order
    foreign key (production_id, order_id) references public.order_productions (id, order_id),
  constraint order_deliveries_warranty_same_order
    foreign key (warranty_id, order_id) references public.post_sale_warranties (id, order_id),
  constraint order_deliveries_id_order_key unique (id, order_id)
);

create index order_deliveries_order_id_idx on public.order_deliveries (order_id);
create index order_deliveries_production_id_idx on public.order_deliveries (production_id);
create index order_deliveries_warranty_id_idx on public.order_deliveries (warranty_id);
create index order_deliveries_delivered_by_idx on public.order_deliveries (delivered_by);

create trigger order_deliveries_set_updated_at
  before update on public.order_deliveries
  for each row execute function private.set_updated_at();

create table public.order_delivery_items (
  id            uuid primary key default gen_random_uuid(),
  delivery_id   uuid not null,
  order_id      uuid not null,
  order_item_id uuid not null,
  quantity      integer not null check (quantity > 0),
  created_at    timestamptz not null default now(),
  constraint order_delivery_items_delivery_same_order
    foreign key (delivery_id, order_id) references public.order_deliveries (id, order_id) on delete cascade,
  constraint order_delivery_items_item_same_order
    foreign key (order_item_id, order_id) references public.order_items (id, order_id),
  constraint order_delivery_items_unique_item unique (delivery_id, order_item_id)
);

create index order_delivery_items_order_id_idx on public.order_delivery_items (order_id);
create index order_delivery_items_order_item_id_idx on public.order_delivery_items (order_item_id);

-- ---------------------------------------------------------------------
-- Estado operativo derivado (RF-M04-04): producción vigente y entregas
-- que no son de garantía
-- ---------------------------------------------------------------------
create function private.refresh_order_ops_status(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_production public.production_status;
  v_full boolean;
  v_any boolean;
  v_status public.order_ops_status;
begin
  select p.status into v_production
  from public.order_productions p
  where p.order_id = p_order_id and p.warranty_id is null and p.status <> 'cancelada';

  select coalesce(bool_and(coalesce(d.qty, 0) >= i.quantity), false),
         coalesce(bool_or(coalesce(d.qty, 0) > 0), false)
    into v_full, v_any
  from public.order_items i
  left join (
    select di.order_item_id, sum(di.quantity) as qty
    from public.order_delivery_items di
    join public.order_deliveries dl on dl.id = di.delivery_id
    where di.order_id = p_order_id and dl.warranty_id is null
    group by di.order_item_id
  ) d on d.order_item_id = i.id
  where i.order_id = p_order_id;

  v_status := case
    when v_production is null then 'pendiente_liberar'
    when v_full then 'entrega_completa'
    when v_any then 'entrega_parcial'
    when v_production = 'listo_para_entregar' then 'listo_para_entregar'
    else 'en_produccion'
  end;

  update public.orders o
  set ops_status = v_status
  where o.id = p_order_id and o.ops_status is distinct from v_status;
end;
$$;

revoke execute on function private.refresh_order_ops_status(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Reglas de producción
-- ---------------------------------------------------------------------
create function private.order_productions_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_api boolean := current_user = 'authenticated';
  v_order public.orders;
  v_blockers text[];
  v_warranty public.warranty_status;
begin
  if tg_op = 'INSERT' then
    if v_is_api then
      new.status := 'en_produccion';
      new.ready_at := null;
      new.cancel_reason := null;
      new.released_by := (select auth.uid());
      new.released_at := now();
    end if;

    select * into v_order from public.orders o where o.id = new.order_id;
    if not found then
      raise exception 'Orden no encontrada';
    end if;

    if v_is_api then
      if new.warranty_id is null then
        -- Candado preventivo (RF-M05-01)
        v_blockers := private.order_release_blockers(v_order);
        if cardinality(v_blockers) > 0 then
          raise exception 'No se puede liberar a producción: %', array_to_string(v_blockers, '; ');
        end if;
        if exists (
          select 1 from public.order_productions p
          where p.order_id = new.order_id and p.warranty_id is null and p.status <> 'cancelada'
        ) then
          raise exception 'La orden ya está liberada a producción';
        end if;
      else
        select w.status into v_warranty from public.post_sale_warranties w where w.id = new.warranty_id;
        if v_warranty = 'cerrada' then
          raise exception 'La garantía está cerrada';
        end if;
      end if;

      if not exists (select 1 from public.lab_providers l where l.id = new.lab_provider_id and l.active) then
        raise exception 'El laboratorio debe estar activo';
      end if;
    end if;
    return new;
  end if;

  if not v_is_api then
    return new;
  end if;

  if (new.order_id, new.warranty_id) is distinct from (old.order_id, old.warranty_id) then
    raise exception 'La orden y la garantía de una producción no se cambian';
  end if;
  if old.status = 'cancelada' then
    raise exception 'Una producción cancelada no se modifica';
  end if;

  if new.lab_provider_id is distinct from old.lab_provider_id then
    if old.status <> 'en_produccion' then
      raise exception 'El laboratorio solo se cambia mientras la orden está en producción';
    end if;
    if not exists (select 1 from public.lab_providers l where l.id = new.lab_provider_id and l.active) then
      raise exception 'El laboratorio debe estar activo';
    end if;
  end if;

  if new.status is distinct from old.status then
    if old.status = 'en_produccion' and new.status = 'listo_para_entregar' then
      new.ready_at := coalesce(new.ready_at, private.today_co());
      if new.ready_at > private.today_co() then
        raise exception 'La fecha real de listo no puede ser futura';
      end if;
    elsif old.status = 'listo_para_entregar' and new.status = 'en_produccion' then
      if exists (select 1 from public.order_deliveries d where d.production_id = old.id) then
        raise exception 'Ya hay entregas de esta producción; no se puede devolver a En producción';
      end if;
      new.ready_at := null;
    elsif new.status = 'cancelada' then
      if old.warranty_id is null and exists (
        select 1 from public.order_deliveries d
        where d.order_id = old.order_id and d.warranty_id is null
      ) then
        raise exception 'La orden ya tiene entregas; la producción no se cancela';
      end if;
      if old.warranty_id is not null and exists (
        select 1 from public.order_deliveries d where d.warranty_id = old.warranty_id
      ) then
        raise exception 'La reposición ya tiene entregas; la producción no se cancela';
      end if;
    else
      raise exception 'Transición de producción no permitida';
    end if;
  elsif new.ready_at is distinct from old.ready_at and new.ready_at > private.today_co() then
    raise exception 'La fecha real de listo no puede ser futura';
  end if;

  return new;
end;
$$;

create trigger order_productions_before_write
  before insert or update on public.order_productions
  for each row execute function private.order_productions_before_write();

create function private.order_productions_after_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.warranty_id is null then
    perform private.refresh_order_ops_status(new.order_id);
  else
    -- La garantía pasa a En reposición mientras tenga una producción vigente
    update public.post_sale_warranties w
    set status = case
      when exists (
        select 1 from public.order_productions p
        where p.warranty_id = w.id and p.status <> 'cancelada'
      ) then 'en_reposicion'::public.warranty_status
      else 'abierta'::public.warranty_status
    end
    where w.id = new.warranty_id and w.status <> 'cerrada';
  end if;
  return null;
end;
$$;

revoke execute on function private.order_productions_after_write() from public, anon, authenticated;

create trigger order_productions_after_write
  after insert or update on public.order_productions
  for each row execute function private.order_productions_after_write();

-- ---------------------------------------------------------------------
-- Reglas de entrega
-- ---------------------------------------------------------------------
create function private.order_deliveries_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
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

  if not new.evidence_received or (v_files and new.delivery_evidence_r2_key is null) then
    raise exception 'Registre la evidencia de la entrega (foto o acta firmada)';
  end if;

  return new;
end;
$$;

create trigger order_deliveries_before_write
  before insert or update or delete on public.order_deliveries
  for each row execute function private.order_deliveries_before_write();

create function private.order_delivery_items_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_delivery record;
  v_item record;
  v_delivered bigint;
begin
  if current_user <> 'authenticated' then
    return new;
  end if;

  select d.warranty_id, d.production_id, p.status as production_status
    into v_delivery
  from public.order_deliveries d
  left join public.order_productions p on p.id = d.production_id
  where d.id = new.delivery_id;

  select i.item_type, i.quantity into v_item from public.order_items i where i.id = new.order_item_id;

  if v_delivery.warranty_id is null then
    if v_item.item_type in ('gafas_completas', 'lentes')
       and v_delivery.production_status is distinct from 'listo_para_entregar' then
      raise exception 'Las gafas completas y los lentes se entregan cuando la producción está lista';
    end if;
    select coalesce(sum(di.quantity), 0) into v_delivered
    from public.order_delivery_items di
    join public.order_deliveries d on d.id = di.delivery_id
    where di.order_item_id = new.order_item_id and d.warranty_id is null;
  else
    select coalesce(sum(di.quantity), 0) into v_delivered
    from public.order_delivery_items di
    join public.order_deliveries d on d.id = di.delivery_id
    where di.order_item_id = new.order_item_id and d.warranty_id = v_delivery.warranty_id;
  end if;

  if v_delivered + new.quantity > v_item.quantity then
    raise exception 'Se entregarían % unidades de un ítem con %', v_delivered + new.quantity, v_item.quantity;
  end if;

  return new;
end;
$$;

create trigger order_delivery_items_before_insert
  before insert on public.order_delivery_items
  for each row execute function private.order_delivery_items_before_insert();

create function private.order_delivery_items_after_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.refresh_order_ops_status(coalesce(new.order_id, old.order_id));
  return null;
end;
$$;

revoke execute on function private.order_delivery_items_after_write() from public, anon, authenticated;

create trigger order_delivery_items_after_write
  after insert or delete on public.order_delivery_items
  for each row execute function private.order_delivery_items_after_write();

-- Registro atómico de una entrega con sus ítems (SECURITY INVOKER)
create function public.register_delivery(p_delivery jsonb, p_items jsonb)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
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
    order_id, warranty_id, delivered_at, receiver_name, evidence_received, delivery_evidence_r2_key, notes
  )
  select r.order_id, r.warranty_id, coalesce(r.delivered_at, private.today_co()), r.receiver_name,
         coalesce(r.evidence_received, false), r.delivery_evidence_r2_key, r.notes
  from jsonb_populate_record(null::public.order_deliveries, p_delivery) r
  returning id, order_id into v_id, v_order_id;

  insert into public.order_delivery_items (delivery_id, order_id, order_item_id, quantity)
  select v_id, v_order_id, x.order_item_id, x.quantity
  from jsonb_to_recordset(p_items) as x (order_item_id uuid, quantity int)
  where x.quantity > 0;

  return v_id;
end;
$$;

revoke execute on function public.register_delivery(jsonb, jsonb) from public, anon;
grant execute on function public.register_delivery(jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- Reglas de garantía
-- ---------------------------------------------------------------------
create function private.post_sale_warranties_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
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
      if not new.evidence_received or (v_files and new.evidence_r2_key is null) then
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
$$;

create trigger post_sale_warranties_before_write
  before insert or update on public.post_sale_warranties
  for each row execute function private.post_sale_warranties_before_write();

-- ---------------------------------------------------------------------
-- Órdenes: no se anulan con entregas; al anular se cancela la producción
-- ---------------------------------------------------------------------
create function private.orders_cancel_fulfillment_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'authenticated' and new.is_cancelled and not old.is_cancelled
     and exists (select 1 from public.order_deliveries d where d.order_id = old.id) then
    raise exception 'La orden ya tiene entregas; gestiónela como posventa en lugar de anularla';
  end if;
  return new;
end;
$$;

create trigger orders_cancel_fulfillment_guard
  before update of is_cancelled on public.orders
  for each row execute function private.orders_cancel_fulfillment_guard();

create function private.orders_after_cancel()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.is_cancelled and not old.is_cancelled then
    update public.order_productions p
    set status = 'cancelada', cancel_reason = 'Orden anulada'
    where p.order_id = new.id and p.status <> 'cancelada';
  end if;
  return null;
end;
$$;

revoke execute on function private.orders_after_cancel() from public, anon, authenticated;

create trigger orders_after_cancel
  after update of is_cancelled on public.orders
  for each row execute function private.orders_after_cancel();

-- ---------------------------------------------------------------------
-- Vistas
-- ---------------------------------------------------------------------
-- v_orders: se agregan los bloqueos para liberar
create or replace view public.v_orders
with (security_invoker = true)
as
select
  o.id,
  o.order_number,
  o.campaign_id,
  j.deal_id,
  d.deal_name_branch,
  j.status as campaign_status,
  o.company_id,
  c.name as company_name,
  o.branch_id,
  br.name as branch_name,
  o.city_id,
  ci.name as city_name,
  o.agreement_id,
  o.buyer_id,
  b.full_name as buyer_name,
  b.document_type as buyer_document_type,
  b.document_id as buyer_document_id,
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
  (select count(*) from public.order_items i where i.order_id = o.id) as items_count,
  private.order_missing_requirements(o) as missing_requirements,
  o.created_by,
  u.full_name as created_by_name,
  o.created_at,
  o.updated_at,
  private.order_release_blockers(o) as release_blockers
from public.orders o
join public.buyers b on b.id = o.buyer_id
left join public.companies c on c.id = o.company_id
left join public.company_branches br on br.id = o.branch_id
left join public.cities ci on ci.id = o.city_id
left join public.campaigns_jornadas j on j.id = o.campaign_id
left join public.deals_opportunities d on d.id = j.deal_id
left join public.agreements_convenios a on a.id = o.agreement_id
left join public.users_profiles u on u.id = o.created_by;

-- Tablero de producción
create view public.v_productions
with (security_invoker = true)
as
select
  p.id,
  p.order_id,
  o.order_number,
  p.warranty_id,
  p.lab_provider_id,
  l.name as lab_name,
  p.status,
  p.sent_to_lab_at,
  p.promised_date,
  p.ready_at,
  (p.status = 'en_produccion' and p.promised_date < private.today_co()) as is_overdue,
  p.cancel_reason,
  p.notes,
  p.released_at,
  p.released_by,
  u.full_name as released_by_name,
  b.full_name as buyer_name,
  b.document_id as buyer_document_id,
  c.name as company_name,
  ci.name as city_name,
  o.ops_status
from public.order_productions p
join public.orders o on o.id = p.order_id
join public.buyers b on b.id = o.buyer_id
join public.lab_providers l on l.id = p.lab_provider_id
left join public.companies c on c.id = o.company_id
left join public.cities ci on ci.id = o.city_id
left join public.users_profiles u on u.id = p.released_by;

-- Entregado y pendiente por ítem (sin contar reposiciones de garantía)
create view public.v_order_item_delivery
with (security_invoker = true)
as
select
  i.id as order_item_id,
  i.order_id,
  i.item_type,
  i.frame_description,
  i.lens_type,
  i.lens_filter,
  i.description,
  i.quantity,
  coalesce(d.delivered, 0)::int as delivered_quantity,
  (i.quantity - coalesce(d.delivered, 0))::int as pending_quantity
from public.order_items i
left join (
  select di.order_item_id, sum(di.quantity) as delivered
  from public.order_delivery_items di
  join public.order_deliveries dl on dl.id = di.delivery_id
  where dl.warranty_id is null
  group by di.order_item_id
) d on d.order_item_id = i.id;

create view public.v_warranties
with (security_invoker = true)
as
select
  w.id,
  w.order_id,
  o.order_number,
  w.incident_type,
  w.description,
  w.status,
  w.resolution,
  w.evidence_received,
  w.responsible_user_id,
  r.full_name as responsible_name,
  w.opened_by,
  ob.full_name as opened_by_name,
  w.created_at,
  w.closed_by,
  cb.full_name as closed_by_name,
  w.closed_at,
  b.full_name as buyer_name,
  b.document_id as buyer_document_id,
  c.name as company_name,
  w.updated_at
from public.post_sale_warranties w
join public.orders o on o.id = w.order_id
join public.buyers b on b.id = o.buyer_id
join public.users_profiles r on r.id = w.responsible_user_id
left join public.users_profiles ob on ob.id = w.opened_by
left join public.users_profiles cb on cb.id = w.closed_by
left join public.companies c on c.id = o.company_id;

-- ---------------------------------------------------------------------
-- Auditoría (RNF-01)
-- ---------------------------------------------------------------------
create trigger order_productions_audit
  after insert or update or delete on public.order_productions
  for each row execute function private.audit_row_change();
create trigger order_deliveries_audit
  after insert or update or delete on public.order_deliveries
  for each row execute function private.audit_row_change();
create trigger order_delivery_items_audit
  after insert or update or delete on public.order_delivery_items
  for each row execute function private.audit_row_change();
create trigger post_sale_warranties_audit
  after insert or update or delete on public.post_sale_warranties
  for each row execute function private.audit_row_change();

-- ---------------------------------------------------------------------
-- Privilegios
-- ---------------------------------------------------------------------
grant select on public.order_productions to authenticated;
grant insert (order_id, warranty_id, lab_provider_id, sent_to_lab_at, promised_date, notes)
  on public.order_productions to authenticated;
grant update (lab_provider_id, sent_to_lab_at, promised_date, ready_at, status, cancel_reason, notes)
  on public.order_productions to authenticated;

grant select, delete on public.order_deliveries to authenticated;
grant insert (order_id, warranty_id, delivered_at, receiver_name, evidence_received,
              delivery_evidence_r2_key, notes)
  on public.order_deliveries to authenticated;
grant update (receiver_name, evidence_received, delivery_evidence_r2_key, notes)
  on public.order_deliveries to authenticated;

grant select on public.order_delivery_items to authenticated;
grant insert (delivery_id, order_id, order_item_id, quantity) on public.order_delivery_items to authenticated;

grant select on public.post_sale_warranties to authenticated;
grant insert (order_id, incident_type, description, responsible_user_id)
  on public.post_sale_warranties to authenticated;
grant update (incident_type, description, responsible_user_id, resolution, evidence_received,
              evidence_r2_key, status)
  on public.post_sale_warranties to authenticated;

grant select on public.v_productions, public.v_order_item_delivery, public.v_warranties to authenticated;

-- ---------------------------------------------------------------------
-- RLS (matriz §3.2)
-- 08 Producción y 09 Entrega: Operación crea y edita; demás, lectura.
-- 12 Posventa: Operación crea y edita; Dirección cierra.
-- ---------------------------------------------------------------------
alter table public.order_productions    enable row level security;
alter table public.order_deliveries     enable row level security;
alter table public.order_delivery_items enable row level security;
alter table public.post_sale_warranties enable row level security;

create policy order_productions_select on public.order_productions
  for select to authenticated
  using ((select private.is_internal_user()));
create policy order_productions_insert on public.order_productions
  for insert to authenticated
  with check ((select private.has_role('operacion')));
create policy order_productions_update on public.order_productions
  for update to authenticated
  using ((select private.has_role('operacion')))
  with check ((select private.has_role('operacion')));

create policy order_deliveries_select on public.order_deliveries
  for select to authenticated
  using ((select private.is_internal_user()));
create policy order_deliveries_insert on public.order_deliveries
  for insert to authenticated
  with check ((select private.has_role('operacion')));
create policy order_deliveries_update on public.order_deliveries
  for update to authenticated
  using ((select private.has_role('operacion')))
  with check ((select private.has_role('operacion')));
create policy order_deliveries_delete on public.order_deliveries
  for delete to authenticated
  using ((select private.has_role('operacion')));

create policy order_delivery_items_select on public.order_delivery_items
  for select to authenticated
  using ((select private.is_internal_user()));
create policy order_delivery_items_insert on public.order_delivery_items
  for insert to authenticated
  with check ((select private.has_role('operacion')));

create policy post_sale_warranties_select on public.post_sale_warranties
  for select to authenticated
  using ((select private.is_internal_user()));
create policy post_sale_warranties_insert on public.post_sale_warranties
  for insert to authenticated
  with check ((select private.has_role('operacion')));
create policy post_sale_warranties_update on public.post_sale_warranties
  for update to authenticated
  using ((select private.has_role('operacion', 'direccion')))
  with check ((select private.has_role('operacion', 'direccion')));
