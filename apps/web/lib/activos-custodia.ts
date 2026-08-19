// Los activos principales que cada sede custodia, para el ANEXO IV del
// contrato de trabajo — "Constancia de recepción y responsabilidad de
// activos". No es un inventario: es una FOTO tomada a mano el 2026-08-19
// desde cayla-retail.vercel.app/finanzas/activos (pantallas de AQP, LIM y
// TRU que Felipe compartió), pensada para imprimirse dentro del contrato.
//
// POR QUÉ EL VALOR ES EL COSTO DE COMPRA, NO EL VALOR DE HOY YA DEPRECIADO
//
// El Anexo IV original (el de Angie, sede TRU) ya declaraba el costo de
// compra — el mismo criterio de Finanzas: "Su valor se consigna para
// efectos de identificación y eventual reposición". Si algo se pierde o
// daña, se repone al precio de compra, no al valor contable de hoy.
// Confirmado con Felipe el 2026-08-19: se mantiene ese mismo criterio.
//
// POR QUÉ ES UNA CONSTANTE Y NO UNA CONSULTA A `retail.activos_fijos`
//
// La migración de unificación de cayla-retail (agosto 2026) creó las 22
// tablas del esquema `retail` VACÍAS — no copió ninguna fila del proyecto
// viejo. Aunque la tabla existiera con datos hoy, cruzar en vivo dos
// aplicaciones distintas para un documento legal que se firma UNA vez por
// contrato es más riesgo del que vale: si retail cambia un activo mañana,
// no debe reescribir en silencio lo que alguien ya firmó ayer. Se congela
// al armar el contrato, igual que la política salarial se congela al
// publicarse (0141).
//
// POR QUÉ SOLO "LO PRINCIPAL" EN LIM, Y NO TODO
//
// AQP y TRU tienen 9 bienes cada una: cabe la lista completa. LIM (el
// Taller) tiene más de 21 —maquinaria de costura y corte, sobre todo— y no
// todas las tocan todas las personas. Acá solo quedan las de mayor valor;
// el resto de la lista (sillas, mesas, un ventilador, dos "por identificar")
// se deja fuera a propósito y se cubre con el campo libre de cada persona
// en pantalla, no copiando cifras de poco peso a un documento legal.
//
// SI UN BIEN CAMBIA (se pierde, se repone, se compra uno nuevo)
//
// Se edita esta lista a mano. No hay sincronización automática con Finanzas
// de retail — es la misma razón por la que `rangos.ts` no lee `parametros_laborales`
// en vivo para su lista de dropdown: es una copia de trabajo, la verdad vive
// en otro sitio, y se actualiza cuando alguien la mira y la corrige.

export interface ActivoCustodia {
  bien: string;
  serie: string | null;
  costo: number;
}

export const ACTIVOS_POR_SEDE: Record<string, ActivoCustodia[]> = {
  AQP: [
    { bien: 'MacBook Air 13" chip M5', serie: "CVVK6HGDJM", costo: 4500.0 },
    { bien: 'MacBook Air 13" (segunda unidad)', serie: "C74L6MFDV7", costo: 4200.0 },
    { bien: "Mac Mini chip M4", serie: "HWXW6FXHPK", costo: 4000.0 },
    { bien: "iPhone 15 — 128 GB", serie: "H9YGXH6XVJ", costo: 2100.0 },
    { bien: "Laptop Lenovo V14-IIL", serie: "PF1TN315", costo: 1500.0 },
    { bien: "Cafetera y molino", serie: null, costo: 1419.0 },
    { bien: "Parlante JBL Authentics 200", serie: "GTO255-LPO001460", costo: 959.0 },
    { bien: "Parlante JBL Authentics 200 (2.ª)", serie: "GTO255-LPO001303", costo: 959.0 },
    { bien: "Smartphone Xiaomi Redmi 13X", serie: "66728/W5QU02203", costo: 600.0 },
  ],
  TRU: [
    { bien: "Mac Mini chip M4 (16 GB / 2024)", serie: "XY7LDJ34J6", costo: 4000.0 },
    { bien: "Mac Mini chip M4 (16 GB / 2024) — 2.ª", serie: "KMHQNW753C", costo: 4000.0 },
    { bien: "Mac Mini chip M4 (16 GB / 2024) — 3.ª", serie: "H7T6XQ4F5P", costo: 4000.0 },
    { bien: "Laptop Lenovo Legion 5 15IMH-05", serie: "PF35R64F", costo: 2000.0 },
    { bien: "Parlante JBL Authentics 500", serie: "GG1192-DP0018698 (por verificar)", costo: 1899.0 },
    { bien: "Cámara Canon EOS 80D + lentes", serie: "442026000337", costo: 1800.0 },
    { bien: "Parlante JBL Authentics 300", serie: "TL1528-LO026546", costo: 1289.0 },
    { bien: "iPhone 12", serie: "DNPGQ6E70FON", costo: 1200.0 },
    { bien: "Smartphone Xiaomi Redmi Note 12", serie: null, costo: 750.0 },
  ],
  // Taller. Solo la maquinaria de mayor valor — ver nota arriba.
  LIM: [
    { bien: "Máquina recta JUKI DDL-8000C (computarizada IA)", serie: "4D0TM01611", costo: 3744.0 },
    { bien: 'Mac Mini chip M4 / 16 GB ("Lim Production")', serie: "C37NKGQNHO", costo: 3500.0 },
    { bien: "Remalladora JUKI MO-6714DA (BE6-40H)", serie: "8MOUD03299", costo: 3492.0 },
    { bien: "Overlock Siruba 757L-516M-3-35", serie: "125L011862", costo: 2675.4 },
    { bien: "Máquina recta Siruba DL8000-BM1-16Q", serie: "925T010120", costo: 1680.0 },
    { bien: "Máquina recta JUKI DDL-8700", serie: "4D0UD00888", costo: 1668.5 },
    { bien: "Máquina recta JUKI DDL-8700", serie: "4D0UD00812", costo: 1548.0 },
    { bien: "Cortadora Jack", serie: null, costo: 950.0 },
    { bien: "Cortadora de tela", serie: null, costo: 519.2 },
    { bien: "Plancha industrial Silver Star", serie: null, costo: 230.0 },
  ],
  // Central es administración y Desarrollo Organizacional, no vende ni
  // produce (0099) — sin registro de activos en Finanzas de retail.
  CCO: [],
};

export function activosDeSede(codigoSede: string): ActivoCustodia[] {
  return ACTIVOS_POR_SEDE[codigoSede] ?? [];
}

export function formatSolesActivo(n: number): string {
  return new Intl.NumberFormat("es-PE", {
    style: "currency",
    currency: "PEN",
    minimumFractionDigits: 2,
  }).format(n);
}
