-- =====================================================================
-- SRS 1.6 · §3.1: nuevo rol 'costos' (auxiliar contable). Va en una
-- migración propia: PostgreSQL no permite usar un valor de enum en la
-- misma transacción en que se agrega.
-- =====================================================================

alter type public.app_role add value if not exists 'costos';
