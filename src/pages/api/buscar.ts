import type { APIRoute } from 'astro';
import { safeSearch } from '../../lib/options';
import { orderNumber } from '../../lib/orders';

type Hit = { type: string; label: string; sub: string; href: string };
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'private, no-store' } });

/** Búsqueda global del buscador (Ctrl+K). Cada consulta respeta la RLS del usuario. */
export const GET: APIRoute = async ({ url, locals }) => {
  if (!locals.profile?.active) return json({ error: 'Sesión no válida.' }, 401);
  const q = safeSearch(url.searchParams.get('q'));
  if (q.length < 2) return json({ hits: [] });
  const { supabase } = locals;
  const doc = q.toUpperCase().replace(/[\s.-]/g, '');
  const num = /^(ord-?)?0*(\d{1,9})$/i.exec(q.replace(/\s/g, ''))?.[2];

  const [buyers, companies, deals, orders] = await Promise.all([
    supabase.from('buyers').select('id, full_name, document_id').or(`full_name.ilike.%${q}%,document_id.ilike.%${doc || q}%`).limit(6),
    supabase.from('companies').select('id, name, nit').or(`name.ilike.%${q}%,nit.ilike.%${doc || q}%`).limit(5),
    supabase.from('v_deals_board').select('id, deal_name_branch, company_name').ilike('deal_name_branch', `%${q}%`).limit(4),
    num
      ? supabase.from('v_orders').select('id, order_number, buyer_name, company_name').eq('order_number', Number(num)).limit(3)
      : supabase.from('v_orders').select('id, order_number, buyer_name, company_name').ilike('buyer_name', `%${q}%`).order('created_at', { ascending: false }).limit(4),
  ]);

  const hits: Hit[] = [
    ...(orders.data ?? []).map((o) => ({ type: 'Órdenes', label: `${orderNumber(o.order_number)} · ${o.buyer_name}`, sub: o.company_name ?? 'Particular', href: `/ordenes/${o.id}` })),
    ...(buyers.data ?? []).map((b) => ({ type: 'Compradores', label: b.full_name, sub: `Doc. ${b.document_id} · expediente 360°`, href: `/compradores/${b.id}` })),
    ...(companies.data ?? []).map((c) => ({ type: 'Empresas', label: c.name, sub: c.nit ? `NIT ${c.nit} · vista 360°` : 'Vista 360°', href: `/empresas/${c.id}/360` })),
    ...(deals.data ?? []).map((d) => ({ type: 'Oportunidades', label: d.deal_name_branch ?? '', sub: d.company_name ?? '', href: `/oportunidades/${d.id}` })),
  ];
  return json({ hits });
};
