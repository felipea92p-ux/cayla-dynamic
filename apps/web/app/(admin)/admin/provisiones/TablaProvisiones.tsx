import type { ReactNode } from "react";
import { formatSoles } from "@/lib/rangos";
import { Tabla, TablaEncabezado, Th, Fila } from "@/components/ui/tabla";
import { Insignia } from "@/components/ui/insignia";
import {
  ETIQUETA_ESTADO_FILA,
  estadosFila,
  fechaCorta,
  gratiConBonificacion,
  montoProximo,
  proximoDesembolso,
  resumen,
  totalProximo,
  type EstadoFila,
  type ProvData,
  type ProvPersona,
} from "@/lib/admin/provisiones";

export type AbrirPersona = (persona: ProvPersona, origen: HTMLElement) => void;

const VARIANTE: Record<EstadoFila, "alerta" | "advertencia" | "informativo" | "neutral"> = {
  sin_tramo: "alerta",
  vencido: "advertencia",
  pagado_de_mas: "informativo",
  al_dia: "neutral",
  no_aplica: "neutral",
};

export function Estados({ persona, data }: { persona: ProvPersona; data: ProvData }) {
  return (
    <span className="flex flex-wrap gap-1">
      {estadosFila(persona, data).map((e) => (
        <Insignia key={e} variante={VARIANTE[e]} atenuada={e === "al_dia" || e === "no_aplica"}>
          {ETIQUETA_ESTADO_FILA[e]}
        </Insignia>
      ))}
    </span>
  );
}

// Un negativo no se esconde (decisión de la 0158) y tampoco se deja solo: dice
// que es un pago de más y que el detalle explica de dónde sale.
function Monto({ n, sub }: { n: number; sub?: ReactNode }) {
  if (n < 0) {
    return (
      <>
        <span className="text-pizarra">{formatSoles(n)}</span>
        <span className="block text-xs text-pizarra">pagado de más · ver origen</span>
      </>
    );
  }
  return (
    <>
      {formatSoles(n)}
      {sub && <span className="block text-xs text-taupe">{sub}</span>}
    </>
  );
}

// La tabla principal: siete columnas de dinero y estado. El detalle por
// ventana (julio/diciembre, mayo/noviembre, días, aniversario, cada pago) vive
// en el panel lateral, no se perdió: se movió.
//
// «Gratificación» lleva su 9 % adentro para que Gratificación + CTS +
// Vacaciones sea exactamente el «Saldo total» que manda la base (la regla del
// 2026-08-19: un total que no cuadra con lo que se ve enseña a desconfiar).
export function TablaProvisiones({
  data,
  personas,
  onAbrir,
  vacio,
}: {
  data: ProvData;
  personas: ProvPersona[];
  onAbrir: AbrirPersona;
  vacio: ReactNode;
}) {
  if (personas.length === 0) {
    return (
      <div className="rounded-superficie border border-sand bg-papel px-4 py-10 text-center text-sm text-taupe">
        {vacio}
      </div>
    );
  }

  const prox = proximoDesembolso(data);
  const r = resumen(personas);
  const totalProx = totalProximo(personas, data);
  const cuandoProx = prox?.fiable ? `acumulado · ${fechaCorta(prox.fecha).replace(/ \d{4}$/, "")}` : undefined;
  const hayProxNegativo = personas.some((p) => (montoProximo(p, data) ?? 0) < 0);
  const sinMontoProx = "Del 16 al 31 de diciembre el próximo pago es del año siguiente y todavía no tiene monto.";

  return (
    <>
      <div className="hidden md:block">
        <Tabla alturaMaxima="70vh" className="[font-variant-numeric:tabular-nums]">
          <TablaEncabezado>
            <Th>Persona</Th>
            <Th>Sede</Th>
            <Th className="text-right">Gratificación</Th>
            <Th className="text-right">CTS</Th>
            <Th className="text-right">Vacaciones</Th>
            <Th className="text-right">Próximo pago</Th>
            <Th className="text-right">Saldo total</Th>
            <Th>Estado</Th>
            <Th>
              <span className="sr-only">Detalle</span>
            </Th>
          </TablaEncabezado>
          <tbody>
            {personas.map((p) => {
              const mp = montoProximo(p, data);
              return (
                <Fila key={p.persona_id} className="cursor-pointer" onClick={(e) => onAbrir(p, e.currentTarget)}>
                  <td className="px-4 py-2 align-top">
                    {/* El botón es la puerta del teclado; el clic en la fila, la del ratón. */}
                    <button
                      type="button"
                      className="text-left font-medium underline-offset-2 hover:underline"
                      onClick={(e) => {
                        e.stopPropagation();
                        onAbrir(p, e.currentTarget);
                      }}
                    >
                      {p.nombre}
                    </button>
                    {/* CAMBIO 0365 — quien hoy tiene tramo pero tuvo un hueco en el año
                        también reservó de menos; sin este texto no se ve en ningún sitio. */}
                    {!p.sin_salario_vigente && (p.dias_sin_salario ?? 0) > 0 && (
                      <span className="block text-xs text-rojo-profundo">
                        {p.dias_sin_salario} {p.dias_sin_salario === 1 ? "día" : "días"} sin salario cargado
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-2 align-top">{p.sede}</td>
                  <td className="px-4 py-2 text-right align-top">
                    <Monto n={gratiConBonificacion(p)} sub={p.be_total ? `incl. 9 % ${formatSoles(p.be_total)}` : undefined} />
                  </td>
                  <td className="px-4 py-2 text-right align-top">
                    <Monto n={p.cts_total} />
                  </td>
                  <td className="px-4 py-2 text-right align-top">
                    <Monto n={p.vac} sub={`${p.vac_dias.toFixed(1)} días`} />
                  </td>
                  <td className="px-4 py-2 text-right align-top">
                    {mp === null ? (
                      <span className="text-taupe" title={prox ? sinMontoProx : undefined}>—</span>
                    ) : (
                      <Monto n={mp} sub={cuandoProx} />
                    )}
                  </td>
                  <td className="bg-sand/30 px-4 py-2 text-right align-top font-semibold">
                    {formatSoles(p.gran_total)}
                  </td>
                  <td className="px-4 py-2 align-top">
                    <Estados persona={p} data={data} />
                  </td>
                  <td className="px-3 py-2 text-right align-top text-taupe" aria-hidden>
                    ›
                  </td>
                </Fila>
              );
            })}
          </tbody>
          <tfoot>
            <tr className="border-t border-taupe/40 bg-sand/50 font-medium">
              <td className="px-4 py-2" colSpan={2}>
                Total · {personas.length} {personas.length === 1 ? "persona" : "personas"}
              </td>
              <td className="px-4 py-2 text-right">{formatSoles(r.gratificacion)}</td>
              <td className="px-4 py-2 text-right">{formatSoles(r.cts)}</td>
              <td className="px-4 py-2 text-right">{formatSoles(r.vacaciones)}</td>
              <td className="px-4 py-2 text-right">
                {totalProx === null ? "—" : formatSoles(totalProx)}
                {hayProxNegativo && (
                  <span className="block text-xs font-normal text-taupe">sin descontar pagos de más</span>
                )}
              </td>
              <td className="px-4 py-2 text-right font-semibold">{formatSoles(r.total)}</td>
              <td className="px-4 py-2" colSpan={2} />
            </tr>
          </tfoot>
        </Tabla>
      </div>

      {/* En el teléfono la matriz no se comprime: una tarjeta por persona. */}
      <ul className="grid gap-3 md:hidden [font-variant-numeric:tabular-nums]">
        {personas.map((p) => {
          const mp = montoProximo(p, data);
          return (
            <li key={p.persona_id}>
              <button
                type="button"
                onClick={(e) => onAbrir(p, e.currentTarget)}
                className="grid w-full gap-2 rounded-superficie border border-sand bg-papel p-4 text-left"
              >
                <span className="flex items-baseline justify-between gap-3">
                  <span className="font-medium">
                    {p.nombre} <span className="text-xs font-normal text-taupe">{p.sede}</span>
                  </span>
                  <span className="font-semibold">{formatSoles(p.gran_total)}</span>
                </span>
                <Estados persona={p} data={data} />
                <span className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
                  <Dato etiqueta="Gratificación" valor={formatSoles(gratiConBonificacion(p))} />
                  <Dato etiqueta="CTS" valor={formatSoles(p.cts_total)} />
                  <Dato etiqueta="Vacaciones" valor={formatSoles(p.vac)} />
                  <Dato
                    etiqueta="Próximo pago"
                    valor={mp === null || !prox ? "—" : `${formatSoles(mp)} · ${fechaCorta(prox.fecha).replace(/ \d{4}$/, "")}`}
                  />
                </span>
              </button>
            </li>
          );
        })}
      </ul>
    </>
  );
}

function Dato({ etiqueta, valor }: { etiqueta: string; valor: string }) {
  return (
    <span className="min-w-0">
      <span className="block text-xs text-taupe">{etiqueta}</span>
      <span className={valor.startsWith("-") ? "text-pizarra" : undefined}>{valor}</span>
    </span>
  );
}

// Las practicantes siguen a la vista (lo pidió la 0428), pero fuera de la tabla
// de reservas: su «nada que reservar» es para siempre, no «aún no», y dentro
// de la tabla ese cero volvía a parecerse al de quien entró esta semana.
// Decidido con Felipe el 2026-09-15 (sección plegada, no fila con «No aplica»).
export function Practicantes({ personas, onAbrir }: { personas: ProvPersona[]; onAbrir: AbrirPersona }) {
  if (personas.length === 0) return null;
  return (
    <details className="mt-4 overflow-hidden rounded-superficie border border-sand bg-papel">
      <summary className="cursor-pointer px-4 py-3 text-sm font-medium">
        Practicantes · no generan gratificación, CTS ni vacaciones ({personas.length})
      </summary>
      <ul className="divide-y divide-sand border-t border-sand">
        {personas.map((p) => (
          <li key={p.persona_id}>
            <button
              type="button"
              onClick={(e) => onAbrir(p, e.currentTarget)}
              className="grid w-full grid-cols-[minmax(0,1fr)_auto] gap-x-4 px-4 py-2 text-left text-sm transition-colors hover:bg-crema/60 sm:grid-cols-[minmax(0,1fr)_4rem_9rem]"
            >
              <span className="font-medium">{p.nombre}</span>
              <span className="text-taupe">{p.sede}</span>
              <span className="hidden text-taupe sm:block">desde {fechaCorta(p.fecha_ingreso)}</span>
            </button>
          </li>
        ))}
      </ul>
      <p className="border-t border-sand px-4 py-2 text-xs text-taupe">
        Modalidad formativa (Ley 28518): la ley no les da estos tres beneficios. No es que falte cargar algo.
      </p>
    </details>
  );
}
