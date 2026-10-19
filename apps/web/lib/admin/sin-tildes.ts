// Buscar «Gutierrez» tiene que encontrar a «Gutiérrez»: quien escribe con prisa no pone la tilde, y media
// plantilla lleva una en el apellido. Mismo normalizador que /admin/horas y que el buscador global.
export function sinTildes(t: string): string {
  return t.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();
}
