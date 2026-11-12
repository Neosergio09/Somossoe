const copFormatter = new Intl.NumberFormat('es-CO', {
  style: 'currency',
  currency: 'COP',
  maximumFractionDigits: 0,
});

const dateFormatter = new Intl.DateTimeFormat('es-CO', { dateStyle: 'medium', timeZone: 'UTC' });
const dateTimeFormatter = new Intl.DateTimeFormat('es-CO', {
  dateStyle: 'medium',
  timeStyle: 'short',
  timeZone: 'America/Bogota',
});
const weekdayFormatter = new Intl.DateTimeFormat('es-CO', {
  weekday: 'long',
  day: 'numeric',
  month: 'long',
  timeZone: 'UTC',
});
const monthFormatter = new Intl.DateTimeFormat('es-CO', { month: 'long', year: 'numeric', timeZone: 'UTC' });

export function cop(value: number | null | undefined): string {
  return value == null ? '—' : copFormatter.format(value);
}

/** Fecha sin hora (YYYY-MM-DD), sin corrimiento por zona horaria. */
export function fmtDate(value: string | null | undefined): string {
  return value ? dateFormatter.format(new Date(`${value}T00:00:00Z`)) : '—';
}

export function fmtDateTime(value: string | null | undefined): string {
  return value ? dateTimeFormatter.format(new Date(value)) : '—';
}

export function fmtWeekday(value: string): string {
  return weekdayFormatter.format(new Date(`${value}T00:00:00Z`));
}

export function fmtMonth(value: string): string {
  return monthFormatter.format(new Date(`${value}-01T00:00:00Z`));
}

export function fmtTime(value: string | null | undefined): string {
  return value ? value.slice(0, 5) : '—';
}

/** Hoy en Colombia (YYYY-MM-DD). */
export function todayCo(): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Bogota' }).format(new Date());
}

/** Razón (0.3667) como porcentaje con un decimal; null → "—". */
export function pct(value: number | null | undefined): string {
  return value == null ? '—' : `${(Number(value) * 100).toLocaleString('es-CO', { maximumFractionDigits: 1 })} %`;
}
