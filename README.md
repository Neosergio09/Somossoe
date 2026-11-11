# Somossoe

CRM interno de Somos SOE: preventa, jornadas empresariales, órdenes, producción, entregas, facturación (vínculo con Alegra) y cartera.

La especificación funcional (SRS v1.4) es la fuente de verdad y vive fuera de este repositorio, en `documentacion aceptada/`.

**Stack:** Astro 7 (SSR) + Tailwind 4 + TypeScript + Zod · Supabase (Postgres, Auth, RLS) · Vercel.

## Puesta en marcha local

```bash
pnpm install
supabase start                 # levanta Supabase local (Docker)
supabase db reset              # migraciones + datos de prueba (supabase/seed.sql)
cp .env.example .env           # y completar con: supabase status -o env
pnpm dev                       # http://localhost:4321
```

Variables (`.env`):

| Variable | Origen (`supabase status -o env`) | Uso |
| :--- | :--- | :--- |
| `PUBLIC_SUPABASE_URL` | `API_URL` | Cliente con la sesión del usuario |
| `PUBLIC_SUPABASE_PUBLISHABLE_KEY` | `PUBLISHABLE_KEY` | Cliente con la sesión del usuario |
| `SUPABASE_SECRET_KEY` | `SECRET_KEY` | Solo servidor: alta de usuarios por Dirección |

### Usuarios de prueba (solo local)

Contraseña de todos: `Somossoe2026!`

| Correo | Rol |
| :--- | :--- |
| `direccion@somossoe.test` | Dirección |
| `comercial@somossoe.test` | Comercial (ejecutiva de la empresa de ejemplo) |
| `comercial2@somossoe.test` | Comercial (sin cuentas asignadas: para probar que cada Comercial edita solo lo suyo) |
| `operacion@somossoe.test` | Operación |
| `cartera@somossoe.test` | Administración / Cartera |
| `nuevo@somossoe.test` | Sin activar (para ver la pantalla de pendiente) |

## Base de datos (Supabase)

- Migraciones: `supabase/migrations/`
- Pruebas pgTAP: `supabase/tests/database/`
- Datos de prueba locales: `supabase/seed.sql` (no se suben al remoto)
- Puertos locales: API 55421 · DB 55422 · Studio 55423 (para no chocar con otros proyectos locales).

```bash
supabase db reset          # aplica todas las migraciones desde cero (con datos de prueba)
supabase db reset --no-seed && supabase test db   # las pruebas corren sobre una BD sin seed
pnpm db:types              # regenera src/lib/database.types.ts
supabase db push --linked  # sube migraciones al proyecto remoto
```

### Primer usuario de Dirección (remoto)

Los perfiles nacen inactivos y sin rol. Tras crear el primer usuario en Auth (dashboard de Supabase), actívalo desde el SQL Editor:

```sql
update public.users_profiles
set role = 'direccion', active = true
where email = '<correo>';
```

Desde ahí, Dirección crea, asigna roles y activa al resto de usuarios en `/admin/usuarios`.

## Estructura de la app

- `src/middleware.ts`: sesión de Supabase por petición, protección de rutas y usuarios sin activar.
- `src/lib/forms.ts`: POST con `_action`, validación con Zod y traducción de errores de la BD.
- `src/pages/`: empresas, oportunidades (Kanban y bitácora), convenios, jornadas (calendario, sesiones y asistencia), órdenes (comprador, ítems, plan de cuotas y verificación de requisitos), producción y entregas (liberación con candado, laboratorio y entregas parciales), posventa (garantías y reposiciones) y administración.
- Las reglas de negocio y permisos viven en la base de datos (triggers + RLS); la interfaz solo oculta lo que el rol no puede hacer.

```bash
pnpm check   # tipos (astro check)
pnpm build   # build de producción (adaptador de Vercel)
```
