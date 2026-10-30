"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { EnlaceVolver } from "@/components/enlace-volver";
import { Cargando } from "@/components/cargando";
import { PapelBono } from "@/components/papel-bono";
import { Boton } from "@/components/ui/boton";
import { CabeceraPagina } from "@/components/ui/cabecera-pagina";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { nombreDelMes } from "@/lib/bandeja-mia";
import { puedePedirBono, traerMiBono, type MiBono } from "@/lib/mi-bono";
import { formatSoles } from "@/lib/rangos";
import { FirmaEditor } from "@/app/(admin)/admin/personas/[id]/FirmaEditor";

/**
 * Tu bono de cumpleaños: pedirlo, y ver en qué quedó (0477/0478).
 *
 * PEDIRLO ES FIRMAR LA CONSTANCIA (0478), Y AL FIRMAR ENTRA A SU BOLETA
 * (0479). Desde Info se llega acá con «Pedir mi bono». Al firmar, el bono
 * queda como una línea de su boleta del periodo que corre y se paga junto con
 * su planilla: no hay nadie a quien esperar. Solo si no había un periodo de
 * planilla abierto —o alguien quitó la línea— queda «pedido», y ahí sí DO lo
 * transfiere y confirma la fecha (el respaldo de la 0478). UN PRACTICANTE
 * entra a la boleta igual (0521): entre la 0519 y la 0520 se le transfería a
 * mano, y Felipe lo revirtió el 2026-10-13 —«no transferir a cada rato, sino
 * pagar al fin del periodo»—. Lo que cambia para él es la constancia, que lleva
 * su propio texto, y que su boleta paga una «subvención», no una planilla. Qué le toca (y si
 * el botón aparece) lo contesta `fn_mi_bono_cumpleanos`, la misma función que
 * el servidor usa de puerta: la pantalla no puede ofrecer un pedido que la
 * base después rechace.
 *
 * QUÉ REEMPLAZA. Hasta hoy el único camino era admin/documentacion: se
 * imprimía la constancia, se firmaba a mano y un admin subía el escaneo.
 * Esta pantalla reemplaza el papel para quien firma desde acá — misma
 * decisión que ya tomó la 0423 para la declaración de ruta: la firma
 * digital tiene el MISMO valor que el escaneo.
 *
 * SIN CANDADO DE SECUENCIA, A DIFERENCIA DE LO QUE PARECÍA HACER FALTA. El
 * bono se paga por transferencia (confirmado con Felipe, 2026-09-16), así
 * que no hay ningún paso previo de un admin que desbloquee esta pantalla —
 * la persona firma en cuanto le corresponde, exactamente como ya hace con
 * su declaración de ruta. La única puerta es la de siempre: en planilla (o
 * practicante, desde la 0519), activa, y sin una constancia vigente todavía
 * este año.
 *
 * EL MONTO NUNCA SE PIDE ACÁ. Lo calcula el servidor con el bono_onomastico
 * vigente — nunca una cifra que la persona escriba.
 */

interface MiDocumento {
  fecha_firma: string | null;
  firma: string | null;
  monto_declarado: number | null;
}

interface Yo {
  id: string;
  nombreOficial: string;
  documento: string | null;
  /** Modalidad formativa (0519): otro texto en la constancia, y su bono nunca va a la boleta. */
  practicante: boolean;
}

function fechaLarga(iso: string): string {
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric" }).format(
    new Date(`${iso}T12:00:00`),
  );
}

function MiCumpleanosContenido() {
  const router = useRouter();
  const supabase = createAdminSupabaseClient();

  const [yo, setYo] = useState<Yo | null>(null);
  const [bono, setBono] = useState<MiBono | null>(null);
  const [miFirma, setMiFirma] = useState<string | null>(null);
  const [miDocumento, setMiDocumento] = useState<MiDocumento | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // La firma de la empresa — igual que /mio/movilidad: se muestra siempre,
  // sin importar quién mire, porque es la del cargo, no la de la sesión.
  const [firmaEmpresa, setFirmaEmpresa] = useState<string | null>(null);
  const [firmanteNombre, setFirmanteNombre] = useState<string | null>(null);
  const [firmanteCargo, setFirmanteCargo] = useState<string | null>(null);

  const [firmando, setFirmando] = useState(false);
  const [verDocumento, setVerDocumento] = useState(false);
  const [aviso, setAviso] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  const cargar = useCallback(async () => {
    setCargando(true);
    setError(null);

    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/mio");
      return;
    }
    // Del almacén de la sesión, sin viajar a la red: `getUser()` es una ronda al servidor de
    // autenticación por cada pantalla, y la base ya valida el token en cada consulta.
    const uid = sesion.session.user.id;
    if (!uid) {
      setCargando(false);
      setError("No se pudo leer tu sesión. Vuelve a entrar.");
      return;
    }

    const { data: p } = await supabase
      .from("personas").select("id, nombres, apellidos, documento, tipo_vinculo").eq("auth_user_id", uid).maybeSingle();
    if (!p) {
      setCargando(false);
      setError("Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.");
      return;
    }
    const { data: ficha } = await supabase
      .from("datos_personales").select("nombre_dni").eq("persona_id", p.id as string).maybeSingle();
    const nombre = `${p.nombres as string} ${p.apellidos as string}`;
    setYo({
      id: p.id as string,
      nombreOficial: (ficha?.nombre_dni as string | null) || nombre,
      documento: (p.documento as string | null) ?? null,
      practicante: p.tipo_vinculo === "practicante",
    });

    const { data: cfgFirmante } = await supabase
      .from("configuracion").select("valor").eq("clave", "firmante_empresa").maybeSingle();
    const vf = (cfgFirmante?.valor ?? null) as { persona_id?: string; cargo?: string } | null;
    if (vf?.persona_id) {
      const { data: firmante } = await supabase
        .from("personas").select("nombres, apellidos").eq("id", vf.persona_id).maybeSingle();
      if (firmante) setFirmanteNombre(`${firmante.nombres as string} ${firmante.apellidos as string}`);
    }
    setFirmanteCargo(vf?.cargo ?? null);

    const [{ bono: miBono, error: eBono }, { data: fu }, { data: fe }, { data: docs }] =
      await Promise.all([
        // Qué le toca, con el monto que rige hoy (0478). `parametros_laborales`
        // solo la lee DO; esta función lo trae para mostrarlo ANTES de pedir.
        traerMiBono(supabase),
        supabase.rpc("fn_mi_firma"),
        supabase.rpc("fn_firma_empresa"),
        // Con `p_persona_id` y no sin argumentos: para DO, esta RPC sin
        // argumento devuelve los documentos de TODO el equipo, y la pantalla
        // pintaría como «tuya» la constancia de otra persona (0429).
        supabase.rpc("fn_documentos_listar", { p_persona_id: p.id as string }),
      ]);
    setCargando(false);
    if (eBono) {
      setError(mensajeDeError(eBono, "traer tu bono de cumpleaños"));
      return;
    }
    setBono(miBono);
    setMiFirma((fu as string | null) ?? null);
    setFirmaEmpresa((fe as string | null) ?? null);

    // La constancia es la que dice la base, por su id — no «la de este año»
    // según el reloj del navegador, que en año nuevo puede ir por delante.
    type FilaDoc = { id: string; fecha_firma: string | null; firma_persona: string | null; monto_declarado: number | null };
    const doc = miBono?.documento_id
      ? ((docs as FilaDoc[] | null) ?? []).find((d) => d.id === miBono.documento_id)
      : undefined;
    setMiDocumento(doc ? {
      fecha_firma: doc.fecha_firma,
      firma: doc.firma_persona,
      monto_declarado: doc.monto_declarado,
    } : null);
  }, [supabase, router]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  useTituloDocumento(yo && miDocumento?.firma ? `${yo.nombreOficial} — Constancia del bono de cumpleaños` : null);

  async function firmar() {
    if (!miFirma) {
      setAviso({ tipo: "error", texto: "Todavía no configuraste tu firma. Bájala aquí abajo antes de confirmar." });
      return;
    }
    setFirmando(true);
    setAviso(null);
    const { error: eFirmar } = await supabase.rpc("fn_confirmar_mi_bono_cumpleanos");
    setFirmando(false);
    if (eFirmar) {
      setAviso({ tipo: "error", texto: mensajeDeError(eFirmar, "pedir tu bono") });
      return;
    }
    // Qué pasó exactamente lo dice la tarjeta de abajo, ya recargada: «en tu
    // boleta» si había periodo abierto, «pedido» si no. Este aviso no
    // adivina cuál de las dos fue.
    setAviso({ tipo: "ok", texto: "Listo, pediste tu bono. Abajo ves en qué quedó." });
    await cargar();
  }

  if (cargando) {
    return <main className="p-6"><Cargando /></main>;
  }
  if (error) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          {error} <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
        </p>
        <EnlaceVolver href="/mio" className="mt-3 inline-block text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Info
        </EnlaceVolver>
      </main>
    );
  }

  return (
    <main className="mx-auto w-full min-w-0 max-w-2xl px-4 py-6 sm:p-6">
      <EnlaceVolver href="/mio" className="mb-4 inline-block text-sm text-taupe hover:text-tinta hover:underline">
        ← Volver a Info
      </EnlaceVolver>
      <CabeceraPagina
        titulo="Tu bono de cumpleaños"
        descripcion={
          <>
            Una asignación de {bono?.monto != null ? formatSoles(bono.monto) : "la empresa"} en el mes de tu
            cumpleaños. Se pide firmando tu constancia aquí —sin imprimir ni escanear nada—{" "}
            y se suma a tu boleta.
          </>
        }
      />

      {aviso && (
        <p className={`mb-4 rounded-lg px-4 py-3 text-sm ${
          aviso.tipo === "ok" ? "bg-verde/10 text-verde" : "bg-rojo/10 text-rojo"}`}
        >
          {aviso.texto}
        </p>
      )}

      {/* Lo que todavía no se puede pedir: se dice por qué y qué hacer, nunca un botón que va a fallar. */}
      {(!bono || bono.estado === "no_aplica") && (
        <p className="rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
          Este año no te corresponde el bono de cumpleaños: es para quien está en planilla o hace prácticas en
          CAYLA —no durante la preselección ni con un contrato de menos de una semana—, y rige desde que
          existe o desde tu ingreso. Si crees que es un error, avisa a Desarrollo Organizacional.
        </p>
      )}
      {bono?.estado === "sin_fecha" && (
        <p className="rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
          Falta tu fecha de nacimiento en tu ficha, así que el sistema no sabe cuándo es tu cumpleaños.
          Avisa a Desarrollo Organizacional para que la registre.
        </p>
      )}
      {bono?.estado === "proximo" && bono.mes_cumpleanos && (
        <p className="rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
          Tu cumpleaños es en {nombreDelMes(bono.mes_cumpleanos)}: desde el primer día de ese mes vas a poder
          pedirlo aquí, y también te lo recordaremos en tu Info.
        </p>
      )}

      {/* Ya lo pidió (en su boleta, o esperando a DO), o ya se entregó. */}
      {(bono?.estado === "pedido" || bono?.estado === "en_boleta" || bono?.estado === "entregado") && (
        <section className="rounded-2xl border border-sand p-5 text-sm">
          {bono.estado === "en_boleta" ? (
            <p className="text-tinta">
              Lo pediste el {bono.pedido_el ? fechaLarga(bono.pedido_el) : "—"}
              {bono.monto != null && <> por {formatSoles(bono.monto)}</>}. Ya está en tu boleta
              {bono.periodo_fin ? <> del periodo que cierra el {fechaLarga(bono.periodo_fin)}</> : null} y se
              paga junto con {yo?.practicante ? "tu subvención" : "tu planilla"}.{" "}
              <Link href="/mio/boleta" className="underline underline-offset-2 hover:text-rojo-profundo">
                Ver mi boleta →
              </Link>
            </p>
          ) : bono.estado === "pedido" ? (
            <p className="text-tinta">
              Lo pediste el {bono.pedido_el ? fechaLarga(bono.pedido_el) : "—"}
              {bono.monto != null && <> por {formatSoles(bono.monto)}</>}.{" "}
              Todavía no está en ninguna boleta, así que Desarrollo Organizacional te lo transfiere:
              cuando lo confirme, aquí verás la fecha.
            </p>
          ) : bono.via === "boleta" ? (
            // No hay «día en que se transfirió»: la planilla no lo guarda por
            // persona. Se dice el periodo, que es un hecho.
            <p className="text-verde">
              Pagado con {yo?.practicante ? "tu subvención" : "tu planilla"}{bono.periodo_fin ? <> del periodo que cerró el {fechaLarga(bono.periodo_fin)}</> : null}
              {bono.monto != null && <>: {formatSoles(bono.monto)}</>}.
            </p>
          ) : (
            <p className="text-verde">
              {bono.pedido_el ? "Transferido" : "Recibido"} el {bono.entregado_el ? fechaLarga(bono.entregado_el) : "—"}
              {bono.monto != null && <>: {formatSoles(bono.monto)}</>}.
            </p>
          )}
          {miDocumento?.firma && !verDocumento && (
            <Boton variante="enlace" className="mt-3 block" onClick={() => setVerDocumento(true)}>
              Ver mi constancia firmada
            </Boton>
          )}
        </section>
      )}

      {miDocumento?.firma && verDocumento && (bono?.estado === "pedido" || bono?.estado === "en_boleta" || bono?.estado === "entregado") && (
        <div className="mt-4 rounded-2xl border border-sand p-5">
          <div className="mb-3 flex items-center justify-between print:hidden">
            <h2 className="font-serif text-lg">Tu constancia firmada</h2>
            <div className="flex items-center gap-3">
              <Boton variante="primario" tamano="sm" onClick={() => window.print()}>
                Imprimir / Guardar como PDF
              </Boton>
              <Boton variante="enlace" onClick={() => setVerDocumento(false)}>Cerrar</Boton>
            </div>
          </div>
          <PapelBono
            practicante={yo?.practicante ?? false}
            monto={miDocumento.monto_declarado}
            fecha={miDocumento.fecha_firma}
            estadoPago={{
              transferidoEl: bono.estado === "entregado" && bono.via !== "boleta" ? bono.entregado_el : null,
              enBoleta: bono.via === "boleta",
            }}
            nombreOficial={yo?.nombreOficial ?? null}
            documento={yo?.documento ?? null}
            firmaPersona={miDocumento.firma}
            firmaEmpresa={firmaEmpresa}
            firmanteNombre={firmanteNombre}
            firmanteCargo={firmanteCargo}
          />
        </div>
      )}

      {/* Pedirlo: su mes, o después si se le pasó. */}
      {bono && puedePedirBono(bono) && (
        <div className="rounded-2xl border border-sand p-5">
          {bono.estado === "vencido" && (
            <p className="mb-4 rounded-lg bg-ambar/10 px-3 py-2 text-sm text-tinta">
              Ya pasó tu cumpleaños y todavía no lo pides: aún estás a tiempo.
            </p>
          )}
          {bono.monto === null && (
            <p className="mb-4 rounded-lg bg-rojo/10 px-3 py-2 text-sm text-rojo">
              No hay un monto de bono de onomástico vigente en el sistema, así que todavía no se puede pedir.
              Avisa a Desarrollo Organizacional.
            </p>
          )}
          <p className="mb-4 text-sm text-taupe">
            Al pedirlo firmas esta constancia. Léela: es lo que acredita que el bono es por tu cumpleaños y no
            parte de {yo?.practicante ? "tu subvención" : "tu sueldo"}.
          </p>
          <PapelBono
            practicante={yo?.practicante ?? false}
            monto={bono.monto}
            fecha={null}
            estadoPago={{ transferidoEl: null, enBoleta: false }}
            nombreOficial={yo?.nombreOficial ?? null}
            documento={yo?.documento ?? null}
            firmaPersona={miFirma}
            firmaEmpresa={firmaEmpresa}
            firmanteNombre={firmanteNombre}
            firmanteCargo={firmanteCargo}
          />

          <div className="mb-4 mt-4 border-t border-sand pt-4">
            <h3 className="mb-1 font-serif text-base">Tu firma</h3>
            {yo && (
              <FirmaEditor
                supabase={supabase}
                nombreOficial={yo.nombreOficial}
                avisar={(tipo, texto) => setAviso({ tipo, texto })}
                onGuardada={setMiFirma}
              />
            )}
          </div>

          <Boton variante="primario" cargando={firmando} disabled={!miFirma || bono.monto === null}
            onClick={() => void firmar()}>
            Pedir mi bono
          </Boton>
          {!miFirma && (
            <p className="mt-2 text-xs text-taupe">Configura tu firma arriba antes de poder pedirlo.</p>
          )}
        </div>
      )}
    </main>
  );
}

export default function MiCumpleanosPage() {
  return <MiCumpleanosContenido />;
}
