import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from './database.types';
import { ensure, FormError } from './forms';
import { MANUAL_STAGES, STAGE_LABELS, type DealStage } from './labels';

type LostSubstatus = Database['public']['Enums']['lost_substatus'];

/**
 * Cambia la etapa de una oportunidad. Las reglas del embudo (Reunión en
 * bitácora, convenio aprobado, etapas automáticas…) las valida la BD.
 * Devuelve la etiqueta de la nueva etapa.
 */
export async function changeDealStage(
  supabase: SupabaseClient<Database>,
  dealId: string,
  stage: DealStage,
  lostSubstatus?: LostSubstatus | null,
): Promise<string> {
  if (!MANUAL_STAGES.includes(stage)) {
    throw new FormError('Esa etapa avanza automáticamente con las jornadas y la facturación.');
  }
  if (stage === 'cierre_perdido' && !lostSubstatus) {
    throw new FormError('Seleccione el sub-estado del cierre perdido.');
  }
  ensure(
    await supabase
      .from('deals_opportunities')
      .update({ stage, lost_substatus: stage === 'cierre_perdido' ? lostSubstatus! : null })
      .eq('id', dealId)
      .select('id')
      .single(),
  );
  return STAGE_LABELS[stage];
}
