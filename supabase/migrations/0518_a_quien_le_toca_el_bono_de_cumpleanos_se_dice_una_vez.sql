-- ============================================================================
-- 0518 — A quién le toca el bono de cumpleaños se dice una sola vez
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que el bono de cumpleaños sea de TODO el equipo con contrato de trabajo o
--   convenio de prácticas —quien está en planilla y quien es practicante—,
--   con dos excepciones: quien está en periodo de prueba (`tipo_vinculo =
--   'prueba'`) y quien tiene un contrato de menos de una semana. Y que esa
--   regla viva en UN solo lugar, `fn_persona_le_corresponde_bono_cumpleanos`,
--   y la lean las tres puertas que hoy la tenían cada una por su cuenta:
--
--     · `fn_mi_bono_cumpleanos`   — lo que ve la persona en su Info, en su
--                                   Bandeja y en /mio/cumpleanos; y la puerta
--                                   de la firma (`fn_confirmar_mi_bono_…`).
--     · `fn_documento_registrar`  — el cargo en papel que registra DO.
--     · `fn_documentos_tablero`   — lo que DO ve en Documentación y en su
--                                   Bandeja («Bono sin constancia firmada»).
--
--   Decidido por Cayla el 2026-10-13: «todos pueden firmar, siendo
--   practicante, en planilla, todos excepto los que tienen un contrato de
--   menos de una semana o están en prueba».
--
-- EL DEFECTO, VISTO EN VIVO
--
--   Daniel Ruiz es practicante (0424 lo midió en producción) y cumple en
--   octubre. El 2026-10-13 no tenía nada en su Info ni en su Bandeja, mientras
--   DO sí lo veía en la suya como «Bono de cumpleaños sin constancia firmada».
--   Reproducido en el Postgres local con un perfil igual (practicante, cumple
--   en octubre) contra un control en planilla:
--
--     fn_documentos_tablero  (lo que ve DO)        → este_mes
--     fn_mi_bono_cumpleanos  (lo que ve él)        → no_aplica
--     fn_mi_bono_cumpleanos  (control en planilla) → este_mes, S/ 180
--
--   Dos funciones contestando distinto sobre la misma persona. La causa: el
--   tablero lista a quien le corresponde MOVILIDAD (0424: planilla o
--   practicante) y calcula `bono_estado` a todo el que lista, mientras
--   `fn_mi_bono_cumpleanos` y `fn_documento_registrar` exigían `en_planilla`
--   a secas. La 0478 ya lo había dejado anotado como pendiente en
--   `docs/estado.md`; faltaba decidir hacia qué lado se cerraba.
--
-- LA REGLA, EN NÚMEROS
--
--   Le toca si `tipo_vinculo in ('planilla', 'practicante')` Y su contrato
--   dura al menos siete días. Los días de contrato se cuentan con los dos
--   extremos incluidos: `fecha_fin_contrato - fecha_ingreso + 1`. Un contrato
--   del 10 al 16 de octubre son 7 días → le toca; del 10 al 15 son 6 → no.
--   Sin `fecha_fin_contrato` (indefinido) le toca. `fecha_ingreso` es NOT
--   NULL, así que la resta nunca da null.
--
--   `prueba` queda fuera aunque `en_planilla` lo incluya: `en_planilla`
--   significa «se le mide asistencia y disciplina» (0085) y eso sigue siendo
--   cierto para quien está en prueba; lo que NO devenga son los beneficios,
--   decisión de Felipe del 2026-07-26 registrada en la misma 0085. Esta
--   migración aplica al bono el mismo criterio.
--
-- DECIDÍ:     una función nueva que dice a quién le toca, leída por las tres
--             puertas. Las tres se reescriben con UN cambio marcado cada una
--             (`CAMBIO 0518`), partiendo de su versión vigente.
-- DESCARTÉ:   (a) reusar `fn_persona_le_corresponde_movilidad`, que hoy casi
--             contesta lo mismo. Es exactamente lo que produjo este defecto:
--             el bono vivía colgado de una pregunta de movilidad, y cuando la
--             movilidad cambió (0424) el bono cambió a medias. Y ya no
--             contestan igual: la movilidad sí le toca a quien está en prueba.
--             (b) cambiar la fórmula de `en_planilla`: es columna generada y
--             la leen catorce lugares con el significado de la 0085.
--             (c) medir el contrato corto en `contratos_generados` (el
--             contrato firmado vigente): no todo el equipo tiene su contrato
--             ahí —los anteriores al generador viven en papel—, y la 0312 ya
--             copia la `fecha_fin` del contrato firmado a
--             `personas.fecha_fin_contrato`. Se lee de donde ya está.
-- SE ROMPE SI: alguien crea un tipo de vínculo nuevo que deba tener bono y no
--             lo agrega aquí — se quedaría en `no_aplica` en silencio, igual
--             que Daniel. Por eso la lista vive en UNA función y la prueba 413
--             recorre los cinco vínculos. Y si DO registra un contrato corto
--             SIN `fecha_fin_contrato`, el sistema no tiene cómo saber que es
--             corto: lo tratará como indefinido.
--
-- UNA CONSECUENCIA QUE CONVIENE SABER
--
--   Quien cumple años estando en prueba y pasa a planilla antes de fin de
--   año queda en `vencido` («ya cumplió este año y no lo pidió: todavía
--   puede») y lo puede pedir entonces. No es un cambio de esta migración: es
--   lo que la 0478 ya hacía con cualquier cumpleaños pasado. Si Cayla quiere
--   que el bono se pierda al cumplir en prueba, es otra decisión y otra
--   migración.
--
-- LO QUE SE COMPROBÓ ANTES DE ENTREGAR (dentro de BEGIN … ROLLBACK)
--
--   Con una practicante simulada: `fn_mi_bono_cumpleanos` → este_mes con su
--   monto; la firma crea la constancia y la línea `bono` en su boleta; y la
--   planilla de su periodo suma el bono a lo que cobra (y EsSalud no se
--   mueve: para practicantes la base es siempre el piso de la RMV). Con una
--   persona en prueba y una con contrato de 6 días: las tres puertas dicen
--   que no. Ver la prueba pgTAP 413, que corre con y sin esta migración.
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   · No toca `fn_confirmar_mi_bono_cumpleanos`: su puerta ya es
--     `fn_mi_bono_cumpleanos`, así que hereda el cambio sin reescribirse.
--   · No toca la planilla: la línea `bono` de `movimientos_planilla` ya la
--     suma para cualquier vínculo (0479).
--   · No abre el bono a un locador por RxH ni a `no_trabajador`: no son parte
--     del equipo con contrato de CAYLA. Si Cayla también los quiere, es una
--     línea en la función y un caso en la 413.
--   · No cambia a quién LISTA el tablero (sigue siendo quien cobra
--     movilidad): solo qué dice de su bono.
--
-- QUÉ ASUME (md5 de PARTIDA — pedirlos a PRODUCCIÓN antes de pegar)
--
--   Los tres md5 de abajo son del Postgres LOCAL. `donde-vive.sh` de cada
--   función imprime la consulta para producción; si allá coincide el
--   «sin comentarios», se sigue; si no coincide ninguno, NO se pega.
--
--   fn_mi_bono_cumpleanos   vigente: 0479 · 6a9d7307f6fa7e4446da67117012736f
--                                   sin comentarios 983554cf53130f082aeb06f5f34224e5
--   fn_documento_registrar  vigente: 0448 · 5909cada98bc2f879fd8f30dffeaffbe
--                                   sin comentarios 47307a097a4fd667babdb721e5dbaf0e
--   fn_documentos_tablero   vigente: 0492 · 05b59757df2ad4477cadf7a62bcfb428
--                                   sin comentarios 92f3a7f764ed0f545cd3c2ea8fde1fe8
--
--   Comprobado el 2026-10-13 que ninguna rama remota redefine ninguna de las
--   tres en una migración posterior a la 0492.
--
-- CONCURRENCIA
--
--   Nada nuevo: dos firmas a la vez las sigue frenando el índice único
--   `idx_documentos_bono_uno_por_anio` (0157), sea cual sea el vínculo.
--
-- CÓMO SE REVIERTE
--
--   Volver a pegar `fn_mi_bono_cumpleanos` de la 0479, `fn_documento_registrar`
--   de la 0448 y `fn_documentos_tablero` de la 0492 (esa última con su
--   `drop function` delante, como está allá), y después:
--     drop function if exists fn_persona_le_corresponde_bono_cumpleanos(uuid);
--   Las constancias que ya hayan firmado practicantes NO se anulan al revertir:
--   son plata que se pagó o se debe.
-- ============================================================================


-- ── A · Un solo lugar para «¿le toca el bono de cumpleaños?» ───────────────
create or replace function fn_persona_le_corresponde_bono_cumpleanos(p_persona_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p.tipo_vinculo in ('planilla', 'practicante')
            -- Días de contrato con los dos extremos incluidos: del 10 al 16
            -- son 7. Sin fecha de fin es indefinido, y le toca.
            and (p.fecha_fin_contrato is null
                 or p.fecha_fin_contrato - p.fecha_ingreso + 1 >= 7)
       from personas p
      where p.id = p_persona_id),
    false
  );
$$;

comment on function fn_persona_le_corresponde_bono_cumpleanos(uuid) is
  'A quién le toca el bono de cumpleaños (0518, decidido por Cayla el '
  '2026-10-13): en planilla o practicante, nunca en periodo de prueba ni con '
  'un contrato de menos de 7 días (extremos incluidos). La leen '
  'fn_mi_bono_cumpleanos, fn_documento_registrar y fn_documentos_tablero. '
  'Separada de fn_persona_le_corresponde_movilidad a propósito: son dos '
  'beneficios distintos y ya no contestan igual (la movilidad sí es para prueba).';

-- Solo la llaman funciones del propio esquema.
revoke all on function fn_persona_le_corresponde_bono_cumpleanos(uuid) from public, anon, authenticated;


-- ── B · Lo que ve la persona: cuerpo de la 0479, un cambio (CAMBIO 0518) ───
create or replace function fn_mi_bono_cumpleanos()
returns table (
  estado         text,
  mes_cumpleanos integer,
  anio           integer,
  monto          numeric,
  documento_id   uuid,
  pedido_el      date,
  entregado_el   date,
  via            text,
  periodo_fin    date
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  -- CAMBIO 0479 (marcador: la comprobación del bloque 0 reconoce esta versión)
  -- CAMBIO 0518 (marcador: la comprobación del final reconoce esta versión)
  v_yo   uuid := fn_persona_actual_id();
  v_mes  integer;
  v_doc  documentos_firmados%rowtype;
  v_tab  record;
  v_fin  date;
begin
  if v_yo is null then
    return;
  end if;

  select extract(month from d.fecha_nacimiento)::int into v_mes
    from datos_personales d
   where d.persona_id = v_yo and d.fecha_nacimiento is not null;

  -- 1 · Un pedido sin pagar manda sobre todo lo demás (de cualquier año: una
  --     deuda vieja no se tapa con una nueva). «Sin pagar» quiere decir: DO no
  --     confirmó una transferencia Y tampoco está en una boleta cuyo periodo ya
  --     se pagó. Con la boleta pagada la constancia sale de acá y cae al
  --     tablero, que la ve vigente y dice «entregado».
  select d.* into v_doc
    from documentos_firmados d
   where d.persona_id = v_yo and d.tipo = 'bono'
     and d.anulado_at is null and not d.es_negativa
     and d.firma_persona_confirmada_at is not null
     and d.entrega_confirmada_el is null
     and not exists (
           select 1
             from movimientos_planilla m
             join periodos_planilla pp on pp.id = m.periodo_id
            where m.id = d.movimiento_id
              and fn_fecha_en_periodo_pagado(pp.fecha_ini, d.persona_id))
   order by d.anio desc, d.fecha_firma desc, d.created_at desc, d.id desc
   limit 1;
  if found then
    if v_doc.movimiento_id is null then
      return query select 'pedido'::text, v_mes, v_doc.anio, v_doc.monto_declarado,
                          v_doc.id, v_doc.fecha_firma, null::date, 'transferencia'::text, null::date;
    else
      select pp.fecha_fin into v_fin
        from movimientos_planilla m
        join periodos_planilla pp on pp.id = m.periodo_id
       where m.id = v_doc.movimiento_id;
      return query select 'en_boleta'::text, v_mes, v_doc.anio, v_doc.monto_declarado,
                          v_doc.id, v_doc.fecha_firma, null::date, 'boleta'::text, v_fin;
    end if;
    return;
  end if;

  -- 2 · Lo que dice el tablero de SU fila. `true` es obligatorio: sin él, una
  --     persona de DO recibiría la fila de cualquier compañera (ver 0423).
  select t.bono_estado, t.bono_id into v_tab
    from fn_documentos_tablero(true) t
   limit 1;

  -- ⇩⇩⇩ CAMBIO 0518 ⇩⇩⇩ Antes: `p.en_planilla` a secas, que dejaba fuera a
  -- quien es practicante. Ahora pregunta a la función que decide el bono.
  if not found
     or fn_persona_le_corresponde_bono_cumpleanos(v_yo) is not true then
  -- ⇧⇧⇧ CAMBIO 0518 ⇧⇧⇧
    return query select 'no_aplica'::text, v_mes, extract(year from fn_hoy_lima())::int,
                        null::numeric, null::uuid, null::date, null::date, null::text, null::date;
    return;
  end if;

  -- 3 · Ya se entregó este año, por el camino que fuera.
  if v_tab.bono_estado = 'ok' then
    select d.* into v_doc from documentos_firmados d where d.id = v_tab.bono_id;

    if v_doc.movimiento_id is not null then
      -- Pagado con la planilla: si el periodo no estuviera pagado, el paso 1 lo
      -- habría devuelto como `en_boleta`. No hay día exacto que decir, solo el
      -- periodo (ver «NO SE INVENTA UNA FECHA DE PAGO»).
      select pp.fecha_fin into v_fin
        from movimientos_planilla m
        join periodos_planilla pp on pp.id = m.periodo_id
       where m.id = v_doc.movimiento_id;
      return query select 'entregado'::text, v_mes, v_doc.anio, v_doc.monto_declarado, v_doc.id,
                          v_doc.fecha_firma, null::date, 'boleta'::text, v_fin;
    else
      -- Transferencia confirmada por DO, o cargo en papel (su fecha_firma ya es
      -- la de entrega: la escribe quien recibe, el día que recibe).
      return query select 'entregado'::text, v_mes, v_doc.anio, v_doc.monto_declarado, v_doc.id,
                          case when v_doc.firma_persona_confirmada_at is not null then v_doc.fecha_firma end,
                          coalesce(v_doc.entrega_confirmada_el, v_doc.fecha_firma),
                          case when v_doc.firma_persona_confirmada_at is not null
                               then 'transferencia' else 'papel' end,
                          null::date;
    end if;
    return;
  end if;

  -- 4 · Todavía no hay constancia: el estado del tablero, con el monto que
  --     rige hoy — se muestra ANTES de pedir, nunca se firma a ciegas (0477).
  return query select v_tab.bono_estado::text, v_mes, extract(year from fn_hoy_lima())::int,
                      fn_bono_monto_vigente(), null::uuid, null::date, null::date, null::text, null::date;
end;
$$;

grant execute on function fn_mi_bono_cumpleanos() to authenticated;
revoke execute on function fn_mi_bono_cumpleanos() from public, anon;


-- ── C · El cargo en papel de DO: cuerpo de la 0448, un cambio (CAMBIO 0518) ─
create or replace function fn_documento_registrar(
  p_tipo            text,
  p_fecha_firma     date,
  p_persona_id      uuid    default null,
  p_ruta_declarada  text    default null,
  p_monto_declarado numeric default null,
  p_anio            integer default null,
  p_es_negativa     boolean default false,
  p_nota            text    default null,
  p_storage_path    text    default null,
  p_id              uuid    default null   -- no nulo = enlazar el archivo recién subido
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id           uuid;
  v_alcance      text;
  v_yo           uuid := fn_persona_actual_id();
  -- ⇩⇩⇩ CAMBIO 0448 ⇩⇩⇩ para auditar la rama de enlazar archivo.
  v_persona_doc  uuid;
  v_tipo_doc     text;
  v_archivo_ant  text;
  -- ⇧⇧⇧ CAMBIO 0448 ⇧⇧⇧
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional registra documentos firmados.';
  end if;

  if p_tipo not in ('ruta', 'politica', 'bono') then
    raise exception 'Tipo de documento inválido: «%».', p_tipo;
  end if;

  -- El alcance no se recibe: se deduce del tipo, que es lo único que puede
  -- decidirlo. Recibirlo abriría la puerta a una ruta declarada «de empresa».
  v_alcance := case when p_tipo = 'politica' then 'empresa' else 'individual' end;

  if p_fecha_firma is null then
    raise exception 'Falta la fecha en que se firmó el documento.';
  end if;
  if p_fecha_firma > fn_hoy_lima() then
    raise exception 'La fecha de firma no puede ser futura.';
  end if;

  -- Enlazar el archivo a una fila que ya existe.
  if p_id is not null then
    -- ⇩⇩⇩ CAMBIO 0448 ⇩⇩⇩ Antes este bloque actualizaba y volvía sin dejar
    -- ningún rastro de quién reemplazó el archivo ni de cuál era el
    -- anterior. `select ... for update` bloquea la fila y captura el
    -- `storage_path` de ANTES, en el mismo momento en que se decide el
    -- cambio — no después, que es cuando ya se perdió.
    select persona_id, tipo, storage_path
      into v_persona_doc, v_tipo_doc, v_archivo_ant
      from documentos_firmados
     where id = p_id and anulado_at is null
     for update;
    if not found then raise exception 'Ese documento no existe o está anulado.'; end if;

    update documentos_firmados
       set storage_path = coalesce(p_storage_path, storage_path)
     where id = p_id;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (coalesce(v_persona_doc, v_yo),
       'documento_archivo_reemplazado',
       coalesce(v_archivo_ant, '(sin archivo)'),
       coalesce(p_storage_path, v_archivo_ant, '(sin archivo)'),
       v_yo,
       v_tipo_doc || ' · se reemplazó el archivo firmado');
    -- ⇧⇧⇧ CAMBIO 0448 ⇧⇧⇧

    return p_id;
  end if;

  -- ⇩⇩⇩ CAMBIO 0448 ⇩⇩⇩ Una negativa sin motivo quedaba con quién y cuándo,
  -- pero sin ningún porqué — ver «QUÉ PROMETE» arriba.
  if coalesce(p_es_negativa, false) and
     (p_nota is null or length(trim(p_nota)) < 3) then
    raise exception 'Para registrar que se negó a firmar hace falta anotar el motivo (mínimo 3 caracteres).';
  end if;
  -- ⇧⇧⇧ CAMBIO 0448 ⇧⇧⇧

  if v_alcance = 'individual' then
    if p_persona_id is null then
      raise exception 'Falta de quién es el documento.';
    end if;
    if not exists (select 1 from personas where id = p_persona_id and estado = 'activo') then
      raise exception 'Esa persona no existe o no está activa.';
    end if;
    -- La ruta admite a quien es practicante (0397/0424).
    if p_tipo = 'ruta' and not fn_persona_le_corresponde_movilidad(p_persona_id) then
      raise exception 'Esa persona no está en planilla ni es practicante: no le corresponde declarar su ruta.';
    end if;
    -- ⇩⇩⇩ CAMBIO 0518 ⇩⇩⇩ El bono también (antes: `en_planilla` a secas). Es
    -- la misma pregunta que se hace `fn_mi_bono_cumpleanos`: el cargo en papel
    -- y la firma desde Info no pueden contestar distinto sobre la misma persona.
    if p_tipo = 'bono' and fn_persona_le_corresponde_bono_cumpleanos(p_persona_id) is not true then
      raise exception 'Esa persona no está en planilla ni es practicante: no le corresponde ese documento.';
    end if;
    -- ⇧⇧⇧ CAMBIO 0518 ⇧⇧⇧
  elsif p_persona_id is not null then
    raise exception 'La política de movilidad la emite CAYLA: no se atribuye a una persona.';
  end if;

  if p_tipo = 'bono' and p_anio is null then
    raise exception 'Falta de qué año es la constancia del bono.';
  end if;

  -- ── REEMPLAZAR ES REEMPLAZAR (0211) ──────────────────────────────────
  -- Una política nueva anula la anterior. Ver 0211/0424 para la historia
  -- completa de por qué esto tiene que pasar antes del insert.
  if p_tipo = 'politica' and p_id is null then
    update documentos_firmados
       set anulado_at = now(),
           anulado_por = v_yo,
           anulado_motivo = 'Reemplazada por la política firmada el ' ||
                            to_char(p_fecha_firma, 'DD/MM/YYYY')
     where tipo = 'politica' and anulado_at is null;
  end if;
  insert into documentos_firmados (
    alcance, persona_id, tipo, storage_path, fecha_firma,
    ruta_declarada, monto_declarado, anio, es_negativa, nota, registrado_por
  ) values (
    v_alcance, p_persona_id, p_tipo, p_storage_path, p_fecha_firma,
    nullif(trim(coalesce(p_ruta_declarada, '')), ''),
    case when p_es_negativa then null else p_monto_declarado end,
    p_anio, coalesce(p_es_negativa, false),
    nullif(trim(coalesce(p_nota, '')), ''), v_yo
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (coalesce(p_persona_id, v_yo),
     case when p_es_negativa then 'documento_negativa' else 'documento_firmado' end,
     null,
     p_tipo || ' · firmado el ' || p_fecha_firma::text,
     v_yo,
     case when p_es_negativa
          then 'Se registró la negativa a firmar'
          else 'Alta de documento firmado' end);

  return v_id;
end;
$$;

grant execute on function fn_documento_registrar(text,date,uuid,text,numeric,integer,boolean,text,text,uuid)
  to authenticated;

-- ── D · Lo que ve DO: cuerpo de la 0492, un cambio (CAMBIO 0518) ───────────
-- Misma firma y mismas columnas que la 0492, así que alcanza con `create or
-- replace` y no queda ninguna sobrecarga.
create or replace function fn_documentos_tablero(p_solo_mi_fila boolean default false)
returns table (
  persona_id uuid, persona text, sede text, fecha_ingreso date,
  ruta_id uuid, ruta_firmada_el date, ruta_monto numeric, ruta_negativa boolean,
  ruta_desfasada boolean, ruta_firma_persona_confirmada_at timestamptz,
  ruta_tarifa_vigente numeric,
  bono_id uuid, bono_anio integer, bono_firmada_el date, bono_mes integer, bono_estado text,
  estado text,
  ruta_por_renovar text   -- CAMBIO 0492
)
language sql
stable
security definer
set search_path = public
as $function$
  with hoy as (
    select fn_hoy_lima()                             as dia,
           extract(year  from fn_hoy_lima())::int    as anio,
           extract(month from fn_hoy_lima())::int    as mes,
           (date_trunc('month', fn_hoy_lima()) + interval '1 month - 1 day')::date
                                                     as fin_de_mes,
           coalesce(
             (select min(vigente_desde) from parametros_laborales
               where clave = 'bono_onomastico' and valor > 0),
             '1900-01-01'::date)                     as bono_desde
  ),
  ruta as (
    select distinct on (d.persona_id)
           d.persona_id, d.id, d.fecha_firma, d.monto_declarado, d.es_negativa,
           d.firma_persona_confirmada_at,
           d.ruta_costo_pasaje   -- CAMBIO 0492
    from documentos_firmados d
    where d.tipo = 'ruta' and d.anulado_at is null
    order by d.persona_id, d.fecha_firma desc, d.created_at desc, d.id desc
  ),
  bono as (
    select distinct on (d.persona_id)
           d.persona_id, d.id, d.anio, d.fecha_firma
    from documentos_firmados d, hoy
    where d.tipo = 'bono' and d.anulado_at is null and not d.es_negativa
      and d.anio = hoy.anio
    order by d.persona_id, d.fecha_firma desc, d.created_at desc, d.id desc
  )
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    p.fecha_ingreso,
    r.id, r.fecha_firma, r.monto_declarado, coalesce(r.es_negativa, false),
    (r.monto_declarado is not null
      and tar.valor is not null
      and r.monto_declarado <> tar.valor),
    r.firma_persona_confirmada_at,
    tar.valor,
    b.id, b.anio, b.fecha_firma,
    dp.mes_nacimiento,
    case
      when b.id is not null            then 'ok'
      -- ⇩ CAMBIO 0518 ⇩ La misma regla que fn_mi_bono_cumpleanos y el cargo en
      -- papel: a quien no le toca, el tablero no le pide nada.
      when fn_persona_le_corresponde_bono_cumpleanos(p.id) is not true then 'no_aplica'
      -- ⇧ CAMBIO 0518 ⇧
      when dp.mes_nacimiento is null   then 'sin_fecha'
      when make_date(hoy.anio, dp.mes_nacimiento, 1)
             < date_trunc('month', hoy.bono_desde)::date then 'no_aplica'
      when make_date(hoy.anio, dp.mes_nacimiento, 1)
             < date_trunc('month', p.fecha_ingreso)::date then 'no_aplica'
      when dp.mes_nacimiento = hoy.mes then 'este_mes'
      when dp.mes_nacimiento <  hoy.mes then 'vencido'
      else                                  'proximo'
    end,
    case
      when r.id is null                    then 'sin_ruta'
      when coalesce(r.es_negativa, false)  then 'se_nego'
      else 'ok'
    end,
    -- ⇩⇩⇩ CAMBIO 0492 ⇩⇩⇩ El mismo criterio que usa el candado de la firma.
    fn_ruta_por_renovar(r.fecha_firma, r.firma_persona_confirmada_at,
                        r.ruta_costo_pasaje, r.es_negativa)
  from personas p
  cross join hoy
  left join sedes s on s.id = p.sede_base_id
  left join ruta r on r.persona_id = p.id
  left join bono b on b.persona_id = p.id
  left join lateral (
    select extract(month from d.fecha_nacimiento)::int as mes_nacimiento
    from datos_personales d
    where d.persona_id = p.id and d.fecha_nacimiento is not null
  ) dp on true
  left join lateral (
    select pl.valor
    from parametros_laborales pl
    where pl.clave = 'movilidad_diaria'
      and pl.vigente_desde <= hoy.dia
      and (pl.vigente_hasta is null or pl.vigente_hasta >= hoy.dia)
      and (pl.sede_codigo = s.codigo or pl.sede_codigo is null)
    order by (pl.sede_codigo is null), pl.vigente_desde desc
    limit 1
  ) tar on true
  where p.estado = 'activo'
    and not p.cuenta_de_servicio   -- CAMBIO 0491: una cuenta de servicio (estación de retail) no es una persona
    -- ⇩⇩⇩ CAMBIO 0424 ⇩⇩⇩ Antes: `and p.en_planilla`. Ver el encabezado de
    -- esta migración — es la línea que dejaba a Benjamin, Fernanda y Daniel
    -- fuera del tablero aunque ya pudieran cobrar movilidad desde la 0397.
    and fn_persona_le_corresponde_movilidad(p.id)
    and (p.id = fn_persona_actual_id()
         or (not coalesce(p_solo_mi_fila, false) and fn_es_admin_o_lider() is true))
    and p.id is distinct from (
      select (c.valor->>'persona_id')::uuid
      from configuracion c
      where c.clave = 'firmante_empresa'
    )
    and (p.fecha_fin_contrato is null or p.fecha_fin_contrato > hoy.fin_de_mes)
  order by (r.id is not null), p.apellidos;
$function$;

grant execute on function fn_documentos_tablero(boolean) to authenticated;
revoke execute on function fn_documentos_tablero(boolean) from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (518, 'a_quien_le_toca_el_bono_de_cumpleanos_se_dice_una_vez')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_persona_le_corresponde_bono_cumpleanos') = 1 as tiene_regla,
  (select position('CAMBIO 0518' in prosrc) > 0 from pg_proc where proname = 'fn_mi_bono_cumpleanos')  as mi_bono_al_dia,
  (select position('CAMBIO 0518' in prosrc) > 0 from pg_proc where proname = 'fn_documento_registrar') as registrar_al_dia,
  (select position('CAMBIO 0518' in prosrc) > 0 from pg_proc where proname = 'fn_documentos_tablero')  as tablero_al_dia,
  (select count(*) from pg_proc where proname in ('fn_mi_bono_cumpleanos', 'fn_documento_registrar', 'fn_documentos_tablero')) = 3 as sin_sobrecargas,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 518) as registro;
