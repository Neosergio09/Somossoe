/// <reference types="astro/client" />
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from './lib/database.types';
import type { CircuitSummary } from './lib/circuit';

type AppRole = Database['public']['Enums']['app_role'];

declare global {
  namespace App {
    interface Locals {
      supabase: SupabaseClient<Database>;
      userId: string | null;
      profile: {
        id: string;
        full_name: string;
        email: string;
        role: AppRole | null;
        active: boolean;
      } | null;
      /** Rol con el que Dirección previsualiza la interfaz ("Ver como"); profile.role ya lo refleja */
      viewAs?: AppRole | null;
      /** Rol real de la cuenta cuando "Ver como" está activo */
      realRole?: AppRole | null;
      /** Resumen del circuito ya cargado por la página (lo reutiliza el layout) */
      summary?: CircuitSummary;
    }
  }
}

export {};
