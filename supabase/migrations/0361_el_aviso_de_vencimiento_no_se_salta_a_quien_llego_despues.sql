-- ============================================================================
-- 0361_el_aviso_de_vencimiento_no_se_salta_a_quien_llego_despues.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que un contrato por vencer o unas vacaciones por vencer generen su fila
--   de aviso para CADA admin o líder de DO activo con correo — incluidos los
--   que se dieron de alta DESPUÉS de que ese vencimiento se avisara por
--   primera vez. Y que nadie reciba dos veces el mismo aviso.
--
--   Dicho en una línea: la identidad de "esto ya se avisó" pasa de ser
--   (tipo, hecho) a ser (tipo, hecho, a quién, por qué canal).
--
-- QUÉ ASUME
--   · Que la 0356 y la 0357 ya están pegadas en producción. NO lo asume a
--     ciegas: la guardia del bloque 0 se niega a aplicarse si no lo están.
--   · Que el cuerpo vigente de `fn_generar_alertas_vencimiento` es el que
--     dejó la 0357. También lo comprueba, por md5.
--   · Que `alertas.persona_id`, en las filas de estos dos tipos, es el
--     DESTINATARIO del aviso — no la persona cuyo contrato vence. Eso lo
--     decidió la 0356 y no se cambia acá: la persona del vencimiento va en
--     `payload->>'persona_id'`.
--
-- ── EL DEFECTO, EN LENGUAJE DE NEGOCIO ─────────────────────────────────────
--
-- La 0356 escribió el freno anti-duplicado mirando el HECHO y olvidándose de
-- a quién se le avisa:
--
--     and not exists (select 1 from alertas a
--                     where a.tipo = 'contrato_por_vencer'
--                       and a.payload ->> 'evento' = <persona>|<fecha>)
--
-- El día que ese vencimiento entra en su ventana, el `cross join` reparte una
-- fila a cada persona de DO que exista EN ESE MOMENTO, y todas entran: el
-- `not exists` no ve las filas que está insertando su propio `insert`. Hasta
-- ahí, bien.
--
-- El problema es el día siguiente. A partir de la segunda corrida ya existe
-- una fila con ese `evento`, así que la condición apaga el aviso para TODO el
-- mundo — también para quien todavía no estaba. Si mañana entra una nueva
-- líder de DO, no recibe el aviso de ese contrato NUNCA. No lo recibe tarde:
-- no lo recibe. Se destraba sola solo cuando el hecho CAMBIA —un contrato
-- renovado a otra fecha, el siguiente aniversario de vacaciones—, o sea
-- meses después, y con el vencimiento ya encima o ya pasado.
--
-- Y falla en el peor de los modos que esta casa conoce: en silencio. Nadie
-- ve un error; alguien simplemente no recibe un correo que jamás supo que
-- debía llegarle. Es el mismo tipo de fallo que la 0356 nombró en su propio
-- encabezado como razón de existir.
--
-- ── POR QUÉ ADEMÁS SE COMPARA EL CANAL, SI HOY TODO ES 'email' ─────────────
--
-- Porque hoy es inerte y demostrablemente inerte: los dos `insert` escriben
-- `'email'` literal, así que cuando coinciden tipo, evento y destinatario,
-- el canal coincide siempre. Cero cambio de comportamiento hoy.
--
-- Y porque el día que exista el canal 'push' —la 0354 lo dejó escrito, y
-- `push_tokens` ya está en el esquema— quien escriba ese tercer bloque va a
-- copiar el `not exists` del bloque de al lado, que es exactamente cómo nació
-- este defecto. Sin el canal en la comparación, esa copia le devolvería un
-- push silenciosamente bloqueado por el correo que ya salió. Completar ahora
-- la identidad cuesta una columna; descubrirlo después cuesta otra migración
-- y un aviso que no llegó.
--
-- ── POR QUÉ LA GUARDIA NO PUEDE SER SOLO UN md5 ────────────────────────────
--
-- La casa declara el md5 de partida pidiéndoselo a PRODUCCIÓN. Acá no se
-- puede: al escribir esto, `fn_generar_alertas_vencimiento` NO EXISTE en
-- producción. Comprobado con `select count(*) from pg_proc where
-- proname = 'fn_generar_alertas_vencimiento'` en el SQL Editor → 0.
-- La 0356 y la 0357 están fusionadas a `main` pero todavía sin pegar.
--
-- Un md5 contra algo que no existe no compara nada: o aborta con un mensaje
-- que no explica, o —peor— se declara conforme comparando dos nulos. Así que
-- el md5 va, pero como CUARTA comprobación, no como única. Las tres primeras
-- son las que dicen POR QUÉ falta:
--
--   1 · El CHECK `alertas_tipo_check` tiene que admitir los dos tipos nuevos
--       (lo redefine la 0356). ES LA MÁS IMPORTANTE Y BLOQUEA: sin ella la
--       función existe, se ve sana, y sus `insert` revientan contra el CHECK
--       a las 08:00 de la mañana dentro de pg_cron — sin pantalla que lo
--       muestre y sin nadie mirando `cron.job_run_details`. Justo el fallo
--       silencioso que esta migración vino a quitar, reintroducido por la
--       puerta de al lado.
--
--   2 · `fn_vacaciones_saldo_interno` tiene que existir (la crea la 0357).
--       BLOQUEA por lo mismo: el cuerpo la llama, y PL/pgSQL no resuelve las
--       llamadas al crear la función. Sin ella, `create or replace` pasa sin
--       una queja y el bloque de vacaciones muere de noche.
--
--   3 · El cron 'generar-alertas-vencimiento' tiene que estar programado
--       (lo programa la 0356). AVISA, NO BLOQUEA — y la diferencia es
--       deliberada. Que falte el cron no produce un resultado equivocado:
--       produce NINGÚN resultado, visible para cualquiera que note que no
--       llega ni un aviso. Bloquear por algo inofensivo enseña que los
--       frenos de esta casa son trámite, y quien aprende eso usa
--       `--no-verify` el día que el freno importa.
--
--   4 · El md5 del cuerpo vigente, para no revertir en silencio el trabajo de
--       otra sesión. Se aceptan los DOS valores, tal cual y sin comentarios,
--       como manda `donde-vive.sh`: la mitad de las funciones de producción
--       se pegaron sin sus comentarios y su md5 nunca va a ser el del
--       repositorio.
--
--   md5 de partida — el cuerpo que deja la 0357, medido en el Postgres LOCAL
--   (no en producción, donde la función aún no existe):
--       tal_cual        = 2a96822b83e5d741d4e5ce390dd34751
--       sin comentarios = 302fc77c9abf81e831ecfdcb484a0505
--       length(prosrc)  = 2677
--   Vuelve a pedirlo a producción JUSTO ANTES de pegar esto, no antes de
--   escribirlo: un md5 es una foto, y caduca en cuanto otra sesión trabaja.
--
--   La quinta cara de la guardia es que reconoce su propio trabajo: si el
--   cuerpo ya contiene `a.persona_id = do_.id`, la migración ya se pegó. Se
--   detecta por CÓDIGO y no por un marcador en comentario, a propósito: un
--   comentario se pierde si el cuerpo se pega sin comentarios, y su texto
--   cambia al renumerar el archivo.
--
--   Pero reconocerse NO es saltarse el md5, y esa es la corrección que costó
--   más pensar acá. La primera versión de esta guardia, al encontrar la
--   cadena, se declaraba «ya aplicada» y NO comparaba nada. Como esa cadena es
--   el arreglo mismo, toda migración futura que lo conserve —que son todas— la
--   llevaría dentro: repegar la 0361 sobre una 0375 imaginaria la revertía sin
--   un solo error, imprimiendo «Se vuelve a aplicar sin daño» mientras lo
--   hacía, y la consulta de comprobación del final seguía devolviendo 1|2|2|1.
--   Reproducido contra el Postgres local. Es el accidente de la 0261 sobre la
--   0275 por la puerta de al lado — y una guardia que se apaga a sí misma es
--   peor que no tenerla, porque además tranquiliza.
--
--   Así que hay DOS md5 declarados y siempre se compara uno:
--     · el de PARTIDA (la 0357), si el cuerpo aún no tiene el arreglo;
--     · el de LLEGADA (esta migración), si ya lo tiene. Si no coincide,
--       alguien construyó encima y esto BLOQUEA.
--
--   md5 de llegada — el cuerpo que deja ESTA migración:
--       tal_cual        = 6fb28b2376967b404851e974af4f804b
--       sin comentarios = c72c309fa3761cf2ed9a911d70ecade3
--       length(prosrc)  = 3303
--   Medido DESPUÉS de fijar el número del archivo: los marcadores «CAMBIO
--   0361» del cuerpo cambian al renumerar, y eso da la firma más
--   desconcertante que hay acá — misma longitud, distinto hash.
--
-- ── LA TANDA QUE ESTO PRODUCE — MÍDELA ANTES DE PEGAR ──────────────────────
--
-- Corregir la deduplicación tiene un efecto secundario que hay que nombrar:
-- la primera corrida del cron después de pegar esto genera de golpe las filas
-- que les faltaban a los destinatarios dados de alta después de la primera
-- corrida. Son avisos que DEBIERON existir, no ruido — pero salen juntos, y
-- `fn_alertas_email_pendientes` manda UN CORREO POR FILA.
--
-- El detalle que evita el susto: HOY, en producción, esa tanda vale CERO.
-- La cola de vencimientos está vacía porque la función nunca ha corrido allá.
-- En la primera corrida, el código de hoy y el corregido generan exactamente
-- lo mismo. La diferencia solo aparece más adelante, el día que entre alguien
-- nuevo a DO.
--
-- Lo que sí conviene mirar antes de pegar NO es la diferencia, es el número
-- absoluto: cuántos correos salen esa primera mañana. Esta consulta responde
-- las dos cosas. SOLO LEE — pégala en el SQL Editor antes de nada:
--
--   with do_ as (
--     select id from personas
--      where rol in ('admin','lider_do') and estado = 'activo' and email is not null
--   ),
--   ev as (
--     select 'contrato_por_vencer'::text as tipo,
--            p.id::text || '|' || p.fecha_fin_contrato::text as evento
--       from personas p
--      where p.estado = 'activo' and p.fecha_fin_contrato is not null
--        and p.fecha_fin_contrato >= fn_hoy_lima()
--        and p.fecha_fin_contrato <= fn_hoy_lima() + 30
--     union all
--     select 'vacaciones_por_vencer'::text,
--            p.id::text || '|' || (x.r ->> 'vence_el')
--       from personas p
--       cross join lateral (select fn_vacaciones_saldo_interno(p.id, fn_hoy_lima()) as r) x
--      where p.estado = 'activo'
--        and (x.r ->> 'aplica')::boolean is true
--        and (x.r ->> 'records_sin_gozar')::int > 0
--        and ((x.r ->> 'dias_para_vencer')::int <= 60 or (x.r ->> 'records_vencidos')::int > 0)
--   ),
--   pares as (select ev.tipo, ev.evento, d.id as destinatario_id from ev cross join do_ d)
--   select (select count(*) from do_)   as destinatarios_do,
--          count(distinct pares.evento) as eventos_en_ventana,
--          count(*)                     as pares_totales,
--          count(*) filter (where not exists (
--            select 1 from alertas a
--             where a.tipo = pares.tipo and a.payload ->> 'evento' = pares.evento))
--                                       as correos_con_el_codigo_de_hoy,
--          count(*) filter (where not exists (
--            select 1 from alertas a
--             where a.tipo = pares.tipo and a.payload ->> 'evento' = pares.evento
--               and a.persona_id = pares.destinatario_id and a.canal = 'email'))
--                                       as correos_tras_el_arreglo
--     from pares;
--
--   Cómo se lee:
--     · `correos_tras_el_arreglo` es cuántos correos salen la próxima
--       corrida del cron. Es el número que le importa al buzón de DO.
--     · La resta contra `correos_con_el_codigo_de_hoy` es la tanda de puesta
--       al día que agrega ESTA migración. Hoy en producción va a dar 0.
--     · Si `correos_tras_el_arreglo` pasa de ~10, para y decide antes: con
--       un correo por fila, ~18 vencimientos × 3 personas de DO son 54
--       correos en una mañana a las mismas tres personas. Eso deja de ser un
--       aviso — el mismo criterio con el que la 0356 descartó avisar también
--       a la encargada. El arreglo de esa ráfaga es un digest (una fila por
--       destinatario con los N eventos dentro), y es otra migración.
--
--   Si la corres ANTES de pegar la 0357, quita el `union all` de vacaciones:
--   `fn_vacaciones_saldo_interno` todavía no existe y da la cota inferior.
--
--   Medida en el Postgres local con datos de prueba (3 personas de DO, 2
--   contratos en ventana, 5 récords de vacaciones alertables), tras haber
--   corrido el código de HOY una vez y haber dado de alta una cuarta persona
--   de DO después:
--       destinatarios_do | eventos | pares | con_el_codigo_de_hoy | tras_el_arreglo
--                      4 |       7 |    28 |                    0 |               7
--   Los 7 son exactamente los 7 eventos × la persona que llegó tarde.
--
-- ── QUÉ NO CAMBIA ──────────────────────────────────────────────────────────
--   · El cuerpo es el de la 0357 con cuatro líneas distintas y ni una más.
--     Comprobado con `diff` contra ese archivo.
--   · No toca `fn_alertas_email_pendientes` (0354 → 0358 → 0359): esta
--     migración escribe en la cola, aquella la vacía. Se pegan en cualquier
--     orden.
--   · No toca `fn_vacaciones_saldo` ni `fn_vacaciones_saldo_interno`.
--   · No cambia el CHECK, el cron, ni la firma: `create or replace` sobre
--     una función sin argumentos no puede producir una sobrecarga.
--
-- ── CÓMO SE REVIERTE ───────────────────────────────────────────────────────
--   Volver a pegar la sección 3 de la 0357 tal cual. No hay datos que
--   deshacer: esta migración no borra ni modifica ninguna fila de `alertas`.
--   Revertir significa volver a que quien entre a DO después de la primera
--   corrida no reciba nunca el aviso de un vencimiento ya alertado.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ───────────────────────────────────────
--   La consulta del final. Va la última porque el SQL Editor solo muestra el
--   resultado de la última. Tiene que devolver `arreglo_puesto = 2` (las dos
--   ramas comparan el destinatario) y `firma_intacta = 1`.
-- ============================================================================

-- ── 0 · La guardia: esta migración se niega si le falta el suelo ───────────
do $guardia$
declare
  v_constraint    text;
  v_prosrc        text;
  v_md5           text;
  v_md5_sin       text;
  v_ya_arreglada  boolean;
begin
  -- 1 · El CHECK de la 0356. BLOQUEA.
  select pg_get_constraintdef(oid) into v_constraint
    from pg_constraint where conname = 'alertas_tipo_check';

  if v_constraint is null
     or position('contrato_por_vencer' in v_constraint) = 0
     or position('vacaciones_por_vencer' in v_constraint) = 0 then
    raise exception using
      message = 'FALTA LA 0356. El CHECK alertas_tipo_check todavía no admite '
             || '«contrato_por_vencer» ni «vacaciones_por_vencer».',
      hint    = 'Pega primero 0356 y después 0357, y recién entonces esta. Sin el '
             || 'CHECK, esta función se instala sana y sus insert revientan a las '
             || '08:00 dentro de pg_cron, sin pantalla que lo muestre.';
  end if;

  -- 2 · El cálculo de vacaciones sin guardia, de la 0357. BLOQUEA.
  --     PL/pgSQL no resuelve las llamadas al crear la función: sin esta
  --     comprobación, la falta se descubriría de noche y no al pegar.
  if to_regprocedure('public.fn_vacaciones_saldo_interno(uuid, date)') is null then
    raise exception using
      message = 'FALTA LA 0357. La función fn_vacaciones_saldo_interno(uuid, date) '
             || 'no existe, y el bloque de vacaciones de acá la llama.',
      hint    = 'Pega la 0357 antes que esta.';
  end if;

  -- 3 · El cuerpo vigente. BLOQUEA si es otro.
  select p.prosrc into v_prosrc
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_generar_alertas_vencimiento';

  if v_prosrc is null then
    raise exception using
      message = 'FALTA LA 0356. La función fn_generar_alertas_vencimiento no existe todavía.',
      hint    = 'Pega 0356 y 0357 antes que esta. Esta migración CORRIGE esa función; '
             || 'no la crea desde cero a propósito, para no plantar en producción una '
             || 'versión que nadie revisó contra las dos anteriores.';
  end if;

  -- Reconoce su propio trabajo: se detecta por CÓDIGO, no por un comentario.
  -- Un comentario se pierde si el cuerpo se pega sin comentarios, y su texto
  -- cambia al renumerar el archivo — dos formas conocidas de falsa alarma.
  v_ya_arreglada := position('a.persona_id = do_.id' in v_prosrc) > 0;

  v_md5 := md5(v_prosrc);
  v_md5_sin := md5(array_to_string(array(
    select regexp_replace(l, '[[:space:]]*--.*$', '')
      from unnest(string_to_array(v_prosrc, chr(10))) as l
     where btrim(l) not like '--%'
  ), chr(10)));

  if v_ya_arreglada then
    -- Reconocer el propio trabajo NO puede significar saltarse el md5. Si el
    -- cuerpo lleva el arreglo pero NO es el que deja esta migración, alguien
    -- construyó encima y repegar esto lo borraría: exactamente el accidente de
    -- la 0261 sobre la 0275, por la puerta de al lado. Así que aquí también se
    -- compara — contra el md5 de LLEGADA, no el de partida.
    if v_md5 <> '6fb28b2376967b404851e974af4f804b'
       and v_md5_sin <> 'c72c309fa3761cf2ed9a911d70ecade3' then
      raise exception using
        message = 'PARA. fn_generar_alertas_vencimiento ya compara el destinatario, pero NO '
               || 'es el cuerpo que deja esta migración. md5 encontrado: ' || v_md5
               || ' (' || length(v_prosrc) || ' caracteres). Se esperaba '
               || '6fb28b2376967b404851e974af4f804b (3303) o, sin comentarios, '
               || 'c72c309fa3761cf2ed9a911d70ecade3.',
        hint    = 'Una migración posterior construyó sobre la 0361 conservando el arreglo. '
               || 'Repegar esto la revertiría EN SILENCIO, imprimiendo «sin daño» mientras '
               || 'lo hace. Corre ./scripts/donde-vive.sh fn_generar_alertas_vencimiento y '
               || 'pega esa migración posterior, no esta.';
    end if;
    raise notice 'Esta migración YA estaba aplicada (el cuerpo compara el destinatario, y es '
                 'el cuerpo de la 0361). Se vuelve a aplicar sin daño.';
  else
    if v_md5 <> '2a96822b83e5d741d4e5ce390dd34751'
       and v_md5_sin <> '302fc77c9abf81e831ecfdcb484a0505' then
      raise exception using
        message = 'PARA. fn_generar_alertas_vencimiento no es la de la 0357. '
               || 'md5 encontrado: ' || v_md5 || ' (' || length(v_prosrc) || ' caracteres). '
               || 'Se esperaba 2a96822b83e5d741d4e5ce390dd34751 (2677) o, sin comentarios, '
               || '302fc77c9abf81e831ecfdcb484a0505.',
        hint    = 'Otra sesión la reescribió. Pegar esto la revertiría en silencio. '
               || 'Corre ./scripts/donde-vive.sh fn_generar_alertas_vencimiento y mide '
               || 'DÓNDE está la diferencia antes de proponer explicaciones.';
    end if;

    if v_md5 <> '2a96822b83e5d741d4e5ce390dd34751' then
      raise notice 'Producción tiene el cuerpo de la 0357 SIN sus comentarios. '
                   'Mismo código: se sigue.';
    end if;
  end if;

  -- 4 · El cron de la 0356. AVISA, NO BLOQUEA.
  --     Que falte no da un resultado equivocado: no da ninguno, y eso se ve.
  --     El bloque anidado existe porque leer cron.job puede fallar por
  --     permisos o porque la extensión no esté, y un aviso jamás debe tumbar
  --     una migración.
  begin
    if not exists (select 1 from cron.job where jobname = 'generar-alertas-vencimiento') then
      raise warning 'El cron «generar-alertas-vencimiento» no está programado. La función '
                    'queda corregida, pero nadie la va a llamar. Lo programa la 0356.';
    end if;
  exception when others then
    raise warning 'No se pudo comprobar el cron «generar-alertas-vencimiento» (%). '
                  'Compruébalo a mano: select jobname from cron.job;', sqlerrm;
  end;
end
$guardia$;

-- ── 1 · El cuerpo de la 0357, con la identidad del aviso completa ──────────
-- CAMBIO 0361: los dos `not exists` comparan además el destinatario y el
-- canal. Todo lo demás es la 0357 palabra por palabra.
create or replace function fn_generar_alertas_vencimiento()
returns int
language plpgsql security definer set search_path = public
as $fn$
declare
  v_generadas int := 0;
  v_parcial int;
begin
  insert into alertas (persona_id, tipo, canal, payload)
  select do_.id, 'contrato_por_vencer', 'email',
    jsonb_build_object(
      'evento', p.id::text || '|' || p.fecha_fin_contrato::text,
      'persona_id', p.id,
      'persona', p.nombres || ' ' || p.apellidos,
      'sede', coalesce(s.codigo, '—'),
      'fecha_fin_contrato', p.fecha_fin_contrato,
      'dias_restantes', (p.fecha_fin_contrato - fn_hoy_lima())::int
    )
  from personas p
  left join sedes s on s.id = p.sede_base_id
  cross join (
    select id from personas where rol in ('admin', 'lider_do') and estado = 'activo' and email is not null
  ) do_
  where p.estado = 'activo'
    and p.fecha_fin_contrato is not null
    and p.fecha_fin_contrato >= fn_hoy_lima()
    and p.fecha_fin_contrato <= fn_hoy_lima() + 30
    -- CAMBIO 0361: el aviso ya dado lo es PARA ALGUIEN. Sin `a.persona_id`,
    -- la primera fila de este hecho apagaba el aviso para todo DO, incluido
    -- quien entrara después y nunca lo recibiría.
    and not exists (
      select 1 from alertas a
      where a.tipo = 'contrato_por_vencer'
        and a.payload ->> 'evento' = p.id::text || '|' || p.fecha_fin_contrato::text
        and a.persona_id = do_.id
        and a.canal = 'email'
    );
  get diagnostics v_parcial = row_count;
  v_generadas := v_generadas + v_parcial;

  -- Mismo criterio que fn_vacaciones_por_vencer (0297): por vencer en 60 días
  -- O ya con algún récord vencido — un récord vencido es MÁS urgente, no
  -- menos, y silenciarlo repetiría el bug real que la 0301 tuvo que arreglar.
  insert into alertas (persona_id, tipo, canal, payload)
  select do_.id, 'vacaciones_por_vencer', 'email',
    jsonb_build_object(
      'evento', p.id::text || '|' || (x.r ->> 'vence_el'),
      'persona_id', p.id,
      'persona', p.nombres || ' ' || p.apellidos,
      'sede', coalesce(s.codigo, '—'),
      'dias_pendientes', (x.r ->> 'dias_pendientes')::numeric,
      'records_vencidos', (x.r ->> 'records_vencidos')::int,
      'vence_el', (x.r ->> 'vence_el')::date,
      'dias_para_vencer', (x.r ->> 'dias_para_vencer')::int
    )
  from personas p
  left join sedes s on s.id = p.sede_base_id
  cross join lateral (select fn_vacaciones_saldo_interno(p.id, fn_hoy_lima()) as r) x
  cross join (
    select id from personas where rol in ('admin', 'lider_do') and estado = 'activo' and email is not null
  ) do_
  where p.estado = 'activo'
    and (x.r ->> 'aplica')::boolean is true
    and (x.r ->> 'records_sin_gozar')::int > 0
    and ( (x.r ->> 'dias_para_vencer')::int <= 60 or (x.r ->> 'records_vencidos')::int > 0 )
    -- CAMBIO 0361: igual que arriba. Acá dolía más: un récord vencido sigue
    -- siendo el mismo hecho durante todo un año, así que quien entrara a DO
    -- en ese año no se enteraba de una indemnización de una remuneración
    -- entera (art. 23 del D. Leg. 713) que ya estaba corriendo.
    and not exists (
      select 1 from alertas a
      where a.tipo = 'vacaciones_por_vencer'
        and a.payload ->> 'evento' = p.id::text || '|' || (x.r ->> 'vence_el')
        and a.persona_id = do_.id
        and a.canal = 'email'
    );
  get diagnostics v_parcial = row_count;
  v_generadas := v_generadas + v_parcial;

  return v_generadas;
end;
$fn$;

insert into migraciones_aplicadas (numero, nombre)
values (361, 'el_aviso_de_vencimiento_no_se_salta_a_quien_llego_despues')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ──────────────────────────────────────────────────────────
-- arreglo_puesto = 2   → las dos ramas comparan el destinatario
-- canal_en_la_clave = 2
-- firma_intacta = 1    → sigue habiendo UNA sola fn_generar_alertas_vencimiento
--                        (dos serían el accidente 0297/0299: «function is not unique»)
-- cron_programado = 1  → el reloj que la llama sigue en pie
select
  (select count(*) from pg_proc where proname = 'fn_generar_alertas_vencimiento') as firma_intacta,
  (select (length(prosrc) - length(replace(prosrc, 'a.persona_id = do_.id', ''))) / length('a.persona_id = do_.id')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_generar_alertas_vencimiento')   as arreglo_puesto,
  (select (length(prosrc) - length(replace(prosrc, 'a.canal = ''email''', ''))) / length('a.canal = ''email''')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_generar_alertas_vencimiento')   as canal_en_la_clave,
  (select count(*) from cron.job where jobname = 'generar-alertas-vencimiento')    as cron_programado;
