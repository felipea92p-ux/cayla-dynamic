// Liquidaciones con el detalle abierto: quien va a marcar una liquidación como pagada tiene que ver el Total junto al botón, sin deslizar nada.
//
// El medidor se salta lo que vive dentro de una caja que corre de lado, porque ahí se llega deslizando. Justo por eso el defecto del #689 no se habría
// visto con un escenario normal: a 375 px el detalle se abría dentro de la tabla, con el botón a la vista y el monto del Total afuera. `limite` apaga ese
// salto, y `ambito` lo acota al detalle, para no exigírselo a nada más de la pantalla. Y `td` hace que los montos cuenten: por defecto solo se miden
// botones, campos y títulos, y lo que no debía perderse aquí era una cifra.
//
// Las dos personas son de `scripts/local/sembrar.mjs`. Si no aparecen no da verde: da ERROR, y dice qué correr.

const MARCA = "data-medicion-detalle";

/** @returns {import('./registro.mjs').Escenario} */
function detalleAbierto({ id, nombre, pestana, persona }) {
  return {
    id,
    nombre,
    ambito: `[${MARCA}]`,
    limite: "main",
    elementosClave: ["td"],
    async preparar(pagina) {
      await pagina.getByRole("button", { name: new RegExp(`^${pestana}`) }).click();
      // Por el nombre y no «el primer Revisar»: abrir a otra persona con S/ 0.00 mediría una pantalla que no es la que importa.
      const enLaLista = pagina.getByText(persona, { exact: true }).filter({ visible: true }).first();
      await enLaLista.waitFor({ timeout: 6000 }).catch(() => {
        throw new Error(`«${persona}» no está en ${pestana}. Corre «node scripts/local/sembrar.mjs --solo-ceses»; si alguien cambió su liquidación al probar, deshazlo en la pantalla.`);
      });
      const fila = enLaLista.locator("xpath=ancestor::*[.//button[starts-with(normalize-space(.), 'Revisar')]][1]");
      await fila.getByRole("button", { name: /^Revisar/ }).click();

      const rotuloTotal = pagina.locator("td").filter({ hasText: /^Total$/ }).filter({ visible: true }).first();
      await rotuloTotal.waitFor({ timeout: 15000 });
      const total = await rotuloTotal.evaluate((celda, marca) => {
        // La marca la pone la medición, no la pantalla: así se puede medir también una versión vieja de la pantalla.
        celda.closest("table").parentElement.setAttribute(marca, "");
        return celda.nextElementSibling?.textContent ?? "";
      }, MARCA);
      if (!/[1-9]/.test(total)) throw new Error(`El Total de «${persona}» es «${total}»: este escenario tiene que medir un detalle con monto.`);
    },
  };
}

/** @type {import('./registro.mjs').PantallaSinModulo} */
const pantallaLiquidaciones = {
  id: "liquidaciones",
  nombre: "Liquidaciones",
  ruta: "/admin/liquidaciones",
  cuenta: "do",
  escenarios: [
    { id: "inicial", nombre: "Estado inicial" },
    detalleAbierto({ id: "detalle-pendiente", nombre: "El detalle abierto, en Pendientes", pestana: "Pendientes", persona: "Filomena del Rosario Altamirano-Bustamante de la Cruz Zevallos" }),
    detalleAbierto({ id: "detalle-pagada", nombre: "El detalle abierto, en Pagadas", pestana: "Pagadas", persona: "Olga Bustos Rivas" }),
  ],
};

export default pantallaLiquidaciones;
