/**
 * «Gutiérrez» → «gutierrez». Para buscar a alguien escribiendo con prisa, sin
 * tildes ni mayúsculas.
 *
 * Hoy hay tres copias locales de esto (admin/horarios, admin/contratos,
 * components/buscador-global). Esta es la que deberían importar; se deja así y
 * no se migran las tres en el mismo cambio de la Bandeja para no mezclar un
 * rediseño con un refactor de otras pantallas.
 */
export function sinTildes(texto: string): string {
  return texto.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}
