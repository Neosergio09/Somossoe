import type { APIRoute } from 'astro';
import { z } from '../../../lib/forms';
import { SUPPORT_BUCKET, SUPPORT_KINDS, SUPPORT_MAX_BYTES, SUPPORT_TYPES } from '../../../lib/supports';

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

const schema = z.object({
  kind: z.enum(SUPPORT_KINDS),
  type: z.string(),
  size: z.number().int().positive(),
});

/**
 * Prepara la subida de un soporte: devuelve un enlace de subida firmado
 * para que el navegador envíe el archivo directo a Storage (sin pasar por
 * el servidor de la app). La RLS de storage.objects valida el rol.
 */
export const POST: APIRoute = async ({ request, locals }) => {
  if (!locals.profile?.active || !locals.userId) return json({ error: 'Sesión no válida.' }, 401);

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Solicitud inválida.' }, 400);
  }
  const parsed = schema.safeParse(body);
  if (!parsed.success) return json({ error: 'Solicitud inválida.' }, 400);
  const { kind, type, size } = parsed.data;

  const ext = SUPPORT_TYPES[type];
  if (!ext) return json({ error: 'Formato no permitido: use PDF, JPG, PNG o WEBP.' }, 422);
  if (size > SUPPORT_MAX_BYTES) return json({ error: 'El archivo supera 10 MB.' }, 422);

  const path = `${kind}/${locals.userId}/${crypto.randomUUID()}.${ext}`;
  const { data, error } = await locals.supabase.storage.from(SUPPORT_BUCKET).createSignedUploadUrl(path);
  if (error || !data) {
    console.error(error);
    return json({ error: 'No tiene permiso para adjuntar este tipo de soporte.' }, 403);
  }
  return json({ path, signedUrl: data.signedUrl });
};
