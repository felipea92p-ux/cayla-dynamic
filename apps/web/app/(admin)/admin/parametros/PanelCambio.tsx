"use client";

// El panel lateral con el que se cambia UN parámetro, en dos pasos:
//
//   1 · el valor nuevo y el motivo;
//   2 · «a quién afecta» y, recién ahí, confirmar.
//
// Los dos pasos son a propósito. Lo que Felipe pidió es que antes de guardar el
// sistema diga a quién le cambia algo; un solo paso con un botón «Guardar» deja
// esa lectura para después de hecho. Para los parámetros que tienen personas
// detrás (días de prueba, aviso de descanso médico) el paso 2 las lista con su
// antes y su después; para los demás dice en palabras qué cambia y qué no.
//
// Nada de lo que se valida acá es la última palabra: la que manda es
// `fn_parametro_cambiar` (mínimo, máximo, entero, motivo, quién puede), y su
// mensaje se muestra tal cual si la base rechaza algo que esta pantalla dejó pasar.
//
// Un parámetro que rige POR FECHAS (clase plata, 0574) pide además «Rige desde»,
// y su paso 2 lo da `fn_parametro_vista_previa`, que también se niega si la fecha
// cae en un periodo ya pagado: el aviso llega antes de confirmar, no después.
// Se guarda con `fn_parametro_cambiar_vigencia`.

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import {
  describirCambioDeParametro,
  hoyLima,
  validarValorParametro,
  valorConUnidad,
} from "@cayla-dynamic/shared";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Rotulo } from "@/components/ui/rotulo";
import { Fila, Tabla, TablaEncabezado, Th } from "@/components/ui/tabla";
import { useToast } from "@/components/toast";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import type { FilaPrueba } from "@/lib/admin/pruebas";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";
import { avisoDeCambioDePlata, opcionesDeVigencia, type PeriodoCiclo } from "@/lib/admin/cambio-de-plata";
import {
  fechaInicialDeVigencia,
  fechaMinimaDeVigencia,
  fuenteDeImpacto,
  impactoDeVistaPrevia,
  valorAntesDelCambio,
  impactoAvisoDescansoMedico,
  impactoDiasDePrueba,
  notaDeEfecto,
  type FilaSubsidio,
  type FilaVistaPrevia,
  type Impacto,
  type ParametroFila,
} from "@/lib/admin/parametros";

type Paso = "formulario" | "confirmar" | "hecho";

export function PanelCambio({
  fila,
  valorInicial,
  motivoInicial,
  onCerrar,
  onGuardado,
}: {
  fila: ParametroFila;
  /** Para «volver a este valor»: arranca con el valor del historial, no con el de hoy. */
  valorInicial?: string;
  motivoInicial?: string;
  onCerrar: () => void;
  onGuardado: () => void;
}) {
  const { avisar } = useToast();
  const [texto, setTexto] = useState(valorInicial ?? String(fila.valor_actual));
  const [motivo, setMotivo] = useState(motivoInicial ?? "");
  const [paso, setPaso] = useState<Paso>("formulario");
  const [errorValor, setErrorValor] = useState<string | undefined>();
  const [errorMotivo, setErrorMotivo] = useState<string | undefined>();
  const [calculando, setCalculando] = useState(false);
  const [guardando, setGuardando] = useState(false);
  const [impacto, setImpacto] = useState<Impacto | null>(null);
  const [errorImpacto, setErrorImpacto] = useState<string | null>(null);
  const [valorNuevo, setValorNuevo] = useState<number | null>(null);

  // Solo para los que rigen por fechas. La fecha NACE con un valor (CLAUDE.md:
  // un campo de fecha que bloquea el envío no arranca vacío) y lo que se ve es
  // exactamente lo que se manda.
  const conFechas = fila.rige_por_fechas;
  const ultimaVersion = fila.proximo_desde ?? fila.vigente_desde;
  const minimo = fechaMinimaDeVigencia(ultimaVersion);
  const [desde, setDesde] = useState(() => fechaInicialDeVigencia(hoyLima(), ultimaVersion));
  const [errorDesde, setErrorDesde] = useState<string | undefined>();
  // 0578 · los cambios de plata: atajos de fecha por ciclo, doble confirmación y comunicado en borrador.
  const [periodos, setPeriodos] = useState<PeriodoCiclo[]>([]);
  const [seguro, setSeguro] = useState(false);
  const [comunicado, setComunicado] = useState<string | null>(null);
  useEffect(() => {
    if (!conFechas) return;
    void createAdminSupabaseClient()
      .from("periodos_planilla")
      .select("fecha_ini, fecha_fin")
      .order("fecha_ini", { ascending: false })
      .limit(6)
      .then(({ data }) => setPeriodos((data ?? []) as PeriodoCiclo[]));
  }, [conFechas]);
  const opciones = useMemo(() => opcionesDeVigencia(hoyLima(), periodos), [periodos]);
  const opcionElegida = opciones.find((o) => o.fecha === desde) ?? null;
  // Contra qué se compara: el valor que regiría ese día sin el cambio.
  const base = conFechas ? valorAntesDelCambio(fila) : fila.valor_actual;

  const rango =
    fila.valor_min !== null && fila.valor_max !== null
      ? `De ${fila.valor_min} a ${fila.valor_max} ${fila.unidad}.`
      : null;

  async function verAQuienAfecta() {
    const v = validarValorParametro(fila, texto);
    setErrorValor(v.ok ? undefined : v.mensaje);
    const motivoLimpio = motivo.trim();
    setErrorMotivo(motivoLimpio.length >= 3 ? undefined : "Escribe el motivo: es lo que explica el número dentro de un año.");
    let fechaOk = true;
    if (conFechas) {
      if (!desde) {
        setErrorDesde("Elige desde qué fecha rige el valor nuevo.");
        fechaOk = false;
      } else if (minimo && desde < minimo) {
        setErrorDesde(`Ya hay un cambio que rige desde el ${isoADiaMesAnio(ultimaVersion ?? minimo)}: la fecha tiene que ser desde el ${isoADiaMesAnio(minimo)}.`);
        fechaOk = false;
      } else {
        setErrorDesde(undefined);
      }
    }
    if (!v.ok || motivoLimpio.length < 3 || !fechaOk) return;
    if (v.valor === base) {
      setErrorValor(
        conFechas && fila.proximo_valor !== null
          ? `Ese ya es el valor programado (${valorConUnidad(base, fila.unidad)}).`
          : `Ese ya es el valor de hoy (${valorConUnidad(base, fila.unidad)}).`,
      );
      return;
    }

    setCalculando(true);
    setErrorImpacto(null);
    setImpacto(null);
    const supabase = createAdminSupabaseClient();
    if (conFechas) {
      const { data, error } = await supabase.rpc("fn_parametro_vista_previa", {
        p_parametro: fila.parametro,
        p_valor: v.valor,
        p_desde: desde,
      });
      if (error) {
        // Casi siempre es la fecha (un periodo ya pagado): se queda en el formulario.
        setErrorDesde(mensajeDeError(error, "ver a quién le toca"));
        setCalculando(false);
        return;
      }
      setImpacto(
        impactoDeVistaPrevia(
          (data ?? []) as FilaVistaPrevia[],
          valorConUnidad(base, fila.unidad),
          `${valorConUnidad(v.valor, fila.unidad)} desde el ${isoADiaMesAnio(desde)}`,
        ),
      );
      setValorNuevo(v.valor);
      setCalculando(false);
      setPaso("confirmar");
      return;
    }
    const fuente = fuenteDeImpacto(fila.parametro);
    if (fuente === "pruebas") {
      const { data, error } = await supabase.rpc("fn_pruebas_abiertas");
      if (error) setErrorImpacto(mensajeDeError(error, "ver quién está en preselección"));
      else setImpacto(impactoDiasDePrueba((data ?? []) as unknown as FilaPrueba[], v.valor));
    } else if (fuente === "descanso_medico") {
      const { data, error } = await supabase.rpc("fn_ausencias_subsidio");
      if (error) setErrorImpacto(mensajeDeError(error, "ver los días de descanso médico"));
      else {
        const filas: FilaSubsidio[] = (data ?? []).map((r) => ({
          persona_id: r.persona_id,
          nombre: r.nombre,
          dias_calendario: r.dias_calendario,
        }));
        setImpacto(impactoAvisoDescansoMedico(filas, fila.valor_actual, v.valor));
      }
    }
    setValorNuevo(v.valor);
    setCalculando(false);
    setPaso("confirmar");
  }

  async function confirmar() {
    if (valorNuevo === null) return;
    setGuardando(true);
    const supabase = createAdminSupabaseClient();
    const { error } = conFechas
      ? await supabase.rpc("fn_parametro_cambiar_vigencia", {
          p_parametro: fila.parametro,
          p_valor: valorNuevo,
          p_desde: desde,
          p_motivo: motivo.trim(),
        })
      : await supabase.rpc("fn_parametro_cambiar", {
          p_parametro: fila.parametro,
          p_valor: valorNuevo,
          p_motivo: motivo.trim(),
        });
    setGuardando(false);
    if (error) {
      avisar("error", mensajeDeError(error, "cambiar el parámetro"));
      return;
    }
    const cuando = conFechas ? ` desde el ${isoADiaMesAnio(desde)}` : "";
    avisar("ok", `${fila.nombre}: ${describirCambioDeParametro(base, valorNuevo, fila.unidad)}${cuando}. Quedó escrito en el historial.`);
    onGuardado();
    if (conFechas) {
      // El comunicado en borrador para el grupo afectado; si falla, el cambio ya está hecho.
      const r = await supabase.rpc("fn_parametro_comunicado", {
        p_parametro: fila.parametro,
        p_antes: base,
        p_nuevo: valorNuevo,
        p_desde: desde,
      });
      setComunicado(r.error ? null : (r.data as string | null));
      setPaso("hecho");
      return;
    }
    onCerrar();
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <Rotulo>{fila.nombre}</Rotulo>
        <p className="mt-1 text-sm text-taupe">{fila.descripcion}</p>
      </div>

      {paso === "formulario" ? (
        <>
          <Campo
            etiqueta={`Valor nuevo (${fila.unidad})`}
            inputMode={fila.tipo_valor === "entero" ? "numeric" : "decimal"}
            value={texto}
            onChange={(e) => {
              setTexto(e.target.value);
              setErrorValor(undefined);
            }}
            error={errorValor}
          />
          <p className="-mt-2 text-xs text-taupe">
            Hoy vale {valorConUnidad(fila.valor_actual, fila.unidad)}
            {conFechas && fila.vigente_desde ? ` (desde el ${isoADiaMesAnio(fila.vigente_desde)})` : ""}.{" "}
            {conFechas && fila.proximo_desde && fila.proximo_valor !== null
              ? `Ya hay un cambio programado: ${valorConUnidad(fila.proximo_valor, fila.unidad)} desde el ${isoADiaMesAnio(fila.proximo_desde)}. `
              : ""}
            {rango}
          </p>
          {conFechas && (
            <>
              <Campo
                etiqueta="Rige desde"
                type="date"
                value={desde}
                min={minimo ?? undefined}
                onChange={(e) => {
                  setDesde(e.target.value);
                  setErrorDesde(undefined);
                }}
                error={errorDesde}
              />
              <div className="-mt-2 flex flex-wrap gap-2">
                {opciones.map((o) => (
                  <Boton
                    key={o.clave}
                    tamano="sm"
                    variante={o.fecha === desde ? "primario" : "secundario"}
                    onClick={() => {
                      setDesde(o.fecha);
                      setErrorDesde(undefined);
                    }}
                  >
                    {o.etiqueta}
                  </Boton>
                ))}
              </div>
              <p className="text-xs text-taupe">
                Lo ya pagado no se toca: la fecha tiene que caer en un periodo sin pagar
                {minimo ? ` y ser desde el ${isoADiaMesAnio(minimo)}` : ""}. Antes de esa fecha sigue rigiendo el valor de hoy.
              </p>
            </>
          )}
          <AreaTexto
            etiqueta="Motivo del cambio"
            rows={3}
            value={motivo}
            onChange={(e) => {
              setMotivo(e.target.value);
              setErrorMotivo(undefined);
            }}
            error={errorMotivo}
            placeholder="Por qué se cambia. Se guarda con tu nombre y la hora."
          />
          <div className="flex justify-end gap-2">
            <Boton onClick={onCerrar}>Cancelar</Boton>
            <Boton variante="primario" cargando={calculando} onClick={verAQuienAfecta}>
              Ver a quién afecta
            </Boton>
          </div>
        </>
      ) : paso === "confirmar" ? (
        <>
          <BannerAviso
            variante="informativo"
            titulo={`${describirCambioDeParametro(base, valorNuevo ?? 0, fila.unidad)}${conFechas ? ` desde el ${isoADiaMesAnio(desde)}` : ""}`}
          >
            «{motivo.trim()}»
          </BannerAviso>

          {errorImpacto && (
            <BannerAviso variante="advertencia" titulo="No pude calcular a quién afecta">
              {errorImpacto} Puedes confirmar igual: el cambio es reversible y queda en el historial.
            </BannerAviso>
          )}

          {impacto && <ListaDeImpacto impacto={impacto} />}

          {!impacto && !errorImpacto && notaDeEfecto(fila.parametro) && (
            <p className="text-sm text-taupe">{notaDeEfecto(fila.parametro)}</p>
          )}

          {conFechas && (
            <BannerAviso variante="advertencia" titulo="Antes de confirmar">
              <ul className="list-disc pl-5">
                {avisoDeCambioDePlata(
                  opcionElegida ?? { clave: "hoy", fecha: desde, etiqueta: `Desde el ${isoADiaMesAnio(desde)}`, detalle: "" },
                ).map((r) => (
                  <li key={r}>{r}</li>
                ))}
              </ul>
            </BannerAviso>
          )}

          {conFechas && seguro && (
            <BannerAviso variante="alerta" titulo="Segunda confirmación">
              ¿Seguro? Este valor cambia el pago desde el {isoADiaMesAnio(desde)}.
            </BannerAviso>
          )}

          <div className="flex justify-end gap-2">
            <Boton onClick={() => { setSeguro(false); setPaso("formulario"); }} disabled={guardando}>Volver</Boton>
            {conFechas && !seguro ? (
              <Boton variante="primario" onClick={() => setSeguro(true)}>Estoy de acuerdo con el cambio</Boton>
            ) : (
              <Boton variante={conFechas ? "peligro" : "primario"} cargando={guardando} onClick={confirmar}>
                {conFechas ? "Sí, aplicar el cambio" : "Confirmar el cambio"}
              </Boton>
            )}
          </div>
        </>
      ) : null}
      {paso === "hecho" && (
        <>
          <BannerAviso variante="informativo" titulo="Listo: el cambio quedó en el historial">
            Los módulos pueden tardar un momento en mostrar el valor nuevo.
          </BannerAviso>
          {comunicado ? (
            <BannerAviso variante="advertencia" titulo="Falta publicar el comunicado">
              Quedó un comunicado en BORRADOR solo para las personas afectadas. Revísalo y publícalo desde Anuncios.
            </BannerAviso>
          ) : (
            <p className="text-sm text-taupe">Nadie está hoy en el grupo de este parámetro: no hizo falta comunicado.</p>
          )}
          <div className="flex justify-end gap-2">
            <Boton onClick={onCerrar}>Cerrar</Boton>
            {comunicado && (
              <Link href="/admin/anuncios">
                <Boton variante="primario">Ir a Anuncios a publicarlo</Boton>
              </Link>
            )}
          </div>
        </>
      )}
    </div>
  );
}

function ListaDeImpacto({ impacto }: { impacto: Impacto }) {
  return (
    <div className="flex flex-col gap-2">
      <Rotulo como="h3">
        {impacto.filas.length === 0
          ? "A nadie le cambia nada hoy"
          : `Le cambia a ${impacto.filas.length} ${impacto.filas.length === 1 ? "persona" : "personas"}`}
      </Rotulo>
      {impacto.filas.length > 0 && (
        <Tabla>
          <TablaEncabezado>
            <Th>Persona</Th>
            <Th>Hoy</Th>
            <Th>Con el valor nuevo</Th>
          </TablaEncabezado>
          <tbody>
            {impacto.filas.map((f) => (
              <Fila key={f.persona}>
                <td className="px-4 py-2">{f.persona}</td>
                <td className="px-4 py-2 text-taupe">{f.antes}</td>
                <td className="px-4 py-2">{f.despues}</td>
              </Fila>
            ))}
          </tbody>
        </Tabla>
      )}
      {impacto.sinCambio > 0 && (
        <p className="text-xs text-taupe">
          {impacto.sinCambio} {impacto.sinCambio === 1 ? "persona más no cambia" : "personas más no cambian"} de situación.
        </p>
      )}
      {impacto.nota && <p className="text-sm text-taupe">{impacto.nota}</p>}
    </div>
  );
}
