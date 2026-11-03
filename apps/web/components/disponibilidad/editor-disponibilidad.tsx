"use client";

import { useMemo, useState } from "react";
import { Ban, Check, CircleAlert, Clock, Copy, Plus, X, type LucideIcon } from "lucide-react";
import { hoyLima } from "@cayla-dynamic/shared";
import { Boton } from "@/components/ui/boton";
import { Campo } from "@/components/ui/campo";
import { AreaTexto } from "@/components/ui/area-texto";
import { Filtro } from "@/components/ui/filtro";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { Rotulo } from "@/components/ui/rotulo";
import { sumarDias } from "@/lib/mi-semana";
import {
  ATAJOS, MOTIVOS, NOMBRE_DIA, ORDEN_DIAS, aBloques, aplicarAtajo, copiarDia, avisoDeHoras, horasDisponibles, opcionesHora,
  resumenEnPalabras, semanaVacia, validar,
  type Bloque, type EstadoBloque, type Excepcion, type ModoDia, type Motivo, type SemanaTipo, type Ventana,
} from "@/lib/disponibilidad";

/**
 * El formulario de disponibilidad: lo usa la colaboradora en «Lo mío · Mi
 * disponibilidad» y DO en /admin/disponibilidad cuando la registra por ella.
 * Las reglas viven en lib/disponibilidad.ts (con sus pruebas); acá solo se
 * dibujan. Lo que valida la pantalla lo vuelve a validar la base (0584).
 *
 * Las fechas no arrancan vacías (CLAUDE.md, «un campo de fecha cuyo vacío
 * BLOQUEA el envío no puede arrancar en ""»): «Desde» nace en hoy, una fecha
 * puntual nace en mañana y un «hasta» nace tres meses después de «desde».
 */

export interface EnvioDisponibilidad {
  tipo: "total" | "parcial";
  motivo: Motivo | null;
  desde: string;
  hasta: string | null;
  bloques: Bloque[];
  nota: string | null;
}

type Hasta = "sin_fin" | "fin_ciclo" | "fecha";

// Un día se marca con UN toque, sin desplegables encadenados: el color nunca va
// solo, cada opción lleva su ícono y su palabra. «Por horas» abre sus tramos, y
// cada tramo dice su propio estado (antes era un desplegable «Solo algunas
// horas» y, adentro, otro «No puedo»: se leía como una doble negación).
const MODOS: { valor: ModoDia; label: string; icono: LucideIcon }[] = [
  { valor: "puede", label: "Puedo", icono: Check },
  { valor: "prefiere_no", label: "Prefiero no", icono: CircleAlert },
  { valor: "no_puede", label: "No puedo", icono: Ban },
  { valor: "horas", label: "Por horas", icono: Clock },
];

const ESTADOS: { valor: EstadoBloque; label: string }[] = [
  { valor: "no_puede", label: "No puedo" },
  { valor: "prefiere_no", label: "Prefiero no" },
];

const selectClase = "rounded-control border border-borde-control bg-hueso px-2 py-1.5 text-sm text-tinta";

export function EditorDisponibilidad({
  inicial, ventana, jornada, quien = "tu", textoBoton, enviando, onEnviar,
}: {
  inicial?: { tipo: "total" | "parcial"; semana: SemanaTipo; excepciones: Excepcion[]; motivo: Motivo | null };
  ventana: Ventana[];
  jornada: number | null;
  quien?: "tu" | "ella";
  textoBoton: string;
  enviando: boolean;
  onEnviar: (e: EnvioDisponibilidad) => void;
}) {
  const hoy = hoyLima();
  const opciones = useMemo(() => opcionesHora(), []);
  const [tipo, setTipo] = useState<"total" | "parcial">(inicial?.tipo ?? "parcial");
  const [semana, setSemana] = useState<SemanaTipo>(inicial?.semana ?? semanaVacia());
  const [excepciones, setExcepciones] = useState<Excepcion[]>(inicial?.excepciones ?? []);
  const [motivo, setMotivo] = useState<Motivo | null>(inicial?.motivo ?? null);
  const [desde, setDesde] = useState(hoy);
  const [hastaModo, setHastaModo] = useState<Hasta>("sin_fin");
  const [hastaFecha, setHastaFecha] = useState(sumarDias(hoy, 90));
  const [nota, setNota] = useState("");

  const parcial = tipo === "parcial";
  const error = parcial ? validar(semana, excepciones) : null;
  const resumen = parcial ? resumenEnPalabras(semana, excepciones, quien) : [quien === "tu" ? "Puedes cualquier día y hora." : "Puede cualquier día y hora."];
  const libres = parcial ? horasDisponibles(semana, ventana) : null;
  const aviso = avisoDeHoras(libres, jornada, quien);
  const bloques = parcial ? aBloques(semana, excepciones) : [];
  const hasta = hastaModo === "sin_fin" ? null : hastaFecha;
  const faltaMotivo = parcial && !motivo;
  const sinNada = parcial && bloques.length === 0;
  const fechaFuera = excepciones.find((x) => x.fecha < desde || (hasta !== null && x.fecha > hasta));
  const hastaAntes = hasta !== null && hasta < desde;
  const bloqueo = error ?? (sinNada ? "Marca al menos un día u hora, o elige «Cualquier día y hora»." : null)
    ?? (faltaMotivo ? "Elige el motivo." : null)
    ?? (hastaAntes ? "La fecha «hasta» es anterior a «desde»." : null)
    ?? (fechaFuera ? `La fecha puntual del ${fechaFuera.fecha} cae fuera de la vigencia.` : null);

  const cambiarDia = (d: number, modo: ModoDia) =>
    setSemana((s) => ({
      ...s,
      [d]: { modo, tramos: modo === "horas" ? (s[d].tramos.length ? s[d].tramos : [{ desde: "08:30", hasta: "14:00", estado: "no_puede" }]) : [] },
    }));
  const cambiarTramo = (d: number, i: number, campo: "desde" | "hasta" | "estado", valor: string) =>
    setSemana((s) => ({ ...s, [d]: { ...s[d], tramos: s[d].tramos.map((t, j) => (j === i ? { ...t, [campo]: valor } : t)) } }));
  const agregarTramo = (d: number) =>
    setSemana((s) => ({ ...s, [d]: { ...s[d], tramos: [...s[d].tramos, { desde: "16:00", hasta: "20:00", estado: "no_puede" }] } }));
  const quitarTramo = (d: number, i: number) =>
    setSemana((s) => {
      const tramos = s[d].tramos.filter((_, j) => j !== i);
      return { ...s, [d]: { modo: tramos.length ? "horas" : "puede", tramos } };
    });

  const enviar = () => {
    if (bloqueo) return;
    onEnviar({ tipo, motivo: parcial ? motivo : null, desde, hasta, bloques, nota: nota.trim() || null });
  };

  return (
    <div className="flex flex-col gap-4">
      <div role="radiogroup" aria-label="Disponibilidad" className="grid gap-2 sm:grid-cols-2">
        {([
          ["total", "Cualquier día y hora", quien === "tu" ? "Tu líder de equipo te puede poner en cualquier turno." : "Se le puede poner en cualquier turno."],
          ["parcial", "Hay días u horas que no puedo", "Marca cada día como lo necesites. Lo que no toques queda como «Puedo»."],
        ] as const).map(([v, titulo, texto]) => (
          <label key={v}
            className={`flex cursor-pointer gap-3 rounded-control border p-3 ${tipo === v ? "border-tinta bg-papel" : "border-sand bg-hueso"}`}>
            <input type="radio" name="tipo-disponibilidad" checked={tipo === v} onChange={() => setTipo(v)} className="mt-1 accent-tinta" />
            <span>
              <span className="block font-medium">{titulo}</span>
              <span className="text-sm text-taupe">{texto}</span>
            </span>
          </label>
        ))}
      </div>

      {parcial && (
        <>
          <dl className="grid gap-1 rounded-control bg-hueso p-3 text-sm sm:grid-cols-3">
            <div>
              <dt className="font-medium">Puedo</dt>
              <dd className="text-taupe">{quien === "tu" ? "Tu líder de equipo te puede poner." : "Se la puede poner."}</dd>
            </div>
            <div>
              <dt className="font-medium">Prefiero no</dt>
              <dd className="text-taupe">Se intenta evitar, pero si falta gente {quien === "tu" ? "te puede tocar" : "le puede tocar"}.</dd>
            </div>
            <div>
              <dt className="font-medium">No puedo</dt>
              <dd className="text-taupe">{quien === "tu" ? "No te ponen" : "No se la pone"} en ese día u hora.</dd>
            </div>
          </dl>

          <div className="flex flex-wrap gap-2" aria-label="Atajos">
            {ATAJOS.map((a) => (
              <Boton key={a.valor} tamano="sm" onClick={() => setSemana((s) => aplicarAtajo(s, a.valor, ventana))}>{a.label}</Boton>
            ))}
          </div>

          <ul className="flex flex-col gap-2">
            {ORDEN_DIAS.map((d) => {
              const dia = semana[d];
              return (
                <li key={d} className="flex flex-col gap-2 rounded-control bg-hueso px-3 py-2.5">
                  <span className="font-medium capitalize">{NOMBRE_DIA[d]}</span>
                  <div role="group" aria-label={`Qué pasa el ${NOMBRE_DIA[d]}`} className="flex flex-wrap gap-2">
                    {MODOS.map((m) => {
                      const Icono = m.icono;
                      return (
                        <Filtro key={m.valor} activo={dia.modo === m.valor} className="inline-flex min-h-10 items-center gap-1.5"
                          onClick={() => cambiarDia(d, m.valor)}>
                          <Icono className="h-3.5 w-3.5" aria-hidden="true" />{m.label}
                        </Filtro>
                      );
                    })}
                  </div>
                  {dia.modo === "horas" && (
                    <div className="flex flex-col gap-3 border-l-2 border-sand pl-3">
                      {dia.tramos.map((t, i) => (
                        <div key={i} className="flex flex-wrap items-center gap-2 text-sm">
                          <div role="group" aria-label="Estado del tramo" className="flex gap-1.5">
                            {ESTADOS.map((x) => (
                              <Filtro key={x.valor} tamano="sm" activo={t.estado === x.valor} className="min-h-9"
                                onClick={() => cambiarTramo(d, i, "estado", x.valor)}>{x.label}</Filtro>
                            ))}
                          </div>
                          <span>de</span>
                          <select aria-label="Desde" className={selectClase} value={t.desde} onChange={(e) => cambiarTramo(d, i, "desde", e.target.value)}>
                            {opciones.slice(0, -1).map((h) => <option key={h} value={h}>{h}</option>)}
                          </select>
                          <span>a</span>
                          <select aria-label="Hasta" className={selectClase} value={t.hasta} onChange={(e) => cambiarTramo(d, i, "hasta", e.target.value)}>
                            {opciones.slice(1).map((h) => <option key={h} value={h}>{h}</option>)}
                          </select>
                          <button type="button" aria-label="Quitar este tramo" onClick={() => quitarTramo(d, i)}
                            className="rounded-control p-1 text-taupe hover:text-tinta"><X className="h-4 w-4" /></button>
                        </div>
                      ))}
                      <div className="flex flex-wrap gap-x-4 gap-y-1">
                        <Boton variante="enlace" className="text-sm" onClick={() => agregarTramo(d)}>
                          <Plus className="mr-1 inline h-3.5 w-3.5" />Otro tramo
                        </Boton>
                        <Boton variante="enlace" className="text-sm" onClick={() => setSemana((s) => copiarDia(s, d))}>
                          <Copy className="mr-1 inline h-3.5 w-3.5" />Copiar a los demás días
                        </Boton>
                      </div>
                    </div>
                  )}
                </li>
              );
            })}
          </ul>

          <div className="flex flex-col gap-2">
            <Rotulo>Un día puntual (un examen, una cita)</Rotulo>
            {excepciones.map((x, i) => (
              <div key={i} className="flex flex-wrap items-end gap-2 text-sm">
                <Campo etiqueta="Fecha" type="date" value={x.fecha} min={desde}
                  onChange={(e) => e.target.value && setExcepciones((xs) => xs.map((y, j) => (j === i ? { ...y, fecha: e.target.value } : y)))} />
                <div role="group" aria-label="Estado" className="flex gap-1.5">
                  {ESTADOS.map((e2) => (
                    <Filtro key={e2.valor} tamano="sm" activo={x.estado === e2.valor} className="min-h-9"
                      onClick={() => setExcepciones((xs) => xs.map((y, j) => (j === i ? { ...y, estado: e2.valor } : y)))}>{e2.label}</Filtro>
                  ))}
                </div>
                <div role="group" aria-label="Todo el día o unas horas" className="flex gap-1.5">
                  <Filtro tamano="sm" activo={!x.desde} className="min-h-9"
                    onClick={() => setExcepciones((xs) => xs.map((y, j) => (j === i ? { ...y, desde: null, hasta: null } : y)))}>Todo el día</Filtro>
                  <Filtro tamano="sm" activo={!!x.desde} className="min-h-9"
                    onClick={() => setExcepciones((xs) => xs.map((y, j) => (j === i && !y.desde ? { ...y, desde: "16:00", hasta: "20:00" } : y)))}>Unas horas</Filtro>
                </div>
                {x.desde && x.hasta && (
                  <>
                    <select aria-label="Desde" className={selectClase} value={x.desde}
                      onChange={(e) => setExcepciones((xs) => xs.map((y, j) => (j === i ? { ...y, desde: e.target.value } : y)))}>
                      {opciones.slice(0, -1).map((h) => <option key={h} value={h}>{h}</option>)}
                    </select>
                    <select aria-label="Hasta" className={selectClase} value={x.hasta}
                      onChange={(e) => setExcepciones((xs) => xs.map((y, j) => (j === i ? { ...y, hasta: e.target.value } : y)))}>
                      {opciones.slice(1).map((h) => <option key={h} value={h}>{h}</option>)}
                    </select>
                  </>
                )}
                <button type="button" aria-label="Quitar esta fecha" onClick={() => setExcepciones((xs) => xs.filter((_, j) => j !== i))}
                  className="rounded-control p-1 text-taupe hover:text-tinta"><X className="h-4 w-4" /></button>
              </div>
            ))}
            <Boton variante="enlace" className="self-start text-sm"
              onClick={() => setExcepciones((xs) => [...xs, { fecha: sumarDias(desde, 1), desde: null, hasta: null, estado: "no_puede" }])}>
              <Plus className="mr-1 inline h-3.5 w-3.5" />Agregar una fecha
            </Boton>
          </div>

          <div className="flex flex-col gap-2">
            <Rotulo>¿Por qué? {quien === "tu" ? "(lo ven solo tu líder de equipo y DO)" : "(lo ven solo su líder de equipo y DO)"}</Rotulo>
            <div className="flex flex-wrap gap-2">
              {MOTIVOS.map((m) => (
                <Filtro key={m.valor} tamano="sm" activo={motivo === m.valor} onClick={() => setMotivo(m.valor)}>{m.label}</Filtro>
              ))}
            </div>
          </div>
        </>
      )}

      <div className="flex flex-wrap items-end gap-3">
        <Campo etiqueta="Desde" type="date" value={desde} min={hoy} onChange={(e) => e.target.value && setDesde(e.target.value)} />
        <label className="flex flex-col gap-1">
          <span className="text-sm text-taupe">Hasta</span>
          <select className={`${selectClase} py-2`} value={hastaModo} onChange={(e) => setHastaModo(e.target.value as Hasta)}>
            <option value="sin_fin">Sin fecha de fin</option>
            <option value="fin_ciclo">Fin del ciclo de estudios</option>
            <option value="fecha">Elegir fecha</option>
          </select>
        </label>
        {hastaModo !== "sin_fin" && (
          <Campo etiqueta={hastaModo === "fin_ciclo" ? "Fin del ciclo" : "Fecha"} type="date" value={hastaFecha} min={desde}
            onChange={(e) => e.target.value && setHastaFecha(e.target.value)} />
        )}
      </div>

      <AreaTexto etiqueta="Algo más que quieras contar (opcional)" value={nota} maxLength={300} rows={2}
        onChange={(e) => setNota(e.target.value)} />

      <div className="rounded-control bg-hueso p-3 text-sm" aria-live="polite">
        {resumen.map((l) => <p key={l}>{l}</p>)}
        {libres !== null && !aviso && (
          <p className="mt-1 text-taupe">
            Quedan {Number.isInteger(libres) ? libres : libres.toFixed(1).replace(".", ",")} h disponibles a la semana
            {jornada !== null ? ` para una jornada de ${jornada} h` : ""}.
          </p>
        )}
      </div>

      {aviso && <BannerAviso variante="advertencia" role="status">{aviso}</BannerAviso>}
      {bloqueo && <p className="text-sm text-rojo-profundo" role="alert">{bloqueo}</p>}

      <Boton variante="primario" className="self-start" cargando={enviando} disabled={!!bloqueo} onClick={enviar}>
        {textoBoton}
      </Boton>
    </div>
  );
}
