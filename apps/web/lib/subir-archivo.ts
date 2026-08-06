import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * SUBIR UN ARCHIVO A UN BUCKET PRIVADO, CON AVANCE Y CON IDENTIDAD.
 *
 * PROMETE: deja el archivo en `bucket/ruta` firmando el envío con la sesión de
 *   quien está usando el panel, e informa el porcentaje mientras sube.
 *   Devuelve `null` si quedó guardado, o un texto en español explicando el
 *   fallo. Nunca lanza.
 * ASUME: hay sesión abierta. Quién puede escribir lo decide la política del
 *   bucket en la base, no esta función.
 * NO HACE: no registra nada en ninguna tabla. Eso es de quien la llama.
 *
 * ── POR QUÉ EXISTE ──────────────────────────────────────────────────────────
 * Las tres pantallas que suben papeles (el cargo de un memo, el comprobante de
 * educación, el documento firmado) usaban `createSignedUploadUrl` y luego un
 * PUT crudo a esa URL. Ese camino NO lleva la identidad de quien sube: el SDK
 * pega el archivo en `/object/upload/sign/…?token=…` y el token solo dice "esta
 * ruta puede recibir un archivo", no "la sube Felipe".
 *
 * Y las políticas de los tres buckets preguntan justamente por la persona
 * (`fn_es_admin_o_lider()`, `fn_expediente_puede_adjuntar()`). Sin identidad esas
 * funciones devuelven falso y Postgres rechaza la fila con «new row violates
 * row-level security policy». Medido contra el Postgres local el 2026-08-06:
 * el mismo INSERT pasa con el JWT del admin y se rechaza sin él.
 *
 * Se eligió mandar el archivo con XHR y no con `supabase.storage.upload()`
 * porque el SDK no informa el avance: un escaneo de 8 MB por la conexión de una
 * tienda deja la pantalla muda un minuto largo, y una espera muda se lee como
 * que el sistema se colgó. El formato del envío —POST a `/object/{bucket}/…`,
 * FormData con `cacheControl` y el archivo, cabeceras `apikey` y
 * `Authorization`— es el mismo que arma el SDK.
 */
export async function subirArchivoConProgreso(
  supabase: SupabaseClient,
  bucket: string,
  ruta: string,
  archivo: File,
  alAvanzar: (pct: number) => void,
): Promise<string | null> {
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!base || !anon) return "el sistema no tiene configurado el almacén de archivos";

  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) return "tu sesión caducó; vuelve a entrar y repite la subida";

  // Cada tramo por separado: un nombre con espacios o acentos no debe partir la ruta.
  const rutaUrl = ruta.split("/").map(encodeURIComponent).join("/");

  return new Promise((resolver) => {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", `${base}/storage/v1/object/${bucket}/${rutaUrl}`);
    xhr.setRequestHeader("apikey", anon);
    xhr.setRequestHeader("authorization", `Bearer ${token}`);
    xhr.setRequestHeader("x-upsert", "true");
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) alAvanzar(Math.round((e.loaded / e.total) * 100));
    };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) { resolver(null); return; }
      // El almacén contesta con un JSON que explica el rechazo. Vale más ese
      // texto que un número de estado: «row-level security» dice que falta un
      // permiso, y «Payload too large» que el archivo no cabe.
      let detalle = xhr.status === 413
        ? "el archivo pasa el tope global del proyecto"
        : `el servidor respondió ${xhr.status}`;
      try {
        const cuerpo = JSON.parse(xhr.responseText) as { message?: string; error?: string };
        if (cuerpo.message || cuerpo.error) detalle = cuerpo.message ?? cuerpo.error!;
      } catch { /* respuesta sin JSON: nos quedamos con el código */ }
      resolver(detalle);
    };
    xhr.onerror = () => resolver("se cortó la conexión durante la subida");
    xhr.onabort = () => resolver("la subida se canceló");

    const cuerpo = new FormData();
    cuerpo.append("cacheControl", "3600");
    cuerpo.append("", archivo);
    xhr.send(cuerpo);
  });
}
