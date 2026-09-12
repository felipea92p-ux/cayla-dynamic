"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { AreaTexto } from "@/components/ui/area-texto";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { MARCADOR_FIRMA_EMPRESA, MARCADOR_FIRMA_PERSONA } from "@/lib/admin/contrato-texto";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { ordenarContratoVigente } from "@/lib/mi-contrato";
import { FirmaEditor } from "@/app/(admin)/admin/personas/[id]/FirmaEditor";
import { hoyLima } from "@cayla-dynamic/shared";

// Tu contrato, en autoservicio — mismo criterio que /mio/boleta: siempre el
// propio (`auth_user_id` de la sesión, nunca un id que viaje en la URL), y el
// documento congelado que ya se generó, no uno recalculado con los datos de
// hoy — el sueldo o el cargo pueden haber cambiado desde que se firmó.
//
// `contratos_lectura` (0272) ya deja a cada persona leer sus propias filas de
// `contratos_generados`, así que esta pantalla consulta la tabla directo, sin
// necesitar una función nueva.
//
// EL DESEMPATE («cuál es el vigente» si hay más de uno) copia el de
// `fn_contrato_firmado_vigente_de` (0312): esa función no está concedida a
// `authenticated` a propósito (es SECURITY DEFINER y devolvería la fila de
// CUALQUIER persona), así que acá se repite el mismo criterio —nunca uno
// inventado— contra la propia fila, que la RLS ya deja ver.
//
// LAS DOS FIRMAS SE ESTAMPAN AL MOSTRAR, NUNCA AL GUARDAR — igual que en
// admin/contratos: `documento_html` congela el texto PACTADO, no cómo se ve.
// La de la empresa (0397, `fn_firma_empresa`) ya no depende de que quien mire
// SEA la firmante: es la del cargo, no la de la sesión, así que puede
// mostrarse aquí, donde quien mira es la propia colaboradora. La suya propia
// (`fn_mi_firma`, sin cambios) sale de la misma tabla y función que ya usa el
// editor de admin/personas/[id] — 0397 solo le abrió el guardado a cualquier
// persona, no solo a admin/líder.
function MiContratoContenido() {
  const router = useRouter();
  const supabase = createAdminSupabaseClient();

  const [yo, setYo] = useState<{ id: string; nombre: string; nombreOficial: string } | null>(null);
  const [contrato, setContrato] = useState<{
    id: string;
    tipo: string;
    fecha_inicio: string;
    fecha_fin: string | null;
    fecha_firma: string | null;
    storage_path: string | null;
    documento_html: string | null;
    // Confirmación DIGITAL (0402) de que la firma de abajo va en este
    // contrato — distinta de `fecha_firma`, que sigue siendo el escaneado
    // físico. Se congela al confirmar: si después cambias tu firma general,
    // este contrato sigue mostrando la que confirmaste hasta que vuelvas a
    // confirmar.
    firma_persona_confirmada_at: string | null;
  } | null>(null);
  const [miFirma, setMiFirma] = useState<string | null>(null);
  const [firmaEmpresa, setFirmaEmpresa] = useState<string | null>(null);
  const [avisoFirma, setAvisoFirma] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [confirmando, setConfirmando] = useState(false);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // ── Pedir revisión de este contrato (0427) ──────────────────────────────
  // Mismo mecanismo que ya usa /mio/movilidad para «algo cambió» —una tabla,
  // tres RPC, una fila en la Bandeja de admin—, pero SIN el candado de
  // movilidad: acá siempre se puede pedir, porque a diferencia de la
  // declaración de ruta, confirmar tu firma en este contrato no queda
  // «vigente y al día» bloqueando nada — se puede reconfirmar cuando sea
  // (0406). Esto es para lo otro: un dato del contrato en sí (fecha, sueldo,
  // cargo) que está mal.
  const [miRevision, setMiRevision] = useState<{
    motivo: string; pedida_at: string; atendida_at: string | null; respuesta: string | null;
  } | null>(null);
  const [formRevisionAbierto, setFormRevisionAbierto] = useState(false);
  const [motivoRevision, setMotivoRevision] = useState("");
  const [enviandoRevision, setEnviandoRevision] = useState(false);
  const [avisoRevision, setAvisoRevision] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  const cargar = useCallback(async () => {
    setCargando(true);
    setError(null);

    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) {
      router.replace("/mio");
      return;
    }

    const { data: sesionAuth } = await supabase.auth.getUser();
    const uid = sesionAuth.user?.id;
    if (!uid) {
      setCargando(false);
      setError("No se pudo leer tu sesión. Vuelve a entrar.");
      return;
    }

    const { data: p } = await supabase
      .from("personas").select("id, nombres, apellidos").eq("auth_user_id", uid).maybeSingle();
    if (!p) {
      setCargando(false);
      setError("Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.");
      return;
    }
    // `nombre_dni`, no `nombres`+`apellidos`: es el nombre que se imprime en el
    // contrato y en la firma tipográfica (ver FirmaEditor), y sale del DNI, no
    // de cómo se escribió la ficha.
    const { data: ficha } = await supabase
      .from("datos_personales").select("nombre_dni").eq("persona_id", p.id).maybeSingle();
    const nombre = `${p.nombres as string} ${p.apellidos as string}`;
    const yoActual = { id: p.id as string, nombre, nombreOficial: (ficha?.nombre_dni as string | null) || nombre };
    setYo(yoActual);

    const [{ data: c, error: eContrato }, { data: mf }, { data: fe }, { data: revs, error: eRevs }] = await Promise.all([
      // El orden vive en lib/mi-contrato.ts: la Bandeja señala el MISMO papel
      // que abre esta pantalla, y dos `order by` escritos por separado se
      // separan solos con el tiempo.
      ordenarContratoVigente(
        supabase
          .from("contratos_generados")
          .select("id, tipo, fecha_inicio, fecha_fin, fecha_firma, storage_path, documento_html, firma_persona_confirmada_at")
          .eq("persona_id", yoActual.id)
          .is("anulado_at", null),
      )
        .limit(1)
        .maybeSingle(),
      supabase.rpc("fn_mi_firma"),
      supabase.rpc("fn_firma_empresa"),
      // Sin admin de por medio: para quien no es admin, esta misma RPC ya
      // devuelve solo lo suyo (0427), igual que fn_movilidad_revisiones_pedidas.
      supabase.rpc("fn_contrato_revisiones_pedidas", { p_solo_pendientes: false }),
    ]);
    setCargando(false);
    if (eContrato) {
      setError(eContrato.message);
      return;
    }
    setContrato(c as typeof contrato);
    setMiFirma((mf as string | null) ?? null);
    setFirmaEmpresa((fe as string | null) ?? null);
    // La más reciente primero (fn_contrato_revisiones_pedidas ya ordena por
    // pedida_at desc); si no falló, aunque venga vacía, es una respuesta real.
    type Revision = { motivo: string; pedida_at: string; atendida_at: string | null; respuesta: string | null };
    setMiRevision(eRevs ? null : (((revs as Revision[] | null) ?? [])[0] ?? null));
  }, [supabase, router]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  useTituloDocumento(yo && contrato ? `${yo.nombre} — Contrato` : null);

  async function verEscaneado() {
    if (!contrato?.storage_path) return;
    const fallo = await abrirArchivoFirmado(supabase, "contratos", contrato.storage_path);
    if (fallo) setError(fallo);
  }

  // Paso aparte de "Guardar firma" (que solo configura la imagen, reusable en
  // cualquier documento): esto congela una copia de esa imagen EN ESTE
  // contrato, visible para admin/líder tanto en la lista de contratos como al
  // abrir este documento (ver admin/contratos).
  //
  // Y DESDE LA 0430, ESTO FIRMA EL CONTRATO — la primera vez. Antes solo
  // tocaba `firma_persona_confirmada_at`, una columna aparte que nada leía
  // para decidir «¿está firmado?»; ahora el servidor también pone
  // `fecha_firma` (si todavía no la tenía), que es la columna que el resto
  // del sistema sí usa. Reconfirmar después —para corregir la imagen de tu
  // firma— nunca vuelve a fechar el contrato: el servidor lo protege con
  // `coalesce`, y acá se refleja igual, sin pisar una `fecha_firma` que ya
  // exista.
  async function confirmarFirma() {
    if (!contrato) return;
    setConfirmando(true);
    const { error: eConfirmar } = await supabase.rpc("fn_confirmar_mi_firma_contrato", { p_contrato_id: contrato.id });
    if (eConfirmar) {
      setAvisoFirma({ tipo: "error", texto: eConfirmar.message });
    } else {
      setContrato((c) => (c ? {
        ...c,
        firma_persona_confirmada_at: new Date().toISOString(),
        fecha_firma: c.fecha_firma ?? hoyLima(),
      } : c));
      setAvisoFirma({ tipo: "ok", texto: "Contrato firmado." });
    }
    setConfirmando(false);
  }

  async function pedirRevision() {
    if (motivoRevision.trim().length < 5) {
      setAvisoRevision({ tipo: "error", texto: "Cuéntanos qué está mal, aunque sea en una línea." });
      return;
    }
    setEnviandoRevision(true);
    const { error: eRevision } = await supabase.rpc("fn_pedir_revision_contrato", {
      p_motivo: motivoRevision.trim(),
    });
    setEnviandoRevision(false);
    if (eRevision) {
      setAvisoRevision({ tipo: "error", texto: mensajeDeError(eRevision, "pedir la revisión") });
      return;
    }
    setAvisoRevision({ tipo: "ok", texto: "Pedido. Desarrollo Organizacional lo va a ver." });
    setMotivoRevision("");
    setFormRevisionAbierto(false);
    await cargar();
  }

  if (cargando) {
    return (
      <main className="p-6">
        <Cargando />
      </main>
    );
  }

  if (error) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          {error}{" "}
          <Boton variante="enlace" onClick={() => void cargar()}>
            Reintentar
          </Boton>
        </p>
        <Link href="/mio" className="mt-3 inline-block text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Info
        </Link>
      </main>
    );
  }

  if (!yo || !contrato || !contrato.documento_html) {
    return (
      <main className="p-6">
        <p className="max-w-md rounded-lg bg-sand/40 px-4 py-3 text-sm text-taupe">
          Todavía no tienes un contrato registrado en el sistema. Si crees que deberías tener uno, avisa a
          Desarrollo Organizacional.
        </p>
        <Link href="/mio" className="mt-3 inline-block text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Info
        </Link>
      </main>
    );
  }

  const html = contrato.documento_html
    .replaceAll(MARCADOR_FIRMA_EMPRESA, firmaEmpresa ? `<img src="${firmaEmpresa}" alt="Firma de la empresa" />` : "&nbsp;")
    .replaceAll(MARCADOR_FIRMA_PERSONA, miFirma ? `<img src="${miFirma}" alt="Tu firma" />` : "&nbsp;");

  return (
    <main className="mx-auto max-w-2xl p-6 print:p-0">
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3 print:hidden">
        <Link href="/mio" className="text-sm text-taupe hover:text-tinta hover:underline">
          ← Volver a Info
        </Link>
        <div className="flex flex-wrap items-center gap-3">
          {contrato.storage_path && (
            // Nativo a propósito: Boton variante="enlace" no aplica tamaño (solo
            // CHROME, sin TAMANOS), así que quedaría en el cuerpo por defecto —
            // más grande que el "Imprimir" de al lado, con el que hoy alinea en
            // text-sm. Mismo criterio de "no forzar" que ya se aplica en otras
            // pantallas para enlaces cuyo tratamiento no calza en el componente.
            <button onClick={() => void verEscaneado()} className="text-sm text-taupe underline hover:text-tinta">
              Ver el escaneado firmado
            </button>
          )}
          <Boton variante="primario" onClick={() => window.print()}>
            Imprimir / Guardar como PDF
          </Boton>
        </div>
      </div>

      {/* Desde la 0430, confirmar tu firma abajo YA firma el contrato — no
          hace falta imprimir ni escanear nada. Este aviso solo sale mientras
          de verdad no hay ninguna firma puesta (ni digital ni la vía de
          escaneo que Desarrollo Organizacional conserva como respaldo). */}
      {!contrato.fecha_firma && (
        <p className="mb-4 rounded-lg bg-ambar/[0.08] px-4 py-3 text-sm text-taupe print:hidden">
          Este contrato todavía no ha sido firmado. Lo que ves es el borrador tal como se generó.
        </p>
      )}

      {/* Confirmar acá firma el contrato — no hace falta imprimir, firmar a
          mano ni subir ningún escaneo (0430, mismo criterio que Movilidad).
          Desarrollo Organizacional conserva la vía del escaneo como
          respaldo para quien no pueda autoservirse desde aquí. */}
      <div className="mb-4 rounded-lg border border-sand bg-papel p-4 print:hidden">
        <h2 className="mb-1 font-serif text-base">Tu firma</h2>
        <p className="mb-3 text-xs text-taupe">
          Al confirmar, tu firma queda estampada en el documento de abajo, junto a la de la empresa, y el
          contrato queda firmado.
        </p>
        {avisoFirma && (
          <p className={`mb-3 text-xs ${avisoFirma.tipo === "ok" ? "text-verde" : "text-rojo"}`}>{avisoFirma.texto}</p>
        )}
        <FirmaEditor
          supabase={supabase}
          nombreOficial={yo.nombreOficial}
          avisar={(tipo, texto) => setAvisoFirma({ tipo, texto })}
          onGuardada={setMiFirma}
        />

        {/* Aparte de "Guardar firma" de arriba a propósito: guardar la firma
            solo configura la imagen (reusable en cualquier documento futuro);
            esto confirma que ESA imagen va en ESTE contrato puntual —y, la
            primera vez, lo firma (0430)—, y lo dice en admin/contratos, en
            la lista y al abrir el documento. */}
        <div className="mt-3 border-t border-sand pt-3">
          {contrato.firma_persona_confirmada_at ? (
            <p className="mb-2 text-xs text-verde">
              Confirmaste tu firma en este contrato el{" "}
              {new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric" })
                .format(new Date(contrato.firma_persona_confirmada_at))}.
              {" "}Si cambiaste tu firma después, vuelve a confirmar para que se actualice acá.
            </p>
          ) : (
            <p className="mb-2 text-xs text-taupe">Todavía no confirmaste tu firma en este contrato.</p>
          )}
          <button
            onClick={() => void confirmarFirma()}
            disabled={confirmando || !miFirma}
            className="rounded-lg bg-tinta px-3 py-1.5 text-xs font-medium text-crema disabled:opacity-40"
          >
            {confirmando
              ? "Confirmando…"
              : contrato.firma_persona_confirmada_at
                ? "Confirmar mi firma aquí"
                : "Firmar este contrato"}
          </button>
        </div>
      </div>

      {/* ── ¿ALGO ESTÁ MAL? (0427) ─────────────────────────────────────────
          Mismo mecanismo que «¿Algo cambió?» en /mio/movilidad, pero SIN su
          candado: acá no hay un estado "vigente y al día" que bloquee nada
          —confirmar tu firma se puede repetir cuando sea (0406)— así que esto
          es simplemente el canal para avisar de un dato del contrato (fecha,
          sueldo, cargo) que está mal, con acceso directo a ver qué dice el
          documento hoy antes de escribir el motivo. */}
      <div className="mb-4 rounded-lg border border-sand p-4 print:hidden">
        <h2 className="mb-1 font-serif text-base">¿Algo está mal en tu contrato?</h2>
        <p className="mb-3 text-xs text-taupe">
          Si una fecha, tu sueldo o tu cargo no coinciden con lo que se acordó, avisa acá y Desarrollo
          Organizacional lo revisa. Revisa primero{" "}
          <a href="#documento" className="text-taupe underline hover:text-tinta">
            qué dice el documento aquí abajo
          </a>
          {contrato.storage_path && (
            <>
              {" "}—o el{" "}
              <button onClick={() => void verEscaneado()} className="text-taupe underline hover:text-tinta">
                escaneado firmado
              </button>
              {" "}que también tienes
            </>
          )}
          .
        </p>

        {avisoRevision && (
          <p className={`mb-3 text-xs ${avisoRevision.tipo === "ok" ? "text-verde" : "text-rojo"}`}>
            {avisoRevision.texto}
          </p>
        )}

        {miRevision && !miRevision.atendida_at ? (
          <div className="rounded-lg border border-tinta/20 px-3 py-2 text-xs">
            <p className="text-taupe">Pediste una revisión:</p>
            <p className="mt-1">«{miRevision.motivo}»</p>
            <p className="mt-2 text-taupe">Todavía sin responder.</p>
          </div>
        ) : (
          <>
            {miRevision?.atendida_at && (
              <p className="mb-3 rounded-lg bg-verde/10 px-3 py-2 text-xs text-verde">
                Tu pedido anterior («{miRevision.motivo}») quedó respondido:{" "}
                {miRevision.respuesta ?? "sin comentario"}
              </p>
            )}
            {formRevisionAbierto ? (
              <div>
                <AreaTexto
                  value={motivoRevision}
                  onChange={(e) => setMotivoRevision(e.target.value)}
                  rows={2}
                  placeholder="Ej. mi sueldo aparece distinto al acordado"
                />
                <div className="mt-2 flex items-center gap-3">
                  <Boton variante="primario" tamano="sm" cargando={enviandoRevision}
                    onClick={() => void pedirRevision()}>
                    Pedir revisión
                  </Boton>
                  <Boton variante="secundario" tamano="sm" onClick={() => setFormRevisionAbierto(false)}>
                    Cancelar
                  </Boton>
                </div>
              </div>
            ) : (
              <Boton variante="secundario" tamano="sm" onClick={() => setFormRevisionAbierto(true)}>
                Pedir revisión
              </Boton>
            )}
          </>
        )}
      </div>

      <div
        id="documento"
        className="hoja rounded-lg border border-sand p-8 text-sm leading-relaxed print:rounded-none print:border-0 print:p-0"
        dangerouslySetInnerHTML={{ __html: html }}
      />
    </main>
  );
}

export default function MiContratoPage() {
  return <MiContratoContenido />;
}
