import type { ReactNode } from "react";
import { formatSoles } from "@/lib/rangos";
import { cx } from "@/components/ui/cx";
import {
  calendario,
  fechaCorta,
  proximoDesembolso,
  resumen,
  totalAtrasadoDelProximo,
  totalConAtrasado,
  totalProximo,
  type ProvData,
  type ProvPersona,
} from "@/lib/admin/provisiones";

// Lo primero que se ve al entrar: cuánto hay por beneficio y qué sale del banco
// y cuándo.
//
// CADA TARJETA DICE QUÉ ES SU NÚMERO —«saldo no pagado al corte»— y ninguna se
// llama «total provisionado». Ese nombre se leería como lo que hay que tener en
// el banco, y no lo es: no incluye ventanas de años anteriores que quedaron sin
// registrar ni la CTS de noviembre–diciembre (defectos C1 y C2 de la auditoría
// del 2026-09-15, cada uno con su migración aparte). Decidido con Felipe ese día.

export function ResumenProvisiones({
  data,
  personas,
  filtrado,
  onVerCalendario,
}: {
  data: ProvData;
  personas: ProvPersona[];
  filtrado: boolean;
  onVerCalendario: () => void;
}) {
  const r = resumen(personas);
  const prox = proximoDesembolso(data);
  const montoProx = totalProximo(personas, data);
  const atrasado = totalAtrasadoDelProximo(personas, data);
  const todoJunto = totalConAtrasado(personas, data);
  const vencidos = calendario(data, personas).vencidos.reduce((a, v) => a + v.personas.length, 0);

  return (
    <section aria-label="Resumen" className="mb-6 grid gap-3 [font-variant-numeric:tabular-nums]">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-[repeat(3,minmax(0,1fr))_minmax(0,1.35fr)]">
        <Tarjeta etiqueta="Gratificación + 9 %" valor={r.gratificacion} detalle="Saldo no pagado al corte" />
        <Tarjeta etiqueta="CTS" valor={r.cts} detalle="Saldo no depositado al corte" />
        <Tarjeta etiqueta="Vacaciones" valor={r.vacaciones} detalle="Acumulado desde cada aniversario" />
        {/* bg-tinta con text-crema, nunca text-white: en oscuro los dos tokens
            se invierten juntos y la tarjeta sigue legible (ver CLAUDE.md). */}
        <div className="flex flex-col gap-1 rounded-superficie border border-tinta bg-tinta p-4 text-crema">
          <span className="text-xs tracking-wide text-crema/70 uppercase">Próximo desembolso</span>
          {prox ? (
            <>
              <span className="text-xl font-medium">
                {prox.beneficio} · {fechaCorta(prox.fecha)}
              </span>
              <span className="text-sm text-crema/80">
                {montoProx !== null ? (
                  <>
                    {formatSoles(montoProx)} acumulado a hoy
                    {prox.cierre && ` · sigue sumando hasta el ${fechaCorta(prox.cierre)}`}
                  </>
                ) : (
                  "El monto aparece el 1 de enero, cuando empieza el periodo que lo calcula."
                )}
              </span>
              {/* Si lo atrasado de una fecha ya pasada se paga con este depósito,
                  esto es lo que sale del banco ese día. Es el número para decidir
                  entre pagar ya o juntarlo con el próximo. */}
              {atrasado !== null && atrasado > 0 && todoJunto !== null && (
                <span className="text-sm text-crema/80">
                  Más {formatSoles(atrasado)} de {prox.beneficio === "CTS" ? "CTS" : "gratificación"} atrasada ·
                  todo junto, a hoy: <strong className="font-medium text-crema">{formatSoles(todoJunto)}</strong>
                </span>
              )}
            </>
          ) : (
            <span className="text-sm text-crema/80">No quedan desembolsos programados.</span>
          )}
          <button
            type="button"
            onClick={onVerCalendario}
            className="mt-1 self-start text-sm font-medium underline underline-offset-2 hover:text-crema/80"
          >
            Ver calendario →
          </button>
        </div>
      </div>

      <p className="flex flex-wrap gap-x-4 gap-y-1 text-sm text-taupe">
        <span>
          Saldo total devengado no pagado{filtrado ? " (con estos filtros)" : ""}:{" "}
          <strong className="font-medium text-tinta">{formatSoles(r.total)}</strong>
        </span>
        {r.ajustes < 0 && <span>incluye {formatSoles(r.ajustes)} de pagos de más</span>}
        {vencidos > 0 && (
          <span className="text-ambar">
            {vencidos} {vencidos === 1 ? "pago por saldar" : "pagos por saldar"} (según lo registrado)
          </span>
        )}
      </p>
    </section>
  );
}

function Tarjeta({ etiqueta, valor, detalle }: { etiqueta: string; valor: number; detalle: string }) {
  return (
    <div className="flex flex-col gap-0.5 rounded-superficie border border-sand bg-papel p-4">
      <span className="text-xs tracking-wide text-taupe uppercase">{etiqueta}</span>
      <span className={cx("text-xl font-medium", valor < 0 && "text-pizarra")}>{formatSoles(valor)}</span>
      <span className="text-xs text-taupe">{detalle}</span>
    </div>
  );
}

// El calendario de pagos. Primero lo VENCIDO —fecha pasada y saldo pendiente—,
// porque es lo único de esta pantalla que puede ser una obligación incumplida
// hoy (la CTS se deposita por ley). Después lo que viene, rotulado como
// acumulado a hoy: el monto sigue creciendo hasta el cierre del periodo.
//
// La proyección al cierre NO está: es un cálculo nuevo con plata y va en su
// propia función SQL, auditada, en una fase posterior (decisión del 2026-09-15).
export function CalendarioPagos({ data, personas }: { data: ProvData; personas: ProvPersona[] }) {
  const cal = calendario(data, personas);
  const anio = Number(data.as_of.slice(0, 4));
  const titulo = (beneficio: string, mes?: string, periodo?: string) =>
    `${beneficio}${beneficio === "Gratificación" ? " + 9 %" : ""}${mes ? ` · ${mes} (${periodo})` : ""}`;

  return (
    <div className="grid gap-4 [font-variant-numeric:tabular-nums]">
      {cal.vencidos.length > 0 && (
        <Grupo
          titulo="Pendiente de pago · la fecha ya pasó"
          nota="Si ya se pagó por fuera de planilla, falta anotarlo en el libro de desembolsos: mientras no esté anotado, sigue figurando aquí."
        >
          {cal.vencidos.map((e) => (
            <FilaCalendario
              key={`v-${e.fecha}-${e.beneficio}`}
              fecha={e.fecha}
              titulo={titulo(e.beneficio, e.ventana?.mes, e.ventana?.periodo)}
              detalle={e.personas.map((p) => p.nombre).join(", ")}
              monto={e.monto}
              advertencia
            />
          ))}
        </Grupo>
      )}

      <Grupo titulo="Próximos desembolsos">
        {cal.proximos.map((e) => (
          <FilaCalendario
            key={`p-${e.fecha}-${e.beneficio}`}
            fecha={e.fecha}
            titulo={titulo(e.beneficio, e.ventana?.mes, e.ventana?.periodo)}
            detalle={
              e.monto === null || !e.ventana
                ? "El monto aparece el 1 de enero, cuando empieza el periodo que lo calcula."
                : `Acumulado a hoy de ${e.personas.length} ${e.personas.length === 1 ? "persona" : "personas"} · sigue sumando hasta el ${fechaCorta(e.ventana.cierre)}`
            }
            monto={e.monto}
          />
        ))}
        {cal.proximos.length === 0 && (
          <p className="px-4 py-3 text-sm text-taupe">No quedan desembolsos programados este año.</p>
        )}
        <FilaCalendario
          fecha={null}
          titulo="Vacaciones"
          detalle="No tienen una fecha común: se pagan cuando cada persona las goza."
          monto={cal.vacaciones}
        />
      </Grupo>

      <p className="max-w-3xl text-xs text-taupe">
        Solo se muestran las ventanas de {anio}: una ventana de {anio - 1} que no quedó registrada como
        pagada ya no aparece aquí. Los montos no descuentan a una persona lo pagado de más a otra.
      </p>
    </div>
  );
}

function Grupo({ titulo, nota, children }: { titulo: string; nota?: string; children: ReactNode }) {
  return (
    <section className="overflow-hidden rounded-superficie border border-sand bg-papel">
      <h2 className="border-b border-sand bg-hueso px-4 py-2 text-xs font-medium tracking-wide text-taupe uppercase">
        {titulo}
      </h2>
      <div className="divide-y divide-sand">{children}</div>
      {nota && <p className="border-t border-sand px-4 py-2 text-xs text-taupe">{nota}</p>}
    </section>
  );
}

function FilaCalendario({
  fecha,
  titulo,
  detalle,
  monto,
  advertencia = false,
}: {
  fecha: string | null;
  titulo: string;
  detalle: string;
  monto: number | null;
  advertencia?: boolean;
}) {
  const [dia, mes, anio] = fecha ? fechaCorta(fecha).split(" ") : [];
  return (
    <div className="grid grid-cols-[4.5rem_minmax(0,1fr)_auto] items-center gap-4 px-4 py-3">
      <div className="font-serif text-lg leading-tight">
        {fecha ? (
          <>
            {dia} {mes}
            <span className="block font-sans text-xs text-taupe">{anio}</span>
          </>
        ) : (
          <span className="text-taupe">—</span>
        )}
      </div>
      <div className="min-w-0">
        <div className="font-medium">{titulo}</div>
        <div className="text-xs text-taupe">{detalle}</div>
      </div>
      <div className={cx("text-right font-medium", advertencia && "text-ambar")}>
        {monto === null ? "—" : formatSoles(monto)}
      </div>
    </div>
  );
}
