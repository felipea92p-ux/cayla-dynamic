"use client";

// ── Boletas de pago: la pantalla de Desarrollo Organizacional ───────────────
//
// QUÉ ES. La boleta OFICIAL —la que entrega el contador, en foto o en PDF— se
// sube aquí por persona y periodo, se revisa y se publica; cada persona ve la
// suya en «Lo mío». NO es la boleta calculada por el sistema
// (`/admin/planilla/boleta`), que sigue siendo otra cosa y no se toca.
//
// LO QUE LA ORDENA (migración 0482). Los archivos suben primero y la base crea
// la versión después; editar una boleta es agregar una versión, nunca cambiar
// una; y lo que un borrador tiene de la persona es NADA hasta que DO publica.
// Las reglas puras viven en `lib/boletas.ts` y `lib/admin/boletas-pantalla.ts`
// (con pruebas), y cada modal en `components/boletas/`.
//
// CELULAR Y COMPUTADORA. DO trabaja desde los dos: en computadora la lista es una
// tabla, en celular cada persona es una tarjeta con botones de 40 px de alto.

import { Suspense, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { puedeGestionarBoletas } from "@cayla-dynamic/shared";
import { Cargando, SinDatos } from "@/components/cargando";
import { useToast } from "@/components/toast";
import { Boton } from "@/components/ui/boton";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { EditorDeBoleta } from "@/components/boletas/editor-de-boleta";
import { ListaDeBoletas, type AccionDeBoleta } from "@/components/boletas/lista-de-boletas";
import { ModalMarcarPapel } from "@/components/boletas/modales-de-confirmacion";
import { ModalAnularBoleta } from "@/components/boletas/modal-anular-boleta";
import { ModalConstanciaBoleta } from "@/components/boletas/modal-constancia-boleta";
import { ModalRestablecerBoleta } from "@/components/boletas/modal-restablecer-boleta";
import { ModalHistorialBoleta, type VersionDeBoleta } from "@/components/boletas/modal-historial-boleta";
import { ModalPublicarBoletas } from "@/components/boletas/modal-publicar-boletas";
import { ModalVerBoleta } from "@/components/boletas/modal-ver-boleta";
import { TACTIL } from "@/components/boletas/pie-de-modal";
import { ETIQUETA_ESTADO, contarTablero, estadoVisible, type EstadoVisible, type TipoBoleta } from "@/lib/boletas";
import {
  ESTADOS_DEL_FILTRO, accionesDeFila, borradoresDelTablero, etiquetaDePeriodo, filtrarTablero, nombreDePeriodo,
  periodoInicial, sedesDelTablero, type FilaTablero,
} from "@/lib/admin/boletas-pantalla";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useRolActual } from "@/lib/admin/use-rol";
import type { PeriodoInfo } from "@/lib/admin/planilla/tipos";

type Modal =
  | { t: "editar"; fila: FilaTablero }
  | { t: "publicar"; borradores: FilaTablero[] }
  | { t: "historial"; fila: FilaTablero }
  | { t: "anular"; fila: FilaTablero }
  | { t: "papel"; fila: FilaTablero }
  | { t: "constancia"; fila: FilaTablero }
  | { t: "anulacion"; fila: FilaTablero }
  | { t: "restablecer"; fila: FilaTablero };

type Visor = { versionId: string; tipo: TipoBoleta; titulo: string; textoCerrar: string };

function Cifra({ etiqueta, valor }: { etiqueta: string; valor: string }) {
  return (
    <div className="rounded-superficie border border-sand bg-papel px-4 py-3">
      <p className="font-serif text-2xl tabular-nums text-tinta">{valor}</p>
      <p className="text-xs text-taupe">{etiqueta}</p>
    </div>
  );
}

function PantallaBoletas() {
  const rol = useRolActual();
  const puede = puedeGestionarBoletas(rol);
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const { avisar } = useToast();

  // La dirección puede pedir un periodo (`?periodo=`), pero solo al entrar.
  const pedido = useSearchParams().get("periodo");
  const [periodoPedido] = useState(pedido);

  const [periodos, setPeriodos] = useState<PeriodoInfo[] | null>(null);
  const [errorPeriodos, setErrorPeriodos] = useState<string | null>(null);
  const [periodoId, setPeriodoId] = useState<string | null>(null);

  const [filas, setFilas] = useState<FilaTablero[] | null>(null);
  const [errorTablero, setErrorTablero] = useState<string | null>(null);
  // Sube en uno cada vez que hay que volver a pedir el tablero (tras guardar, publicar, anular…).
  const [recarga, setRecarga] = useState(0);

  const [filtroEstado, setFiltroEstado] = useState<EstadoVisible | "todos">("todos");
  const [filtroSede, setFiltroSede] = useState<string>("todas");
  const [buscar, setBuscar] = useState("");

  const [modal, setModal] = useState<Modal | null>(null);
  const [visor, setVisor] = useState<Visor | null>(null);

  // ── Periodos ───────────────────────────────────────────────────────────────
  useEffect(() => {
    if (!puede) return;
    let vigente = true;
    void supabase.rpc("fn_periodos").then(({ data, error }) => {
      if (!vigente) return;
      if (error) { setErrorPeriodos(mensajeDeError(error)); return; }
      const lista = (data as unknown as PeriodoInfo[] | null) ?? [];
      setErrorPeriodos(null);
      setPeriodos(lista);
      setPeriodoId(periodoInicial(lista, periodoPedido));
    });
    return () => { vigente = false; };
  }, [puede, supabase, periodoPedido]);

  // ── El tablero del periodo elegido ─────────────────────────────────────────
  useEffect(() => {
    if (!periodoId) return;
    let vigente = true;
    void supabase.rpc("fn_boletas_tablero", { p_periodo_id: periodoId }).then(({ data, error }) => {
      if (!vigente) return; // llegó tarde: ya se eligió otro periodo
      if (error) { setErrorTablero(mensajeDeError(error)); return; }
      setErrorTablero(null);
      setFilas(data ?? []);
    });
    return () => { vigente = false; };
  }, [supabase, periodoId, recarga]);

  function elegirPeriodo(id: string) {
    setPeriodoId(id);
    setFilas(null);
    setErrorTablero(null);
    setFiltroEstado("todos");
  }

  const periodoActual = periodos?.find((p) => p.id === periodoId) ?? null;
  const nombreDelPeriodo = periodoActual ? nombreDePeriodo(periodoActual) : "";

  const contadores = useMemo(() => (filas ? contarTablero(filas) : null), [filas]);
  const borradores = useMemo(() => (filas ? borradoresDelTablero(filas) : []), [filas]);
  const sedes = useMemo(() => (filas ? sedesDelTablero(filas) : []), [filas]);
  const visibles = useMemo(
    () => (filas ? filtrarTablero(filas, { estado: filtroEstado, sede: filtroSede, texto: buscar }) : []),
    [filas, filtroEstado, filtroSede, buscar],
  );
  const sinPago = filas ? filas.filter((f) => estadoVisible(f) === "sin_pago").length : 0;
  const todosSinPago = filas !== null && filas.length > 0 && sinPago === filas.length;

  // ── Acciones ───────────────────────────────────────────────────────────────
  function abrirVisor(v: Visor) { setVisor(v); }

  function alPulsar(accion: AccionDeBoleta, f: FilaTablero) {
    if (accion === "subir" || accion === "editar") setModal({ t: "editar", fila: f });
    else if (accion === "papel") setModal({ t: "papel", fila: f });
    else if (accion === "historial") setModal({ t: "historial", fila: f });
    else if (accion === "anular") setModal({ t: "anular", fila: f });
    else if (accion === "constancia") setModal({ t: "constancia", fila: f });
    else if (accion === "anulacion") setModal({ t: "anulacion", fila: f });
    else if (accion === "restablecer") setModal({ t: "restablecer", fila: f });
    else if (accion === "ver" && f.version_id) {
      abrirVisor({
        versionId: f.version_id,
        tipo: f.tipo as TipoBoleta,
        titulo: `Boleta de ${f.nombre} · ${nombreDelPeriodo}`,
        textoCerrar: "Cerrar",
      });
    }
  }

  function terminarYRecargar() {
    setModal(null);
    setRecarga((n) => n + 1);
  }

  function alPublicar(publicadas: number, listadas: number) {
    if (publicadas === 0) {
      avisar("error", "No se publicó ninguna boleta: ya no estaban listas. Revisa el tablero.");
    } else if (publicadas < listadas) {
      avisar("ok", `Se publicaron ${publicadas} de ${listadas} boletas. Las demás ya no estaban listas: revisa el tablero.`);
    } else {
      avisar("ok", `${publicadas} ${publicadas === 1 ? "boleta publicada" : "boletas publicadas"}. Cada persona ya puede abrir la suya.`);
    }
    terminarYRecargar();
  }

  function verVersion(f: FilaTablero, v: VersionDeBoleta) {
    abrirVisor({
      versionId: v.version_id,
      tipo: v.tipo as TipoBoleta,
      titulo: `Boleta de ${f.nombre} · ${nombreDelPeriodo} · versión ${v.n}`,
      textoCerrar: "Volver",
    });
  }

  // ── Acceso ─────────────────────────────────────────────────────────────────
  if (rol === null) {
    return <main className="flex-1 p-6"><Cargando /></main>;
  }
  if (!puede) {
    return (
      <main className="flex-1 p-6">
        <p className="max-w-md rounded-control bg-rojo/10 px-4 py-3 text-sm text-rojo-profundo">
          Solo Desarrollo Organizacional puede ver y subir las boletas.
        </p>
      </main>
    );
  }

  return (
    <main className="flex-1 space-y-5 p-4 sm:p-6">
      <div>
        <nav aria-label="Ubicación" className="mb-2 text-xs text-taupe">
          <Link href="/admin/planilla" className="underline underline-offset-2 hover:text-tinta">Planilla</Link> › Boletas
        </nav>
        <CabeceraPagina
          titulo="Boletas de pago"
          descripcion="La boleta oficial de cada persona, por periodo. Se sube, se revisa y recién entonces se publica."
        />
      </div>

      {errorPeriodos && (
        <p role="alert" className="rounded-control bg-rojo/10 px-4 py-3 text-sm text-rojo-profundo">{errorPeriodos}</p>
      )}

      {periodos !== null && periodos.length === 0 && (
        <SinDatos texto="Todavía no hay periodos de planilla." pista="Los crea Desarrollo Organizacional desde Planilla." />
      )}

      {periodos !== null && periodos.length > 0 && (
        <>
          {/* Filtros: en celular se apilan a lo ancho. */}
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <CampoSelect etiqueta="Periodo" value={periodoId ?? ""} onChange={(e) => elegirPeriodo(e.target.value)}>
              {periodos.map((p) => (
                <option key={p.id} value={p.id}>{etiquetaDePeriodo(p)}{p.estado === "pagado" ? " · pagado" : ""}</option>
              ))}
            </CampoSelect>
            <CampoSelect etiqueta="Estado" value={filtroEstado} onChange={(e) => setFiltroEstado(e.target.value as EstadoVisible | "todos")}>
              <option value="todos">Todos</option>
              {ESTADOS_DEL_FILTRO.map((e) => <option key={e} value={e}>{ETIQUETA_ESTADO[e].texto}</option>)}
            </CampoSelect>
            <CampoSelect etiqueta="Sede" value={filtroSede} onChange={(e) => setFiltroSede(e.target.value)}>
              <option value="todas">Todas</option>
              {sedes.map((s) => <option key={s} value={s}>{s}</option>)}
            </CampoSelect>
            <Campo etiqueta="Persona" type="search" placeholder="Buscar por nombre" value={buscar} onChange={(e) => setBuscar(e.target.value)} />
          </div>

          {errorTablero && (
            <div className="space-y-3">
              <p role="alert" className="rounded-control bg-rojo/10 px-4 py-3 text-sm text-rojo-profundo">{errorTablero}</p>
              <Boton className={TACTIL} onClick={() => { setErrorTablero(null); setRecarga((n) => n + 1); }}>Intentar de nuevo</Boton>
            </div>
          )}

          {filas === null && !errorTablero && <Cargando texto="Trayendo las boletas del periodo…" />}

          {filas !== null && contadores && (
            <>
              {todosSinPago ? (
                <BannerAviso variante="neutral" titulo={`${nombreDelPeriodo} todavía no está pagado`}>
                  La boleta oficial se sube cuando el periodo cierra y el contador entrega las boletas. Mientras tanto, cada persona
                  sigue viendo en «Lo mío» cómo va su pago.
                </BannerAviso>
              ) : (
                <>
                  <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
                    <Cifra valor={`${contadores.conBoleta} de ${contadores.total}`} etiqueta="con su boleta" />
                    <Cifra valor={String(contadores.sinPublicar)} etiqueta="subidas sin publicar" />
                    <Cifra valor={String(contadores.faltan)} etiqueta="faltan por subir" />
                    <Cifra valor={String(contadores.firmadas)} etiqueta="firmaron su boleta" />
                  </div>

                  <div className="flex flex-col gap-3 rounded-superficie bg-hueso px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
                    <p className="text-sm text-tinta">
                      {borradores.length > 0
                        ? <>Hay <b className="font-medium">{borradores.length}</b> {borradores.length === 1 ? "boleta subida sin publicar" : "boletas subidas sin publicar"}. La persona no la ve hasta que publiques.</>
                        : "Nada por publicar."}
                    </p>
                    {borradores.length > 0 && (
                      <Boton
                        variante="primario"
                        className={`w-full sm:w-auto ${TACTIL}`}
                        onClick={() => setModal({ t: "publicar", borradores })}
                      >
                        Publicar {borradores.length} {borradores.length === 1 ? "boleta" : "boletas"}
                      </Boton>
                    )}
                  </div>

                  {sinPago > 0 && (
                    <p className="text-xs text-taupe">
                      {sinPago} {sinPago === 1 ? "persona es" : "personas son"} de un grupo que todavía no se paga en este periodo: su boleta se sube cuando el grupo cierra.
                    </p>
                  )}
                </>
              )}

              {visibles.length === 0 ? (
                <SinDatos
                  texto={filas.length === 0 ? "No hay personas en este periodo." : "Nadie coincide con estos filtros."}
                  pista={filas.length === 0 ? undefined : "Prueba con «Todos» en Estado o quita la búsqueda."}
                />
              ) : (
                <ListaDeBoletas filas={visibles} onAccion={alPulsar} />
              )}
            </>
          )}
        </>
      )}

      {/* ── Modales. Solo uno a la vez, más el visor encima de todos. ───────── */}
      {periodoId && modal?.t === "editar" && (
        <EditorDeBoleta
          key={modal.fila.persona_id}
          supabase={supabase}
          fila={modal.fila}
          periodoId={periodoId}
          nombreDelPeriodo={nombreDelPeriodo}
          onCerrar={() => setModal(null)}
          onGuardado={terminarYRecargar}
        />
      )}
      {periodoId && modal?.t === "publicar" && (
        <ModalPublicarBoletas
          supabase={supabase}
          periodoId={periodoId}
          nombreDelPeriodo={nombreDelPeriodo}
          borradores={modal.borradores}
          oculto={visor !== null}
          onVer={(b) => {
            if (!b.version_id) return;
            abrirVisor({
              versionId: b.version_id,
              tipo: b.tipo as TipoBoleta,
              titulo: `Boleta de ${b.nombre} · ${nombreDelPeriodo}`,
              textoCerrar: "Volver",
            });
          }}
          onCerrar={() => setModal(null)}
          onPublicadas={alPublicar}
        />
      )}
      {modal?.t === "historial" && (
        <ModalHistorialBoleta
          key={modal.fila.persona_id}
          supabase={supabase}
          fila={modal.fila}
          nombreDelPeriodo={nombreDelPeriodo}
          oculto={visor !== null}
          onVer={(v) => verVersion(modal.fila, v)}
          onCerrar={() => setModal(null)}
        />
      )}
      {modal?.t === "constancia" && (
        <ModalConstanciaBoleta
          key={modal.fila.persona_id}
          supabase={supabase}
          modo="constancia"
          fila={modal.fila}
          periodo={periodoActual}
          nombreDelPeriodo={nombreDelPeriodo}
          onCerrar={() => setModal(null)}
          onAnular={() => setModal({ t: "anular", fila: modal.fila })}
        />
      )}
      {modal?.t === "anulacion" && (
        <ModalConstanciaBoleta
          key={modal.fila.persona_id}
          supabase={supabase}
          modo="anulacion"
          fila={modal.fila}
          periodo={periodoActual}
          nombreDelPeriodo={nombreDelPeriodo}
          onCerrar={() => setModal(null)}
          onRestablecer={accionesDeFila(modal.fila).restablecer ? () => setModal({ t: "restablecer", fila: modal.fila }) : undefined}
        />
      )}
      {modal?.t === "restablecer" && (
        <ModalRestablecerBoleta
          supabase={supabase}
          fila={modal.fila}
          nombreDelPeriodo={nombreDelPeriodo}
          onCerrar={() => setModal(null)}
          onRestablecida={terminarYRecargar}
        />
      )}
      {modal?.t === "anular" && (
        <ModalAnularBoleta
          key={modal.fila.persona_id}
          supabase={supabase}
          fila={modal.fila}
          nombreDelPeriodo={nombreDelPeriodo}
          onCerrar={() => setModal(null)}
          onAnulada={terminarYRecargar}
        />
      )}
      {periodoId && modal?.t === "papel" && (
        <ModalMarcarPapel
          supabase={supabase}
          fila={modal.fila}
          periodoId={periodoId}
          nombreDelPeriodo={nombreDelPeriodo}
          onCerrar={() => setModal(null)}
          onMarcada={terminarYRecargar}
        />
      )}
      {visor && (
        <ModalVerBoleta
          key={visor.versionId}
          supabase={supabase}
          versionId={visor.versionId}
          tipo={visor.tipo}
          titulo={visor.titulo}
          textoCerrar={visor.textoCerrar}
          onCerrar={() => setVisor(null)}
        />
      )}
    </main>
  );
}

// `useSearchParams` exige un límite de Suspense para que la página se pueda
// construir sin conocer la dirección: mientras se resuelve, se ve la carga.
export default function BoletasPage() {
  return (
    <Suspense fallback={<main className="flex-1 p-6"><Cargando /></main>}>
      <PantallaBoletas />
    </Suspense>
  );
}
