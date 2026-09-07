-- ============================================================================
-- 0389 · Las cuatro que quedaban del mismo empate
-- ============================================================================
-- QUÉ PROMETE
--
--   Cerrar la familia que abrieron la 0386, la 0387 y la 0388: una consulta que
--   pregunta «¿cuál es el último?» ordenando por una columna de fecha que puede
--   valer lo mismo en dos filas. Sin desempate, quién gana lo decide el orden
--   físico de la tabla — un orden que cambia solo.
--
--   Cuatro funciones, un cambio de una línea en cada una:
--
--     fn_contratos_listar
--       antes:  order by c2.generado_at desc limit 1
--       ahora:  order by c2.generado_at desc, c2.fecha_inicio desc,
--                        c2.fecha_fin desc, c2.id desc limit 1
--
--     fn_documentos_estado_politica
--       antes:  order by d.fecha_firma desc, d.created_at desc limit 1
--       ahora:  order by d.fecha_firma desc, d.created_at desc, d.id desc limit 1
--
--     fn_documentos_listar
--       antes:  order by d2.fecha_firma desc, d2.created_at desc limit 1
--       ahora:  order by d2.fecha_firma desc, d2.created_at desc, d2.id desc limit 1
--
--     fn_educacion_espejo_comprobante
--       antes:  order by c.mes_cubierto desc, c.created_at desc limit 1
--       ahora:  order by c.mes_cubierto desc, c.created_at desc, c.id desc limit 1
--
--   Nada más cambia en ninguna de las cuatro: mismas columnas, mismos filtros,
--   mismos permisos.
--
-- QUÉ ASUME
--
--   Las cuatro versiones vigentes, comprobadas con `./scripts/donde-vive.sh` y
--   con `git grep` sobre todas las ramas, en el mensaje en que se entrega este
--   SQL:
--     fn_contratos_listar              → 0287
--     fn_documentos_estado_politica    → 0211
--     fn_documentos_listar             → 0157
--     fn_educacion_espejo_comprobante  → 0290
--
--   md5 de partida, PEDIDOS A PRODUCCIÓN en el SQL Editor (2026-09-07):
--     MD5_PENDIENTE
--
-- POR QUÉ LAS CUATRO EN UNA SOLA MIGRACIÓN
--
--   Porque no son cuatro cambios: es uno. La 0388 las dejó anotadas juntas y
--   juntas se cierran — mismo defecto, misma corrección, mismo párrafo de
--   explicación. Partirlas en cuatro archivos sería cuatro pegadas a mano, o
--   sea cuatro oportunidades de pegar la equivocada, a cambio de nada. Es el
--   mismo criterio con que la 0347 tocó tres funciones de un tirón.
--
-- POR QUÉ NINGUNA CAMBIA NADA EN PRODUCCIÓN, Y CÓMO SE COMPROBÓ
--
--   Es la pregunta que enseñó la 0388, y hay que hacérsela a cada una: ¿la
--   columna que ordena la escribe el sistema con la hora exacta, o la elige una
--   persona en una pantalla? Si la escribe el sistema, el empate solo ocurre
--   dentro de una transacción y en producción no llega a pasar. Si la elige una
--   persona, el empate es real y el desempate cambia comportamiento — que es lo
--   que pasaba con `entregado_at` y el mediodía de Lima en la 0388.
--
--   Preguntado al catálogo:
--
--     contratos_generados.generado_at      ::  now()
--     documentos_firmados.created_at       ::  now()
--     educacion_comprobantes.created_at    ::  now()
--
--   Las tres las pone el sistema, y ninguna función las escribe con un
--   parámetro (se comprobó buscando en el `prosrc` de TODAS las funciones del
--   esquema, que es como se cazó `entregado_at = p_fecha` en la 0388). Y quien
--   inserta lo hace de a una fila por llamada: `fn_contrato_registrar`,
--   `fn_documento_registrar`, `fn_educacion_registrar` y
--   `fn_educacion_adjuntar_comprobante`.
--
--   Las columnas que SÍ elige una persona —`documentos_firmados.fecha_firma`,
--   `educacion_comprobantes.mes_cubierto`— empatan de verdad, y por eso van
--   primeras en el orden: lo que las desempata es la columna del sistema, que
--   ya estaba ahí. Lo que agrega esta migración va DESPUÉS de esa, así que solo
--   puede disparar en un empate que producción no sabe producir.
--
-- POR QUÉ ESTOS DESEMPATES Y NO OTROS
--
--   Ninguno es nuevo. Cada función recibe el que su hermana ya usa para
--   responder la misma pregunta:
--
--     fn_contratos_listar            ← los de fn_contratos_tablero (0386),
--                                      que a su vez vienen de la 0312.
--                                      Las dos alimentan /admin/contratos.
--     fn_documentos_estado_politica  ← el de fn_documentos_tablero (0387)
--     fn_documentos_listar           ← el mismo, sobre la misma tabla
--     fn_educacion_espejo_comprobante← el mismo patrón, adaptado a su columna
--
--   Eso es lo que de verdad arregla esta migración, más que los empates: que
--   dos funciones de la MISMA pantalla dejen de poder contestar distinto a
--   «cuál es el vigente». `fn_contratos_tablero` y `fn_contratos_listar` se
--   dibujan una al lado de la otra en `/admin/contratos`; lo mismo
--   `fn_documentos_tablero` y `fn_documentos_listar` en `/admin/documentacion`.
--
-- LO QUE ESTA MIGRACIÓN NO ES
--
--   No es una corrección de un defecto que se esté viendo hoy. Ninguna de las
--   cuatro está dando una respuesta mala en producción ahora mismo, y por eso
--   se puede pegar sin medir nada antes — a diferencia de la 0388, que sí.
--   Es cerrar la puerta antes de que alguien la cruce.
--
--   Y esta migración NO toca `fn_expediente_generar_falta`: esa la arregla la
--   0388, que va antes y sí cambia comportamiento.
--
-- CÓMO SE REVIERTE
--   Correr de nuevo cada cuerpo tal como quedó en su migración de origen: la
--   0287, la 0211, la 0157 y la 0290 respectivamente. No hay datos que
--   deshacer: esta migración no escribe ninguna fila.
-- ============================================================================

-- ── 1 · fn_contratos_listar ─────────────────────────────────────────────────
-- Cuerpo vigente: 0287. Un cambio, marcado CAMBIO 0389.
drop function if exists fn_contratos_listar(uuid);

create or replace function fn_contratos_listar(p_persona_id uuid default null)
returns table (
  id                    uuid,
  persona_id            uuid,
  persona               text,
  tipo                  text,
  cargo                 text,
  sede                  text,
  remuneracion_mensual  numeric,
  fecha_inicio          date,
  fecha_fin             date,
  horas_semanales       numeric,
  generado_at           timestamptz,
  generado_por          text,
  storage_path          text,
  fecha_firma           date,
  copia_entregada_at    date,
  comunicado_mtpe_at    date,
  anulado_at            timestamptz,
  anulado_motivo        text,
  vigente               boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id, c.persona_id, p.nombres || ' ' || p.apellidos,
    c.tipo, c.cargo, s.nombre,
    c.remuneracion_mensual, c.fecha_inicio, c.fecha_fin, c.horas_semanales,
    c.generado_at,
    gen.nombres || ' ' || gen.apellidos,
    c.storage_path, c.fecha_firma,
    c.copia_entregada_at, c.comunicado_mtpe_at,
    c.anulado_at, c.anulado_motivo,
    (c.anulado_at is null and c.id = (
       select c2.id from contratos_generados c2
        where c2.persona_id = c.persona_id and c2.anulado_at is null
        -- ⇩⇩⇩ CAMBIO 0389 ⇩⇩⇩ Los MISMOS tres desempates que la 0386 le puso a
        -- `fn_contratos_tablero`, y por eso mismo: las dos responden «cuál
        -- contrato manda» para la misma pantalla, y no pueden contestar
        -- distinto. `generado_at` es `now()`, igual para toda fila nacida en
        -- una misma transacción.
        order by c2.generado_at desc, c2.fecha_inicio desc,
                 c2.fecha_fin desc, c2.id desc limit 1))
  from contratos_generados c
  join personas p on p.id = c.persona_id
  left join personas gen on gen.id = c.generado_por
  left join sedes s on s.id = c.sede_id
  where (fn_es_admin_o_lider() is true or c.persona_id = fn_persona_actual_id())
    and (p_persona_id is null or c.persona_id = p_persona_id)
  order by c.generado_at desc;
$$;

grant execute on function fn_contratos_listar(uuid) to authenticated;


-- ── 2 · fn_documentos_estado_politica ──────────────────────────────────────
-- Cuerpo vigente: 0211. Un cambio, marcado CAMBIO 0389.
create or replace function fn_documentos_estado_politica()
returns table (
  id            uuid,
  cargada       boolean,
  fecha_firma   date,
  primer_pago   date,
  llego_tarde   boolean,
  storage_path  text
)
language sql
stable
security definer
set search_path = public
as $$
  with pol as (
    select d.id, d.fecha_firma, d.storage_path
    from documentos_firmados d
    where d.tipo = 'politica' and d.anulado_at is null
    -- 0211 · DESEMPATE POR created_at. Sin él, dos políticas con la misma
    -- fecha_firma —el caso NORMAL, porque la política conserva la fecha del
    -- papel— dejaban a Postgres elegir cualquiera, y elegía la vieja: el
    -- reemplazo se guardaba y la pantalla seguía enseñando el anterior.
    -- Con la anulación automática de fn_documento_registrar esto no debería
    -- llegar a hacer falta; está por lo que ya haya en producción de antes.
    -- ⇩⇩⇩ CAMBIO 0389 ⇩⇩⇩ `id desc` cierra lo que la 0211 dejó abierto: su
    -- desempate por `created_at` resuelve el caso normal (dos políticas con la
    -- misma fecha del papel), pero `created_at` es `now()` y empata entre filas
    -- de una misma transacción. Es el mismo ancla que la 0387 le puso a
    -- `fn_documentos_tablero`, sobre esta misma tabla.
    order by d.fecha_firma desc, d.created_at desc, d.id desc
    limit 1
  ),
  -- Cuándo empezó a pagarse movilidad: la primera tarifa mayor que cero.
  inicio as (
    select min(vigente_desde) as desde
    from parametros_laborales
    where clave = 'movilidad_diaria' and valor > 0
  )
  select
    pol.id,
    pol.id is not null,
    pol.fecha_firma,
    inicio.desde,
    (pol.fecha_firma is not null and inicio.desde is not null
       and pol.fecha_firma > inicio.desde),
    pol.storage_path
  from inicio
  left join pol on true;
$$;

grant execute on function fn_documento_registrar(text,date,uuid,text,numeric,integer,boolean,text,text,uuid) to authenticated;
grant execute on function fn_documentos_estado_politica() to authenticated;


-- ── 3 · fn_documentos_listar ───────────────────────────────────────────────
-- Cuerpo vigente: 0157. Un cambio, marcado CAMBIO 0389.
create or replace function fn_documentos_listar(p_persona_id uuid default null)
returns table (
  id              uuid,
  alcance         text,
  persona_id      uuid,
  persona         text,
  tipo            text,
  fecha_firma     date,
  ruta_declarada  text,
  monto_declarado numeric,
  anio            integer,
  es_negativa     boolean,
  storage_path    text,
  nota            text,
  registrado_por  text,
  anulado_at      timestamptz,
  anulado_motivo  text,
  vigente         boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    d.id, d.alcance, d.persona_id,
    coalesce(p.nombres || ' ' || p.apellidos, 'CAYLA'),
    d.tipo, d.fecha_firma, d.ruta_declarada, d.monto_declarado, d.anio,
    d.es_negativa, d.storage_path, d.nota,
    reg.nombres || ' ' || reg.apellidos,
    d.anulado_at, d.anulado_motivo,
    -- Vigente = es la más reciente de su tipo para esa persona, y no está anulada.
    (d.anulado_at is null and d.id = (
       select d2.id from documentos_firmados d2
        where d2.tipo = d.tipo and d2.anulado_at is null
          and d2.persona_id is not distinct from d.persona_id
        -- ⇩⇩⇩ CAMBIO 0389 ⇩⇩⇩ Mismo ancla que la 0387 en `fn_documentos_tablero`
        -- y que arriba en `fn_documentos_estado_politica`: las tres deciden
        -- «cuál documento vale» sobre la misma tabla, y ya no pueden discrepar.
        order by d2.fecha_firma desc, d2.created_at desc, d2.id desc limit 1))
  from documentos_firmados d
  left join personas p on p.id = d.persona_id
  left join personas reg on reg.id = d.registrado_por
  where (fn_es_admin_o_lider() is true or d.persona_id = fn_persona_actual_id())
    and (p_persona_id is null or d.persona_id = p_persona_id)
  order by d.fecha_firma desc, d.created_at desc;
$$;

grant execute on function fn_documentos_listar(uuid) to authenticated;


-- ── 4 · fn_educacion_espejo_comprobante ────────────────────────────────────
-- Cuerpo vigente: 0290. Un cambio, marcado CAMBIO 0389. Es la función de un
-- trigger: no se re-declara el trigger, que sigue apuntando a este nombre.
create or replace function fn_educacion_espejo_comprobante()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_asignacion uuid := coalesce(new.asignacion_id, old.asignacion_id);
begin
  update asignaciones_educacion a
     set comprobante_url = (
       select c.storage_path
         from educacion_comprobantes c
        where c.asignacion_id = v_asignacion
        -- ⇩⇩⇩ CAMBIO 0389 ⇩⇩⇩ `mes_cubierto` lo elige quien sube el papel y NO es
        -- único por asignación (el índice único es sobre `storage_path`), así
        -- que dos comprobantes del mismo mes empatan en el primer criterio;
        -- `created_at` los separa salvo dentro de una misma transacción. El
        -- ancla cierra ese resto.
        order by c.mes_cubierto desc, c.created_at desc, c.id desc
        limit 1)
   where a.id = v_asignacion;

  return null;
end;
$$;

insert into migraciones_aplicadas (numero, nombre)
values (389, 'las_cuatro_que_quedaban_del_mismo_empate')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
begin
  raise notice '0389 · cuatro funciones ganan su desempate: fn_contratos_listar, fn_documentos_estado_politica, fn_documentos_listar, fn_educacion_espejo_comprobante.';
  raise notice '0389 · ninguna cambia una fila: las tres columnas que ordenan son now() y nadie las escribe a mano.';
end $mig$;
