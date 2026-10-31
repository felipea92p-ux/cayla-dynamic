-- ============================================================================
-- 0568 — La falta grave llega hasta el despido
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que el tercer peldaño del art. 54.1 —el despido— exista, se pueda recorrer
-- entero y no se pueda falsear. Cuatro piezas, cada una necesaria para la
-- siguiente:
--
--   1. El catálogo del art. 53 admite las faltas GRAVES del numeral 53.3. Hoy
--      su CHECK solo deja entrar 53.1 y 53.2, así que una falta grave no se
--      podía ni nombrar.
--   2. `fn_expediente_crear_conducta` admite el nivel `imputacion`: DO cita el
--      literal exacto del 53.3 y concede el plazo del art. 31 de la LPCL.
--   3. `fn_expediente_crear_despido` arma la carta de despido A PARTIR de su
--      imputación, que es la única fuente de la causa.
--   4. Un trigger impide cambiarle la causa a una carta de despido por una
--      escritura directa.
--
-- ── EL AGUJERO QUE CIERRA, MEDIDO ───────────────────────────────────────────
--
-- Hoy no existe NINGUNA forma de emitir una carta de despido. Se comprobó
-- preguntándole al catálogo: `fn_expediente_generar_falta` y
-- `fn_expediente_generar_tardanza` llegan hasta la imputación y ahí paran con
-- un mensaje que lo dice —«el despido se genera tras evaluar los descargos
-- (paso manual de Gerencia)»—, `fn_expediente_crear_conducta` rechaza todo lo
-- que no sea verbal o amonestación, y `fn_expediente_crear_borrador` (que sí
-- acepta el nivel) no la llama ninguna pantalla.
--
-- Así que «el paso manual de Gerencia» no era un paso: era el final del
-- camino. El expediente se armaba completo y la decisión se ejecutaba fuera
-- del sistema, en un Word, sin que la causa de la carta quedara atada a la de
-- la imputación.
--
-- Y por el mismo camino faltaba el plazo. `fn_expediente_comunicar_cargos` y
-- `fn_expediente_declarar_cargos_comunicados` rechazan los dos niveles de
-- arriba —«La imputación y el despido siguen el procedimiento del artículo
-- 57»—, y ese procedimiento no estaba escrito en ninguna función. Una
-- imputación no tenía manera de recibir su `descargo_vence_at`.
--
-- ── QUÉ NO HACE, Y POR QUÉ ──────────────────────────────────────────────────
--
-- · NO arranca el reloj del art. 31. El plazo de descargo de una imputación
--   corre desde la RECEPCIÓN de la carta, no desde que se redacta
--   —`fn_expediente_resolver` ya lo dice así: «el plazo del art. 31 corre
--   desde la recepción»—. Esta migración guarda los días concedidos
--   (`plazo_descargo_dias`) y la 0569 calcula el vencimiento al entregar,
--   donde ya va a reescribir `fn_expediente_entregar` por el art. 57.8. Una
--   función reescrita una vez por dos razones, y no dos veces.
--
-- · NO exige que todo despido venga de una imputación. El segundo párrafo del
--   art. 57.2 exceptúa «el supuesto de falta grave flagrante en que no resulte
--   razonable conceder dicho plazo», y eso es ley: bloquearlo dejaría a CAYLA
--   sin poder despedir por una agresión presenciada. Lo que sí se vuelve
--   imposible es una cadena FALSA: si hay imputación, la causa se hereda y no
--   se puede tocar.
--
-- · NO registra a mano el literal e) (asistencia) ni el f) (hostigamiento
--   sexual), aunque los dos entran al catálogo. Ver abajo.
--
-- · NO toca `fn_expediente_resolver`, y ahí queda un defecto medido que esta
--   migración esquiva pero no arregla: resolver no comprueba que el plazo de
--   descargo haya vencido, así que hoy se puede archivar o decidir el despido
--   el mismo día de la entrega, sin haber escuchado. `fn_expediente_crear_despido`
--   pone esa puerta por su lado (no arma la carta si el plazo sigue corriendo y
--   no se valoró ningún descargo), que es donde hace daño. Arreglar resolver es
--   su propia entrega: reescribirlo acá, sin su md5 de producción pedido para
--   él, es el accidente de la 0276.
--
-- · NO crea pantallas. La imputación y el despido se piden hoy por RPC.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
-- · Que `fn_expediente_puede_actuar` ya reparte la competencia del art. 54.4 c):
--   para los niveles `imputacion` y `despido` solo pasa `fn_es_admin_o_lider()`
--   —admin o lider_do—, porque la rama de `supervisor_sede` está acotada a
--   `verbal` y `amonestacion`. Esta migración NO vuelve a comprobar roles: los
--   pregunta ahí. Es la decisión de Felipe del 2026-10-29: «solo DO/Gerencia
--   citan».
--
-- · Que la FIRMA de la carta de despido ya está reservada a la Gerencia
--   General: `fn_expediente_puede_suscribir` devuelve `p_rol = 'admin'` para
--   el nivel `despido`, y `trg_expediente_firmante_elegible` lo hace cumplir.
--   Por eso acá DO puede PREPARAR la carta y no puede firmarla — la misma
--   forma que la 0567 le dio a la suspensión.
--
-- · Que el 53.3 del RIT v4.0 es enunciativo. Su propio texto lo dice: «Son
--   faltas graves, únicamente, las tipificadas en el artículo 25 de la LPCL»,
--   y cierra con «Las demás causales del artículo 25 de la LPCL se aplican
--   conforme a su propio texto, aunque este Reglamento no las desarrolle».
--   El catálogo, entonces, no agota el art. 25: ayuda a citarlo.
--
-- ── POR QUÉ LA CAUSA SE HEREDA EN VEZ DE COMPROBARSE ────────────────────────
--
-- El art. 57.7 dice: «La causa expresada en la carta de imputación vincula a
-- la carta de despido y no puede modificarse». El primer diseño recibía la
-- causa en `fn_expediente_crear_despido` y comprobaba que coincidiera con la
-- de la imputación. Se descartó: una comprobación es un `if`, y un `if` existe
-- porque el dato pudo llegar mal.
--
-- La carta de despido no recibe causa. Recibe su imputación, y de ahí saca la
-- causa, el tipo de causal, el periodo de los hechos y la persona. No puede
-- divergir porque no hay nada que divergir — y el caso borde desaparece en vez
-- de gestionarse.
--
-- ── POR QUÉ 53.3 e) Y f) ENTRAN AL CATÁLOGO PERO NO SE REGISTRAN A MANO ─────
--
-- Las dos van con `se_registra_a_mano = false`, que es la columna que la 0510
-- creó justo para esto, y por dos razones distintas:
--
-- · e) ASISTENCIA (abandono, inasistencias, impuntualidad reiterada). No la
--   escribe una persona: la miden los motores. `fn_expediente_generar_falta` y
--   `fn_expediente_generar_tardanza` ya construyen esa cadena con sus umbrales
--   y sus exclusiones, por las causales `falta` y `tardanza`. Dejarla
--   registrable a mano por conducta abriría una SEGUNDA puerta a la misma
--   pregunta, con otros umbrales —el defecto que la 0237 vino a cerrar, y que
--   la 0297/0299 repitió el 2026-08-25 con dos funciones del mismo nombre.
--
-- · f) HOSTIGAMIENTO SEXUAL. Tiene procedimiento propio y plazos propios
--   (arts. 47 a 51 del RIT, Ley 27942): comité de intervención, medidas de
--   protección a la víctima, plazos que no son los del art. 55 ni los del 57.
--   Tramitarlo como un memo disciplinario no es un atajo: es incumplir la ley
--   que lo regula, y además lo haría visible a quien no debe verlo. Entra al
--   catálogo para que el sistema sepa NOMBRARLO y para que el día que alguien
--   lo busque encuentre el literal con su texto; no para tramitarlo acá.
--
-- Están en el catálogo y no fuera de él porque el catálogo es el Reglamento, y
-- el Reglamento las tiene. Omitirlas haría que la pantalla enseñara un art. 53
-- incompleto a quien lo consulte.
--
-- ── POR QUÉ UNA COLUMNA PARA LOS DÍAS Y NO UN 6 ESCRITO EN EL CÓDIGO ────────
--
-- El art. 57.2 concede «un plazo no menor de seis (6) días naturales para que
-- se defienda de los cargos formulados, o de treinta (30) días naturales para
-- que demuestre su capacidad». Son dos plazos distintos, y el primero es un
-- MÍNIMO: conceder ocho días es lícito y es mejor defensa. Un 6 fijo en el
-- código le quitaría a DO la posibilidad de ser más generosa que el mínimo
-- legal, que es justamente lo que conviene cuando un despido se va a discutir.
--
-- Y son días NATURALES, no hábiles: `fn_sumar_dias_habiles` sirve al plazo del
-- art. 55.2 (dos días hábiles para las sanciones menores) y no a este. Dos
-- relojes distintos porque la ley usa dos relojes distintos.
--
-- ── MD5 DE PARTIDA (pedido a PRODUCCIÓN el 2026-10-30) ──────────────────────
--
--   fn_expediente_crear_conducta   3359 caracteres
--                                  tal cual        a7cdf75aebea7b63b7d3c26d1f98e79f
--                                  sin comentarios 51311ad41a18dcdbd2fae6c4e6dbdcea
--                                  retornos \r     0
--
-- Coincide byte por byte con la 0510 de este repositorio, que es la última que
-- la define (comprobado con `donde-vive.sh`). El cuerpo de abajo parte de ese
-- texto: lo que cambia está marcado «CAMBIO 0568».
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   drop trigger if exists trg_bloquea_causa_del_despido on expediente_disciplinario;
--   drop function if exists fn_bloquear_causa_del_despido();
--   drop function if exists fn_expediente_crear_despido(uuid, date, text);
--   alter table expediente_disciplinario drop constraint if exists chk_plazo_descargo_del_art_31;
--   alter table expediente_disciplinario drop column if exists plazo_descargo_dias;
--   alter table faltas_catalogo drop constraint if exists chk_gravedad_grave_del_numeral;
--   -- y devolver `chk_conducta_completa` a su forma de la 0510 (líneas 276-292
--   -- de esa migración), que es la misma menos la rama nueva del 53.3.
--   drop index if exists uq_conducta_un_hecho_un_documento;
--   create unique index uq_conducta_un_hecho_un_documento
--     on expediente_disciplinario (persona_id, falta_numeral, falta_literal, periodo_desde)
--     where tipo_causal = 'conducta' and estado <> 'anulado';
--   -- y volver a pegar la 0510 desde «create or replace function
--   -- fn_expediente_crear_conducta» hasta su `revoke`.
--
-- Las filas del 53.3 en `faltas_catalogo` NO se revierten: el catálogo es
-- inmutable por trigger (`trg_faltas_catalogo_inmutable`) y puede haber
-- documentos que las citen. Quedarse con seis literales que nadie usa no rompe
-- nada; borrar una falta que un documento entregado cita, sí.
-- ============================================================================

begin;


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · El catálogo admite la falta grave
-- ════════════════════════════════════════════════════════════════════════════
-- Dos CHECK se abren. `chk_gravedad_del_numeral` NO se toca: dice
-- «(numeral = '53.1') = (gravedad = 'leve')», y para un 53.3 grave eso es
-- false = false, o sea verdadero. Lo que se agrega es la otra mitad, para que
-- los tres numerales queden amarrados a su gravedad y no haya forma de
-- escribir un 53.3 «significativa» ni un 53.2 «grave».

alter table faltas_catalogo drop constraint if exists faltas_catalogo_numeral_check;
alter table faltas_catalogo add constraint faltas_catalogo_numeral_check
  check (numeral in ('53.1', '53.2', '53.3'));

alter table faltas_catalogo drop constraint if exists faltas_catalogo_gravedad_check;
alter table faltas_catalogo add constraint faltas_catalogo_gravedad_check
  check (gravedad in ('leve', 'significativa', 'grave'));

alter table faltas_catalogo drop constraint if exists chk_gravedad_grave_del_numeral;
alter table faltas_catalogo add constraint chk_gravedad_grave_del_numeral
  check ((numeral = '53.3') = (gravedad = 'grave'));

comment on table faltas_catalogo is
  'Las faltas leves (53.1), significativas (53.2) y graves (53.3) del RIT, por versión. Inmutable: una versión nueva agrega sus filas. Cada documento de conducta del expediente apunta a la suya.';

-- Textos literales de docs/reglamento-interno-de-trabajo.md, v4.0, art. 53.3.
-- `on conflict do nothing` y no `do update`: la fila es inmutable, y repegar
-- esta migración no debe ni intentar tocarla (igual que la 0510).
insert into faltas_catalogo (rit_version, numeral, literal, gravedad, se_registra_a_mano, texto) values
  (4.0, '53.3', 'a', 'grave', true,  $t$En el literal a) del artículo 25 de la LPCL —incumplimiento de las obligaciones de trabajo que supone el quebrantamiento de la buena fe laboral, y la inobservancia de este Reglamento, expedido y puesto en conocimiento conforme al artículo 60, que revista gravedad—: registrar la asistencia de otra persona o permitir que otra registre la propia; alterar o manipular el terminal, el sistema o los registros de asistencia; consignar datos falsos en una justificación, en una solicitud de corrección de marcaje o en un descargo.$t$),
  (4.0, '53.3', 'b', 'grave', true,  $t$En el literal c) —apropiación consumada o frustrada de bienes o servicios de la Empresa o que se encuentran bajo su custodia, así como su retención o utilización indebidas, en beneficio propio o de terceros y con prescindencia de su valor—: disponer de producto o de dinero de caja sin autorización. El faltante de caja o de mercadería, por sí solo y sin que se acredite la apropiación, la retención o la utilización indebida, no encuadra en este literal: se evalúa como falta significativa conforme al literal g) del numeral 53.2.$t$),
  (4.0, '53.3', 'c', 'grave', true,  $t$En el literal d) —uso o entrega a terceros de información reservada—: entregar a terceros listas de clientas, precios, diseños, moldes, patrones, proveedores o información de planilla, en los términos del artículo 41.$t$),
  (4.0, '53.3', 'd', 'grave', true,  $t$En el literal f) —actos de violencia, grave indisciplina, injuria y faltamiento de palabra—: la agresión física o verbal en agravio de la Empresa, de quien la representa, del personal jerárquico o de otra colaboradora, sea dentro del centro de trabajo o fuera de él cuando los hechos se deriven directamente de la relación de trabajo. La agresión física o verbal contra una clienta o contra un tercero se evalúa bajo el literal a) cuando por su gravedad quebrante la buena fe laboral, y en los demás casos como falta significativa del literal h) del numeral 53.2.$t$),
  -- false: la miden los motores por las causales `tardanza` y `falta`. Ver el
  -- encabezado.
  (4.0, '53.3', 'e', 'grave', false, $t$En el literal h) —asistencia—: el abandono de trabajo por más de tres (3) días consecutivos; las ausencias injustificadas por más de cinco (5) días en un periodo de treinta (30) días calendario; las ausencias injustificadas por más de quince (15) días en un periodo de ciento ochenta (180) días calendario; y la impuntualidad reiterada acusada por la Empresa, siempre que se hayan aplicado previamente amonestaciones escritas y suspensiones entregadas. Los umbrales, su cómputo y sus exclusiones son los de los artículos 19, 20 y 21.$t$),
  -- false: tiene procedimiento propio (arts. 47 a 51, Ley 27942). No va por un
  -- memo disciplinario. Ver el encabezado.
  (4.0, '53.3', 'f', 'grave', false, $t$En el literal i) —hostigamiento sexual—: las conductas descritas en el artículo 47, con el procedimiento y las garantías de los artículos 48 a 51.$t$)
on conflict (rit_version, numeral, literal) do nothing;


-- ════════════════════════════════════════════════════════════════════════════
-- 2 · Una imputación por conducta ya puede citar su literal
-- ════════════════════════════════════════════════════════════════════════════
-- `chk_conducta_completa`, de la 0510, obliga hoy a que una imputación o un
-- despido por conducta tengan los tres campos de la falta en NULL. Su comentario
-- dice por qué: «Imputación y despido por conducta: nunca un literal del
-- catálogo […] se fundan en una falta GRAVE del 53.3, que cita el artículo 25
-- de la LPCL y no un literal del catálogo».
--
-- Eso era cierto cuando se escribió, y dejó de serlo hace veinte líneas: el
-- 53.3 ya está en el catálogo. La restricción no estaba mal — guardaba una
-- premisa, y la premisa cambió. Dejarla como está haría imposible lo que esta
-- migración viene a hacer, y lo haría en el sitio donde más cuesta notarlo: el
-- freno salta al INSERTAR, con el mensaje de un CHECK, no con una explicación.
--
-- Lo cazó la prueba 458 al primer intento, antes de pegar nada.
--
-- La forma nueva admite las DOS, y es un superconjunto de la vieja —ninguna
-- fila que pasaba deja de pasar—:
--
--   · los tres en NULL: una imputación preparada por la puerta vieja
--     (`fn_expediente_crear_borrador`), que no recibe la falta. La prueba 170
--     crea una así, y tiene que seguir pasando.
--   · los tres completos Y el numeral igual a '53.3': la imputación que cita su
--     literal. Que el numeral sea 53.3 no es adorno: es el 53.4 hecho
--     imposible de contradecir desde la base —«La calificación de una conducta
--     como falta significativa nunca habilita el despido»—, no solo desde una
--     función que alguien podría no llamar.
--
-- Lo que NO se exige en esta rama es el hecho único con su relato de veinte
-- caracteres, que la rama de la sanción menor sí pide. Una imputación de la
-- puerta vieja trae sus hechos en otro formato (la 170 usa `{"fecha","tipo"}`),
-- y romper eso no agrega ninguna garantía: el relato ya lo exige
-- `fn_expediente_crear_conducta`, que es por donde se crean las nuevas.
alter table expediente_disciplinario drop constraint if exists chk_conducta_completa;
alter table expediente_disciplinario
  add constraint chk_conducta_completa check (coalesce(
    case
      when tipo_causal = 'conducta' and nivel in ('verbal', 'amonestacion', 'suspension') then
           num_nonnulls(falta_rit_version, falta_numeral, falta_literal, conocido_el) = 4
       and periodo_desde is not null
       and periodo_hasta = periodo_desde
       and conocido_el >= periodo_desde
       and case when jsonb_typeof(hechos) = 'array' then jsonb_array_length(hechos) = 1 else false end
       and (hechos->0->>'fecha')::date = periodo_desde
       and length(btrim(coalesce(hechos->0->>'relato', ''))) >= 20
      -- CAMBIO 0568 · Imputación y despido por conducta: o sin literal (la
      -- puerta vieja), o con el literal completo de una falta GRAVE.
      when tipo_causal = 'conducta' then
           num_nulls(falta_rit_version, falta_numeral, falta_literal) = 3
        or (num_nonnulls(falta_rit_version, falta_numeral, falta_literal) = 3
            and falta_numeral = '53.3')
      else num_nulls(falta_rit_version, falta_numeral, falta_literal, conocido_el) = 4
    end, false));


-- Y el mismo cambio de premisa alcanza al índice único de al lado,
-- `uq_conducta_un_hecho_un_documento`, que la 0510 creó sobre
-- (persona, numeral, literal, periodo_desde) con el comentario «52.5 · El mismo
-- hecho no se documenta dos veces».
--
-- Nunca había alcanzado a una imputación ni a un despido, y no por decisión:
-- los tres campos de la falta iban en NULL, y en un índice único dos NULL no
-- chocan. Al citar el literal, la carta de despido —que hereda persona, falta y
-- fecha de su imputación— choca con ella. O sea: el índice haría imposible que
-- una imputación llegue a su propia carta, que es el peldaño que esta migración
-- viene a construir. Lo cazó la prueba 458 dos aserciones después del CHECK.
--
-- La respuesta no es relajar el 52.5 sino decir a qué se refiere. El 52.5
-- protege de SANCIONAR dos veces el mismo hecho, y la escala de sanciones del
-- 54.1 son tres: llamada verbal, amonestación escrita y suspensión. La
-- imputación de cargos no es una sanción —es el preaviso del art. 31 de la
-- LPCL, que abre el derecho de defensa— y el despido no es un peldaño de esa
-- escala: es la extinción del vínculo.
--
-- Así que el índice deja fuera solo el nivel `despido`. Lo que sigue
-- garantizando, y es lo que importa: un hecho, una sanción; y un hecho, una
-- sola imputación —imputar dos veces el mismo hecho, cada vez con su plazo,
-- sería el non bis in idem roto por la otra punta—. Lo único que deja de
-- garantizar es «un solo despido por hecho», que no hace falta vigilar acá:
-- a una persona se la cesa una vez, y de eso responden `fecha_cese` y el estado
-- del vínculo.
drop index if exists uq_conducta_un_hecho_un_documento;
create unique index uq_conducta_un_hecho_un_documento
  on expediente_disciplinario (persona_id, falta_numeral, falta_literal, periodo_desde)
  -- CAMBIO 0568 · `nivel <> 'despido'`: la carta hereda el hecho de su
  -- imputación a propósito (art. 57.7), así que no puede chocar con ella.
  where tipo_causal = 'conducta' and estado <> 'anulado' and nivel <> 'despido';


-- ════════════════════════════════════════════════════════════════════════════
-- 3 · Los días de plazo del art. 31, guardados
-- ════════════════════════════════════════════════════════════════════════════
alter table expediente_disciplinario
  add column if not exists plazo_descargo_dias int;

comment on column expediente_disciplinario.plazo_descargo_dias is
  'Días NATURALES de plazo de descargo concedidos en una imputación de cargos (art. 57.2 del RIT, art. 31 de la LPCL). Mínimo seis. El vencimiento se calcula al ENTREGAR, porque el plazo corre desde la recepción.';

-- El mínimo legal, hecho imposible de bajar. `is null` queda permitido a
-- propósito: las filas de antes no lo tienen, y una imputación creada por la
-- puerta vieja (`fn_expediente_crear_borrador`) tampoco.
alter table expediente_disciplinario drop constraint if exists chk_plazo_descargo_del_art_31;
alter table expediente_disciplinario add constraint chk_plazo_descargo_del_art_31
  check (plazo_descargo_dias is null or plazo_descargo_dias >= 6);


-- ════════════════════════════════════════════════════════════════════════════
-- 4 · DO cita la falta grave y concede el plazo
-- ════════════════════════════════════════════════════════════════════════════
-- Se reescribe `fn_expediente_crear_conducta` en vez de escribir una función
-- nueva al lado. La razón es el art. 52.3 y la integridad conceptual: «qué
-- falta del Reglamento es esta, y vale» se contesta UNA vez. Una segunda
-- función copiaría el catálogo, las fechas, el relato y el régimen —treinta
-- líneas— y el día que una de las dos cambie, las dos puertas contestarán
-- distinto.
--
-- Lo que decide los frenos es el NIVEL, que es como lo decide el Reglamento:
-- el art. 55 para la sanción menor, el art. 57 para la imputación.
--
-- DROP antes del CREATE, y no `create or replace`: el parámetro nuevo tiene
-- valor por defecto, así que la firma vieja de 7 argumentos y la nueva de 8
-- aceptarían las dos una llamada de 7, y Postgres respondería «function
-- fn_expediente_crear_conducta is not unique». No falla al pegar la migración:
-- falla al abrir la pantalla. Es exactamente lo que pasó con
-- `fn_vacaciones_por_vencer` el 2026-08-25 (0297 y 0299), que dejó el aviso de
-- vacaciones sin mostrarse en producción.
drop function if exists fn_expediente_crear_conducta(uuid, text, text, text, date, date, text);

create or replace function fn_expediente_crear_conducta(
  p_persona_id    uuid,
  p_numeral       text,
  p_literal       text,
  p_nivel         text,
  p_fecha_hecho   date,
  p_conocido_el   date,
  p_relato        text,
  -- CAMBIO 0568 · Días naturales de descargo. Obligatorio para `imputacion`,
  -- prohibido para los demás niveles: es el plazo del art. 31 de la LPCL.
  p_dias_descargo int default null
)
returns uuid language plpgsql volatile security definer set search_path = public as $$
declare
  v_falta faltas_catalogo%rowtype;
  v_p     personas%rowtype;
  v_id    uuid;
  v_sin_rit text;
begin
  if fn_expediente_puede_actuar(p_persona_id, p_nivel) is not true then
    raise exception 'Sin permiso para registrar una falta de nivel % sobre esta persona. La líder de equipo registra llamadas verbales y amonestaciones de integrantes de su sede; a una líder la amonesta DO.', p_nivel;
  end if;

  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;
  -- RIT 2.5 y 2.6: locadoras y practicantes no están en el régimen disciplinario.
  if v_p.estado <> 'activo' or v_p.en_planilla is not true then
    raise exception 'A esta persona no le alcanza el régimen disciplinario del Reglamento: no está activa o no tiene contrato de trabajo (RIT 2.5 y 2.6).';
  end if;

  -- CAMBIO 0568 · Antes: «p_nivel not in ('verbal','amonestacion')». La
  -- imputación de cargos entra como tercer nivel; la suspensión sigue fuera
  -- porque no se crea, se ELEVA desde la amonestación (0567).
  if p_nivel not in ('verbal', 'amonestacion', 'imputacion') then
    raise exception 'Por conducta se registra una llamada verbal, una amonestación escrita o una imputación de cargos. Una suspensión no se crea: se eleva desde la amonestación (art. 54.7).';
  end if;

  -- La falta, del catálogo de la versión vigente del RIT.
  select * into v_falta from faltas_catalogo
   where rit_version = (select max(rit_version) from faltas_catalogo)
     and numeral = p_numeral and literal = p_literal;
  if not found then
    raise exception 'La falta %) del numeral % no está en el catálogo del Reglamento vigente (art. 53): solo se sanciona lo que está escrito ahí (52.3).', p_literal, p_numeral;
  end if;
  if not v_falta.se_registra_a_mano then
    raise exception 'El literal %) del numeral % no se registra a mano: lo calcula el sistema o lo miden los motores de tardanzas e inasistencias.', p_literal, p_numeral;
  end if;

  -- CAMBIO 0568 · La correspondencia del art. 54.8, en los dos sentidos.
  --
  -- Hacia arriba: solo la falta grave habilita el art. 57. Lo dice el 53.4 sin
  -- rodeos: «La calificación de una conducta como falta significativa nunca
  -- habilita el despido».
  if p_nivel = 'imputacion' and v_falta.gravedad <> 'grave' then
    raise exception 'Una imputación de cargos solo procede por falta GRAVE del numeral 53.3; el literal %) del numeral % es %. El numeral 53.4 lo dice sin rodeos: la falta significativa nunca habilita el despido.', p_literal, p_numeral, v_falta.gravedad;
  end if;
  -- Hacia abajo: una falta grave no se amonesta de frente. El art. 57.6 ii) sí
  -- permite acabar en una sanción menor, pero DESPUÉS de imputar y escuchar —no
  -- en lugar de eso—. Amonestar por un 53.3 saltándose el art. 57 deja el
  -- hecho grave documentado como leve y consumido por el non bis in idem del
  -- 52.5: no se podrá volver sobre él.
  if p_nivel in ('verbal', 'amonestacion') and v_falta.gravedad = 'grave' then
    raise exception 'El literal %) del numeral % es una falta GRAVE: no se amonesta de frente, se imputa (art. 57.2). Si al evaluar el descargo corresponde una sanción menor, el art. 57.6 ii) la permite, pero después de imputar y escuchar.', p_literal, p_numeral;
  end if;

  -- CAMBIO 0568 · El plazo del art. 31 de la LPCL. Días NATURALES: el reloj
  -- de `fn_sumar_dias_habiles` es el del art. 55.2 y no sirve acá.
  if p_nivel = 'imputacion' then
    if p_dias_descargo is null then
      raise exception 'Falta el plazo de descargo. El art. 57.2 exige concederlo por escrito: no menor de seis (6) días naturales para defenderse de los cargos.';
    end if;
    if p_dias_descargo < 6 then
      raise exception 'El plazo de descargo no puede ser menor de seis (6) días naturales (art. 57.2 del RIT, art. 31 de la LPCL). Pediste %.', p_dias_descargo;
    end if;
  elsif p_dias_descargo is not null then
    raise exception 'El plazo de seis días del art. 57.2 es de la imputación de cargos. Una amonestación abre el plazo del art. 55.2 (dos días hábiles), y eso se hace con fn_expediente_comunicar_cargos.';
  end if;

  if p_fecha_hecho is null or p_fecha_hecho > fn_hoy_lima() then
    raise exception 'La fecha del hecho es obligatoria y no puede ser futura.';
  end if;
  if p_conocido_el is null or p_conocido_el > fn_hoy_lima() then
    raise exception 'La fecha en que se supo del hecho es obligatoria y no puede ser futura (RIT 52.6).';
  end if;
  if p_conocido_el < p_fecha_hecho then
    raise exception 'No se puede saber de un hecho antes de que ocurra: la fecha en que se supo es anterior a la del hecho.';
  end if;
  if length(btrim(coalesce(p_relato, ''))) < 20 then
    raise exception 'Describe qué pasó, con al menos una frase completa: es lo que la persona va a leer y lo que se discute si lo cuestiona (RIT 55.3).';
  end if;

  -- CAMBIO 0568 · El numeral 60.5, que en el camino del art. 57 no lo
  -- comprobaba nadie.
  --
  -- `fn_expediente_comunicar_cargos` y `fn_expediente_declarar_cargos_comunicados`
  -- ya lo comprueban para la amonestación y la suspensión, y las dos rechazan
  -- la imputación. Así que la rama del despido —la que más cuesta si se
  -- equivoca— era la única sin este freno.
  --
  -- Pesa especialmente acá porque el propio literal a) del 53.3 condiciona la
  -- falta grave a un Reglamento «expedido y puesto en conocimiento conforme al
  -- artículo 60»: imputar la inobservancia de un Reglamento cuya entrega no
  -- consta es imputar el incumplimiento de algo que no se puede probar que la
  -- persona recibió.
  if p_nivel = 'imputacion' then
    v_sin_rit := fn_reglamento_no_acusado(p_persona_id, p_fecha_hecho);
    if v_sin_rit is not null then raise exception '%', v_sin_rit; end if;
  end if;

  insert into expediente_disciplinario (
    persona_id, tipo_causal, nivel, estado, hechos, periodo_desde, periodo_hasta,
    falta_rit_version, falta_numeral, falta_literal, conocido_el, creado_por,
    plazo_descargo_dias)
  values (
    p_persona_id, 'conducta', p_nivel, 'borrador',
    -- La fecha en ISO a mano y no con ::text, que depende del DateStyle de
    -- la sesión: los demás hechos del expediente se guardan así y el memo la
    -- lee así.
    jsonb_build_array(jsonb_build_object('fecha', to_char(p_fecha_hecho, 'YYYY-MM-DD'), 'relato', btrim(p_relato))),
    p_fecha_hecho, p_fecha_hecho,
    v_falta.rit_version, v_falta.numeral, v_falta.literal, p_conocido_el, fn_persona_actual_id(),
    p_dias_descargo)
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception 'Ese hecho ya está registrado: esta persona ya tiene un documento por la misma falta en la misma fecha. Un mismo hecho no se documenta dos veces (RIT 52.5).';
end;
$$;

grant execute on function fn_expediente_crear_conducta(uuid, text, text, text, date, date, text, int) to authenticated;
revoke execute on function fn_expediente_crear_conducta(uuid, text, text, text, date, date, text, int) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 5 · La carta de despido, hecha de su imputación
-- ════════════════════════════════════════════════════════════════════════════
-- No recibe causa. Recibe la imputación entregada y resuelta, y de ahí hereda
-- la causa (57.7), el tipo de causal, el periodo de los hechos y la persona.
--
-- Quién puede: DO o la Gerencia la PREPARAN (`fn_expediente_puede_actuar` con
-- nivel `despido`); solo la Gerencia la FIRMA, y eso ya lo hace cumplir
-- `trg_expediente_firmante_elegible` con `fn_expediente_puede_suscribir`.
-- Misma forma que la 0567 le dio a la suspensión: preparar no es imponer.
create or replace function fn_expediente_crear_despido(
  p_imputacion_id uuid,
  p_fecha_cese    date,
  p_motivo        text
)
returns uuid language plpgsql volatile security definer set search_path = public as $$
declare
  v_imp expediente_disciplinario%rowtype;
  v_id  uuid;
begin
  select * into v_imp from expediente_disciplinario where id = p_imputacion_id;
  if not found then raise exception 'Esa imputación de cargos no existe.'; end if;

  if fn_expediente_puede_actuar(v_imp.persona_id, 'despido') is not true then
    raise exception 'Sin permiso para preparar una carta de despido. La suscribe siempre la Gerencia General (art. 54.4 c del RIT).';
  end if;

  if v_imp.nivel <> 'imputacion' then
    raise exception 'La carta de despido se arma a partir de una imputación de cargos, que es la que formuló la causa y abrió el plazo (art. 57.7). Este documento es %.', v_imp.nivel;
  end if;

  -- El plazo del art. 31 corre desde la RECEPCIÓN. Una imputación que no se
  -- entregó no abrió ningún plazo, así que no hay nada que resolver ni que
  -- despedir.
  if v_imp.estado <> 'entregado' then
    raise exception 'Esa imputación todavía no se entregó (está %). El plazo de descargo corre desde la recepción: sin entrega no hay procedimiento abierto.', v_imp.estado;
  end if;

  -- El art. 57.6 exige resolver por escrito, y solo una de sus tres salidas
  -- lleva al despido. Sin esa decisión, la carta se estaría escribiendo antes
  -- de haberla tomado.
  if v_imp.resuelto_at is null then
    raise exception 'Primero se resuelve el procedimiento por escrito (art. 57.6): archivo, sanción menor o despido. Usa fn_expediente_resolver.';
  end if;
  if v_imp.resuelto_resultado <> 'despido' then
    raise exception 'Ese procedimiento se resolvió como «%» el %. El archivo no se reabre con una carta de despido: si hay una falta grave nueva, el art. 57.7 manda imputarla aparte, con su propio plazo.',
      v_imp.resuelto_resultado, to_char(v_imp.resuelto_at at time zone 'America/Lima', 'DD/MM/YYYY');
  end if;

  -- Y haberla tomado DESPUÉS de escuchar. `fn_expediente_resolver` no comprueba
  -- esto hoy —está dicho en el encabezado—, así que el freno va acá, que es
  -- donde se vuelve irreversible: o el plazo venció, o hay un descargo valorado.
  if v_imp.descargo_vence_at is not null
     and v_imp.descargo_vence_at > now()
     and v_imp.descargo_acogido is null then
    raise exception 'El plazo de descargo vence el % y no consta ningún descargo valorado. Despedir antes de que termine de defenderse deja el despido sin el art. 31 cumplido.',
      to_char(v_imp.descargo_vence_at at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI');
  end if;

  if p_fecha_cese is null then
    raise exception 'Falta la fecha de cese. El art. 32 de la LPCL exige que la carta indique de modo preciso la causa y la fecha de cese.';
  end if;
  -- Un cese con fecha pasada es un despido antedatado: la persona habría
  -- trabajado días que la carta declara fuera del vínculo, y el plazo de
  -- impugnación del art. 36 se contaría desde una fecha que no ocurrió.
  if p_fecha_cese < fn_hoy_lima() then
    raise exception 'La fecha de cese no puede ser anterior a hoy: el vínculo se extingue con la carta, no antes de ella.';
  end if;

  if length(btrim(coalesce(p_motivo, ''))) < 20 then
    raise exception 'Escribe por qué se resuelve el despido pese al descargo: es lo que se lee el día que se impugne (art. 57.6).';
  end if;

  insert into expediente_disciplinario (
    persona_id, tipo_causal, nivel, estado, hechos,
    periodo_desde, periodo_hasta, doc_previo_id,
    -- La causa NO se recibe: se hereda. Art. 57.7.
    falta_rit_version, falta_numeral, falta_literal, conocido_el,
    fecha_cese, observacion, creado_por)
  values (
    v_imp.persona_id, v_imp.tipo_causal, 'despido', 'borrador', v_imp.hechos,
    v_imp.periodo_desde, v_imp.periodo_hasta, v_imp.id,
    v_imp.falta_rit_version, v_imp.falta_numeral, v_imp.falta_literal, v_imp.conocido_el,
    p_fecha_cese, btrim(p_motivo), fn_persona_actual_id())
  returning id into v_id;

  insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (v_imp.persona_id, 'expediente.carta_de_despido',
          'imputación ' || coalesce(v_imp.correlativo, v_imp.id::text),
          'despido con cese el ' || to_char(p_fecha_cese, 'DD/MM/YYYY'),
          fn_persona_actual_id(),
          'Carta de despido preparada a partir de esa imputación; la causa se hereda (art. 57.7). ' || btrim(p_motivo));

  return v_id;
end;
$$;

grant execute on function fn_expediente_crear_despido(uuid, date, text) to authenticated;
revoke execute on function fn_expediente_crear_despido(uuid, date, text) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 6 · La causa de un despido no se cambia por una escritura directa
-- ════════════════════════════════════════════════════════════════════════════
-- El molde de la casa para un campo sensible, cuarta instancia después de
-- `fn_cambiar_regimen_pension` (0261), `fn_set_rol` (0295/0296) y
-- `fn_set_sede_base` (0342): una función guardián que valida, y un trigger que
-- rechaza lo que no venga de ella.
--
-- `current_user <> 'postgres'` es como Postgres distingue «lo hizo una función
-- interna» de «lo hizo un cliente por PostgREST»: el rol de conexión es
-- `authenticated` en los dos casos. Deja pasar al SQL Editor a propósito, que
-- es por donde se arregla un dato a mano.
--
-- Y no lleva `security definer`: el trigger tiene que correr con los permisos
-- de quien escribe, no con los del dueño, o cualquiera podría saltárselo
-- llamándolo desde otra función definer. Es la misma razón de la 0550.
create or replace function fn_bloquear_causa_del_despido()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.nivel <> 'despido' and old.nivel <> 'despido' then
    return new;
  end if;

  if (new.falta_rit_version is distinct from old.falta_rit_version
      or new.falta_numeral  is distinct from old.falta_numeral
      or new.falta_literal  is distinct from old.falta_literal
      or new.doc_previo_id  is distinct from old.doc_previo_id)
     and current_user <> 'postgres' then
    raise exception 'La causa de una carta de despido y la imputación de la que viene no se cambian: el art. 57.7 las deja vinculadas («La causa expresada en la carta de imputación vincula a la carta de despido y no puede modificarse»). Si la falta es otra, el procedimiento se reinicia con una imputación nueva y un plazo nuevo.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_bloquea_causa_del_despido on expediente_disciplinario;
create trigger trg_bloquea_causa_del_despido
  before update on expediente_disciplinario
  for each row execute function fn_bloquear_causa_del_despido();


insert into migraciones_aplicadas (numero, nombre) values (568, 'la_falta_grave_llega_hasta_el_despido')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

commit;


-- ════════════════════════════════════════════════════════════════════════════
-- COMPROBAR DESPUÉS DE PEGAR (en el SQL Editor)
-- ════════════════════════════════════════════════════════════════════════════
-- select
--   (select count(*) from faltas_catalogo where numeral = '53.3')              as graves_en_catalogo,
--   (select count(*) from faltas_catalogo where numeral = '53.3'
--       and se_registra_a_mano)                                                as graves_a_mano,
--   (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and p.proname = 'fn_expediente_crear_conducta')
--                                                                             as versiones_de_crear_conducta,
--   (select pg_get_function_identity_arguments(p.oid) from pg_proc p
--      join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public' and p.proname = 'fn_expediente_crear_despido') as firma_del_despido,
--   (select count(*) from pg_trigger
--     where tgrelid = 'expediente_disciplinario'::regclass
--       and tgname = 'trg_bloquea_causa_del_despido')                          as candado_puesto,
--   (select numero || ':' || nombre from migraciones_aplicadas where numero = 568) as registro;
--
-- Se espera: 6 · 4 · 1 · «p_imputacion_id uuid, p_fecha_cese date, p_motivo text» · 1 · «568:la_falta_grave_llega_hasta_el_despido».
--
-- `versiones_de_crear_conducta` = 1 es la que importa: un 2 significa que la
-- firma vieja de 7 argumentos sobrevivió al DROP y que la pantalla de registrar
-- una falta va a contestar «function is not unique» la próxima vez que se abra.
