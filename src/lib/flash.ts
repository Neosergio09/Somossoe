import type { AstroCookies } from 'astro';

export type Flash = { type: 'ok' | 'error'; message: string };

const COOKIE = 'flash';

export function setFlash(cookies: AstroCookies, flash: Flash) {
  cookies.set(COOKIE, JSON.stringify(flash), {
    path: '/',
    httpOnly: true,
    sameSite: 'lax',
    maxAge: 60,
  });
}

export function takeFlash(cookies: AstroCookies): Flash | null {
  const cookie = cookies.get(COOKIE);
  if (!cookie) return null;
  cookies.delete(COOKIE, { path: '/' });
  try {
    const parsed = JSON.parse(cookie.value) as Flash;
    return parsed?.message ? parsed : null;
  } catch {
    return null;
  }
}
