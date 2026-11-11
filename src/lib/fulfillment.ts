import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from './database.types';
import { checkbox, date, ensure, FormError, parseForm, text, uuid, z, type ActionHandler } from './forms';

type Client = SupabaseClient<Database>;

/**
 * Acciones de producción y entrega compartidas por la ficha de la orden
 * (producción de la venta) y la de la garantía (reposición).
 */
export function fulfillmentActions(
  supabase: Client,
  context: { orderId: string; warrantyId?: string | null },
): Record<string, ActionHandler> {
  const productionId = (form: FormData) => {
    const id = String(form.get('production_id') ?? '');
    if (!id) throw new FormError('Producción no indicada.');
    return id;
  };
  const updateProduction = async (id: string, patch: Database['public']['Tables']['order_productions']['Update']) => {
    ensure(
      await supabase
        .from('order_productions')
        .update(patch)
        .eq('id', id)
        .eq('order_id', context.orderId)
        .select('id')
        .single(),
    );
  };

  return {
    release: async (form) => {
      const input = parseForm(
        z.object({
          lab_provider_id: uuid(),
          sent_to_lab_at: date(),
          promised_date: date(),
          notes: text(1000).optional(),
        }),
        form,
      );
      ensure(
        await supabase
          .from('order_productions')
          .insert({ ...input, notes: input.notes ?? null, order_id: context.orderId, warranty_id: context.warrantyId ?? null })
          .select('id')
          .single(),
      );
      return { message: context.warrantyId ? 'Reposición enviada al laboratorio.' : 'Orden liberada a producción.' };
    },
    production_update: async (form) => {
      const input = parseForm(
        z.object({
          lab_provider_id: uuid(),
          sent_to_lab_at: date(),
          promised_date: date(),
          notes: text(1000).optional(),
        }),
        form,
      );
      await updateProduction(productionId(form), { ...input, notes: input.notes ?? null });
      return { message: 'Producción actualizada.' };
    },
    production_ready: async (form) => {
      const input = parseForm(z.object({ ready_at: date() }), form);
      await updateProduction(productionId(form), { status: 'listo_para_entregar', ready_at: input.ready_at });
      return { message: 'Producción marcada como lista para entregar.' };
    },
    production_back: async (form) => {
      await updateProduction(productionId(form), { status: 'en_produccion', ready_at: null });
      return { message: 'Producción devuelta a En producción.' };
    },
    production_cancel: async (form) => {
      const reason = String(form.get('cancel_reason') ?? '').trim();
      if (!reason) throw new FormError('Indique el motivo de la cancelación.');
      await updateProduction(productionId(form), { status: 'cancelada', cancel_reason: reason });
      return { message: 'Producción cancelada.' };
    },
    deliver: async (form) => {
      const input = parseForm(
        z.object({
          delivered_at: date(),
          receiver_name: text(150),
          evidence_received: checkbox(),
          notes: text(1000).optional(),
        }),
        form,
      );
      if (!input.evidence_received) throw new FormError('Registre la evidencia de la entrega (foto o acta firmada).');
      const items = [...form.entries()]
        .map(([key, value]) => ({ m: /^qty\[([0-9a-f-]{36})\]$/.exec(key), value: String(value).trim() }))
        .filter((x) => x.m && x.value !== '')
        .map((x) => ({ order_item_id: x.m![1], quantity: Number(x.value) }));
      if (items.some((i) => !Number.isInteger(i.quantity) || i.quantity < 0)) {
        throw new FormError('Las cantidades deben ser números enteros.');
      }
      if (!items.some((i) => i.quantity > 0)) throw new FormError('Indique al menos un ítem con cantidad a entregar.');
      ensure(
        await supabase.rpc('register_delivery', {
          p_delivery: {
            order_id: context.orderId,
            warranty_id: context.warrantyId ?? null,
            delivered_at: input.delivered_at,
            receiver_name: input.receiver_name,
            evidence_received: true,
            notes: input.notes ?? null,
          },
          p_items: items,
        }),
      );
      return { message: 'Entrega registrada.' };
    },
    delete_delivery: async (form) => {
      const deliveryId = String(form.get('delivery_id') ?? '');
      ensure(
        await supabase.from('order_deliveries').delete().eq('id', deliveryId).eq('order_id', context.orderId).select('id').single(),
      );
      return { message: 'Entrega eliminada.' };
    },
  };
}

export async function activeLabs(supabase: Client) {
  const { data } = await supabase.from('lab_providers').select('id, name').eq('active', true).order('name');
  return data ?? [];
}
