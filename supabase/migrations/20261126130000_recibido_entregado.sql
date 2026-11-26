-- =====================================================================
-- Backlog V0.2 · SOE-14 y SOE-18: pedido enviado, lente recibido en SOE y
-- entregado como hechos distintos, cada uno con fecha y responsable.
--
-- * La producción ya guarda el envío (released_by/at, sent_to_lab_at) y la
--   fecha real de recibido (ready_at). Se agrega QUIÉN registró la
--   recepción (received_by, received_recorded_at).
-- * El n.º de pedido del laboratorio puede corregirse sin perder el
--   anterior: production_reference_history con motivo obligatorio.
-- * Las entregas ya guardan fecha, receptor, evidencia y quién entregó.
-- =====================================================================

alter table public.order_productions
  add column received_by                 uuid references public.users_profiles (id),
  add column received_recorded_at        timestamptz,
  add column lab_reference_change_reason text;

create index order_productions_received_by_idx on public.order_productions (received_by);

grant update (lab_reference_change_reason) on public.order_productions to authenticated;

create table public.production_reference_history (
  id             uuid primary key default gen_random_uuid(),
  production_id  uuid not null references public.order_productions (id),
  order_id       uuid not null references public.orders (id),
  old_reference  text not null,
  new_reference  text,
  reason         text not null check (length(trim(reason)) > 0),
  changed_by     uuid references public.users_profiles (id),
  changed_at     timestamptz not null default now()
);
create index production_reference_history_production_idx on public.production_reference_history (production_id);
create index production_reference_history_order_idx on public.production_reference_history (order_id);
create index production_reference_history_changed_by_idx on public.production_reference_history (changed_by);

alter table public.production_reference_history enable row level security;
revoke all on public.production_reference_history from public, anon, authenticated;
grant select on public.production_reference_history to authenticated;
create policy production_reference_history_select on public.production_reference_history
  for select to authenticated
  using ((select private.is_internal_user()));

-- El historial lo escribe solo la base (la app no tiene permiso de insertar)
create function private.log_production_reference_change(
  p_production_id uuid, p_order_id uuid, p_old text, p_new text, p_reason text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.production_reference_history (production_id, order_id, old_reference, new_reference, reason, changed_by)
  values (p_production_id, p_order_id, p_old, p_new, p_reason, (select auth.uid()));
$$;

revoke execute on function private.log_production_reference_change(uuid, uuid, text, text, text) from public, anon;
grant execute on function private.log_production_reference_change(uuid, uuid, text, text, text) to authenticated;

-- Quién recibió y cambios del n.º de pedido. SECURITY INVOKER para
-- distinguir la app (authenticated) de las cargas heredadas. El nombre
-- empieza por «z» para ejecutarse después de las demás reglas.
create function private.order_productions_tracking()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_api boolean := current_user = 'authenticated';
  v_reason text := nullif(trim(coalesce(new.lab_reference_change_reason, '')), '');
begin
  new.lab_reference_change_reason := null;
  if tg_op = 'INSERT' then
    if v_is_api then
      new.received_by := null;
      new.received_recorded_at := null;
    end if;
    return new;
  end if;

  -- Recepción en SOE: queda quién la registró
  if new.status = 'listo_para_entregar' and old.status is distinct from 'listo_para_entregar' then
    new.received_by := (select auth.uid());
    new.received_recorded_at := now();
  elsif new.status = 'en_produccion' and old.status = 'listo_para_entregar' then
    new.received_by := null;
    new.received_recorded_at := null;
  elsif v_is_api then
    new.received_by := old.received_by;
    new.received_recorded_at := old.received_recorded_at;
  end if;

  -- Corrección del n.º de pedido desde la app: se conserva el anterior con motivo
  if v_is_api and old.lab_order_reference is not null
     and new.lab_order_reference is distinct from old.lab_order_reference then
    if v_reason is null then
      raise exception 'Indique el motivo del cambio del n.º de pedido del laboratorio';
    end if;
    perform private.log_production_reference_change(old.id, old.order_id, old.lab_order_reference,
                                                    new.lab_order_reference, v_reason);
  end if;
  return new;
end;
$$;

revoke execute on function private.order_productions_tracking() from public, anon, authenticated;

create trigger z_order_productions_tracking
  before insert or update on public.order_productions
  for each row execute function private.order_productions_tracking();

create or replace view public.v_productions
with (security_invoker = true)
as
SELECT p.id,
    p.order_id,
    o.order_number,
    p.warranty_id,
    p.lab_provider_id,
    l.name AS lab_name,
    p.status,
    p.sent_to_lab_at,
    p.promised_date,
    p.ready_at,
    p.status = 'en_produccion'::production_status AND p.promised_date < private.today_co() AS is_overdue,
    p.cancel_reason,
    p.notes,
    p.released_at,
    p.released_by,
    u.full_name AS released_by_name,
    b.full_name AS buyer_name,
    b.document_id AS buyer_document_id,
    c.name AS company_name,
    ci.name AS city_name,
    o.ops_status,
    p.lab_order_reference,
    o.buyer_id,
    o.company_id,
        CASE
            WHEN p.status <> 'cancelada'::production_status THEN COALESCE(p.ready_at, private.today_co()) - p.sent_to_lab_at
            ELSE NULL::integer
        END AS days_in_lab,
        CASE
            WHEN p.status = 'listo_para_entregar'::production_status THEN private.today_co() - p.ready_at
            ELSE NULL::integer
        END AS days_since_received,
    p.received_by,
    ru.full_name AS received_by_name,
    p.received_recorded_at,
    (select count(*) from production_reference_history h where h.production_id = p.id) AS reference_changes
   FROM order_productions p
     JOIN orders o ON o.id = p.order_id
     JOIN buyers b ON b.id = o.buyer_id
     JOIN lab_providers l ON l.id = p.lab_provider_id
     LEFT JOIN companies c ON c.id = o.company_id
     LEFT JOIN cities ci ON ci.id = o.city_id
     LEFT JOIN users_profiles u ON u.id = p.released_by
     LEFT JOIN users_profiles ru ON ru.id = p.received_by;
