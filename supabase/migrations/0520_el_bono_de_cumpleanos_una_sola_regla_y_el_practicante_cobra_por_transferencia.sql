-- ============================================================================
-- 0520 — El bono de cumpleaños: una sola regla, y el practicante cobra por
--        transferencia
-- ============================================================================
--
-- POR QUÉ EXISTE (léelo entero: es la historia de dos migraciones chocando)
--
--   El 2026-10-13, el mismo caso —Daniel Ruiz, practicante, cumple en octubre,
--   no veía su bono en Info mientras DO lo veía pendiente— se arregló DOS veces
--   en dos sesiones distintas, con dos personas distintas decidiendo:
--
--     · La 0518 (esta rama, decidido por Cayla): el bono es para todo el
--       equipo salvo quien está en periodo de prueba y quien tiene un contrato
--       de menos de una semana; una función nueva lo dice una vez
--       (`fn_persona_le_corresponde_bono_cumpleanos`) y la leen las tres
--       puertas (Info/firma, cargo en papel, tablero de DO). El practicante
--       cobra como cualquiera: su bono entra a la boleta (0479).
--       **Pegada en producción el 2026-10-13.**
--     · La 0519 (PR #524, decidido por Felipe): el bono también es para el
--       practicante; otra función (`fn_persona_le_corresponde_bono`); y el
--       practicante NUNCA va a la boleta —queda «pedido» y DO le transfiere—
--       porque su subvención no es remuneración (Ley 28518, art. 47) y nadie
--       auditó qué hace la planilla con un bono de practicante. **Nunca se
--       pegó, y ya no puede pegarse:** su freno de md5 de partida exige las
--       funciones de la 0479/0448, y producción ya tiene las de la 0518
--       (medido en local: aborta antes de tocar nada). Su frontend SÍ se
--       publicó al fusionar el #524: hoy la pantalla le dice al practicante
--       «DO te lo transfiere» mientras la base lo manda a la boleta.
--
--   Cayla decidió el mismo día: **unir las dos.** Esta migración es esa unión.
--
-- QUÉ PROMETE
--
--   1. UNA regla, en UNA función, con el nombre de la 0519 (ya citado en el
--      código publicado) y el cuerpo de la 0518: le toca a quien está en
--      planilla o es practicante, nunca en periodo de prueba ni con un
--      contrato de menos de 7 días (los dos extremos incluidos; sin fecha de
--      fin es indefinido y le toca). La leen las tres puertas:
--      `fn_mi_bono_cumpleanos`, `fn_documento_registrar`, `fn_documentos_tablero`.
--   2. El practicante firma igual que cualquiera, pero su bono NO entra a la
--      boleta: queda «pedido», DO lo ve en «por transferir» y lo confirma con
--      la fecha (el camino de respaldo de la 0478). Es el cuerpo de
--      `fn_confirmar_mi_bono_cumpleanos` de la 0519, tal cual, con sus
--      marcadores renombrados a 0520 para que la base diga qué se pegó.
--   3. La función de la 0518 (`fn_persona_le_corresponde_bono_cumpleanos`)
--      desaparece: dos funciones para la misma pregunta es el defecto que las
--      dos migraciones vinieron a cerrar.
--
-- DECIDÍ:     partir de los cuerpos de la 0518 para las tres puertas (son los
--             que están en producción) y del de la 0519 para la firma, y que
--             el freno de abajo exija EXACTAMENTE ese estado.
-- DESCARTÉ:   (a) dejar las dos funciones y que cada puerta lea una: es tener
--             dos reglas con otro nombre. (b) reescribir la 0519 para que
--             acepte la 0518 debajo: una migración que ya está fusionada en
--             main no se edita; se la deja en `no-se-pegan.txt` con su razón.
--             (c) mandar el bono del practicante a la boleta (0518): mi propia
--             medición mostró que la planilla le arma base de retención de
--             cuarta con el bono dentro, un camino que nadie diseñó para él.
-- SE ROMPE SI: alguien vuelve a pegar la 0518 DESPUÉS de esta: sus `create or
--             replace` devolverían las tres puertas a la función vieja y la
--             recrearían. La 0518 ya está aplicada y no se vuelve a pegar
--             (anotado en docs/estado.md). Y si un practicante firmó entre la
--             0518 y esta migración, su bono SÍ está en una boleta: se ve con
--             `select … from documentos_firmados d join personas p … where
--             p.tipo_vinculo = 'practicante' and d.movimiento_id is not null`.
--
-- MD5 DE PARTIDA — el estado D de producción, confirmado el 2026-10-13 por
-- los marcadores (`CAMBIO 0518` en las tres puertas, ninguno en la firma):
--
--   fn_mi_bono_cumpleanos            0518 · 6fd41381b22ef30e7e4fcb42f6aeb490
--                                           sin comentarios 1a72a2beda3c84a4d90a8ab9433b603c
--   fn_documento_registrar           0518 · 5dfb2d92f073c7da11cfedaeb7bb978a
--                                           sin comentarios 2def483a9b7d64cf303b4a49058493d7
--   fn_documentos_tablero            0518 · 6dcecfdd7833315d4f91590680373086
--                                           sin comentarios 20058af78854793462f839e0a4e44da1
--   fn_confirmar_mi_bono_cumpleanos  0479 · b6706e42305134b1eee243c71cbb271d
--                                           sin comentarios e796c2b32398dae48a1a72f5f9a70707
--
--   El freno compara también con los retornos de carro quitados (`chr(13)`):
--   la 0492 vivía así en producción (pegada desde Windows) y ese desenlace
--   parecía «otra versión» sin serlo.
--
-- CONCURRENCIA
--
--   Nada nuevo: dos firmas a la vez las sigue frenando el índice único
--   `idx_documentos_bono_uno_por_anio` (0157); dos confirmaciones de DO, el
--   `for update` de `fn_confirmar_entrega_bono` (0478).
--
-- CÓMO SE REVIERTE
--
--   Volver a pegar la 0518 entera (deja las tres puertas con su función y la
--   recrea) y después `fn_confirmar_mi_bono_cumpleanos` de la 0479; luego
--     drop function if exists fn_persona_le_corresponde_bono(uuid);
--   Las constancias firmadas no se tocan: son plata que se pagó o se debe.
--
-- Idempotente: se puede pegar dos veces (la segunda, el freno se salta solo).
-- ============================================================================


-- ── 0 · EL FRENO ────────────────────────────────────────────────────────────
do $freno$
declare
  v_fn    text;
  v_tal   text;
  v_sin   text;
  v_falla text := '';
begin
  if exists (select 1 from migraciones_aplicadas
              where numero = 520
                and nombre = 'el_bono_de_cumpleanos_una_sola_regla_y_el_practicante_cobra_por_transferencia') then
    raise notice '0520 ya estaba aplicada: no se comprueban los md5 de partida.';
    return;
  end if;
  if not exists (select 1 from migraciones_aplicadas where numero = 518) then
    raise exception 'FALTA LA 0518. Esta migración parte de sus funciones; pégala antes.';
  end if;
  for v_fn, v_tal, v_sin in
    select * from (values
      ('fn_mi_bono_cumpleanos',           '6fd41381b22ef30e7e4fcb42f6aeb490', '1a72a2beda3c84a4d90a8ab9433b603c'),   -- 0518
      ('fn_documento_registrar',          '5dfb2d92f073c7da11cfedaeb7bb978a', '2def483a9b7d64cf303b4a49058493d7'),   -- 0518
      ('fn_documentos_tablero',           '6dcecfdd7833315d4f91590680373086', '20058af78854793462f839e0a4e44da1'),   -- 0518
      ('fn_confirmar_mi_bono_cumpleanos', 'b6706e42305134b1eee243c71cbb271d', 'e796c2b32398dae48a1a72f5f9a70707')    -- 0479
    ) as t(fn, tal_cual, sin_comentarios)
  loop
    if not exists (
      select 1
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
             lateral (values (p.prosrc), (replace(p.prosrc, chr(13), ''))) as v(src)
       where n.nspname = 'public' and p.proname = v_fn
         and (md5(v.src) = v_tal
              or md5(array_to_string(array(
                   select regexp_replace(l, '[[:space:]]*--.*$', '')
                   from unnest(string_to_array(v.src, chr(10))) as l
                   where btrim(l) not like '--%'
                 ), chr(10))) = v_sin))
    then
      v_falla := v_falla || '  · ' || v_fn || chr(10);
    end if;
  end loop;
  if v_falla <> '' then
    raise exception E'PARA. Producción no tiene el cuerpo del que se copió esta migración:\n%\nPegarla revertiría en silencio lo que haya entre medias. Corre ./scripts/donde-vive.sh sobre cada una y reconstrúyela desde la versión de producción. (Nada se ha modificado: esto abortó antes de tocar nada.)', v_falla;
  end if;
end
$freno$;


-- ── A · UNA sola pregunta: ¿le toca el bono de cumpleaños? ─────────────────
-- Nombre de la 0519, cuerpo de la 0518.
create or replace function fn_persona_le_corresponde_bono(p_persona_id uuid)
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

comment on function fn_persona_le_corresponde_bono(uuid) is
  'A quién le toca el bono de cumpleaños (0518 + 0519 → 0520, decidido por '
  'Cayla el 2026-10-13): en planilla o practicante, nunca en periodo de prueba '
  'ni con un contrato de menos de 7 días (extremos incluidos). La leen '
  'fn_mi_bono_cumpleanos, fn_documento_registrar y fn_documentos_tablero. '
  'Separada de fn_persona_le_corresponde_movilidad a propósito: son dos '
  'beneficios distintos y ya no contestan igual (la movilidad sí es para prueba).';

-- Solo la llaman funciones del propio esquema.
revoke all on function fn_persona_le_corresponde_bono(uuid) from public, anon, authenticated;


-- ── B · Lo que ve la persona: cuerpo de la 0518, la función renombrada ──────
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
  -- CAMBIO 0520 (marcador): la regla se pregunta a fn_persona_le_corresponde_bono.
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
     or fn_persona_le_corresponde_bono(v_yo) is not true then
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


-- ── C · El cargo en papel de DO: cuerpo de la 0518, la función renombrada ──
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
    -- CAMBIO 0520 (marcador): misma puerta, la función que se quedó.
    -- ⇩⇩⇩ CAMBIO 0518 ⇩⇩⇩ El bono también (antes: `en_planilla` a secas). Es
    -- la misma pregunta que se hace `fn_mi_bono_cumpleanos`: el cargo en papel
    -- y la firma desde Info no pueden contestar distinto sobre la misma persona.
    if p_tipo = 'bono' and fn_persona_le_corresponde_bono(p_persona_id) is not true then
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


-- ── D · Lo que ve DO en el tablero: cuerpo de la 0518, la función renombrada ─
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
      -- CAMBIO 0520 (marcador): misma regla, la función que se quedó.
      -- ⇩ CAMBIO 0518 ⇩ La misma regla que fn_mi_bono_cumpleanos y el cargo en
      -- papel: a quien no le toca, el tablero no le pide nada.
      when fn_persona_le_corresponde_bono(p.id) is not true then 'no_aplica'
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


-- ── E · La firma: cuerpo de la 0519 — el practicante nunca va a la boleta ───
-- Parte de la 0479 (lo que hay en producción). Marcadores renombrados a 0520.
create or replace function fn_confirmar_mi_bono_cumpleanos()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo          uuid := fn_persona_actual_id();
  v_imagen      text;
  v_monto       numeric;
  v_anio        integer := extract(year from fn_hoy_lima())::int;
  v_id          uuid;
  v_ip          text;
  v_ua          text;
  v_estado      text;
  -- CAMBIO 0479 (marcador: la comprobación del bloque 0 reconoce esta versión)
  -- CAMBIO 0520 (antes 0519) (marcador): `v_practicante` y el `if` que protege la boleta.
  v_practicante boolean;
  v_periodo     uuid;
  v_periodo_ini date;
  v_periodo_fin date;
  v_mov         uuid;
begin
  if v_yo is null then
    raise exception 'No se encontró tu persona.';
  end if;

  -- Firmar es pedir plata: solo en el mes de su cumpleaños, o después si se le
  -- pasó (0478).
  select b.estado into v_estado from fn_mi_bono_cumpleanos() b;

  if v_estado = 'pedido' then
    raise exception 'Ya pediste tu bono. Desarrollo Organizacional te avisa por aquí cuando lo transfiera.';
  elsif v_estado = 'en_boleta' then
    raise exception 'Tu bono ya está en tu boleta: se paga junto con tu planilla.';
  elsif v_estado = 'entregado' then
    raise exception 'Tu bono de cumpleaños de este año ya se entregó.';
  elsif v_estado = 'proximo' then
    raise exception 'Tu bono se pide en el mes de tu cumpleaños.';
  elsif v_estado = 'sin_fecha' then
    raise exception 'Falta tu fecha de nacimiento en tu ficha. Avisa a Desarrollo Organizacional.';
  elsif v_estado is distinct from 'este_mes' and v_estado is distinct from 'vencido' then
    raise exception 'Este año no te corresponde el bono de cumpleaños. Si crees que es un error, avisa a Desarrollo Organizacional.';
  end if;

  select imagen into v_imagen from firmas_escaneadas where persona_id = v_yo;
  if v_imagen is null then
    raise exception 'Todavía no configuraste tu firma. Ve a la pestaña «Firma» antes de confirmar.';
  end if;

  v_monto := fn_bono_monto_vigente();

  -- ⇩ CAMBIO 0479 ⇩ `<= 0` además de null: la línea de boleta exige monto > 0,
  -- y un bono «apagado» con valor 0 no debe llegar hasta un error de check.
  if v_monto is null or v_monto <= 0 then
    raise exception 'No hay un monto de bono de onomástico vigente. Avisa a Desarrollo Organizacional antes de firmar.';
  end if;

  begin
    v_ip := nullif(split_part(
      coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'x-forwarded-for',
      ',', 1), '');
    v_ua := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'user-agent';
  exception when others then
    v_ip := null;
    v_ua := null;
  end;

  -- ⇩⇩⇩ CAMBIO 0479 ⇩⇩⇩ LA LÍNEA DE BOLETA.
  -- El último periodo que ya empezó: el que contiene hoy o, entre el 29 y el
  -- día en que DO crea el siguiente, el que se está por cerrar. `for share` lo
  -- pone en fila con `fn_periodo_pagado`, que toma `for update` sobre la misma
  -- fila: después de esperar, la pregunta de abajo ya ve el pago.
  --
  -- ⇩ CAMBIO 0520 (antes 0519) ⇩ UN PRACTICANTE NUNCA VA A LA BOLETA. Su convenio de
  -- modalidad formativa no es una relación laboral y su subvención no es
  -- remuneración (Ley 28518, art. 47): meter este monto en una boleta de
  -- planilla lo mezclaría con lo que no debe mezclarse. Su bono queda
  -- «pedido» —firmado, sin línea en ninguna boleta— y lo transfiere DO, que es
  -- exactamente el camino de respaldo de la 0478. Sin periodo no hay lectura
  -- ni `for share`: ni siquiera se toca la planilla.
  v_practicante := exists (
    select 1 from personas where id = v_yo and tipo_vinculo = 'practicante');

  if not v_practicante then
    select pp.id, pp.fecha_ini, pp.fecha_fin into v_periodo, v_periodo_ini, v_periodo_fin
      from periodos_planilla pp
     where pp.fecha_ini <= fn_hoy_lima()
     order by pp.fecha_ini desc
     limit 1
     for share;
  end if;

  -- Periodo pagado para su grupo, o ninguno: no se escribe en la boleta. La
  -- firma vale igual y la constancia queda `pedido` (respaldo de la 0478).
  if v_periodo is not null and not fn_fecha_en_periodo_pagado(v_periodo_ini, v_yo) then
    insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, creado_por)
    values (v_periodo, v_yo, 'bono', 'Asignación por cumpleaños', v_monto, v_yo)
    returning id into v_mov;
  end if;
  -- ⇧⇧⇧ CAMBIO 0479 ⇧⇧⇧

  insert into documentos_firmados (
    alcance, persona_id, tipo, fecha_firma, monto_declarado, anio,
    registrado_por, firma_persona, firma_persona_confirmada_at,
    firma_persona_ip, firma_persona_user_agent, movimiento_id
  ) values (
    'individual', v_yo, 'bono', fn_hoy_lima(), v_monto, v_anio,
    v_yo, v_imagen, now(), v_ip, v_ua, v_mov
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_yo, 'documento_firmado', null, 'bono · firmado digitalmente el ' || fn_hoy_lima()::text, v_yo,
     'Firma digital de la constancia del bono de cumpleaños, reemplaza el escaneo físico.');

  if v_mov is not null then
    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (v_yo, 'bono_en_boleta', null,
       'S/ ' || v_monto::text || ' · boleta del periodo que cierra el ' || v_periodo_fin::text, v_yo,
       'El bono de cumpleaños firmado desde el sistema entró a la boleta del periodo abierto (0479).');
  end if;

  return v_id;
end;
$$;

grant execute on function fn_confirmar_mi_bono_cumpleanos() to authenticated;
revoke execute on function fn_confirmar_mi_bono_cumpleanos() from public, anon;

-- ── F · La función de la 0518 se retira: ya nadie la lee ───────────────────
drop function if exists fn_persona_le_corresponde_bono_cumpleanos(uuid);


insert into migraciones_aplicadas (numero, nombre)
values (520, 'el_bono_de_cumpleanos_una_sola_regla_y_el_practicante_cobra_por_transferencia')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_persona_le_corresponde_bono') = 1            as tiene_regla,
  (select count(*) from pg_proc where proname = 'fn_persona_le_corresponde_bono_cumpleanos') = 0 as sin_la_vieja,
  (select position('CAMBIO 0520' in prosrc) > 0 from pg_proc where proname = 'fn_mi_bono_cumpleanos')           as mi_bono_al_dia,
  (select position('CAMBIO 0520' in prosrc) > 0 from pg_proc where proname = 'fn_documento_registrar')          as registrar_al_dia,
  (select position('CAMBIO 0520' in prosrc) > 0 from pg_proc where proname = 'fn_documentos_tablero')           as tablero_al_dia,
  (select position('CAMBIO 0520' in prosrc) > 0 from pg_proc where proname = 'fn_confirmar_mi_bono_cumpleanos') as firma_al_dia,
  (select count(*) from pg_proc where proname in ('fn_mi_bono_cumpleanos', 'fn_documento_registrar', 'fn_documentos_tablero', 'fn_confirmar_mi_bono_cumpleanos')) = 4 as sin_sobrecargas,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 520) as registro;
