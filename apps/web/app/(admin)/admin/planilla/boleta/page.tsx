"use client";

import { Suspense, useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useRolActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { BoletaHoja } from "@/components/boleta-hoja";
import { MESES_LARGO } from "@/lib/admin/planilla/formato";
import type { Fila, Proyeccion, SubvencionPracticante } from "@/lib/admin/planilla/tipos";
import { nombreOficial, puedeVerPlanilla } from "@cayla-dynamic/shared";

// Boleta INTERNA de CAYLA: resumen para que la persona vea cómo se calculó su
// sueldo del mes, e imprimirlo/entregarlo (Ctrl+P → Guardar como PDF). NO es
// la boleta oficial PLAME — ver el texto de valor al pie, decidido con Felipe
// el 2026-07-14 (formato lista, sin montos porque AFP varía por fondo).
//
// DESDE EL 2026-08-08 ESTA PANTALLA IMPRIME DOS DOCUMENTOS DISTINTOS, no uno con
// filas de menos. Quien está en planilla recibe la boleta interna de siempre;
// quien presta servicios por honorarios recibe un «Detalle de servicios
// prestados», con su propio encabezado, su propio cierre y su propio texto legal.
// El interruptor es uno solo —`esLocador`, más abajo— y sale de `en_planilla`,
// que la base ya calcula sola desde `tipo_vinculo`: no hay una segunda lista de
// nombres que mantener.
//
// La razón no es de redacción. Un documento que CAYLA emite todos los meses
// llamando «remuneración» a un honorario, contando los días que «te tocaba
// venir» y mandándote a consultar «con tu líder de equipo» es prueba escrita de
// subordinación, y pesa más en una inspección que el contrato firmado. Lo que se
// arregla acá no es el vocabulario: es lo que el papel declara.
function BoletaContenido() {
  const router = useRouter();
  const params = useSearchParams();
  const rol = useRolActual();
  const puedeVer = puedeVerPlanilla(rol);

  const periodoId = params.get("periodo");
  const personaId = params.get("persona");

  const [proy, setProy] = useState<Proyeccion | null>(null);
  const [baseLegal, setBaseLegal] = useState<number | null>(null);
  const [documento, setDocumento] = useState<string | null>(null);
  const [fechaIngreso, setFechaIngreso] = useState<string | null>(null);
  const [nombreDni, setNombreDni] = useState<string | null>(null);
  const [subvencionPracticante, setSubvencionPracticante] = useState<SubvencionPracticante | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    if (!periodoId || !personaId) return;
    setCargando(true);
    setError(null);
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/admin/login");
      return;
    }
    const { data, error: e } = await supabase.rpc("fn_proyeccion_periodo", { p_periodo_id: periodoId });
    setCargando(false);
    if (e) {
      setError(e.message);
      return;
    }
    const proyeccion = data as unknown as Proyeccion;
    setProy(proyeccion);

    // Los dos beneficios propios de la Ley 28518 (0465/0467) no salen de
    // fn_proyeccion_periodo — viven en su propia función, `fn_subvenciones_
    // practicante` (0467), que ya usa Provisiones. Se pide aparte y solo
    // cuando esta persona es practicante; si falla, la boleta sigue saliendo
    // sin esas dos líneas — no es un requisito para ver el pago.
    const filaPersona = proyeccion.filas.find((x) => x.persona_id === personaId);
    if (filaPersona?.tipo_vinculo === "practicante") {
      // `as never`: la función nace con la 0467/0485 y los tipos generados de
      // Supabase no la conocen hasta que la migración esté pegada y se
      // regeneren — mismo recurso que ya usa provisiones/page.tsx.
      const { data: sub } = await supabase.rpc("fn_subvenciones_practicante" as never);
      const filas = (sub as { personas?: unknown[] } | null)?.personas ?? [];
      const fila0 = (filas as Array<Record<string, unknown>>).find(
        (x) => x.persona_id === personaId,
      );
      setSubvencionPracticante(
        fila0
          ? {
              sinSubvencion: fila0.sin_subvencion as boolean,
              mediaSubSaldo: fila0.media_sub_saldo as number,
              semestreHasta: fila0.semestre_hasta as string,
              descansoSaldo: fila0.descanso_saldo as number,
              descansoGanado: fila0.descanso_ganado as boolean,
              descansoCumple: fila0.descanso_cumple as string,
            }
          : null,
      );
    } else {
      setSubvencionPracticante(null);
    }

    // La base legal contractual (0103) es un atributo de la PERSONA, no un
    // resultado del cálculo, así que se lee de personas y no de
    // fn_proyeccion_periodo — que son 320 líneas muy testeadas y no hacía falta
    // tocar. La política personas_select_admin_lider (0003) ya permite leerla.
    // Si falla, la boleta sigue funcionando sin esa línea: es información
    // añadida, no un requisito para mostrar el pago.
    const { data: persona } = await supabase
      .from("personas")
      .select("sueldo_base_legal, documento, fecha_ingreso")
      .eq("id", personaId)
      .maybeSingle();
    setBaseLegal(persona?.sueldo_base_legal ?? null);
    // CAMBIO del 2026-08-19 · el documento y la fecha de ingreso, por el mismo
    // camino y por el mismo argumento que la base legal: son atributos de la
    // PERSONA y no del cálculo. Si esta lectura falla, la boleta sigue saliendo
    // sin ellos — es identificación añadida, no un requisito para ver el pago.
    setDocumento(persona?.documento ?? null);
    setFechaIngreso(persona?.fecha_ingreso ?? null);
    // El nombre completo del DNI, por el mismo camino y el mismo argumento:
    // `fn_proyeccion_periodo` arma `nombre` como «nombres apellidos» (el corto,
    // el del terminal) y no se reescribe una función de pago por un nombre. Si
    // la lectura falla o la ficha no lo tiene, la boleta cae al corto.
    const { data: ficha } = await supabase
      .from("datos_personales")
      .select("nombre_dni")
      .eq("persona_id", personaId)
      .maybeSingle();
    setNombreDni((ficha?.nombre_dni as string | null | undefined) ?? null);
  }, [periodoId, personaId, router]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  // El nombre con el que se guarda el PDF. Ver use-titulo-documento.ts para el
  // por qué; aquí solo se arma el texto. Acepta null mientras cargan los datos,
  // que es lo que permite llamarlo arriba sin romper el orden de los hooks.
  const filaTitulo = proy?.filas.find((x) => x.persona_id === personaId);
  // El título del PDF va abreviado ("Boleta interna", no "Boleta interna de
  // pago") — por eso es su propia versión corta y no una transformación de
  // `nombreDelDocumentoDePago`. CAMBIO 0322: un practicante suma su propia
  // rama — antes cualquiera con en_planilla=false caía en "Servicios
  // prestados", que es el nombre de un locador (RxH), no el suyo.
  const tituloDocumento =
    filaTitulo?.tipo_vinculo === "practicante"
      ? "Constancia de subvención"
      : filaTitulo?.en_planilla === false
        ? "Servicios prestados"
        : "Boleta interna";
  useTituloDocumento(
    proy && filaTitulo
      ? `${nombreOficial(nombreDni, filaTitulo.nombre)} — ${tituloDocumento} ${MESES_LARGO[proy.mes_etiqueta - 1]} ${proy.anio_etiqueta}`
      : null,
  );

  if (!periodoId || !personaId) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          Falta el periodo o la persona. Abre la boleta desde el botón{" "}
          <Link href="/admin/planilla" className="underline">
            🧾 Ver boleta
          </Link>{" "}
          de la tabla de Planilla.
        </p>
      </main>
    );
  }

  if (rol === null || cargando) {
    return (
      <main className="p-6">
        <Cargando />
      </main>
    );
  }

  if (!puedeVer) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          Solo administradores y líderes pueden generar boletas.
        </p>
      </main>
    );
  }

  if (error) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          No se pudo cargar el periodo: {error}{" "}
          <Boton variante="enlace" className="font-medium" onClick={() => void cargar()}>
            Reintentar
          </Boton>
        </p>
      </main>
    );
  }

  const f: Fila | undefined = proy?.filas.find((x) => x.persona_id === personaId);

  if (!proy || !f) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          No se encontró a esa persona en este periodo.{" "}
          <Link href="/admin/planilla" className="underline">
            Volver a Planilla
          </Link>
        </p>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-2xl p-6 print:p-0">
      {/* Barra de acciones — no se imprime */}
      <div className="mb-6 flex items-center justify-between print:hidden">
        <Link href="/admin/planilla" className="text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Planilla
        </Link>
        <Boton variante="primario" onClick={() => window.print()}>
          Imprimir / Guardar como PDF
        </Boton>
      </div>

      {/* ── Boleta ── */}
      <BoletaHoja
        f={f}
        proy={proy}
        baseLegal={baseLegal}
        documento={documento}
        fechaIngreso={fechaIngreso}
        nombreDni={nombreDni}
        subvencionPracticante={subvencionPracticante}
      />
    </main>
  );
}

export default function BoletaPage() {
  return (
    <Suspense fallback={<main className="p-6"><Cargando /></main>}>
      <BoletaContenido />
    </Suspense>
  );
}
