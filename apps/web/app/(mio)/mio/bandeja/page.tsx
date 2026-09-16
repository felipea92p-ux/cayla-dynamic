"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";
import { Cargando, SinDatos } from "@/components/cargando";
import { Insignia } from "@/components/ui/insignia";
import {
  DIAS_NOVEDAD, diaYMes, traerBandeja,
  type Bandeja, type EstadoBandeja, type MensajeBandeja,
} from "@/lib/bandeja-mia";

/**
 * «Bandeja» — el buzón de respuestas de cada persona.
 *
 * QUÉ PROBLEMA RESUELVE
 *
 * Hasta hoy, cuando Desarrollo Organizacional aprobaba o rechazaba algo, la
 * persona no se enteraba: tenía que acordarse de volver a la pantalla donde lo
 * había pedido. El rechazo de un cambio de cuenta bancaria —con su motivo, que
 * es lo único que dice qué corregir— vivía enterrado al final del formulario de
 * /mio/editar. Lo mismo con las vacaciones y con los pedidos de revisar un día.
 *
 * Esta pantalla junta las tres en un hilo. Las REGLAS (qué es una respuesta,
 * qué es novedad, cómo se ordenan) viven en lib/bandeja-mia.ts, con sus
 * pruebas, porque el contador del botón de /mio sale de esa misma función: dos
 * sitios contando lo mismo por su cuenta es el defecto que este repositorio ya
 * persiguió cuatro veces en el SQL.
 *
 * QUÉ NO ESTÁ ACÁ, Y ES A PROPÓSITO
 *
 * Los acuses pendientes, los anuncios y «Necesita que hagas algo» siguen
 * pintándose en la portada de /mio. No son respuestas: son cosas que ella tiene
 * que hacer, y el aviso de marcaje incompleto además tiene plazo (se arregla
 * mientras el periodo sigue abierto). Esconderlo detrás de un clic lo volvería
 * más fácil de perder, no menos.
 *
 * Y la sesión se resuelve ACÁ, por `auth_user_id`, sin depender de que /mio ya
 * la haya cargado — mismo criterio que /mio/editar, /mio/boleta y /mio/contrato.
 */

const TONO: Record<EstadoBandeja, "positivo" | "alerta" | "informativo" | "advertencia"> = {
  aprobado: "positivo",
  rechazado: "alerta",
  // Una revisión no se aprueba ni se rechaza: se contesta qué se hizo.
  atendido: "informativo",
  pendiente: "informativo",
  // Los dos que dependen de ella van en ámbar, el tono de «esto te toca a ti»
  // que ya usa el recuadro «Necesita que hagas algo» de /mio. No en rojo: el
  // rojo es el acento sagrado de esta casa y lo gastan los errores, no las
  // tareas — y un contrato sin firmar no es un error de nadie todavía.
  por_firmar: "advertencia",
  por_arreglar: "advertencia",
};

const ETIQUETA: Record<EstadoBandeja, string> = {
  aprobado: "aprobado",
  rechazado: "rechazado",
  atendido: "revisado",
  pendiente: "sin respuesta",
  por_firmar: "falta tu firma",
  por_arreglar: "por arreglar",
};

/** «7 de setiembre», y con año cuando no es el de hoy: «25 de junio de 2025». */
function cuandoFue(fecha: string, hoy: string): string {
  const dia = diaYMes(fecha);
  return fecha.slice(0, 4) === hoy.slice(0, 4) ? dia : `${dia} de ${fecha.slice(0, 4)}`;
}

/** Qué salió de cargar la pantalla. Lo decide el efecto, no el cargador. */
type Resultado =
  | { tipo: "ok"; bandeja: Bandeja; noSePudo: string[] }
  | { tipo: "error"; texto: string }
  | { tipo: "sin-sesion" };

/** Los dos estados que dependen de ella. Se pregunta por el estado y no por la
 *  lista en la que vino: una tarjeta tiene que poder pintarse sola. */
function esPendiente(m: MensajeBandeja): boolean {
  return m.estado === "por_firmar" || m.estado === "por_arreglar";
}

function Tarjeta({ m, hoy }: { m: MensajeBandeja; hoy: string }) {
  return (
    // Los pendientes llevan el borde ámbar del recuadro «Necesita que hagas
    // algo» de /mio: es la misma clase de cosa y se reconoce sin leerla.
    <li className={esPendiente(m)
      ? "rounded-2xl border border-ambar/40 bg-ambar/[0.07] p-4"
      : "rounded-2xl border border-sand bg-papel p-4"}>
      <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1.5">
        <strong className="text-sm font-medium">{m.titulo}</strong>
        <span className="flex shrink-0 items-center gap-1.5">
          {/* «nuevo» solo tiene sentido frente a algo que NO lo es. En la lista
              de pendientes todos lo llevarían, así que ahí no dice nada. */}
          {m.nuevo && !esPendiente(m) && <Insignia variante="contador" tamano="sm">nuevo</Insignia>}
          <Insignia variante={TONO[m.estado]} tamano="sm">{ETIQUETA[m.estado]}</Insignia>
        </span>
      </div>

      {!esPendiente(m) && m.estado !== "pendiente" && (
        <p className="mt-1 text-xs text-taupe">Te respondieron el {cuandoFue(m.fecha, hoy)}.</p>
      )}

      {/* Lo que escribió Desarrollo Organizacional, entero y sin recortar: en un
          rechazo es lo único que le dice qué corregir para volver a intentarlo. */}
      {m.respuesta && (
        <p className="mt-2 rounded-lg bg-hueso px-3 py-2 text-sm whitespace-pre-line">«{m.respuesta}»</p>
      )}

      {m.detalle && <p className="mt-1.5 text-xs text-taupe">{m.detalle}</p>}

      {m.ir && (
        <Link href={m.ir} className="mt-2 inline-block text-xs text-tinta underline underline-offset-2 hover:text-rojo-profundo">
          {esPendiente(m) ? "Hacerlo →" : "Verlo →"}
        </Link>
      )}
    </li>
  );
}

export default function MiBandejaPage() {
  const router = useRouter();
  const supabase = createAdminSupabaseClient();

  const [bandeja, setBandeja] = useState<Bandeja | null>(null);
  const [noSePudo, setNoSePudo] = useState<string[]>([]);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [hoy] = useState(hoyLima);

  // El cargador NO toca estado: devuelve qué pasó y el efecto decide. Así la
  // pantalla no llama a setState de forma síncrona dentro del efecto (lo que
  // encadena renders, y el linter de este repo bloquea), y de paso el orden
  // «primero averiguar, después pintar» queda en un solo sitio legible.
  const cargar = useCallback(async (): Promise<Resultado> => {
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) return { tipo: "sin-sesion" };

    const { data: sesionAuth } = await supabase.auth.getUser();
    const uid = sesionAuth.user?.id;
    if (!uid) return { tipo: "error", texto: "No se pudo leer tu sesión. Vuelve a entrar." };

    const { data: p } = await supabase
      .from("personas").select("id").eq("auth_user_id", uid).maybeSingle();
    if (!p) {
      return {
        tipo: "error",
        texto: "Tu cuenta todavía no está enlazada con tu ficha. Avisa a Desarrollo Organizacional.",
      };
    }

    const { bandeja: b, noSePudo: falta } = await traerBandeja(supabase, p.id as string, hoy);
    return { tipo: "ok", bandeja: b, noSePudo: falta };
  }, [supabase, hoy]);

  useEffect(() => {
    let vivo = true;
    void cargar().then((r) => {
      if (!vivo) return;
      if (r.tipo === "sin-sesion") { router.replace("/mio"); return; }
      if (r.tipo === "error") { setError(r.texto); setCargando(false); return; }
      setBandeja(r.bandeja);
      setNoSePudo(r.noSePudo);
      setCargando(false);
    });
    return () => { vivo = false; };
  }, [cargar, router]);

  // Marca como vistas (bandeja_vistos, 0436/0473) las respuestas que se
  // acaban de pintar como «nuevo», para que la próxima vez que abra la
  // Bandeja ya no lo estén — sin que dependa de que apriete «Verlo →», que ni
  // siquiera existe para vacaciones o para un día revisado. Mismo patrón que
  // ya usa /admin/bandeja: se dispara una vez por carga, en cuanto cambia la
  // referencia de `bandeja`, nunca en cada render.
  useEffect(() => {
    if (!bandeja) return;
    for (const m of bandeja.respuestas) {
      if (m.nuevo && m.marcarVistoComo) {
        void supabase.rpc("fn_bandeja_marcar_visto", {
          p_tipo_item: m.marcarVistoComo.tipo,
          p_item_id: m.marcarVistoComo.itemId,
        });
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- una vez por carga, no por cada render.
  }, [bandeja]);

  return (
    <main className="mx-auto min-h-screen w-full max-w-2xl bg-crema px-5 py-8 text-tinta">
      <Link href="/mio" className="text-sm text-taupe hover:text-tinta hover:underline">
        ← Volver a Info
      </Link>

      <h1 className="mt-3 font-serif text-2xl">Bandeja</h1>
      <p className="mt-1 mb-6 text-sm text-taupe">
        Lo que te falta hacer y lo que te respondieron: tu contrato, los documentos por firmar, tus
        cambios de ficha, tus vacaciones y tus pedidos de revisar un día.
      </p>

      {cargando && <Cargando texto="Cargando tu bandeja…" />}

      {error && (
        <p className="rounded-2xl border border-rojo/30 bg-rojo/[0.06] p-4 text-sm text-tinta">{error}</p>
      )}

      {/* Una consulta que falló y se pinta como lista vacía dice «no tienes
          mensajes». Eso es una afirmación, no un hueco — y acá el hueco puede
          ser el rechazo que ella está esperando. */}
      {noSePudo.length > 0 && (
        <div className="mb-6 rounded-2xl border border-rojo/30 bg-rojo/[0.06] p-4 text-sm">
          <div className="font-medium text-rojo-profundo">No se pudo traer tu bandeja completa</div>
          <p className="mt-1 text-tinta">
            Falta {noSePudo.join(", ")}. Vuelve a cargar la página; si sigue igual, avisa a
            Desarrollo Organizacional.
          </p>
        </div>
      )}

      {bandeja && (
        <>
          {bandeja.pendientes.length === 0 && bandeja.respuestas.length === 0 && bandeja.esperando.length === 0 && noSePudo.length === 0 && (
            <SinDatos
              texto="Todavía no tienes nada en la bandeja."
              pista="Acá aparecen las respuestas a lo que pidas: un cambio en tu ficha, tus vacaciones o que se revise un día tuyo."
            />
          )}

          {/* PRIMERO lo que depende de ella. Es lo único de esta pantalla que
              tiene consecuencias si nadie lo toca. */}
          {bandeja.pendientes.length > 0 && (
            <section className="mb-8">
              <h2 className="mb-1 font-serif text-lg">Necesita que hagas algo</h2>
              <p className="mb-3 text-xs text-taupe">
                Esto no se va solo con el tiempo: sigue acá hasta que lo firmes o lo arregles.
              </p>
              <ul className="space-y-3">
                {bandeja.pendientes.map((m) => <Tarjeta key={m.clave} m={m} hoy={hoy} />)}
              </ul>
            </section>
          )}

          {bandeja.respuestas.length > 0 && (
            <section className="mb-8">
              <h2 className="mb-1 font-serif text-lg">Te respondieron</h2>
              <p className="mb-3 text-xs text-taupe">
                Lo marcado como «nuevo» se respondió en los últimos {DIAS_NOVEDAD} días.
              </p>
              <ul className="space-y-3">
                {bandeja.respuestas.map((m) => <Tarjeta key={m.clave} m={m} hoy={hoy} />)}
              </ul>
            </section>
          )}

          {bandeja.esperando.length > 0 && (
            <section>
              <h2 className="mb-1 font-serif text-lg">Esperando respuesta</h2>
              <p className="mb-3 text-xs text-taupe">
                Lo que pediste y todavía nadie contestó, empezando por lo que lleva más tiempo.
              </p>
              <ul className="space-y-3">
                {bandeja.esperando.map((m) => <Tarjeta key={m.clave} m={m} hoy={hoy} />)}
              </ul>
            </section>
          )}
        </>
      )}
    </main>
  );
}
