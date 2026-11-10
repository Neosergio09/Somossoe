# Somossoe

CRM interno de Somos SOE: preventa, jornadas empresariales, órdenes, producción, entregas, facturación (vínculo con Alegra) y cartera.

La especificación funcional (SRS v1.4) es la fuente de verdad y vive fuera de este repositorio, en `documentacion aceptada/`.

## Base de datos (Supabase)

- Migraciones: `supabase/migrations/`
- Pruebas pgTAP: `supabase/tests/database/`
- Puertos locales: API 55421 · DB 55422 · Studio 55423 (para no chocar con otros proyectos locales).

```bash
supabase start          # levanta el entorno local
supabase db reset       # aplica todas las migraciones desde cero
supabase test db        # corre las pruebas
supabase db push --linked   # sube migraciones al proyecto remoto
```

### Primer usuario de Dirección

Los perfiles nacen inactivos y sin rol. Tras crear el primer usuario en Auth, actívalo desde el SQL Editor:

```sql
update public.users_profiles
set role = 'direccion', active = true
where email = '<correo>';
```

Desde ahí, Dirección asigna roles y activa al resto de usuarios.
