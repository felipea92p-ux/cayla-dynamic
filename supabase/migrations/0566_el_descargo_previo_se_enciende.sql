-- ============================================================================
-- 0566 — El descargo previo se enciende
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que ninguna amonestación escrita ni suspensión se firme sin haber comunicado
-- antes los cargos por escrito y esperado el plazo del art. 55.2 del RIT. Es
-- decir: que los memos que emite una líder de equipo pasen a VALER como
-- escalón para una sanción mayor.
--
-- Cambia UNA FILA. No reescribe ninguna función: la maquinaria entera —comunicar
-- cargos, el plazo de 2 días hábiles, valorar el descargo, y el rechazo al
-- firmar antes de tiempo— la construyó la 0267 y la dejó gobernada por esta
-- clave de `configuracion`. Esta migración solo la pone en true.
--
-- ── POR QUÉ, Y POR QUÉ AHORA ────────────────────────────────────────────────
--
-- El 17-08-2026 Gerencia decidió aplicarla en false: se firmaba sin esperar y el
-- descargo se recogía verbalmente (0267). Lo que no se midió entonces es lo que
-- el propio Reglamento dice que cuesta.
--
-- Art. 55.2, último párrafo, del RIT v4.0 que CAYLA entregó a su equipo:
--
--   «La omisión del descargo previo invalida la sanción, que no puede
--    computarse como antecedente ni servir de escalón para los efectos del
--    literal h) del artículo 25 de la LPCL.»
--
-- Con la política en false, cada memo documentaba el hecho pero no era peldaño
-- de nada. Y el 2026-10-29 se pidió justamente lo contrario: que las líderes
-- puedan emitir memorándums «para así escalar medida disciplinaria de despido de
-- ser necesario». Sin esto, esa escalera no tiene dónde apoyar: el 57.10 exige,
-- para un despido por impuntualidad o inasistencias, «historial disciplinario
-- documentado que acredite el cumplimiento de la gradación de los artículos 19
-- y 21», y un historial de sanciones inválidas no acredita nada.
--
-- Es, además, la mitad barata del problema: el mecanismo ya está construido y
-- probado (prueba 205), así que lo único que faltaba era la decisión.
--
-- ── PARA TODAS LAS CAUSALES, NO SOLO PARA CONDUCTA ──────────────────────────
--
-- Se consideró encenderla solo para la conducta que registran las líderes
-- —donde está el trabajo nuevo— y dejar tardanzas e inasistencias como estaban.
-- Se descartó: es de la gradación de los arts. 19 y 21 de donde sale el despido
-- del 53.3 e), así que dejar esa mitad sin descargo previo deja sin escalón
-- justo la rama que más lo necesita. La clave es una sola y gobierna las tres
-- causales por igual; no se parte.
--
-- ── NO ENTRA AL CATÁLOGO DE PARÁMETROS ──────────────────────────────────────
--
-- `parametros_catalogo` (0552) es para números que DO puede mirar y cambiar, con
-- mínimo y máximo. Esto no es un número y no es de DO: es el procedimiento
-- sancionador del Reglamento, y moverlo cambia si una sanción ya impuesta vale.
-- Vive donde vivía, se cambia por migración, y cada cambio queda fechado en el
-- repositorio. Misma razón por la que la escalera disciplinaria tampoco es un
-- parámetro editable.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
--   · Que `fn_expediente_firmar` sigue leyendo la clave como la dejó la 0267:
--     `valor is distinct from 'false'::jsonb`, con `coalesce(…, true)`. Por eso
--     poner 'true' basta y no hace falta tocar la función. Si alguien la hubiera
--     reescrito para leer `= 'true'`, esto sigue funcionando igual.
--   · Que `fn_expediente_declarar_cargos_comunicados` (0266) existe, que es la
--     salida para los borradores que ya tenían la conversación hecha.
--
-- ── SON TRES PUERTAS, NO UNA (medido, no supuesto) ──────────────────────────
--
-- Auditado el 2026-10-29 contra el esquema real, con control A/B (prueba 456):
-- encender la política no agrega un paso antes de firmar, agrega TRES, y el
-- tercero no estaba escrito en ningún sitio:
--
--   1. comunicar los cargos            → fn_expediente_comunicar_cargos
--   2. esperar el plazo (2 días háb.)  → art. 55.2
--   3. VALORAR el descargo por escrito → fn_expediente_valorar_descargo
--                                        («Falta valorar por escrito el
--                                         descargo … aunque no se haya
--                                         presentado ninguno», art. 19.3)
--   4. firmar
--
-- La tercera sorprende porque se exige incluso cuando la persona no presentó
-- nada: hay que dejar constancia de que no lo presentó (`sin_descargo`). Es
-- correcto —el 55.2 dice que la Empresa «hace constar su valoración por escrito
-- en el propio documento»— y es la que haría leer esto como una avería.
--
-- La pantalla YA lo sabe hacer: `etapaDelBorrador` (apps/web/lib/admin/disciplina.ts)
-- dibuja las cuatro etapas `comunicar → esperando → valorar → firmar` desde que
-- se construyó la 0267, y `/admin/disciplina` ya llama a las dos funciones. No
-- hay pantalla que cambiar: estaba construida esperando esta decisión.
--
-- ── A QUIÉN AFECTA AL PEGARLA ───────────────────────────────────────────────
--
-- A los borradores de amonestación y suspensión que estén abiertos y sin cargos
-- comunicados: desde el momento de pegarla, firmarlos pide primero comunicar los
-- cargos y esperar el plazo. No se pierde ninguno y ninguno queda inválido —
-- quedan a la espera. Para los que ya tuvieron la conversación, el camino es
-- `fn_expediente_declarar_cargos_comunicados`, que declara una comunicación ya
-- ocurrida con su fecha.
--
-- La consulta del final cuenta cuántos son ANTES y DESPUÉS, para que quien pega
-- vea exactamente a quién alcanza.
--
-- Lo ya firmado y lo ya entregado no se toca: una sanción impuesta no cambia de
-- validez por una migración posterior, y la disposición transitoria del RIT dice
-- que los procedimientos en trámite terminan con las reglas con que empezaron.
-- Un borrador sin firmar no es un procedimiento en trámite: es un documento que
-- todavía no impuso nada.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   update configuracion set valor = 'false'::jsonb
--    where clave = 'disciplina_descargo_previo';
--
-- Sin cambio de esquema y sin cambio de datos del expediente: revertir devuelve
-- el comportamiento de la 0267 exactamente.
-- ============================================================================

-- ── El encendido ────────────────────────────────────────────────────────────
-- Idempotente: pegarla dos veces deja el mismo valor. El insert cubre el caso
-- de una base donde la 0267 no hubiera dejado la fila (ausente = se exige, así
-- que el comportamiento ya era este, pero la fila debe existir para que la
-- pantalla pueda leerla).
insert into configuracion (clave, valor, descripcion)
values (
  'disciplina_descargo_previo',
  'true'::jsonb,
  'Si antes de firmar una amonestación o una suspensión hay que comunicar los cargos, esperar el plazo del art. 55.2 del RIT y valorar el descargo por escrito. En true se exige: un memo firmado sin descargo previo no sirve de escalón para el art. 25 h) de la LPCL, y por eso se exige. Encendida el 29-10-2026 (migración 0566); estuvo en false desde el 17-08-2026 (migración 0267).'
)
on conflict (clave) do update
  set valor = 'true'::jsonb,
      descripcion = excluded.descripcion;

insert into migraciones_aplicadas (numero, nombre) values (566, 'el_descargo_previo_se_enciende')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ============================================================================
-- COMPROBACIÓN — pegar junto con la migración y leer las cuatro columnas
-- ============================================================================
--
-- `exige_descargo_previo` debe decir TRUE.
-- `borradores_a_la_espera` son los borradores de amonestación o suspensión que
--   desde ahora piden comunicar cargos antes de firmar. No están roncos: están
--   esperando. Para cada uno, o se comunican los cargos en la pantalla, o se
--   declara la comunicación ya ocurrida con fn_expediente_declarar_cargos_comunicados.
-- `borradores_con_cargos_ya_comunicados` son los que no se ven afectados.
-- `registro` tiene que decir 566 y el nombre de ESTA migración — si dice otro
--   nombre, el número lo tenía ocupado otra y hay que renumerar.
select
  (select valor from configuracion where clave = 'disciplina_descargo_previo')
    = 'true'::jsonb                                            as exige_descargo_previo,
  (select count(*) from expediente_disciplinario
    where estado = 'borrador' and nivel in ('amonestacion', 'suspension')
      and cargos_comunicados_at is null)                       as borradores_a_la_espera,
  (select count(*) from expediente_disciplinario
    where estado = 'borrador' and nivel in ('amonestacion', 'suspension')
      and cargos_comunicados_at is not null)                   as borradores_con_cargos_ya_comunicados,
  (select nombre from migraciones_aplicadas where numero = 566) as registro;
