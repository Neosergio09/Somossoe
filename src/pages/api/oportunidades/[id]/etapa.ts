import type { APIRoute } from 'astro';
import { changeDealStage } from '../../../../lib/deals';
import { setFlash } from '../../../../lib/flash';
import { FormError, z } from '../../../../lib/forms';
import { MANUAL_STAGES, type DealStage } from '../../../../lib/labels';

const schema = z.object({
  stage: z.enum(MANUAL_STAGES as [DealStage, ...DealStage[]]),
  lost_substatus: z.enum(['nurturing', 'no_contactar']).nullish(),
});

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

/** Cambio de etapa desde el Kanban (arrastrar y soltar). */
export const POST: APIRoute = async ({ params, request, locals, cookies }) => {
  if (!locals.profile?.active) return json({ error: 'Sesión no válida.' }, 401);

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Solicitud inválida.' }, 400);
  }
  const parsed = schema.safeParse(body);
  if (!parsed.success) return json({ error: 'Etapa no válida.' }, 400);

  try {
    const label = await changeDealStage(locals.supabase, params.id!, parsed.data.stage, parsed.data.lost_substatus);
    setFlash(cookies, { type: 'ok', message: `Oportunidad movida a ${label}.` });
    return json({ ok: true, label });
  } catch (error) {
    if (error instanceof FormError) return json({ error: error.message }, 422);
    console.error(error);
    return json({ error: 'No se pudo mover la oportunidad. Intente de nuevo.' }, 500);
  }
};
