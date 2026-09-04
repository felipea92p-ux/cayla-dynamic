-- ============================================================================
-- 0360_el_terminal_no_marca_por_otra_sede.sql
-- ============================================================================
-- QUÉ PROMETE
--
--   1. Que un terminal no pueda registrar horas de alguien que no puede marcar
--      en su sede. Hoy la puerta de LECTURA está cerrada y la de ESCRITURA
--      está abierta de par en par.
--   2. Que la regla «esta persona marca en esta sede» esté dicha UNA sola vez,
--      y que las tres puertas que hoy la repiten con sus propias palabras
--      —el roster que se pinta, las marcas que se leen y las que se escriben—
--      pasen a preguntársela a ella.
--   3. Que cerrar esa puerta NO pierda ni una marca real: ni la que la cola
--      offline entrega tarde, ni la del botón «Sí, volví a entrar».
--
-- ── EL DEFECTO, REPRODUCIDO CONTRA EL POSTGRES LOCAL ────────────────────────
--
-- El roster de un terminal solo ofrece a la gente de su sede, más quien tenga
-- `visible_todas_sedes` (0008 → 0285). Pero `fn_registrar_marcaje` nunca
-- compara la sede de `p_persona_id` con la del terminal: solo saca la sede DEL
-- TERMINAL y la escribe. Medido, con una persona cuya `sede_base_id` es LIM y
-- el terminal de TRU:
--
--     roster que ve ese terminal   → 0 personas
--     marcas que ese terminal pudo escribir para ella → 1, con sede_id = TRU
--
-- O sea: basta un UUID y el terminal escribe horas de otra sede. Eso no es un
-- agujero teórico — es una jornada que entra a la planilla con la sede
-- equivocada, y la sede es lo que decide el turno esperado, la tardanza y la
-- movilidad.
--
-- ── POR QUÉ UN DISPARADOR Y NO REESCRIBIR fn_registrar_marcaje ──────────────
--
-- Es la misma decisión que la 0086 dejó por escrito para este mismo problema:
--
--   a) «Un disparador sobre la tabla cubre TODOS los caminos, los de hoy y los
--      que alguien escriba mañana.» Hoy escriben en `marcajes` CUATRO
--      funciones —`fn_registrar_marcaje`, `fn_agregar_marcaje`,
--      `fn_reabrir_dia`, `fn_auto_cierre`— y `authenticated` conserva el
--      `grant` de INSERT sobre la tabla, sin ninguna policy de insert que lo
--      use. El día que alguien agregue esa policy, el candado ya está puesto.
--   b) `fn_registrar_marcaje` mide 12 952 caracteres y va por su versión 0327.
--      Reescribirla para agregar unas líneas es pedir una divergencia.
--   c) Su firma acaba de cambiar. La 0353 —fusionada a `main` el 2026-09-04 a
--      las 10:05, y todavía SIN pegar en producción— le hace `drop` a la firma
--      de 8 argumentos y `create` a una de 9. Si esta migración reescribiera
--      la función, la que se pegara segunda dejaría DOS sobrecargas vivas o
--      abortaría contra el md5 de la otra; y con dos sobrecargas, la llamada
--      de `enviar-marcaje.ts` —que pasa los argumentos NOMBRADOS— sería
--      ambigua: los cuatro terminales dejarían de poder marcar, y fallaría al
--      ABRIR la pantalla, no al pegar el SQL. Es literalmente el accidente de
--      la 0297/0299. Un disparador no toca el cuerpo ni la firma, así que la
--      0353 y esta se pegan en cualquier orden.
--      (Aviso a quien lea esto más tarde: el hecho «la 0353 está sin fusionar»
--      caducó el mismo día en que se escribió. El argumento no: lo que lo
--      sostiene es que la firma cambió, no en qué rama vivía.)
--
-- ── POR QUÉ ACOTADO A origen = 'terminal' ───────────────────────────────────
--
-- Porque las otras tres puertas escriben la sede a propósito y con criterio:
--
--   · `fn_agregar_marcaje` (admin_correccion) toma la sede de la PRIMERA marca
--     viva de ese día — «si la persona ya marcó ese día, de visita en otra
--     tienda, la corrección se graba en esa misma sede», dice su comentario.
--   · `fn_auto_cierre` (auto_cierre) hereda la sede de la jornada.
--   · Una corrección sobre alguien que CAMBIÓ DE SEDE (0342) lleva a propósito
--     la sede ANTIGUA: `marcajes.sede_id` no se actualiza nunca —comprobado, no
--     hay una sola función ni una sola migración que lo haga— así que el pasado
--     de `marcajes` y el presente de `personas` divergen por diseño.
--
-- Meterlas dentro del candado rompería el arreglo de días viejos, que es
-- exactamente el trabajo que se hace el día 28.
--
-- ── LAS TRES PUERTAS, Y POR QUÉ SON TRES Y NO UNA ───────────────────────────
--
-- Un candado que cierra siempre no es un candado: es una pantalla rota, y
-- alguien lo quita en la primera urgencia. Estas son las tres preguntas que
-- de verdad autorizan una marca, y son tres HECHOS distintos. La primera
-- versión de esta migración las intentó con un solo heurístico —«tiene alguna
-- marca viva en esa sede ese día o el anterior»— y hacía mal las tres. Lo que
-- sigue es lo que se midió, no lo que se supuso:
--
--   PUERTA 1 · «esta persona puede marcar en esta sede AHORA».
--     Es la regla del roster, dicha una sola vez (sección 1). Cubre el 99 % de
--     las marcas: la gente de la sede y quien viaja entre sedes (0008).
--
--   PUERTA 2 · «podía marcar aquí CUANDO SE HIZO esta marca».
--     Un candado que solo mire el estado ACTUAL de `personas` castiga a la
--     marca por algo que pasó DESPUÉS de que se hizo. Reproducido: Ana marca a
--     las 09:00 en el terminal de TRU; a las 10:00 Desarrollo Organizacional
--     la mueve a LIM; a las 11:00 la cola offline entrega la marca de las
--     09:00. Con la puerta 1 sola → RECHAZADA, y medido: `marcas guardadas de
--     Ana = 0`. No se pierde una marca, se pierde la JORNADA: la salida cae
--     después por la máquina de estados, que ya no encuentra entrada abierta.
--
--     Y no se pierde despacio. `apps/web/lib/terminal/enviar-marcaje.ts`
--     devuelve `llego: true` ante cualquier error del servidor —una excepción
--     de este disparador lo es— y `sync.ts` aparta la marca a los seis
--     reintentos de 15 s: 90 segundos y cartel rojo. El rescate existe
--     (`fn_marca_apartada_resolver`) pero repone con `v_p.sede_base_id`, la
--     sede NUEVA — o sea que la jornada acaba grabada justo en la sede
--     equivocada que esta migración vino a impedir.
--
--     La respuesta es preguntarle al hecho fechado, no adivinarlo: desde la
--     0342 la sede base SOLO se cambia por `fn_set_sede_base`, que deja la
--     fila en `correcciones_auditoria` con `campo_modificado =
--     'personas.sede_base_id'`, el CÓDIGO de la sede anterior y `corregido_at`.
--     Así que la marca entra si su sede fue la de esta persona hasta DESPUÉS
--     del instante en que se hizo. Es exacto, no se puede encadenar, y cubre
--     la ENTRADA — que es la mitad que el heurístico de marcas vivas no podía
--     cubrir nunca, porque la entrada ES la primera marca del día.
--
--   PUERTA 3 · «esta marca CONTINÚA una jornada que ya está viva aquí».
--     Cubre las dos cosas que la puerta 2 no puede: el botón «Sí, volví a
--     entrar» (`fn_reabrir_dia` escribe con origen 'terminal' y su
--     `retorno_otro` lleva `now()`, o sea un instante POSTERIOR al cambio de
--     sede), y el caso de quien perdió `visible_todas_sedes` —que no está
--     auditado en ninguna parte— con el día ya empezado.
--
--     Se pregunta a `jornadas`, que es el resumen que mantiene el trigger, y
--     no se reconstruye la máquina de estados a mano: `estado in ('abierta',
--     'en_pausa', 'auto_cerrada_pendiente')` ya responde «esta jornada espera
--     su marca». `trg_marcajes_recalcular_jornada` es AFTER, así que en un
--     BEFORE INSERT lo que se lee es el estado ANTERIOR a esta marca, que es
--     justo el que hay que juzgar.
--
--     Y LLEVA LA CONDICIÓN QUE LO CAMBIA TODO: `new.tipo <> 'entrada'`. Esta
--     puerta deja CONTINUAR o CERRAR una jornada; nunca ABRIR una. Sin esa
--     línea el candado se indulta a sí mismo para siempre: quien ya tiene una
--     marca mala de ayer en esa sede —o sea, exactamente la población que este
--     defecto YA dejó en producción— marcaría hoy apoyándose en la de ayer,
--     mañana en la de hoy, y la cadena no se cortaría nunca. Medido, con Beto
--     (sede B) y su entrada+salida de ayer en la sede A escritas por el
--     defecto: sin esa condición su entrada de hoy en A ENTRA; con ella,
--     rebota. Y con ella se cae también la única forma de forzar el candado
--     desde fuera, que era elegir el `timestamp_marca` —lo pone el cliente—
--     para arrimarlo a una jornada viva: probado, la entrada datada mañana
--     apoyada en la jornada de hoy REBOTA.
--
--     El «o el día anterior» no es holgura de cortesía: quien cierra tienda a
--     las 00:30 tiene su entrada en el día de calendario anterior (0240, 0318).
--
-- ── LO QUE SIGUE SIN CUBRIRSE, DICHO CON NOMBRE ─────────────────────────────
--
-- Si a alguien le retiran `visible_todas_sedes` mientras su ENTRADA del día
-- viaja en la cola offline, esa entrada se pierde igual. La puerta 2 no la
-- alcanza porque ese campo NO deja rastro: la 0342 le puso puerta y auditoría
-- a `sede_base_id` y no a él. No se arregla acá a propósito —sería auditar una
-- columna más de `personas`, que es otra migración con su propio trigger y su
-- propia prueba, el molde de la 0296 y la 0342— pero queda escrito para que el
-- día que aparezca el caso nadie lo busque en este archivo. Mientras tanto, la
-- marca no desaparece: cae en `marcas_apartadas`, que es una pantalla que DO
-- mira.
--
-- ── QUÉ SE LLEVA POR DELANTE ESTA MIGRACIÓN (y hay que arreglar con ella) ───
--
-- La prueba `146_el_resellado_del_dia.test.sql` sembraba, FUERA del bloque
-- `session_replication_role = replica`, una marca de terminal en la «sede
-- visitada» para alguien de otra sede base y sin `visible_todas_sedes`. Con
-- este candado ese estado ya no puede existir, así que la prueba abortaba a
-- media ejecución y sus dos últimas aserciones —las que defienden la mejora de
-- la 0188, perdida en producción desde julio— dejaban de correr: la firma
-- «Bad plan. You planned 7 tests but ran 5», con «Failed: 0», que este repo
-- documenta como el fallo que se lee discreto y no lo es.
--
-- No se arregló moviendo el insert dentro del `replica` —eso apagaría también
-- el candado del cese y la prueba pasaría sin que nada exista— sino diciendo
-- la verdad del negocio: quien VISITA otra tienda y marca ahí es exactamente
-- quien tiene `visible_todas_sedes`. El fixture ahora lo lleva. La prueba mide
-- lo mismo que medía.
--
-- ── LO QUE ESTE CANDADO NO COMPRUEBA, Y ES DELIBERADO ───────────────────────
--
-- NO mira `estado = 'activo'`. Esa mitad ya está cerrada desde la 0086 por
-- `trg_marcaje_no_posterior_al_cese`, y está cerrada MEJOR: rechaza por FECHA
-- de la marca, no por estado, así que una marca del lunes entregada tarde por
-- la cola —después de que la persona cesara el martes— sigue entrando, porque
-- esa persona sí trabajó ese lunes. Agregar aquí un `estado = 'activo'`
-- rompería ese caso y perdería el registro de alguien que sí estuvo.
--
-- NO mira `sede_fisica_id` (0166). Es deliberado y es una deuda que se nombra:
-- hoy el roster tampoco lo mira, así que quien tenga sede física distinta de su
-- sede base NO aparece en el terminal donde trabaja, y por tanto no puede estar
-- marcando ahí. Meterlo en esta función cambiaría a quién OFRECE el roster
-- —una pantalla de producción— sin un caso medido que lo pida. Antes de
-- tocarlo hay que correr en el SQL Editor la consulta que está al final del
-- archivo, bajo «LO QUE HAY QUE MIRAR EN PRODUCCIÓN».
--
-- ── SOBRE EL MENSAJE DEL RECHAZO: QUIÉN LO LEE DE VERDAD ────────────────────
--
-- El mensaje está redactado sin el nombre de la persona ni su sede. Conviene
-- saber para quién: NO para la Mac mini. `terminal/marcar/page.tsx` descarta el
-- texto del servidor y pinta siempre el suyo («No quedó registrada — el sistema
-- no aceptó esta marca de X»). Quien lee este texto es Desarrollo
-- Organizacional en la pantalla de marcas apartadas, y los logs. Por eso dice
-- qué hacer («DO puede habilitarla para marcar en todas las sedes») y no
-- filtra de qué sede es nadie: esos logs los mira más gente que DO.
--
-- ── SOBRE fn_persona_marca_en_sede Y EL grant A authenticated ──────────────
--
-- Riesgo aceptado y medido, no descuido: siendo SECURITY DEFINER y ejecutable
-- por `authenticated`, cualquiera con login del panel puede preguntar por el
-- par (uuid de persona, uuid de sede) y deducir la sede base de alguien que su
-- RLS no le deja ver. Se dejó así por tres razones: el grant NO es opcional
-- —sin él el terminal recibe «permission denied for function» al pintar su
-- lista, o sea una sede entera sin poder marcar—; acotar la respuesta a quién
-- pregunta rompería la razón de existir de la función, que es que las tres
-- puertas obtengan LA MISMA respuesta; y lo que se filtra es en qué tienda
-- trabaja alguien, en una empresa de cuatro sedes y treinta personas que se
-- conocen de vista. Si algún día hace falta cerrarlo, el camino es una vista
-- con RLS, no un `if` sobre el llamador.
--
-- ── LO QUE CUESTA, MEDIDO (y por qué se toca la vista igual) ────────────────
--
-- El encargo pedía no tocar `terminal_roster` si el plan de consulta empeoraba.
-- Se midió contra el Postgres local, con 40 personas y 4 sedes sembradas
-- —el tamaño real de CAYLA— dentro de `begin … rollback`:
--
--   · EL PLAN NO CAMBIA DE FORMA. Antes y después es el mismo
--     `Result → One-Time Filter (fn_sede_actual_terminal() IS NOT NULL)
--      → Nested Loop`, con las mismas filas devueltas y descartadas. Lo
--     importante es que el `One-Time Filter` SIGUE ahí: una sesión que no es
--     un terminal corta antes de tocar `personas` fila por fila, que era el
--     freno de la 0285.
--   · LECTURA DEL ROSTER: 0,30 ms → 0,63 ms por lectura. El doble, sí, pero
--     el doble de un tercio de milisegundo. Un terminal refresca su lista cada
--     120 s; con las cuatro sedes eso es ~1 segundo de CPU al día en total.
--   · ESCRITURA DE UNA MARCA: 1,31 ms → 1,97 ms con la versión de una puerta.
--     Las puertas 2 y 3 solo se evalúan cuando la 1 dice que no, o sea casi
--     nunca: en la marca normal el costo es el mismo `exists` de siempre.
--
-- Se paga eso a cambio de que la regla de sede deje de estar escrita en tres
-- sitios. No es una compra cara.
--
-- ── LO QUE ESTE CANDADO NO CUBRE, Y POR QUÉ NO SE AMPLÍA ────────────────────
--
-- Es BEFORE INSERT y no `before insert or update of sede_id`. Se comprobó de
-- tres formas que hoy NADA actualiza `marcajes.sede_id` —ninguna de las
-- funciones vivas en `pg_proc`, ninguna migración, ninguna escritura desde
-- `apps/web`— y que `marcajes` no tiene NI UNA policy de insert o de update:
-- las cuatro que tiene son de `select`, así que el `grant` de escritura que
-- conserva `authenticated` está muerto. La única forma de escribir es a través
-- de una función SECURITY DEFINER.
--
-- Se descartó ampliarlo a UPDATE por un caso concreto, no por pereza: el
-- siguiente trabajo después de esta migración es arreglar las marcas que este
-- defecto YA dejó en producción con la sede equivocada, y eso es un
-- `update marcajes set sede_id = …`. Un candado en esa puerta convertiría la
-- reparación en una pelea. Si algún día aparece una policy de update sobre
-- `marcajes`, esa policy es el problema —la tabla es append-only por diseño— y
-- no este disparador.
--
-- ── ORDEN ENTRE LOS DOS DISPARADORES BEFORE INSERT ──────────────────────────
--
-- Postgres los dispara por orden alfabético del nombre, así que
-- `trg_marcaje_no_posterior_al_cese` corre ANTES que
-- `trg_marcaje_sede_permitida`. Se eligió ese orden, no se heredó: si alguien
-- ya cesado y de otra sede intenta marcar, el mensaje que queda registrado es
-- «esa persona cesó el …», que es el motivo verdadero y el útil.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--   · 0008 (`visible_todas_sedes`), de donde sale la condición de sede.
--   · 0086 (`trg_marcaje_no_posterior_al_cese`), que sigue intacto.
--   · 0240 / 0318 (`jornadas.fecha` y la jornada que cruza medianoche).
--   · 0342 (`fn_set_sede_base`), que es lo que hace fiable la puerta 2: desde
--     ella, un cambio de sede base SIN fila de auditoría no puede ocurrir por
--     ninguna puerta que no sea `postgres` (migraciones, seeds y pruebas). La
--     guardia lo comprueba y AVISA si falta — sin ella la puerta 2 queda
--     inerte, que endurece el candado en vez de aflojarlo.
--   · 0241 (`fn_persona_en_roster_terminal`) y 0285 (`terminal_roster`), que
--     esta migración REESCRIBE para que dejen de llevar su propia copia de la
--     regla. Las dos las comprueba la GUARDIA de abajo, que ABORTA si
--     producción tiene otra versión — no basta con pedirlo en prosa: la 0361
--     de esta misma rama trae guardia ejecutable, y dos partes del mismo
--     trabajo no pueden resolver el mismo problema de dos formas distintas.
--
--     md5 de partida de `fn_persona_en_roster_terminal` (Postgres local):
--       tal cual y sin comentarios = 43efaf0bb189337d338812ced891eee5 (200)
--       (coinciden: esa función no lleva comentarios dentro del cuerpo)
--     PÍDESELO A PRODUCCIÓN JUSTO ANTES DE PEGAR, no antes de escribir:
--       select md5(prosrc), length(prosrc) from pg_proc p
--         join pg_namespace n on n.oid = p.pronamespace
--        where n.nspname='public' and proname='fn_persona_en_roster_terminal';
--     md5 de LLEGADA — el cuerpo que deja ESTA migración, para que repegarla
--     no pueda revertir en silencio a quien construya encima:
--       tal cual y sin comentarios = d23e0408912fe363d6a70b8eaf1711be (204)
--     Se midió DESPUÉS de fijar el número del archivo, no antes: los
--     marcadores del cuerpo cambian al renumerar, y eso produce la firma más
--     desconcertante que hay acá — misma longitud, distinto hash.
--
--     La guardia lo comprueba sola y aborta si no cuadra. Un md5 es una foto:
--     caduca en cuanto otra sesión trabaja.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--     drop trigger  if exists trg_marcaje_sede_permitida on marcajes;
--     drop function if exists fn_marcaje_sede_permitida();
--     -- y volver a pegar el bloque `create or replace view terminal_roster`
--     -- de la 0285 y el `create or replace function
--     -- fn_persona_en_roster_terminal` de la 0241, tal cual están ahí.
--     drop function if exists fn_persona_marca_en_sede(uuid, uuid);
--   Reabre que un terminal escriba horas de gente de otra sede.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final devuelve una fila con SEIS `true`. Y después,
--   mirar en producción la consulta de «LO QUE HAY QUE MIRAR EN PRODUCCIÓN».
-- ============================================================================


-- ── 0 · La guardia: esta migración se niega si producción no es lo que cree ─
--
-- Reescribe DOS objetos vivos: la función que sostiene la policy con la que el
-- terminal lee las marcas del día, y la vista que pinta el roster de las
-- cuatro Mac mini. Pegar cualquiera de las dos sobre una versión distinta la
-- revertiría EN SILENCIO — y `create or replace` no da ninguna señal.
--
-- Reconoce su propio trabajo, pero NO se salta la comprobación por eso: si el
-- cuerpo ya menciona `fn_persona_marca_en_sede` tiene que ser EXACTAMENTE el
-- que deja esta migración. Cualquier otro significa que alguien construyó
-- encima, y repegar esto lo borraría. Es el modo de fallar que este repo lleva
-- todo agosto documentando (la 0261 revirtiendo la 0275), y una guardia que se
-- apaga a sí misma es peor que no tenerla: imprime «sin daño» mientras lo hace.
do $guardia$
declare
  v_prosrc  text;
  v_md5     text;
  v_md5_sin text;
  v_cols    text;
  v_def     text;
begin
  -- 1 · fn_persona_en_roster_terminal (0241). BLOQUEA.
  select p.prosrc into v_prosrc
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_persona_en_roster_terminal';

  if v_prosrc is null then
    raise exception using
      message = 'FALTA LA 0241. fn_persona_en_roster_terminal no existe, y la policy '
             || 'marcajes_select_terminal la necesita.',
      hint    = 'Pega la 0241 antes que esta. Esta migración la REESCRIBE; no la crea '
             || 'desde cero a propósito, para no plantar una versión que nadie revisó.';
  end if;

  v_md5 := md5(v_prosrc);
  v_md5_sin := md5(array_to_string(array(
    select regexp_replace(l, '[[:space:]]*--.*$', '')
      from unnest(string_to_array(v_prosrc, chr(10))) as l
     where btrim(l) not like '--%'
  ), chr(10)));

  if position('fn_persona_marca_en_sede' in v_prosrc) > 0 then
    -- Ya se pegó alguna vez. Tiene que ser ESTA versión, no una construida encima.
    if v_md5 <> 'd23e0408912fe363d6a70b8eaf1711be' and v_md5_sin <> 'd23e0408912fe363d6a70b8eaf1711be' then
      raise exception using
        message = 'PARA. fn_persona_en_roster_terminal ya delega en fn_persona_marca_en_sede, '
               || 'pero NO es el cuerpo que deja esta migración. md5 encontrado: ' || v_md5
               || ' (' || length(v_prosrc) || ' caracteres).',
        hint    = 'Otra migración construyó encima de la 0360. Repegar esto la revertiría '
               || 'en silencio. Corre ./scripts/donde-vive.sh fn_persona_en_roster_terminal '
               || 'y mide DÓNDE está la diferencia antes de proponer explicaciones.';
    end if;
    raise notice 'La 0360 ya estaba aplicada (el roster ya delega la regla de sede). '
                 'Se vuelve a aplicar sin daño.';
  else
    if v_md5 <> '43efaf0bb189337d338812ced891eee5'
       and v_md5_sin <> '43efaf0bb189337d338812ced891eee5' then
      raise exception using
        message = 'PARA. fn_persona_en_roster_terminal no es la de la 0241. '
               || 'md5 encontrado: ' || v_md5 || ' (' || length(v_prosrc) || ' caracteres). '
               || 'Se esperaba 43efaf0bb189337d338812ced891eee5 (200).',
        hint    = 'Otra sesión la reescribió. Pegar esto la revertiría en silencio, y esa '
               || 'función sostiene la policy con la que el terminal lee las marcas del día.';
    end if;
  end if;

  -- 2 · terminal_roster (0285). BLOQUEA.
  --     Se comprueban sus PROPIEDADES y no el md5 de `pg_get_viewdef`: esa
  --     función reescribe la definición y su formato depende de la versión de
  --     Postgres, así que un md5 daría falsas alarmas entre local y producción
  --     sin haber cambiado nada. Lo que importa es que sea LA MISMA VISTA: sus
  --     seis columnas, su security_invoker y sus tres condiciones.
  select string_agg(attname, ',' order by attnum) into v_cols
    from pg_attribute
   where attrelid = 'public.terminal_roster'::regclass and attnum > 0 and not attisdropped;

  if v_cols is distinct from 'id,nombres,apellidos,pin_hash,sede_codigo,sede_nombre' then
    raise exception using
      message = 'PARA. terminal_roster no tiene las seis columnas de la 0285. Tiene: '
             || coalesce(v_cols, '(no existe)') || '.',
      hint    = 'Producción tiene otra vista. Pegar esto la revertiría, y es la que pinta '
             || 'el roster de las cuatro Mac mini.';
  end if;

  if coalesce((select array_to_string(reloptions, ',') from pg_class
                where oid = 'public.terminal_roster'::regclass), '')
     not like '%security_invoker=false%' then
    raise exception using
      message = 'PARA. terminal_roster perdió su security_invoker = false.',
      hint    = 'Con security_invoker activado la vista arrastra las policies de personas '
             || 'y el terminal deja de ver a nadie. Mira la 0285 antes de seguir.';
  end if;

  -- 3 · fn_set_sede_base (0342). AVISA, NO BLOQUEA — y la diferencia es
  --     deliberada, el mismo criterio que la 0361 usa con su cron. Si falta,
  --     el candado sigue siendo correcto: lo que pasa es que la puerta 2 queda
  --     INERTE, porque nadie escribe las filas de auditoría que ella consulta.
  --     Eso no da un resultado equivocado, da uno más estricto — y el precio
  --     es que la marca que la cola entrega tras un cambio de sede se apartaría
  --     en vez de entrar. Bloquear por algo que solo endurece enseñaría que los
  --     frenos de esta casa son trámite.
  if to_regprocedure('public.fn_set_sede_base(uuid, uuid)') is null then
    raise warning 'FALTA LA 0342. Sin fn_set_sede_base nadie escribe la auditoría del cambio '
                  'de sede, así que la PUERTA 2 de este candado queda inerte: la marca que la '
                  'cola offline entregue después de mudar a alguien se va a apartar en vez de '
                  'entrar. El candado funciona igual; pégala cuando puedas.';
  end if;

  v_def := pg_get_viewdef('public.terminal_roster'::regclass, true);
  if position('fn_sede_actual_terminal' in v_def) = 0
     or position('estado' in v_def) = 0
     or (position('visible_todas_sedes' in v_def) = 0
         and position('fn_persona_marca_en_sede' in v_def) = 0) then
    raise exception using
      message = 'PARA. terminal_roster no lleva las condiciones que la 0285 le puso.',
      hint    = 'Definición encontrada: ' || v_def;
  end if;
end
$guardia$;


-- ── 1 · La regla de sede, dicha una sola vez ────────────────────────────────
--
-- SECURITY DEFINER, por la misma razón que la escribió la 0241 para
-- `fn_persona_en_roster_terminal`: la llaman una vista y una policy, y si
-- consultara `personas` en crudo arrastraría las policies de `personas` dentro
-- de la evaluación. La respuesta tiene que ser la del roster, no la de quien
-- mira. (Lo que eso expone está medido y aceptado — ver el encabezado.)
--
-- STABLE, no VOLATILE: se evalúa una vez por fila y el planificador necesita
-- poder reutilizarla dentro de la misma consulta.
--
-- `p_sede_id is not null` va DENTRO y es lo que la hace null-safe por sí sola.
-- Sin esa línea, preguntar por una sesión que no es un terminal
-- —`fn_sede_actual_terminal()` devuelve null— daría TRUE para cualquiera con
-- `visible_todas_sedes`: la comparación de sede da null, pero el `or` la
-- salva. Es el null que se cuela como autorizado, la forma que este repo
-- prohíbe desde la 0078. Hoy la policy de la 0241 y la vista de la 0285 lo
-- compensan cada una por fuera; con esto, ese `is not null` de afuera pasa a
-- ser cinturón además de tirantes, y un cuarto llamador ya no puede olvidarlo.
--
-- `exists` y no una comparación suelta: nunca devuelve null, ni siquiera si la
-- persona no existe. Así el `is not true` de quien la llama no tiene que
-- adivinar.
create or replace function fn_persona_marca_en_sede(
  p_persona_id uuid,
  p_sede_id    uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from personas p
    where p.id = p_persona_id
      and p_sede_id is not null
      and (p.sede_base_id = p_sede_id or p.visible_todas_sedes is true)
  );
$$;

comment on function fn_persona_marca_en_sede(uuid, uuid) is
  'Si esta persona puede marcar en esta sede: es la suya, o viaja entre sedes (visible_todas_sedes, 0008). '
  'Es la MISMA condición que pinta el roster del terminal, que deja leer las marcas del día y que ahora '
  'deja escribirlas — dicha una sola vez para que las tres no puedan volver a decir cosas distintas. '
  'NO responde si la persona está activa: eso lo miran por separado el roster (estado) y el cese (0086, por fecha). Desde la 0360.';

-- El `grant` a authenticated NO es opcional y se midió: `terminal_roster` es
-- `security_invoker = false`, pero eso solo cubre los permisos sobre las TABLAS
-- referidas, no el EXECUTE de una función. Sin este grant, el terminal no
-- recibe cero filas: recibe «permission denied for function
-- fn_persona_marca_en_sede» al pintar su lista — una sede entera sin poder
-- marcar, que es justo el desastre que el encabezado de la 0285 describe.
-- Lo defiende la aserción del roster leído como `authenticated` en la 286.
revoke execute on function fn_persona_marca_en_sede(uuid, uuid) from public, anon;
grant  execute on function fn_persona_marca_en_sede(uuid, uuid) to authenticated, service_role;


-- ── 2 · El candado: un terminal escribe solo de quien puede marcar ahí ──────
create or replace function fn_marcaje_sede_permitida()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dia    date;
  v_codigo text;
begin
  -- Solo el camino del terminal. Las correcciones y el auto-cierre escriben la
  -- sede a propósito, y a veces la ANTIGUA (ver el encabezado).
  if new.origen <> 'terminal' then
    return new;
  end if;

  -- PUERTA 1 · puede marcar aquí AHORA. Es la regla del roster, y es el camino
  -- de casi todas las marcas: las dos de abajo ni se evalúan.
  if fn_persona_marca_en_sede(new.persona_id, new.sede_id) is true then
    return new;
  end if;

  v_dia := (new.timestamp_marca at time zone 'America/Lima')::date;

  -- PUERTA 2 · podía marcar aquí CUANDO SE HIZO la marca.
  -- La cola offline entrega tarde; entretanto DO pudo mudar a esa persona. El
  -- cambio de sede base deja fila desde la 0342 (`fn_set_sede_base`), con el
  -- CÓDIGO de la sede anterior y su instante. Si esta sede era la suya hasta
  -- después de esta marca, la marca es real y entra — incluida la ENTRADA, que
  -- es la que no tiene ninguna otra marca en la que apoyarse.
  if exists (
    select 1
      from correcciones_auditoria ca
      join sedes s on s.codigo = ca.valor_anterior
     where ca.persona_id       = new.persona_id
       and ca.campo_modificado = 'personas.sede_base_id'
       and ca.corregido_at     >= new.timestamp_marca
       and s.id                = new.sede_id
  ) then
    return new;
  end if;

  -- PUERTA 3 · esta marca CONTINÚA una jornada ya viva en esta sede.
  -- `new.tipo <> 'entrada'` no es un detalle: esta puerta deja cerrar o
  -- continuar lo que ya está abierto, nunca ABRIR. Sin esa condición, una
  -- marca mala de ayer autoriza la de hoy y la cadena no se corta jamás — que
  -- es exactamente la población que este defecto ya dejó en producción.
  -- Cubre `fn_reabrir_dia` (escribe con origen 'terminal') y la salida que la
  -- cola entrega después de que a alguien le retiraran `visible_todas_sedes`,
  -- que es el caso que la puerta 2 no puede ver porque ese campo no se audita.
  if new.tipo <> 'entrada' and exists (
    select 1 from jornadas j
     where j.persona_id = new.persona_id
       and j.sede_id    = new.sede_id
       and j.estado in ('abierta', 'en_pausa', 'auto_cerrada_pendiente')
       and j.fecha between v_dia - 1 and v_dia
  ) then
    return new;
  end if;

  -- Quien lee esto es DO en la pantalla de marcas apartadas, y los logs — no
  -- la Mac mini, que pinta su propio texto (ver el encabezado). Dice la sede y
  -- qué hacer; no dice de qué sede es la persona ni cómo se llama.
  select s.codigo into v_codigo from sedes s where s.id = new.sede_id;
  raise exception
    'Esta persona no está habilitada para marcar en la sede %. Si vino de visita, Desarrollo Organizacional puede habilitarla para marcar en todas las sedes.',
    coalesce(v_codigo, 'de esta terminal');
end;
$$;

comment on function fn_marcaje_sede_permitida() is
  'Cierra la puerta de ESCRITURA que quedó abierta cuando se cerró la de lectura: un terminal solo registra '
  'marcas de quien su roster puede ofrecer (puerta 1), de quien podía marcar ahí cuando la marca se hizo '
  '(puerta 2, contra la auditoría de cambio de sede de la 0342) y de quien continúa una jornada ya viva ahí '
  '(puerta 3, que nunca abre una jornada nueva). Acotado a origen = terminal a propósito — las correcciones '
  'de días viejos llevan la sede antigua y tienen que seguir entrando (0342). Desde la 0360.';

-- Idempotente: se pega a mano, y una mano se equivoca.
drop trigger if exists trg_marcaje_sede_permitida on marcajes;
create trigger trg_marcaje_sede_permitida
  before insert on marcajes
  for each row execute function fn_marcaje_sede_permitida();


-- ── 3 · El roster deja de llevar su propia copia de la regla ────────────────
--
-- Mismas seis columnas, mismo `security_invoker = false`, mismas otras dos
-- condiciones (`estado = 'activo'` y el freno del `is not null`). Lo único que
-- cambia es que la condición de sede ya no está escrita aquí.
--
-- El comentario de la 0285 decía que esta vista era «el único sitio donde
-- vive» esa condición, y ya era falso al escribirse: la 0241 la había copiado
-- dentro de `fn_persona_en_roster_terminal` cuarenta migraciones antes, y las
-- dos copias YA habían divergido en el `is not null`. Por eso esta migración
-- no añade una tercera copia para el disparador: quita las dos que había.
create or replace view terminal_roster
with (security_invoker = false)
as
select
  p.id,
  p.nombres,
  p.apellidos,
  p.pin_hash,
  s.codigo as sede_codigo,
  s.nombre  as sede_nombre
from personas p
join sedes s on s.id = p.sede_base_id
where p.estado = 'activo'
  -- El freno se queda AQUÍ además de dentro de la función: es una función sin
  -- argumentos y stable, así que para una sesión que no es terminal se
  -- resuelve una vez y corta antes de tocar `personas` fila por fila.
  and fn_sede_actual_terminal() is not null
  and fn_persona_marca_en_sede(p.id, fn_sede_actual_terminal()) is true;

comment on view terminal_roster is
  'Lo unico que el kiosco de marcaje necesita ver de una persona: como se llama, de que sede es y su pin_hash. Existe porque RLS filtra filas y no columnas, asi que mientras el terminal leyera `personas` su token alcanzaba el DNI y la remuneracion (0285). Desde la 0360 su condicion de sede la responde fn_persona_marca_en_sede.';

revoke all    on terminal_roster from public, anon;
grant  select on terminal_roster to authenticated;


-- ── 4 · Y la policy de lectura tampoco ──────────────────────────────────────
--
-- `create or replace` conserva el oid, así que la policy `marcajes_select_terminal`
-- de la 0241 sigue apuntando a esta misma función y no hay que tocarla.
--
-- El resultado de la policy es IDÉNTICO al de antes: su `fn_sede_actual_terminal()
-- is not null` de fuera ya hacía moot el único caso donde la respuesta cambia
-- (sesión que no es terminal + persona con visible_todas_sedes, que antes daba
-- true y ahora da false). Lo que cambia es que ahora la función no miente
-- cuando la llama otro.
create or replace function fn_persona_en_roster_terminal(p_persona_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
           select 1 from personas p
            where p.id = p_persona_id and p.estado = 'activo'
         )
     and fn_persona_marca_en_sede(p_persona_id, fn_sede_actual_terminal());
$$;

comment on function fn_persona_en_roster_terminal(uuid) is
  'Si esta persona aparece en el roster del terminal autenticado: activa, y con derecho a marcar en su sede. '
  'La mitad de la sede la responde fn_persona_marca_en_sede desde la 0360, la misma que usa la vista '
  'terminal_roster y el disparador de escritura. Creada en la 0241.';

revoke execute on function fn_persona_en_roster_terminal(uuid) from public, anon;
grant  execute on function fn_persona_en_roster_terminal(uuid) to authenticated, service_role;


insert into migraciones_aplicadas (numero, nombre)
values (360, 'el_terminal_no_marca_por_otra_sede')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
-- Seis `true`. El cuarto y el quinto son los que importan: que la regla de
-- sede haya quedado en UN sitio y no en tres.
select
  (select count(*) = 1 from pg_proc
    where proname = 'fn_persona_marca_en_sede')                     as existe_la_regla_de_sede,
  (select count(*) = 1 from pg_trigger
    where tgname = 'trg_marcaje_sede_permitida'
      and tgrelid = 'public.marcajes'::regclass
      and not tgisinternal)                                          as existe_el_candado,
  (select count(*) = 1 from pg_trigger
    where tgname = 'trg_marcaje_no_posterior_al_cese'
      and tgrelid = 'public.marcajes'::regclass
      and not tgisinternal)                                          as el_candado_del_cese_sigue,
  (select pg_get_viewdef('terminal_roster'::regclass)
            like '%fn_persona_marca_en_sede%')                       as el_roster_usa_la_regla,
  (select prosrc like '%fn_persona_marca_en_sede%' from pg_proc
    where proname = 'fn_persona_en_roster_terminal')                 as la_lectura_usa_la_regla,
  (select pg_get_expr(polqual, polrelid) like '%fn_persona_en_roster_terminal%'
     from pg_policy where polname = 'marcajes_select_terminal')      as la_policy_de_lectura_sigue_puesta;


-- ── LO QUE HAY QUE MIRAR EN PRODUCCIÓN (solo lee, no cambia nada) ───────────
--
-- Esta consulta responde de un vistazo las dos preguntas que este candado deja
-- abiertas y que NO se pueden medir en la base local (que no tiene personas):
--
--   · cuánta gente viaja entre sedes de verdad (`visible_todas_sedes`), que es
--     a quién el candado deja pasar por la primera puerta;
--   · quién tiene `sede_fisica_id` distinta de su sede base (0166) — si esa
--     persona trabaja en una sede donde el roster NO la ofrece, entonces su
--     asistencia ya entra hoy por otra puerta, y conviene saber cuál ANTES de
--     dar por cerrado este asunto.
--
-- select p.nombres, p.apellidos,
--        sb.codigo as sede_base, sf.codigo as sede_fisica,
--        p.visible_todas_sedes, p.estado
--   from personas p
--   left join sedes sb on sb.id = p.sede_base_id
--   left join sedes sf on sf.id = p.sede_fisica_id
--  where p.visible_todas_sedes or p.sede_fisica_id is not null
--  order by 1;
