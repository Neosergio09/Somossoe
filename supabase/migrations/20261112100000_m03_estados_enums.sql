-- =====================================================================
-- Valores nuevos de enums (Especificación Módulo de Jornadas V01).
-- Va en una migración propia: PostgreSQL no permite usar un valor de
-- enum en la misma transacción en que se agrega.
--
-- * app_role 'socio': Luis. Consulta todo el CRM, incluidos costos y
--   márgenes; no edita nada.
-- * campaign_status: borrador → programada → en_ejecucion →
--   captura_cerrada → operacion_cerrada | cancelada.
--   El antiguo 'cerrada' pasa a 'operacion_cerrada' (conserva los datos).
-- =====================================================================

alter type public.app_role add value if not exists 'socio';

alter type public.campaign_status rename value 'cerrada' to 'operacion_cerrada';
alter type public.campaign_status add value if not exists 'borrador' before 'programada';
alter type public.campaign_status add value if not exists 'captura_cerrada' before 'operacion_cerrada';
