// Ejemplo de una pantalla con escenarios propios. Lo que se abre con un clic también tiene que caber: el buscador se abre en todos los anchos, y
// el menú solo existe como cajón en celular, así que ese escenario declara su ancho. Si corriera en los otros, repetiría el estado inicial y sumaría
// verdes que no midieron nada.

/** @type {import('./registro.mjs').PantallaSinModulo} */
const pantallaDashboard = {
  id: "dashboard",
  nombre: "Dashboard",
  ruta: "/admin/dashboard",
  cuenta: "admin",
  escenarios: [
    { id: "inicial", nombre: "Estado inicial" },
    {
      id: "buscador",
      nombre: "El buscador abierto",
      async preparar(pagina) {
        await pagina.getByRole("button", { name: "Buscar", exact: true }).first().click();
        await pagina.locator('[role="dialog"][aria-label="Buscar en Dynamic"]').waitFor({ state: "visible", timeout: 6000 });
      },
    },
    {
      id: "menu",
      nombre: "El menú del celular abierto",
      viewports: ["375x812"],
      async preparar(pagina) {
        await pagina.getByRole("button", { name: "Abrir menú", exact: true }).click();
        await pagina.locator('[role="dialog"]').first().waitFor({ state: "visible", timeout: 6000 });
      },
    },
  ],
};

export default pantallaDashboard;
