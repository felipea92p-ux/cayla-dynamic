"use client";

import { useEffect, useState, type ReactNode } from "react";
import type { ClienteCayla, Database } from "@cayla-dynamic/database";
import { EMPRESA, TIPO_DOCUMENTO_LABEL, esTipoDocumento, fechaLima, horaLima } from "@cayla-dynamic/shared";
import type { Constancia } from "@/components/boletas/constancia-de-firma";
import type { TipoBoleta } from "@/lib/boletas";
import type { HojaFirmada } from "@/lib/boletas-archivos";
import { abrirPdf, dibujarPagina } from "@/lib/admin/constancia-medios";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";

/**
 * LA BOLETA FIRMADA COMO UN SOLO DOCUMENTO (2026-10-17).
 *
 * Hasta acá DO veía la boleta en un recuadro y la firma en otro, y no había
 * forma de llevarse las dos juntas: si el contador pedía la prueba de que una
 * persona recibió su boleta, había que mandarle dos cosas y explicarle que iban
 * juntas. Esto las pone en una hoja: quién es (nombre y DNI), de qué periodo,
 * cuándo se pagó, cuándo firmó y a qué hora, la boleta misma y, debajo, la
 * firma. Es lo que se ve en el modal y lo que sale al guardar el PDF.
 *
 * TODO SALE DE LA BASE, nada se le pide a la persona. Su DNI ya está en su
 * ficha, la fecha de pago es la del grupo de pago del periodo y la hora es la
 * del acuse: pedirle que los escriba al firmar solo abriría la puerta a que los
 * escriba distinto.
 *
 * LO QUE DICE DE LA FIRMA ES LO QUE PASÓ, no una declaración que nadie leyó. La
 * persona no firmó un texto: firmó la boleta, y al firmarla la dio por recibida
 * (`fn_boleta_firmar`, 0532). Eso es lo que la hoja afirma, con la hora de Lima.
 *
 * Se dibuja dos veces con los mismos datos: en el modal (`enPapel` falso) y en
 * la copia que se imprime (`enPapel`). Por eso no carga nada por su cuenta: lo
 * que necesita lo traen `useDatosDeConstancia` y `usePaginasDeBoleta`, y quien
 * la arma entera —para DO y para la persona— es `useConstanciaDescargable`.
 */

export type PaginaDeBoleta = {
  /** Lo que se dibuja: la foto, o la página del PDF ya convertida en imagen. */
  src: string;
  alt: string;
  /** Lo que se abre al tocarla: la foto, o el PDF entero. */
  original: string;
};

export type DatosDeConstancia = {
  /** El nombre de la ficha (nombres y apellidos). */
  nombre: string;
  /** Como figura en su DNI (`datos_personales.nombre_dni`); `null` si DO no lo registró. */
  nombreDni: string | null;
  documento: string | null;
  /** `dni`, `ce` o `pasaporte` (0513). */
  tipoDocumento: string | null;
  sede: string | null;
  cargo: string | null;
  /** Cuándo se pagó el grupo de la persona (planilla, RxH…) en ese periodo. */
  pagadoAt: string | null;
  /** `false` si la base no contestó y la hoja se armó con lo que la pantalla ya sabía. */
  completos: boolean;
};

type FilaDeDatos = Database["public"]["Functions"]["fn_boleta_datos_de_constancia"]["Returns"][number];

/**
 * Lo que la hoja dice de la persona, de `fn_boleta_datos_de_constancia` (0533).
 * DO y la persona preguntan a la MISMA función, así «qué dice la constancia de
 * Ana» tiene una sola respuesta. `datos` es `null` mientras carga; con
 * `versionId` en `null` no pide nada.
 *
 * Si la base no contesta, la hoja se arma con `respaldo` —lo que la pantalla ya
 * sabe— y `aviso` lo dice: un «—» no se presenta como si el dato no existiera
 * cuando en realidad no se pudo leer. Y así no se descarga (`completos`).
 */
export function useDatosDeConstancia(
  supabase: ClienteCayla,
  versionId: string | null,
  respaldo: { nombre: string; sede: string | null; cargo: string | null },
): { datos: DatosDeConstancia | null; aviso: string | null } {
  const [leido, setLeido] = useState<{ fila: FilaDeDatos | null } | null>(null);

  useEffect(() => {
    if (!versionId) return;
    let vigente = true;
    void supabase.rpc("fn_boleta_datos_de_constancia", { p_version_id: versionId }).then(({ data, error }) => {
      if (vigente) setLeido({ fila: error ? null : (data ?? [])[0] ?? null });
    });
    return () => { vigente = false; };
  }, [supabase, versionId]);

  if (leido === null) return { datos: null, aviso: null };
  const f = leido.fila;
  if (f) {
    return {
      datos: {
        nombre: f.nombre, nombreDni: f.nombre_dni ?? null, documento: f.documento ?? null,
        tipoDocumento: f.tipo_documento ?? null, sede: f.sede_codigo ?? null, cargo: f.cargo ?? null,
        pagadoAt: f.pagado_at ?? null, completos: true,
      },
      aviso: null,
    };
  }
  return {
    datos: {
      nombre: respaldo.nombre, nombreDni: null, documento: null, tipoDocumento: null,
      sede: respaldo.sede, cargo: respaldo.cargo, pagadoAt: null, completos: false,
    },
    aviso: "No pudimos leer el documento de identidad ni la fecha de pago, y sin ellos la hoja no se descarga. Ciérrala y vuelve a abrirla en un momento.",
  };
}

/** Tope de páginas por PDF: una boleta tiene una o dos; más es un archivo equivocado. */
const MAX_PAGINAS_PDF = 8;

/**
 * Las hojas de la boleta, listas para ir dentro de un documento.
 *
 * Una FOTO va tal cual. Un PDF no se puede poner dentro de otra hoja, así que
 * cada página se dibuja con pdf.js (el mismo de Educación) y se guarda como
 * imagen: solo así la boleta en PDF también sale junto a la firma en el PDF que
 * se descarga. Si no se puede dibujar, se dice, y la boleta se abre aparte.
 */
export function usePaginasDeBoleta(hojas: readonly HojaFirmada[] | null, tipo: TipoBoleta) {
  const [paginas, setPaginas] = useState<PaginaDeBoleta[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!hojas) return;
    const total = hojas.length;
    if (tipo === "imagen") {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- las fotos no se procesan: se usan tal cual llegan
      setPaginas(hojas.map((h, i) => ({
        src: h.url,
        original: h.url,
        alt: total > 1 ? `Hoja ${i + 1} de ${total} de la boleta` : "Boleta de pago",
      })));
      return;
    }

    let vigente = true;
    void (async () => {
      const lista: PaginaDeBoleta[] = [];
      try {
        for (const [i, h] of hojas.entries()) {
          const abierto = await abrirPdf(h.url);
          try {
            const n = Math.min(abierto.pdf.numPages, MAX_PAGINAS_PDF);
            for (let p = 1; p <= n; p++) {
              const canvas = document.createElement("canvas");
              await dibujarPagina(abierto.pdf, p, canvas, 1000);
              lista.push({
                src: canvas.toDataURL("image/jpeg", 0.85),
                original: h.url,
                alt: `${total > 1 ? `Documento ${i + 1}, p` : "P"}ágina ${p} de ${abierto.pdf.numPages} de la boleta`,
              });
            }
          } finally {
            abierto.cerrar();
          }
        }
        if (vigente) setPaginas(lista);
      } catch {
        if (vigente) setError("No pudimos dibujar el PDF de la boleta dentro de la hoja. Ábrelo aparte.");
      }
    })();
    return () => { vigente = false; };
  }, [hojas, tipo]);

  return { paginas, error };
}

/** «07/10/2026» y «10:32», en hora de Lima. */
function fechaYHora(iso: string): { fecha: string; hora: string } {
  return { fecha: isoADiaMesAnio(fechaLima(iso)), hora: horaLima(iso) };
}

function Dato({ etiqueta, children, ancho = false }: { etiqueta: string; children: ReactNode; ancho?: boolean }) {
  return (
    <div className={ancho ? "col-span-2 sm:col-span-1" : undefined}>
      <dt className="text-[11px] uppercase tracking-wide text-taupe">{etiqueta}</dt>
      <dd className="mt-0.5 font-medium text-tinta">{children}</dd>
    </div>
  );
}

export function HojaConstanciaBoleta({
  periodo, version, datos, constancia, paginas, errorPaginas, pdfs, generadaAt, enPapel = false,
}: {
  periodo: { nombre: string; desde: string | null; hasta: string | null };
  version: number | null;
  datos: DatosDeConstancia;
  constancia: Constancia;
  /** `null` mientras se preparan. */
  paginas: readonly PaginaDeBoleta[] | null;
  errorPaginas: string | null;
  /** Las URL de los PDF originales, para abrirlos aparte si no se pudieron dibujar. */
  pdfs: readonly string[];
  generadaAt: string;
  /** La copia que se imprime: sin enlaces, sin avisos de pantalla y con las fotos a la medida de una A4. */
  enPapel?: boolean;
}) {
  // El nombre que firma es el del DNI, no el de uso diario (ver FirmaEditor).
  const nombre = datos.nombreDni?.trim() || datos.nombre;
  const tipoDoc = esTipoDocumento(datos.tipoDocumento) ? TIPO_DOCUMENTO_LABEL[datos.tipoDocumento] : "DNI";
  const documento = datos.documento?.trim() || "—";
  // «Sin registrar» solo si la base CONTESTÓ que no hay fecha; si no contestó, no se sabe.
  const pagado = datos.pagadoAt ? fechaYHora(datos.pagadoAt).fecha : datos.completos ? "Sin registrar" : "—";
  const recibida = constancia.recibida_at ? fechaYHora(constancia.recibida_at) : null;
  const generada = fechaYHora(generadaAt);
  const vista = constancia.vista_at ? fechaYHora(constancia.vista_at) : null;
  const total = paginas?.length ?? 0;
  // En A4 quedan 269 mm útiles: unos 60 para el encabezado y los datos y unos 55
  // para la firma. Una sola hoja tiene que caber con las dos en la MISMA página
  // —medido en el PDF: a 150 mm se iba todo a la página 2 y la primera quedaba
  // en blanco—; con varias, cada una va en su página y la firma sigue a la última.
  const altoEnPapel = total === 1 ? "135mm" : "200mm";

  return (
    <article
      className={`hoja constancia-boleta text-tinta ${enPapel ? "" : "rounded-xl border border-sand bg-papel p-5 sm:p-8"}`}
      aria-label="Constancia de recepción de boleta de pago"
    >
      <header className="border-b border-sand pb-4">
        <p className="text-[11px] uppercase tracking-wide text-taupe">{EMPRESA.nombre} · RUC {EMPRESA.ruc}</p>
        <h3 className="mt-1 font-serif text-xl font-medium leading-snug">Constancia de recepción de boleta de pago</h3>
        <p className="text-sm text-taupe">{periodo.nombre}</p>
      </header>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-3 py-4 text-sm sm:grid-cols-3">
        <Dato etiqueta="Integrante" ancho>{nombre}</Dato>
        <Dato etiqueta={tipoDoc}>{documento}</Dato>
        <Dato etiqueta="Sede">{datos.sede ?? "—"}{datos.cargo ? ` · ${datos.cargo}` : ""}</Dato>
        <Dato etiqueta="Periodo">
          {periodo.desde && periodo.hasta ? `${isoADiaMesAnio(periodo.desde)} al ${isoADiaMesAnio(periodo.hasta)}` : periodo.nombre}
        </Dato>
        <Dato etiqueta="Fecha de pago">{pagado}</Dato>
        <Dato etiqueta={constancia.firma ? "Firmada" : "Recibida"}>
          {recibida ? `${recibida.fecha} · ${recibida.hora}` : "—"}
        </Dato>
      </dl>

      <section className="border-t border-sand pt-4">
        <p className="rotulo-boleta mb-2 text-[11px] uppercase tracking-wide text-taupe">
          Boleta de pago{version ? ` · versión ${version}` : ""}
        </p>
        {errorPaginas ? (
          <div className="rounded-lg border border-sand px-4 py-3 text-sm">
            {enPapel ? (
              <p>La boleta es un PDF que no se pudo incluir en esta hoja: se entrega aparte.</p>
            ) : (
              <>
                <p role="alert" className="text-rojo-profundo">{errorPaginas}</p>
                <div className="mt-2 flex flex-wrap gap-2">
                  {pdfs.map((url, i) => (
                    <a key={url} href={url} target="_blank" rel="noopener noreferrer"
                      className="rounded-lg border border-taupe px-3 py-1.5 text-tinta hover:bg-hueso">
                      Abrir PDF{pdfs.length > 1 ? ` ${i + 1}` : ""}
                    </a>
                  ))}
                </div>
              </>
            )}
          </div>
        ) : paginas === null ? (
          <p className="py-6 text-center text-sm text-taupe">Preparando la boleta…</p>
        ) : (
          <div className="space-y-3">
            {paginas.map((p, i) => (
              <div key={i} className="pagina-boleta">
                {enPapel ? (
                  // eslint-disable-next-line @next/next/no-img-element -- imagen de un bucket privado o dibujada aquí
                  <img src={p.src} alt={p.alt} className="mx-auto block h-auto w-auto max-w-full" style={{ maxHeight: altoEnPapel }} />
                ) : (
                  <a href={p.original} target="_blank" rel="noopener noreferrer" title="Abrir en tamaño completo"
                    className="block overflow-hidden rounded-lg border border-sand bg-hueso">
                    {/* eslint-disable-next-line @next/next/no-img-element -- imagen de un bucket privado o dibujada aquí */}
                    <img src={p.src} alt={p.alt} className="mx-auto block h-auto max-h-[70vh] w-auto max-w-full cursor-zoom-in" />
                  </a>
                )}
              </div>
            ))}
            {!enPapel && <p className="text-xs text-taupe">Toca la boleta para abrirla en tamaño completo.</p>}
          </div>
        )}
      </section>

      <section className={`bloque-firma border-t border-sand ${enPapel ? "mt-3 pt-3" : "mt-6 pt-6"}`}>
        {constancia.firma ? (
          <div
            className={`mx-auto flex w-full max-w-sm flex-col items-center rounded-lg px-4 ${enPapel ? "pt-1" : "border border-sand pb-3 pt-4"}`}
            // Tinta oscura sobre fondo transparente: sobre el modo oscuro la firma
            // desaparecería. Es un papel, y un papel no se oscurece (ver ConstanciaDeFirma).
            style={enPapel ? undefined : { background: "var(--color-crema-fija)", color: "var(--color-tinta-fija)" }}
          >
            {/* eslint-disable-next-line @next/next/no-img-element -- la firma viene como data URL de la base */}
            <img src={constancia.firma} alt={`Firma de ${nombre}`} className={`w-auto max-w-full ${enPapel ? "max-h-16" : "max-h-20"}`} />
            <span className="mt-1 block w-full border-t" style={{ borderColor: "var(--color-tinta-fija)" }} />
            <span className="mt-1.5 text-center text-sm font-medium">{nombre}</span>
            <span className="text-xs">{tipoDoc} {documento}</span>
          </div>
        ) : (
          <p className="mx-auto max-w-md text-center text-sm">
            {nombre} confirmó que la recibió{recibida ? ` el ${recibida.fecha} a las ${recibida.hora}` : ""}, antes de que
            las boletas se firmaran. Esa confirmación no lleva firma.
          </p>
        )}
        {constancia.firma && recibida && (
          <p className={`mx-auto max-w-md text-center text-xs text-taupe ${enPapel ? "mt-2" : "mt-4"}`}>
            Firmó esta boleta en Dynamic el {recibida.fecha} a las {recibida.hora} (hora de Lima), con la firma que tenía
            guardada ese día. Al firmarla, la dio por recibida.
          </p>
        )}
      </section>

      <footer className={`border-t border-sand text-[11px] text-taupe ${enPapel ? "mt-3 pt-2" : "mt-6 pt-3"}`}>
        Hoja generada por Dynamic el {generada.fecha} a las {generada.hora}.
        {vista ? ` La abrió por primera vez el ${vista.fecha} a las ${vista.hora}.` : ""}
      </footer>
    </article>
  );
}
