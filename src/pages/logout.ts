import type { APIRoute } from 'astro';
import { VIEW_AS_COOKIE } from '../lib/viewAs';

export const POST: APIRoute = async ({ locals, cookies, redirect }) => {
  await locals.supabase.auth.signOut();
  cookies.delete(VIEW_AS_COOKIE, { path: '/' });
  return redirect('/login', 303);
};
