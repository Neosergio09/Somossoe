/// <reference types="astro/client" />
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from './lib/database.types';

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
    }
  }
}

export {};
