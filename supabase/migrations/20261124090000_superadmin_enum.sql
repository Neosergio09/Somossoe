-- =====================================================================
-- Rol 'superadmin' (24-nov-2026): Luis pasa de Socio (solo consulta) a
-- Super administrador, que puede ejecutar todo el circuito.
-- Va en una migración propia: PostgreSQL no permite usar un valor de
-- enum en la misma transacción en que se agrega.
-- =====================================================================

alter type public.app_role add value if not exists 'superadmin';
