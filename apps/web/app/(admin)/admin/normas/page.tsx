"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { usePersonaActual } from "@/lib/admin/use-rol";
import { useTituloDocumento } from "@/lib/admin/use-titulo-documento";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { subirArchivoConProgreso } from "@/lib/subir-archivo";
import { abrirArchivoFirmado } from "@/lib/abrir-archivo-firmado";
import { TZ_LIMA, hoyLima } from "@cayla-dynamic/shared";
import { Documento } from "@/components/documento";

// Normas: los documentos que rigen para todo el equipo, y la prueba de que se
// entregaron.
//
// POR QUÉ EXISTE ESTA PANTALLA. El Reglamento Interno promete que se entrega
// «dejando constancia escrita de su recepción», y el D.S. 039-91-TR da cinco
// días naturales para esa entrega. Hasta hoy el reglamento vivía en un enlace
// de Drive —que además se cayó— y no había forma de probar quién recibió qué.
//
// Y hay algo que esto hace y el papel no puede: un cargo firmado a mano dice
// que recibiste UN reglamento; no dice cuál versión. El día que una versión
// sustituya a otra, esa es exactamente la diferencia que importa.
//
// POR QUÉ DOS VÍAS DE CONSTANCIA. Medido en producción el 2026-08-10: de 24
// personas activas, 17 tienen cuenta y 7 no. Casi un tercio del equipo no puede
// entrar al panel. Una pantalla que solo admitiera el acuse propio dejaría la
// prueba incompleta justo donde más se mira, así que DO puede registrar la
// constancia en papel de quien no tiene cuenta, con el cargo escaneado.
//
// POR QUÉ NO TODO DOCUMENTO PIDE CONSTANCIA. El reglamento y la política
// salarial crean obligaciones y la ley exige poder probar que se informaron.
// La presentación de la empresa no crea ninguna. Pedir acuse por ella enseñaría
// que el acuse es trámite, y el día que llegue el reglamento nadie lo leería.
// Lo decide `documentos_tipos.requiere_acuse`, que se administra en la base.

const DO = ["admin", "lider_do"];
const MAX_BYTES_CARGO = 50 * 1024 * 1024;
const TIPOS_CARGO = "image/jpeg,image/png,image/heic,image/webp,application/pdf";

interface Doc {
  documento_id: string;
  tipo: string;
  tipo_nombre: string;
  /** Cuántas veces se ha publicado este tipo en el sistema. Dato técnico. */
  version: number;
  /**
   * La versión que el DOCUMENTO declara en su propio texto — «4.0».
   *
   * Es la que aparece en el cargo que la integrante firma, y por eso es la que
   * manda en pantalla. Antes solo existía el correlativo, y con el Reglamento
   * 4.0 publicado como `version = 1` el legajo de papel y la base no se podían
   * cruzar sin abrir el texto congelado y leerlo. Es opcional: un documento sin
   * versión editorial es legítimo, y entonces se muestra solo el correlativo.
   */
  etiqueta_version: string | null;
  titulo: string;
  documento: string;
  vigente_desde: string;
  publicado_at: string;
  requiere_acuse: boolean;
  mi_acuse_at: string | null;
  total_acuses: number;
  poblacion: number;
}

interface FilaAcuse {
  persona_id: string;
  nombre: string;
  sede: string;
  tiene_cuenta: boolean;
  acusado_at: string | null;
  via: string | null;
  /**
   * La ruta REAL del cargo escaneado, tal como la guardó el registro.
   *
   * No viene de `fn_acuses_documento` —que no la devuelve— sino de una consulta
   * aparte a `documentos_acuses`. Antes se reconstruía a mano como
   * «documento/persona» y eso NUNCA podía funcionar: al subir, la clave lleva
   * sello de tiempo y extensión, y `createSignedUrl` exige la clave exacta. O
   * sea que todos los cargos archivados fallaban con «Object not found»,
   * incluidos los subidos un minuto antes. Es la única prueba que tienen las
   * integrantes sin cuenta: se guardaba bien y no se podía recuperar.
   */
  storage_path: string | null;
}

interface Tipo {
  codigo: string;
  nombre: string;
  requiere_acuse: boolean;
}

/**
 * Qué es principal y qué es anexo.
 *
 * No es cosmética: el artículo 47 del Reglamento dice que los documentos
 * complementarios «tienen finalidad informativa» y que «en caso de discrepancia
 * prevalece este Reglamento». Si los seis aparecieran al mismo nivel, la
 * pantalla estaría diciendo lo contrario que el articulado, y quien la mire
 * creerá lo que ve antes que lo que lee.
 *
 * La lista vive acá y no en la base a propósito: es una decisión de jerarquía
 * normativa, no un dato que DO deba poder cambiar desde una pantalla.
 */
const PRINCIPALES = ["rit"];

/** Un reglamento de 61 artículos pesa cerca de 300 KB. El tope es generoso a
 *  propósito, pero existe: sin él, un archivo equivocado se sube entero antes
 *  de que nadie note que no era un documento. */
const MAX_BYTES_DOC = 2 * 1024 * 1024;

function selloLima(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: TZ_LIMA, day: "2-digit", month: "long", year: "numeric",
    hour: "2-digit", minute: "2-digit", hour12: true,
  }).format(d);
}

// Fecha plana: se formatea en UTC para que no se corra un día por zona horaria.
function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "long", year: "numeric", timeZone: "UTC" })
    .format(new Date(Date.UTC(y, m - 1, d)));
}

/**
 * Cómo se nombra una versión en pantalla.
 *
 * Manda la del documento, y el correlativo baja a decir lo que de verdad es:
 * cuántas veces se ha publicado esto aquí. Antes se leía «versión 1» junto a un
 * texto que se titula «Versión 4.0», dos números que solo coincidirían por
 * casualidad — y el cargo que la integrante firma dice 4.0.
 */
function comoSeLlamaLaVersion(d: Doc): string {
  const publicacion = `${d.version}.ª publicación en el sistema`;
  return d.etiqueta_version ? `versión ${d.etiqueta_version} · ${publicacion}` : publicacion;
}

export default function NormasPage() {
  useTituloDocumento("Normas");
  const yo = usePersonaActual();
  const puedeGestionar = yo !== null && DO.includes(yo.rol);

  const [docs, setDocs] = useState<Doc[]>([]);
  const [abierto, setAbierto] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  const [msg, setMsg] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  /**
   * Los errores de constancia se avisan DONDE se produjeron, no arriba.
   *
   * `msg` es un aviso de página y se pinta debajo del subtítulo. Para lo que es
   * de la pantalla —cargar, publicar, crear un tipo— está bien; para la
   * constancia era el sitio equivocado. El caso que lo demuestra: el formulario
   * del cargo en papel se abre desde una fila del seguimiento y se dibuja DESPUÉS
   * de esa lista, que con el equipo completo son ~24 filas — unos 700 px entre el
   * aviso y el botón que lo provocó. El error más probable, olvidar adjuntar el
   * escaneo, se pintaba fuera de la vista y sin atenuar el botón.
   *
   * Y la asimetría era lo que hacía daño: el ÉXITO sí tenía señal local —el
   * formulario se sustituye por «Dejaste constancia el …»— y el fallo ninguna. En
   * la acción de la que depende la prueba legal, se veía cuando funcionaba y no
   * se veía cuando no.
   */
  const [msgConstancia, setMsgConstancia] = useState<string | null>(null);
  const [msgPapel, setMsgPapel] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [nombreDeclarado, setNombreDeclarado] = useState("");
  // Para llevar el foco al campo que falta, no solo nombrarlo.
  const refNombre = useRef<HTMLInputElement | null>(null);
  const refCargo = useRef<HTMLInputElement | null>(null);

  // El seguimiento de quién falta, sólo para quien puede verlo.
  const [acuses, setAcuses] = useState<Map<string, FilaAcuse[]>>(new Map());
  const [verSeguimiento, setVerSeguimiento] = useState<string | null>(null);
  const [verAnexos, setVerAnexos] = useState(false);

  // ── Publicar una versión ──────────────────────────────────────────────────
  // El texto NO se escribe aquí: se sube el archivo que vive en `docs/`, bajo
  // control de versiones. Pegar 277.000 caracteres a mano es justo donde se
  // pierde un trozo sin que nadie lo note, y el documento que vale como prueba
  // es el que se guarda.
  const [tipos, setTipos] = useState<Tipo[]>([]);
  const [publicando, setPublicando] = useState(false);
  // Alta de un tipo nuevo. La 0208 dejó escrito que este catálogo «se
  // administra desde la pantalla», pero la pantalla no tenía cómo: hasta la
  // 0215 la tabla solo permitía leer, así que cada documento nuevo era una
  // migración. Esto es esa mitad que faltaba.
  const [creandoTipo, setCreandoTipo] = useState(false);
  const [tipoNuevo, setTipoNuevo] = useState({ nombre: "", acuse: true });
  const [tipoElegido, setTipoElegido] = useState("rit");
  const [archivoDoc, setArchivoDoc] = useState<{ nombre: string; texto: string } | null>(null);
  // Pegar el texto en vez de subir un archivo. Ver `PEGAR` más abajo.
  const [pegando, setPegando] = useState(false);
  const [textoPegado, setTextoPegado] = useState("");
  const [tituloDoc, setTituloDoc] = useState("");
  const [vigenteDesde, setVigenteDesde] = useState("");
  const [notasDoc, setNotasDoc] = useState("");
  const [etiquetaDoc, setEtiquetaDoc] = useState("");

  // La constancia en papel de quien no tiene cuenta.
  const [papelPara, setPapelPara] = useState<{ doc: string; persona: string; nombre: string } | null>(null);
  const [archivo, setArchivo] = useState<File | null>(null);
  const [fechaPapel, setFechaPapel] = useState("");
  const [notaPapel, setNotaPapel] = useState("");
  const [progreso, setProgreso] = useState<number | null>(null);

  const supabase = useMemo(() => createAdminSupabaseClient(), []);

  // Todo lo que no es principal es anexo, sin lista escrita a mano: el día que
  // se publique un documento nuevo aparece aquí solo.
  const anexosVisibles = docs.filter((d) => !PRINCIPALES.includes(d.tipo));
  /**
   * Obedecer al «#doc-<id>» con el que llega quien viene del aviso de acuses
   * pendientes.
   *
   * El aviso vive en `components/acuses-pendientes.tsx` y sale en todas las
   * pantallas. Antes sus enlaces apuntaban a `/admin/normas` a secas: con dos
   * constancias pendientes, los dos llevaban al mismo sitio y la persona tenía
   * que buscar — y la segunda suele ser un anexo, que va plegado.
   *
   * Se espera a que `docs` esté cargado porque el elemento no existe hasta
   * entonces, y se despliega el bloque de anexos si el documento está ahí: sin
   * eso, abrirlo no se vería.
   */
  useEffect(() => {
    if (cargando || docs.length === 0) return;
    const id = window.location.hash.replace(/^#doc-/, "");
    if (!id || id === window.location.hash) return;
    const d = docs.find((x) => x.documento_id === id);
    if (!d) return;
    if (!PRINCIPALES.includes(d.tipo)) setVerAnexos(true);
    setAbierto(id);
    requestAnimationFrame(() =>
      document.getElementById(`doc-${id}`)?.scrollIntoView({ behavior: "smooth", block: "start" }));
  }, [cargando, docs]);

  const cargar = useCallback(async () => {
    setCargando(true);
    // ⚠️ El error SÍ se mira. La pantalla de Disciplina no lo miraba y durante
    // días imprimió «no hay nadie» cuando lo que había era un permiso que
    // faltaba (migración 0204). Un falso «no hay documentos» sería lo mismo.
    const { data, error } = await supabase.rpc("fn_documentos_vigentes");
    if (error) {
      setMsg({ tipo: "error", texto: mensajeDeError(error, "cargar los documentos") });
      setCargando(false);
      return;
    }
    const lista = (data as unknown as Doc[]) ?? [];
    setDocs(lista);
    if (lista.length && abierto === null) setAbierto(lista[0].documento_id);
    setCargando(false);
  }, [supabase, abierto]);

  useEffect(() => { void cargar(); }, [cargar]);

  /**
   * Un aviso de constancia se trae a la vista y se lleva el foco al campo.
   *
   * En un efecto y no junto al `setMsg…` por dos razones medidas en el navegador:
   * `BloqueConstancia` se define dentro de esta pantalla, así que cada render le
   * da identidad nueva y React REMONTA el campo — enfocar en el mismo tick apunta
   * al nodo que se va, y con `requestAnimationFrame` tampoco llega. Y el aviso
   * puede nacer fuera de la pantalla: el documento abierto ocupa hasta 60vh, así
   * que el bloque de constancia queda por debajo del pliegue mientras no te
   * desplaces. Un error que no se ve es un error que no existe para quien lo
   * provocó.
   */
  useEffect(() => {
    if (!msgConstancia) return;
    refNombre.current?.scrollIntoView({ block: "center" });
    refNombre.current?.focus({ preventScroll: true });
  }, [msgConstancia]);

  useEffect(() => {
    if (!msgPapel) return;
    refCargo.current?.scrollIntoView({ block: "center" });
    refCargo.current?.focus({ preventScroll: true });
  }, [msgPapel]);

  // El nombre viene puesto, pero es EDITABLE: lo que prueba no es el dato de la
  // base, es que la persona lo escriba. Eso convierte un clic en un acto
  // deliberado — la misma decisión que tomó la política salarial.
  useEffect(() => {
    if (yo?.nombreCompleto) setNombreDeclarado(yo.nombreCompleto);
  }, [yo]);

  // El catálogo de tipos: se lee de la tabla, nunca se escribe en el código.
  // Añadir «Presentación de CAYLA» tiene que ser un dato, no un despliegue.
  useEffect(() => {
    if (!puedeGestionar) return;
    void (async () => {
      const { data } = await supabase
        .from("documentos_tipos")
        .select("codigo, nombre, requiere_acuse")
        .eq("activo", true)
        .order("orden");
      setTipos((data as Tipo[]) ?? []);
    })();
  }, [supabase, puedeGestionar]);

  async function elegirArchivo(f: File | null) {
    setArchivoDoc(null);
    if (!f) return;
    if (f.size > MAX_BYTES_DOC) {
      setMsg({ tipo: "error", texto: `“${f.name}” pesa ${(f.size / 1048576).toFixed(1)} MB y el máximo es 2 MB. ¿Seguro que es el documento?` });
      return;
    }
    const texto = await f.text();
    if (!texto.trim()) {
      setMsg({ tipo: "error", texto: "El archivo está vacío." });
      return;
    }
    setArchivoDoc({ nombre: f.name, texto });
    // El título sale de la primera línea de encabezado del documento, para que
    // no haya dos verdades sobre cómo se llama.
    const h1 = texto.split("\n").find((l) => l.trim().startsWith("# "));
    if (h1 && !tituloDoc) setTituloDoc(h1.replace(/^#\s*/, "").trim());
    setMsg(null);
  }

  /**
   * PEGAR: la segunda vía para traer el texto, y por qué existe.
   *
   * Hasta hoy solo se podía subir un archivo, con este argumento escrito en la
   * pantalla: «el texto vive versionado en el repositorio y así no hay dos
   * verdades». Es cierto para el Reglamento y sus anexos —viven en `docs/`— y
   * es falso para todo lo demás. La misión, la visión y los valores no están en
   * el repositorio ni tienen por qué estarlo: están en un Word o en un Canva, y
   * exigir un `.md` obligaba a fabricar un archivo intermedio cuyo único
   * propósito era pasar por este formulario.
   *
   * Lo que se guarda es idéntico por las dos vías —el texto, congelado en
   * `documentos_institucionales.documento`—, así que la prueba no cambia: un
   * acuse sigue apuntando a las palabras exactas que se mostraron. Lo que
   * cambia es de dónde salieron esas palabras, y eso nunca se guardó.
   *
   * Se mantiene el tope de tamaño: pegar el manual equivocado es tan posible
   * como subirlo.
   */
  function pegarTexto(t: string) {
    setTextoPegado(t);
    if (!t.trim()) { setArchivoDoc(null); return; }
    if (t.length > MAX_BYTES_DOC) {
      setMsg({ tipo: "error", texto: `El texto pegado es enorme (${(t.length / 1048576).toFixed(1)} MB). ¿Seguro que es el documento?` });
      setArchivoDoc(null);
      return;
    }
    setArchivoDoc({ nombre: "Texto pegado", texto: t });
    const h1 = t.split("\n").find((l) => l.trim().startsWith("# "));
    if (h1 && !tituloDoc) setTituloDoc(h1.replace(/^#\s*/, "").trim());
    setMsg(null);
  }

  /** El código a partir del nombre: la tabla exige `^[a-z0-9_]{2,40}$`, así que
   *  se pide UNA cosa —el nombre— y el código se deriva. Pedir los dos obliga a
   *  explicar qué es un código y deja que alguien escriba «Política HS» en el
   *  campo equivocado, que es un error que no se ve hasta que falla el insert. */
  function codigoDesde(nombre: string): string {
    const sinTildes = nombre.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    return sinTildes.toLowerCase().replace(/[^a-z0-9]+/g, "_")
      .replace(/^_+|_+$/g, "").slice(0, 40);
  }

  async function crearTipo() {
    const nombre = tipoNuevo.nombre.trim();
    const codigo = codigoDesde(nombre);
    if (codigo.length < 2) {
      setMsg({ tipo: "error", texto: "El nombre tiene que tener al menos dos letras o números." });
      return;
    }
    if (tipos.some((t) => t.codigo === codigo)) {
      setMsg({ tipo: "error", texto: `Ya existe un documento con ese nombre (${codigo}).` });
      return;
    }
    setOcupado(true); setMsg(null);
    // `orden` al final, y a partir del 100: los seis documentos que vinieron con
    // el sistema ocupan del 10 al 60, así que uno nuevo se coloca detrás sin
    // desplazar a ninguno. No se calcula del máximo real porque esta consulta
    // no trae la columna `orden`, y fingir que sí la usa sería peor que esto.
    const orden = 100 + tipos.length * 10;
    const { error } = await supabase.from("documentos_tipos")
      .insert({ codigo, nombre, orden, requiere_acuse: tipoNuevo.acuse });
    setOcupado(false);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error, "crear el tipo de documento") }); return; }
    const { data } = await supabase.from("documentos_tipos")
      .select("codigo, nombre, requiere_acuse").eq("activo", true).order("orden");
    setTipos((data as Tipo[]) ?? []);
    setTipoElegido(codigo);
    setCreandoTipo(false); setTipoNuevo({ nombre: "", acuse: true });
    setMsg({
      tipo: "ok",
      texto: `«${nombre}» ya se puede publicar${tipoNuevo.acuse ? ", y pedirá constancia a cada integrante" : ", para consulta y sin constancia"}.`,
    });
  }

  async function publicar() {
    if (!archivoDoc) { setMsg({ tipo: "error", texto: "Falta el documento: sube el archivo o pega el texto." }); return; }
    if (!tituloDoc.trim()) { setMsg({ tipo: "error", texto: "Falta el título con el que se va a mostrar." }); return; }
    setOcupado(true); setMsg(null);
    const { data, error } = await supabase.rpc("fn_publicar_documento", {
      p_tipo: tipoElegido,
      p_titulo: tituloDoc.trim(),
      p_documento: archivoDoc.texto,
      p_vigente_desde: vigenteDesde || null,
      p_notas: notasDoc.trim() || null,
      p_etiqueta: etiquetaDoc.trim() || null,
    });
    setOcupado(false);
    if (error) { setMsg({ tipo: "error", texto: mensajeDeError(error, "publicar el documento") }); return; }
    // El título TAMBIÉN se limpia, y esto no es aseo.
    //
    // `elegirArchivo` rellena el título con el «# » del archivo solo si el campo
    // está vacío, para no pisar lo que se haya escrito a mano. Sin limpiarlo
    // aquí, el título de la publicación anterior seguía puesto, el guard lo veía
    // lleno y no lo actualizaba: el 12-08-2026 la Resolución de designación se
    // publicó con el título de la Política de Prevención, y en la lista salían
    // dos documentos con el mismo nombre.
    // `textoPegado` se limpia por la misma razón que el título: si se quedara
    // puesto, la siguiente publicación arrancaría con el documento anterior en
    // el cuadro y bastaría no mirarlo para publicarlo otra vez.
    // Qué prometía este mensaje, y por qué ahora pregunta.
    //
    // Decía siempre «desde ahora cada integrante deja su constancia», y para un
    // documento con `requiere_acuse = false` eso es falso: no se le va a pedir
    // constancia a nadie. Se veía poco mientras publicar un documento sin acuse
    // costaba una migración; se ve al primer intento desde que el catálogo se
    // administra en pantalla. Y un mensaje de éxito que anuncia un trámite que
    // no va a ocurrir deja esperando una lista de pendientes que nunca aparece.
    const pideAcuse = tipos.find((t) => t.codigo === tipoElegido)?.requiere_acuse ?? true;
    setPublicando(false); setArchivoDoc(null); setNotasDoc(""); setTituloDoc(""); setTextoPegado(""); setEtiquetaDoc("");
    await cargar();
    setMsg({
      tipo: "ok",
      texto: pideAcuse
        ? `Publicada la versión ${String(data)}. Desde ahora cada integrante deja su constancia, y quien no tenga cuenta la deja en papel.`
        : `Publicada la versión ${String(data)}. Queda publicada para consulta: este documento no pide constancia a nadie.`,
    });
  }

  async function cargarAcuses(documentoId: string) {
    const { data } = await supabase.rpc("fn_acuses_documento", { p_documento_id: documentoId });
    const filas = (data as unknown as FilaAcuse[]) ?? [];
    // La ruta del cargo se pide APARTE, porque la función no la devuelve. La
    // política `documentos_acuses_lectura` ya deja leer la tabla a administración
    // y a los líderes, que son quienes ven este panel.
    const { data: rutas } = await supabase
      .from("documentos_acuses")
      .select("persona_id, storage_path")
      .eq("documento_id", documentoId);
    const porPersona = new Map((rutas ?? []).map((r) => [r.persona_id as string, r.storage_path as string | null]));
    setAcuses((m) => new Map(m).set(
      documentoId,
      filas.map((f) => ({ ...f, storage_path: porPersona.get(f.persona_id) ?? null })),
    ));
  }

  async function acusar(d: Doc) {
    // Nombre Y apellido, no solo nombre. El `nombre_declarado` es lo que hace de
    // firma en la constancia: escrito de puño y letra en un cargo de papel nadie
    // pone solo el nombre de pila, y una constancia que dice «Ana» no identifica
    // a nadie el día que hay dos Anas en la misma sede.
    if (nombreDeclarado.trim().split(/\s+/).filter(Boolean).length < 2) {
      setMsgConstancia("Escribe tu nombre y tu apellido para dejar constancia.");
      return;
    }
    setOcupado(true); setMsg(null); setMsgConstancia(null);
    const { error } = await supabase.rpc("fn_acusar_documento", {
      p_documento_id: d.documento_id,
      p_nombre_declarado: nombreDeclarado.trim(),
    });
    setOcupado(false);
    if (error) { setMsgConstancia(mensajeDeError(error)); return; }
    await cargar();
    setMsg({ tipo: "ok", texto: "Constancia registrada. No hace falta hacer nada más hasta que se publique una versión nueva." });
  }

  async function guardarPapel() {
    if (!papelPara) return;
    if (!archivo) {
      setMsgPapel("Falta el cargo firmado escaneado. Sin el papel no hay constancia que registrar.");
      return;
    }
    if (archivo.size > MAX_BYTES_CARGO) {
      setMsgPapel(`“${archivo.name}” pesa ${(archivo.size / 1048576).toFixed(1)} MB y el máximo es 50 MB.`);
      return;
    }
    setOcupado(true); setMsg(null); setMsgPapel(null);
    // La ruta cuelga del documento y de la persona: así no hay forma de
    // archivar el cargo contra la versión equivocada.
    const ext = archivo.name.split(".").pop()?.toLowerCase() ?? "bin";
    const ruta = `${papelPara.doc}/${papelPara.persona}-${Date.now()}.${ext}`;

    setProgreso(0);
    const fallo = await subirArchivoConProgreso(supabase, "acuses", ruta, archivo, setProgreso);
    setProgreso(null);
    if (fallo) {
      setOcupado(false);
      setMsgPapel(`El archivo no subió (${fallo}). Vuelve a intentarlo.`);
      return;
    }

    const { error } = await supabase.rpc("fn_registrar_acuse_papel", {
      p_documento_id: papelPara.doc,
      p_persona_id: papelPara.persona,
      p_path: ruta,
      // La fecha buena es la del papel, no la de hoy: de la recepción cuelgan
      // los plazos, y entre firmar y escanear pueden pasar días.
      p_acusado_at: fechaPapel ? new Date(`${fechaPapel}T12:00:00-05:00`).toISOString() : null,
      p_nota: notaPapel.trim() || null,
    });
    setOcupado(false);
    if (error) { setMsgPapel(mensajeDeError(error)); return; }
    const doc = papelPara.doc;
    setPapelPara(null); setArchivo(null); setNotaPapel(""); setMsgPapel(null);
    await cargar();
    await cargarAcuses(doc);
    setMsg({ tipo: "ok", texto: "Constancia en papel registrada, con su cargo archivado." });
  }

  async function verCargo(path: string) {
    // URL firmada de vida corta: el almacén es privado y son papeles firmados.
    const fallo = await abrirArchivoFirmado(supabase, "acuses", path);
    if (fallo) setMsgPapel(fallo);
  }


  /**
   * La constancia propia y su seguimiento.
   *
   * Es una función y no está escrita dos veces porque la usan el Reglamento y
   * los anexos que piden constancia. Estaba solo en el Reglamento, y cuando la
   * migración 0215 marcó la Política de Prevención como que sí la pide, quedó
   * pidiendo una constancia que nadie podía dejar: la etiqueta roja salía en la
   * lista y no había formulario debajo. Veintidós personas viendo un aviso que
   * no se puede resolver.
   *
   * Vive dentro de NormasPage a propósito: cierra sobre `nombreDeclarado`,
   * `acusar`, `verSeguimiento` y media docena más. Sacarla fuera obligaría a
   * pasar doce props, y doce props es donde se cuela el que se olvidó.
   */
  function BloqueConstancia({ d }: { d: Doc }) {
    const filas = acuses.get(d.documento_id) ?? [];
    const pendientes = filas.filter((f) => f.acusado_at === null);
    return (
      <>
        {/* ── La constancia propia ── */}
        {d.requiere_acuse && (
          <div className="mt-4 rounded-lg border border-sand bg-sand/20 p-3">
            {d.mi_acuse_at ? (
              <p className="text-xs text-taupe">
                Dejaste constancia el <strong>{selloLima(d.mi_acuse_at)}</strong>. No hace falta
                hacer nada más hasta que se publique una versión nueva. Si algo de este documento
                no te cuadra, puedes plantearlo a la Gerencia y recibirás respuesta por escrito.
              </p>
            ) : (
              <>
                <p className="mb-2 text-xs text-taupe">
                  Dejar constancia significa que recibiste este documento y fuiste informada de su
                  contenido. No es una firma de conformidad ni renuncia a nada.
                </p>
                {msgConstancia && (
                  <p role="alert" id="error-constancia"
                    className="mb-2 rounded border border-rojo/30 bg-rojo/10 px-2 py-1.5 text-xs text-rojo">
                    {msgConstancia}
                  </p>
                )}
                <div className="flex flex-wrap items-end gap-2">
                  <label className="flex flex-col gap-1 text-xs">
                    Tu nombre y apellido
                    <input ref={refNombre} value={nombreDeclarado}
                      onChange={(e) => { setNombreDeclarado(e.target.value); setMsgConstancia(null); }}
                      placeholder="como lo escribirías a mano"
                      autoComplete="name"
                      aria-invalid={msgConstancia !== null}
                      aria-describedby={msgConstancia ? "error-constancia" : undefined}
                      className={`w-64 rounded border px-2 py-1 text-xs ${msgConstancia ? "border-rojo" : ""}`} />
                  </label>
                  <button onClick={() => void acusar(d)} disabled={ocupado}
                    className="rounded-lg bg-tinta px-3 py-1.5 text-xs font-medium text-crema disabled:opacity-40">
                    Dejar constancia
                  </button>
                </div>
              </>
            )}
          </div>
        )}

        {/* ── El seguimiento, sólo para quien manda ── */}
        {puedeGestionar && d.requiere_acuse && (
          <div className="mt-4">
            <button
              onClick={() => {
                const nuevo = verSeguimiento === d.documento_id ? null : d.documento_id;
                setVerSeguimiento(nuevo);
                if (nuevo) void cargarAcuses(nuevo);
              }}
              className="text-xs font-medium underline">
              {d.total_acuses} de {d.poblacion} han dejado constancia
              {d.total_acuses < d.poblacion && ` · faltan ${d.poblacion - d.total_acuses}`}
              {verSeguimiento === d.documento_id ? " · ocultar" : " · ver quién"}
            </button>

            {verSeguimiento === d.documento_id && (
              <ul className="mt-2 divide-y rounded-lg border border-sand">
                {filas.map((f) => (
                  <li key={f.persona_id} className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 text-xs">
                    <span>
                      {f.nombre} <span className="text-taupe">· {f.sede}</span>
                      {!f.tiene_cuenta && <span className="ml-2 rounded-full bg-sand px-2 py-0.5 text-taupe">sin cuenta</span>}
                    </span>
                    {f.acusado_at ? (
                      <span className="text-taupe">
                        {selloLima(f.acusado_at)} · {f.via === "papel" ? "en papel" : "desde el sistema"}
                      </span>
                    ) : (
                      <button
                        onClick={() => {
                          setPapelPara({ doc: d.documento_id, persona: f.persona_id, nombre: f.nombre });
                          setArchivo(null); setFechaPapel(hoyLima()); setNotaPapel("");
                          setMsg(null); setMsgPapel(null);
                        }}
                        className="rounded border border-tinta/30 px-2 py-0.5 text-tinta hover:bg-sand/40">
                        registrar su cargo en papel
                      </button>
                    )}
                  </li>
                ))}
                {filas.length === 0 && <li className="px-3 py-2 text-xs text-taupe">Sin datos.</li>}
              </ul>
            )}

            {pendientes.length > 0 && verSeguimiento === d.documento_id && (
              <p className="mt-2 text-xs text-taupe">
                Quien no tiene cuenta deja constancia en papel: se le entrega el documento impreso,
                firma el cargo y aquí se archiva el escaneo.
              </p>
            )}
          </div>
        )}

        {/* ── El formulario del cargo en papel ── */}
        {papelPara && papelPara.doc === d.documento_id && (
          <div className="mt-3 rounded-lg border border-sand bg-sand/20 p-3">
            <p className="mb-2 text-xs text-taupe">
              Constancia en papel de <strong>{papelPara.nombre}</strong>. Sin el escaneo del cargo
              firmado no se registra: aquí la constancia es la prueba.
            </p>
            {msgPapel && (
              <p role="alert" id="error-papel"
                className="mb-2 rounded border border-rojo/30 bg-rojo/10 px-2 py-1.5 text-xs text-rojo">
                {msgPapel}
              </p>
            )}
            <div className="grid gap-2 sm:grid-cols-2">
              <label className="flex flex-col gap-1 text-xs">
                Cargo firmado
                <input ref={refCargo} type="file" accept={TIPOS_CARGO}
                  onChange={(e) => { setArchivo(e.target.files?.[0] ?? null); setMsgPapel(null); }}
                  aria-invalid={msgPapel !== null}
                  aria-describedby={msgPapel ? "error-papel" : undefined}
                  className={`rounded border bg-crema px-2 py-1 text-xs file:mr-2 file:rounded file:border-0 file:bg-sand file:px-2 file:py-0.5 file:text-xs ${msgPapel ? "border-rojo" : ""}`} />
              </label>
              <label className="flex flex-col gap-1 text-xs">
                Fecha de recepción
                <input type="date" value={fechaPapel} max={hoyLima()}
                  onChange={(e) => setFechaPapel(e.target.value)}
                  className="rounded border px-2 py-1 text-xs" />
              </label>
              <label className="flex flex-col gap-1 text-xs sm:col-span-2">
                Nota (opcional)
                <input value={notaPapel} onChange={(e) => setNotaPapel(e.target.value)}
                  placeholder="ej. entregado en la tienda, con la encargada presente"
                  className="rounded border px-2 py-1 text-xs" />
              </label>
            </div>
            {progreso !== null && (
              <div className="mt-2">
                <div className="h-1.5 w-full overflow-hidden rounded-full bg-sand">
                  <div className="h-full bg-tinta transition-[width] duration-200" style={{ width: `${progreso}%` }}
                    role="progressbar" aria-valuenow={progreso} aria-valuemin={0} aria-valuemax={100}
                    aria-label="Subiendo el cargo" />
                </div>
                <span className="text-xs text-taupe">Subiendo — {progreso}%</span>
              </div>
            )}
            <div className="mt-2 flex items-center gap-2">
              <button onClick={() => void guardarPapel()} disabled={ocupado}
                className="rounded-lg bg-tinta px-3 py-1 text-xs font-medium text-crema disabled:opacity-40">
                {progreso !== null ? `Subiendo… ${progreso}%` : "Registrar constancia"}
              </button>
              <button onClick={() => setPapelPara(null)} className="rounded-lg border px-3 py-1 text-xs">
                Cancelar
              </button>
            </div>
          </div>
        )}

        {/* ── Los cargos ya archivados ── */}
        {puedeGestionar && verSeguimiento === d.documento_id && filas.some((f) => f.via === "papel") && (
          <p className="mt-3 text-xs text-taupe">
            Cargos archivados:{" "}
            {/* Sin ruta no hay enlace: un botón que promete abrir y falla es peor
                que un nombre en texto plano. Que el cargo existe sigue siendo un
                dato que el seguimiento necesita ver. */}
            {filas.filter((f) => f.via === "papel").map((f) => (
              f.storage_path ? (
                <button key={f.persona_id}
                  onClick={() => void verCargo(f.storage_path!)}
                  className="mr-2 font-medium underline">{f.nombre}</button>
              ) : (
                <span key={f.persona_id} className="mr-2" title="El cargo está registrado pero no se encontró su archivo.">
                  {f.nombre}
                </span>
              )
            ))}
          </p>
        )}
      </>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <h1 className="mb-1 font-serif text-2xl">Normas</h1>
        <p className="mb-5 max-w-2xl text-sm text-taupe">
          Los documentos que rigen para todo el equipo. Aquí se leen, y aquí queda la constancia
          de que se recibieron — con la <strong>versión</strong>, que es lo que un papel firmado no dice.
        </p>

        {msg && (
          <div className={`mb-4 max-w-2xl rounded-lg px-4 py-3 text-sm ${msg.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
            {msg.texto}
          </div>
        )}

        {/* ── Publicar, sólo para quien puede ── */}
        {puedeGestionar && (
          <div className="mb-5 max-w-3xl overflow-hidden rounded-2xl border border-sand bg-papel">
            <button onClick={() => setPublicando((v) => !v)}
              className="flex w-full items-center justify-between border-b bg-sand/50 px-4 py-2 text-left text-sm font-medium">
              <span>Publicar una versión</span>
              <span className="text-xs font-normal text-taupe">{publicando ? "ocultar" : "abrir"}</span>
            </button>
            {publicando && (
              <div className="px-4 py-3">
                <p className="mb-3 text-xs text-taupe">
                  El texto puede venir de un archivo o pegarse aquí — se guarda igual, y congelado:
                  un acuse de hoy seguirá apuntando dentro de cinco años a las palabras que se
                  mostraron hoy. Publicar el <strong>mismo</strong> texto no crea versión nueva —
                  pedir constancia sin que nada cambie enseña que la constancia es trámite.
                </p>
                <div className="grid gap-2 sm:grid-cols-2">
                  <label className="flex flex-col gap-1 text-xs">
                    <span className="flex items-baseline justify-between gap-2">
                      Tipo de documento
                      <button type="button" onClick={() => setCreandoTipo((v) => !v)}
                        className="text-[11px] font-normal text-taupe underline underline-offset-2 hover:text-tinta">
                        {creandoTipo ? "cancelar" : "añadir uno"}
                      </button>
                    </span>
                    <select value={tipoElegido} onChange={(e) => setTipoElegido(e.target.value)}
                      className="rounded border bg-crema px-2 py-1 text-xs">
                      {tipos.map((t) => (
                        <option key={t.codigo} value={t.codigo}>
                          {t.nombre}{t.requiere_acuse ? "" : " (sin constancia)"}
                        </option>
                      ))}
                    </select>
                    {/* Esta lista no viene de fábrica: sale de `documentos_tipos`, que se
                        administra desde aquí. Sin decirlo, el desplegable se lee como un
                        catálogo cerrado y quien tiene un documento que no está en él cree
                        que no cabe — pasó, y por eso está escrito. */}
                    <span className="text-taupe">
                      Esta lista la haces tú. Si tu documento no está, «añadir uno».
                    </span>
                  </label>
                  <label className="flex flex-col gap-1 text-xs">
                    <span className="flex items-baseline justify-between gap-2">
                      {pegando ? "Texto del documento" : "Archivo (.md o .txt)"}
                      <button type="button"
                        onClick={() => { setPegando((v) => !v); setArchivoDoc(null); setTextoPegado(""); }}
                        className="text-[11px] font-normal text-taupe underline underline-offset-2 hover:text-tinta">
                        {pegando ? "subir un archivo" : "o pegar el texto"}
                      </button>
                    </span>
                    {pegando ? (
                      <textarea value={textoPegado} onChange={(e) => pegarTexto(e.target.value)}
                        rows={4} placeholder="Pega aquí el texto — desde Word, Canva, donde esté."
                        className="rounded border bg-crema px-2 py-1 font-mono text-[11px] leading-relaxed" />
                    ) : (
                      <input type="file" accept=".md,.txt,text/markdown,text/plain"
                        onChange={(e) => void elegirArchivo(e.target.files?.[0] ?? null)}
                        className="rounded border bg-crema px-2 py-1 text-xs file:mr-2 file:rounded file:border-0 file:bg-sand file:px-2 file:py-0.5 file:text-xs" />
                    )}
                  </label>
                  <label className="flex flex-col gap-1 text-xs">
                    Título con el que se muestra
                    <input value={tituloDoc} onChange={(e) => setTituloDoc(e.target.value)}
                      placeholder="Reglamento Interno de Trabajo"
                      className="rounded border px-2 py-1 text-xs" />
                  </label>
                  <label className="flex flex-col gap-1 text-xs">
                    Rige desde
                    <input type="date" value={vigenteDesde} onChange={(e) => setVigenteDesde(e.target.value)}
                      className="rounded border px-2 py-1 text-xs" />
                    <span className="text-taupe">Si lo dejas vacío, rige desde hoy.</span>
                  </label>
                  {/* La versión que DICE el documento, que es la que va en el cargo
                      que se firma. No se deduce del texto a propósito: solo el
                      Reglamento la lleva en un sitio predecible, los anexos la
                      tienen embutida en prosa y un texto pegado desde un Word
                      puede no traerla. Un analizador acertaría en uno y fallaría
                      en silencio en el resto. */}
                  <label className="flex flex-col gap-1 text-xs">
                    Versión que dice el documento (opcional)
                    <input value={etiquetaDoc} onChange={(e) => setEtiquetaDoc(e.target.value)}
                      placeholder="ej. 4.0"
                      className="rounded border px-2 py-1 text-xs" />
                    <span className="text-taupe">
                      La que aparece en el cargo que se firma. Si la dejas vacía, se muestra
                      solo el número de publicación.
                    </span>
                  </label>
                  <label className="flex flex-col gap-1 text-xs sm:col-span-2">
                    Nota de la versión (opcional)
                    <input value={notasDoc} onChange={(e) => setNotasDoc(e.target.value)}
                      placeholder="ej. sustituye a la v3.0 de junio de 2026"
                      className="rounded border px-2 py-1 text-xs" />
                  </label>
                </div>

                {creandoTipo && (
                  <div className="mt-3 rounded-lg border border-sand bg-crema/40 p-3">
                    <p className="mb-2 text-xs text-taupe">
                      Un documento nuevo del expediente — una política, un protocolo, la
                      presentación de la empresa. El código interno se deriva del nombre.
                    </p>
                    <div className="grid gap-2 sm:grid-cols-2">
                      <label className="flex flex-col gap-1 text-xs">
                        Nombre
                        <input value={tipoNuevo.nombre}
                          onChange={(e) => setTipoNuevo((t) => ({ ...t, nombre: e.target.value }))}
                          placeholder="Reglamento Interno de Seguridad y Salud"
                          className="rounded border px-2 py-1 text-xs" />
                        {tipoNuevo.nombre.trim() !== "" && (
                          <span className="text-[11px] text-taupe">código: {codigoDesde(tipoNuevo.nombre) || "—"}</span>
                        )}
                      </label>
                      <label className="flex items-start gap-2 text-xs sm:pt-5">
                        <input type="checkbox" checked={tipoNuevo.acuse} className="mt-0.5"
                          onChange={(e) => setTipoNuevo((t) => ({ ...t, acuse: e.target.checked }))} />
                        <span>
                          Pedir constancia a cada integrante
                          <span className="block text-[11px] text-taupe">
                            Desmárcalo si el documento no le impone nada al equipo — una guía
                            interna, un formulario en blanco. Un registro lleno de constancias
                            que no significan nada no prueba nada.
                          </span>
                        </span>
                      </label>
                    </div>
                    <div className="mt-2 flex items-center gap-2">
                      <button onClick={() => void crearTipo()} disabled={ocupado || !tipoNuevo.nombre.trim()}
                        className="rounded-lg bg-tinta px-3 py-1 text-xs font-medium text-crema disabled:opacity-40">
                        Añadir
                      </button>
                    </div>
                  </div>
                )}

                {archivoDoc && (
                  <div className="mt-3 rounded-lg border border-sand bg-crema/40 p-3">
                    {/* El recuento de artículos solo sale si hay alguno: «0 artículos
                        detectados» en unos valores institucionales parece un fallo del
                        lector, y no lo es — ese documento no tiene artículos. */}
                    <p className="text-xs text-taupe">
                      <strong>{archivoDoc.nombre}</strong> · {archivoDoc.texto.length.toLocaleString("es-PE")} caracteres
                      {(() => {
                        const n = archivoDoc.texto.split("\n").filter((l) => /^#{1,4}\s*ART[IÍ]CULO/i.test(l.trim())).length;
                        return n > 0 ? ` · ${n} artículos detectados` : "";
                      })()}
                    </p>
                    <div className="mt-2 max-h-40 overflow-y-auto text-[11px] leading-relaxed text-tinta">
                      <Documento texto={archivoDoc.texto.slice(0, 1200)} />
                    </div>
                    <p className="mt-1 text-xs text-taupe">Vista previa del principio, para comprobar que es el archivo correcto.</p>
                  </div>
                )}

                <div className="mt-3 flex items-center gap-2">
                  <button onClick={() => void publicar()} disabled={ocupado || !archivoDoc}
                    className="rounded-lg bg-tinta px-3 py-1.5 text-xs font-medium text-crema disabled:opacity-40">
                    Publicar
                  </button>
                  <button onClick={() => { setPublicando(false); setArchivoDoc(null); setTituloDoc(""); setTextoPegado(""); }}
                    className="rounded-lg border px-3 py-1.5 text-xs">Cancelar</button>
                </div>
              </div>
            )}
          </div>
        )}

        {cargando ? (
          <Cargando texto="Cargando los documentos…" />
        ) : docs.length === 0 ? (
          <p className="max-w-xl rounded-2xl border border-sand bg-papel px-4 py-6 text-sm text-taupe">
            Todavía no hay ningún documento publicado.
            {puedeGestionar && " Publica el primero con el botón de arriba."}
          </p>
        ) : (
          <div className="space-y-4">
            {docs.filter((d) => PRINCIPALES.includes(d.tipo)).map((d) => {
              return (
                <div key={d.documento_id} id={`doc-${d.documento_id}`}
                  className="max-w-4xl overflow-hidden rounded-2xl border border-sand bg-papel">
                  <button
                    onClick={() => setAbierto(abierto === d.documento_id ? null : d.documento_id)}
                    className="flex w-full flex-wrap items-center justify-between gap-3 border-b bg-sand/50 px-4 py-3 text-left">
                    <span>
                      <span className="font-medium">{d.titulo}</span>
                      <span className="ml-2 text-xs text-taupe">
                        {comoSeLlamaLaVersion(d)} · rige desde {fechaCorta(d.vigente_desde)}
                      </span>
                    </span>
                    {/* `flex-wrap` arriba y `whitespace-nowrap` en la píldora: con
                        los títulos reales de los anexos —«Política de Prevención del
                        Hostigamiento Sexual Laboral»— en los 295 px útiles de un
                        móvil, «falta tu constancia» se partía en dos líneas DENTRO
                        de su cápsula. Una etiqueta de estado partida se lee como
                        pantalla rota, justo en el aviso que empuja a firmar. */}
                    <span className="flex items-center gap-2 text-xs">
                      {!d.requiere_acuse ? (
                        <span className="whitespace-nowrap text-taupe">solo lectura</span>
                      ) : d.mi_acuse_at ? (
                        <span className="whitespace-nowrap rounded-full bg-sand px-2 py-0.5 text-tinta">tu constancia está</span>
                      ) : (
                        <span className="whitespace-nowrap rounded-full bg-rojo/10 px-2 py-0.5 text-rojo">falta tu constancia</span>
                      )}
                      <span className="text-taupe">{abierto === d.documento_id ? "ocultar" : "leer"}</span>
                    </span>
                  </button>

                  {abierto === d.documento_id && (
                    <div className="px-4 py-4">
                      {/* La hoja se compone del MISMO texto que se lee acá, no
                          de un PDF guardado aparte: dos archivos del mismo
                          documento se desincronizan el día que uno cambia. */}
                      <div className="mb-2 flex justify-end gap-3">
                        <a href={`/admin/normas/${d.documento_id}/imprimir`} target="_blank" rel="noopener"
                          className="text-xs text-taupe underline underline-offset-2 hover:text-tinta">
                          imprimir
                        </a>
                        {/* La hoja de constancias es la otra mitad de la prueba:
                            `imprimir` acredita QUÉ se comunicó y esta A QUIÉN. Va
                            al lado y no dentro del seguimiento porque se busca el
                            día que hay que adjuntar un papel, no el día que se
                            persigue una firma. */}
                        {d.requiere_acuse && puedeGestionar && (
                          <a href={`/admin/normas/${d.documento_id}/constancias`} target="_blank" rel="noopener"
                            className="text-xs text-taupe underline underline-offset-2 hover:text-tinta">
                            hoja de constancias
                          </a>
                        )}
                      </div>
                      {/* La altura de la caja, y por qué 60vh y no 28rem.
                          `PRINCIPALES = ["rit"]`, así que esta caja envuelve el
                          ÚNICO documento principal y el más largo del sistema: 61
                          artículos dentro de 448 px fijos, con el botón de dejar
                          constancia pegado justo debajo del recorte. En móvil el
                          scroll anidado obliga a agotar la caja antes de que la
                          página se mueva. Se acota a la pantalla en vez de a una
                          medida fija, y se conserva el tope en escritorio para que
                          el panel de seguimiento —el que usa DO— no acabe 61
                          artículos más abajo. `overscroll-contain` evita que el
                          gesto se le escape a la página al llegar al final. */}
                      <div className="max-h-[60vh] overscroll-contain overflow-y-auto rounded-lg border border-sand bg-crema/40 px-4 py-3 sm:max-h-[28rem]">
                        <Documento texto={d.documento} />
                      </div>

                      <BloqueConstancia d={d} />

                      <p className="mt-4 text-xs text-taupe">
                        Publicado el {selloLima(d.publicado_at)} · {d.tipo_nombre}
                      </p>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}

        {/* ── Anexos ────────────────────────────────────────────────────────
            Plegados y debajo, no al lado. El artículo 47 del Reglamento dice
            que estos documentos «tienen finalidad informativa» y que «en caso
            de discrepancia prevalece este Reglamento»; ponerlos al mismo nivel
            haría que la pantalla dijera lo contrario que el articulado. */}
        {!cargando && anexosVisibles.length > 0 && (
          <div className="mt-6 max-w-4xl overflow-hidden rounded-2xl border border-sand bg-papel">
            <button onClick={() => setVerAnexos((v) => !v)}
              className="flex w-full items-center justify-between border-b bg-sand/50 px-4 py-2 text-left text-sm font-medium">
              <span>Anexos <span className="font-normal text-taupe">· {anexosVisibles.length}</span></span>
              <span className="text-xs font-normal text-taupe">{verAnexos ? "ocultar" : "ver"}</span>
            </button>
            {verAnexos && (
              <div className="px-4 py-3">
                <p className="mb-3 text-xs text-taupe">
                  Documentos que explican y desarrollan el Reglamento. <strong>No crean
                  obligaciones, faltas, sanciones ni plazos distintos</strong> de los que él
                  establece, y si alguno discrepara, prevalece el Reglamento (artículo 47).
                </p>
                <ul className="divide-y">
                  {anexosVisibles.map((a) => (
                    <li key={a.documento_id} id={`doc-${a.documento_id}`} className="py-2">
                      <button onClick={() => setAbierto(abierto === a.documento_id ? null : a.documento_id)}
                        className="flex w-full flex-wrap items-center justify-between gap-3 text-left text-sm">
                        <span>
                          {a.titulo}
                          <span className="ml-2 text-xs text-taupe">{comoSeLlamaLaVersion(a)}</span>
                        </span>
                        <span className="flex items-center gap-2 text-xs">
                          {a.requiere_acuse && (a.mi_acuse_at
                            ? <span className="whitespace-nowrap rounded-full bg-sand px-2 py-0.5 text-tinta">tu constancia está</span>
                            : <span className="whitespace-nowrap rounded-full bg-rojo/10 px-2 py-0.5 text-rojo">falta tu constancia</span>)}
                          <span className="text-taupe">{abierto === a.documento_id ? "ocultar" : "leer"}</span>
                        </span>
                      </button>
                      {abierto === a.documento_id && (
                        <>
                        <div className="mt-2 flex justify-end gap-3">
                          <a href={`/admin/normas/${a.documento_id}/imprimir`} target="_blank" rel="noopener"
                            className="text-xs text-taupe underline underline-offset-2 hover:text-tinta">
                            imprimir
                          </a>
                          {a.requiere_acuse && puedeGestionar && (
                            <a href={`/admin/normas/${a.documento_id}/constancias`} target="_blank" rel="noopener"
                              className="text-xs text-taupe underline underline-offset-2 hover:text-tinta">
                              hoja de constancias
                            </a>
                          )}
                        </div>
                        <div className="mt-1 max-h-[24rem] overflow-y-auto rounded-lg border border-sand bg-crema/40 px-4 py-3">
                          <Documento texto={a.documento} />
                        </div>
                        <BloqueConstancia d={a} />
                        </>
                      )}
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}
      </main>
    </div>
  );
}
