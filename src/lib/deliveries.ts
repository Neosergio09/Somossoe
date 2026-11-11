import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from './database.types';
import type { DeliveryRecord } from '../components/DeliveriesPanel.astro';
import { ITEM_TYPE_LABELS } from './labels';

type Client = SupabaseClient<Database>;

type ItemLike = {
  item_type: Database['public']['Enums']['order_item_type'];
  frame_description: string | null;
  lens_type: string | null;
  description: string | null;
};

export function itemLabel(i: ItemLike): string {
  return i.frame_description ?? i.lens_type ?? i.description ?? ITEM_TYPE_LABELS[i.item_type];
}

/** Entregas de una orden (de la venta o de una garantía) con sus ítems en texto. */
export async function loadDeliveries(
  supabase: Client,
  orderId: string,
  warrantyId: string | null,
): Promise<{ records: DeliveryRecord[]; byItem: Map<string, number> }> {
  let query = supabase
    .from('order_deliveries')
    .select('id, delivered_at, receiver_name, notes, created_at, delivered_by, order_delivery_items(order_item_id, quantity, order_items(item_type, frame_description, lens_type, description))')
    .eq('order_id', orderId)
    .order('delivered_at', { ascending: false })
    .order('created_at', { ascending: false });
  query = warrantyId ? query.eq('warranty_id', warrantyId) : query.is('warranty_id', null);
  const { data } = await query;
  const rows = data ?? [];

  const userIds = [...new Set(rows.map((d) => d.delivered_by).filter((x): x is string => !!x))];
  const { data: users } = userIds.length
    ? await supabase.from('users_profiles').select('id, full_name').in('id', userIds)
    : { data: [] as { id: string; full_name: string }[] };

  const byItem = new Map<string, number>();
  const records = rows.map((d) => {
    for (const di of d.order_delivery_items) byItem.set(di.order_item_id, (byItem.get(di.order_item_id) ?? 0) + di.quantity);
    return {
      id: d.id,
      delivered_at: d.delivered_at,
      receiver_name: d.receiver_name,
      notes: d.notes,
      created_at: d.created_at,
      delivered_by_name: users?.find((u) => u.id === d.delivered_by)?.full_name ?? null,
      items: d.order_delivery_items
        .map((di) => `${di.quantity} × ${di.order_items ? itemLabel(di.order_items) : 'ítem'}`)
        .join(', '),
    };
  });
  return { records, byItem };
}
