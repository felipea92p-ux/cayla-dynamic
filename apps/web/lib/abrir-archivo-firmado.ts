import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * ABRIR UN PAPEL GUARDADO EN UN BUCKET PRIVADO, SIN QUE EL NAVEGADOR LO BLOQUEE.
 *
 * PROMETE: deja el archivo abierto en una pestaña nueva. Devuelve `null` si lo
 *   consiguió, o un texto en español explicando qué pasó. Nunca lanza.
 * ASUME: hay sesión abierta y quien mira tiene permiso — eso lo decide la
 *   política del bucket en la base, no esta función.
 * NO HACE: no descarga nada ni guarda el archivo. Solo lo abre.
 *
 * ── POR QUÉ EXISTE ──────────────────────────────────────────────────────────
 * Las seis pantallas que muestran papeles hacían lo obvio: pedir la URL firmada
 * y, cuando llega, `window.open`. Eso falla A RATOS, y esa intermitencia es lo
 * peor que tiene: el navegador solo deja abrir una pestaña MIENTRAS dura el
 * gesto de la persona que hizo clic, y esperar la firma se come ese permiso. Si
 * la respuesta llega rápida, a veces alcanza; si tarda, el navegador lo trata
 * como una ventana emergente y lo bloquea sin decir nada.
 *
 * Reportado el 2026-08-24 en «Ver» de /admin/educacion, con esas palabras:
 * «algunas veces funciona y otras no». No era el archivo ni el permiso.
 *
 * Acá la pestaña se abre PRIMERO, vacía, dentro del clic —que es cuando el
 * permiso existe— y se la manda a la dirección cuando la firma llega.
 *
 * `opener = null` a mano en vez de la opción `noopener` de `window.open`: con
 * esa opción la función devuelve `null` a propósito (no hay referencia que
 * devolver), y entonces no habría a quién darle la dirección después. La
 * protección es la misma; el camino, otro.
 *
 * Si aun así el navegador bloquea la pestaña —hay quien tiene las emergentes
 * desactivadas del todo—, se devuelve un mensaje que dice exactamente eso, en
 * vez de dejar a la persona mirando una pantalla donde no pasó nada.
 */
export async function abrirArchivoFirmado(
  supabase: SupabaseClient,
  bucket: string,
  ruta: string,
  segundos = 60,
): Promise<string | null> {
  const pestana = window.open("about:blank", "_blank");
  if (pestana) pestana.opener = null;

  const { data, error } = await supabase.storage.from(bucket).createSignedUrl(ruta, segundos);

  if (error || !data) {
    pestana?.close();
    return `No se pudo abrir el archivo: ${error?.message ?? "sin URL"}`;
  }

  if (!pestana) {
    return "El navegador bloqueó la ventana del archivo. Permite las ventanas emergentes para este sitio y vuelve a intentarlo.";
  }

  pestana.location.href = data.signedUrl;
  return null;
}
