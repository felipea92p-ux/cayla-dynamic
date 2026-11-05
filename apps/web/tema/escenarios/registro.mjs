// Los escenarios: lo que NO se ve al cargar una ruta —un modal abierto, el cajón del celular, el buscador— y que hay que medir igual. Un
// escenario es `{ id, ruta, nombre, preparar(pagina), cuentas?, abre?, limpiar?, ancho?, soloPorId? }`:
//   · `ruta`      la pantalla donde ocurre.
//   · `cuentas`   las claves de `tema/cuentas.mjs` que lo ven (sin esto, todas las que entren a esa ruta).
//   · `preparar`  recibe la página YA cargada y hace los clics. Si necesita un registro, llega a él con clics, no con un id escrito a mano.
//   · `abre`      el selector de lo que el escenario DEBE dejar abierto. La CLI lo exige: un escenario que «pasa» sin haber abierto nada mide la
//                 pantalla de siempre y da una falsa tranquilidad.
//   · `limpiar`   deshace lo que cambió FUERA de la página (la red del contexto): el contexto se comparte con los escenarios que siguen.
//   · `ancho`     «escritorio» o «celular» (menos de 700 px): el escenario solo existe en ese tamaño.
//   · `soloPorId` no entra en `--escenarios`; solo se corre pidiéndolo con `--escenario <id>`.
//
// Empieza con pocos y reales: cada obra agrega los de lo que toca.

const esperar = (pagina, ms = 500) => pagina.waitForTimeout(ms);
const clicEnBoton = (nombre) => async (pagina) => {
  await pagina.getByRole("button", { name: nombre, exact: true }).first().click();
  await esperar(pagina);
};

export const ESCENARIOS = [
  {
    id: "panel.buscador",
    ruta: "/admin/dashboard",
    nombre: "El buscador abierto",
    preparar: clicEnBoton("Buscar"),
    abre: '[role="dialog"][aria-label="Buscar en Dynamic"]',
  },
  {
    id: "panel.atajos",
    ruta: "/admin/dashboard",
    ancho: "escritorio",
    nombre: "Los atajos de teclado abiertos",
    preparar: clicEnBoton("Atajos de teclado"),
    abre: '[role="dialog"][aria-label="Atajos de teclado"]',
  },
  {
    id: "panel.cajon-celular",
    ruta: "/admin/dashboard",
    ancho: "celular",
    nombre: "El menú del celular abierto",
    preparar: clicEnBoton("Abrir menú"),
    abre: '[role="dialog"]',
  },
  // El caso que DEBE fallar. Un freno se prueba con algo que debe bloquear: esto pinta, solo en el navegador de la corrida, un texto ilegible, una
  // mancha blanca y un velo que aclara, junto a tres cosas claras a propósito que NO deben contar. Si `--escenario prueba.debe-fallar` sale en
  // verde, el medidor está roto. Lo que espera, exacto, está en `tema/autoprueba.mjs`.
  {
    id: "prueba.debe-fallar",
    ruta: "/admin/dashboard",
    cuentas: ["admin"],
    soloPorId: true,
    nombre: "Defectos pintados a propósito: esto tiene que fallar",
    abre: "#prueba-debe-fallar",
    async preparar(pagina) {
      await pagina.evaluate(() => {
        const caja = document.createElement("div");
        caja.id = "prueba-debe-fallar";
        caja.innerHTML = `
          <p style="color:#9a9a9a;background:#a8a8a8;padding:8px">Texto que no se lee</p>
          <div style="background:#fff;width:400px;height:200px"></div>
          <div class="hoja"><div style="background:#fff;width:400px;height:200px"></div></div>
          <div class="firma-tinta" style="background:#fff;width:400px;height:200px"></div>
          <div style="background:var(--color-crema-fija);width:400px;height:200px"></div>
          <div style="position:fixed;inset:0;background:rgba(255,255,255,.4);pointer-events:none"></div>`;
        document.body.appendChild(caja);
      });
    },
  },
];

export const escenariosDe = (ruta, cuentaClave, celular = false) =>
  ESCENARIOS.filter((e) => e.ruta === ruta && (!e.cuentas || e.cuentas.includes(cuentaClave)) && (!e.ancho || (e.ancho === "celular") === celular));
