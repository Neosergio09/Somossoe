// @ts-check
import { defineConfig, envField } from 'astro/config';
import vercel from '@astrojs/vercel';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  output: 'server',
  adapter: vercel(),
  server: { port: 4321 },
  env: {
    schema: {
      PUBLIC_SUPABASE_URL: envField.string({ context: 'client', access: 'public' }),
      PUBLIC_SUPABASE_PUBLISHABLE_KEY: envField.string({ context: 'client', access: 'public' }),
      SUPABASE_SECRET_KEY: envField.string({ context: 'server', access: 'secret' }),
      // Integración con Alegra (F2, solo lectura). Sin credenciales queda desactivada.
      ALEGRA_API_URL: envField.string({ context: 'server', access: 'secret', default: 'https://api.alegra.com/api/v1' }),
      ALEGRA_API_USER: envField.string({ context: 'server', access: 'secret', optional: true }),
      ALEGRA_API_TOKEN: envField.string({ context: 'server', access: 'secret', optional: true }),
    },
  },
  vite: {
    plugins: [tailwindcss()],
  },
});
