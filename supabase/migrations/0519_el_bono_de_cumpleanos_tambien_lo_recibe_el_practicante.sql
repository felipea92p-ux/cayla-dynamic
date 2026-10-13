-- ============================================================================
-- 0519 — El bono de cumpleaños también lo recibe el practicante
-- ============================================================================
--
-- ESTADO (2026-10-13): LISTA PARA PEGAR TÉCNICAMENTE; LO LEGAL SIGUE ABIERTO.
-- Decidido por Felipe el 2026-10-13 («Opción 2: abrir el bono a practicantes»,
-- después de ver el caso de Daniel Ruiz). El md5 de partida de producción ya
-- está confirmado (ver más abajo). Lo que NO está cerrado son las tres
-- preguntas de «LO QUE FALTA CONFIRMAR» al contador / abogado laboral: Felipe
-- pidió el SQL antes de tenerlas, sabiendo que el texto de la constancia para
-- practicantes (`apps/web/components/papel-bono.tsx`) es provisional.
--
-- ORDEN AL PEGAR: lo ideal es que el frontend con el texto nuevo (PR de esta
-- rama) ya esté publicado ANTES de pegar esto. El frontend es compatible hacia
-- atrás —sin la migración, un practicante sigue sin poder pedir el bono—, así
-- que se puede fusionar primero sin romper nada. Al revés, un practicante que
-- firme entre el pegado y la publicación firmaría el texto de planilla, que lo
-- llama «trabajador» y cita normas laborales.
--
-- QUÉ PROMETE
--
--   Que quien tiene `tipo_vinculo = 'practicante'` (convenio de modalidad
--   formativa, Ley 28518) pueda recibir el bono de cumpleaños igual que quien
--   está en planilla: lo ve en «Lo mío», lo pide firmando su constancia, y
--   Desarrollo Organizacional lo transfiere y lo confirma — o, si prefiere
--   hacerlo en papel, lo registra desde Documentación.
--
-- EL DEFECTO QUE LO MOTIVÓ, MEDIDO EN PRODUCCIÓN EL 2026-10-13
--
--   Daniel Ruiz (practicante, `en_planilla = false`, activo, con cuenta):
--     · `fn_documentos_tablero(true)` le decía bono_estado = 'este_mes'
--       —la 0424 abrió el tablero a practicantes para la declaración de ruta
--       y el bono se coló con ellos—, así que la Bandeja de DO y «Cargos de
--       cumpleaños» le pedían una constancia;
--     · `fn_mi_bono_cumpleanos()` le contestaba 'no_aplica', así que en su
--       pantalla no aparecía «Pedir mi bono»;
--     · y `fn_documento_registrar` habría rechazado el escaneo («Esa persona
--       no está en planilla»).
--   Tres puertas, dos respuestas. Se decidió resolverlo abriendo el bono al
--   practicante y no cerrándolo en el tablero.
--
-- QUÉ HACE
--
--   1. `fn_persona_le_corresponde_bono(uuid)`: UN solo lugar para «¿le
--      corresponde el bono?» — en planilla, o practicante. Hoy da lo mismo que
--      `fn_persona_le_corresponde_movilidad` (0424), pero es OTRA pregunta y
--      puede divergir mañana: por eso no se reutiliza esa función.
--   2. `fn_mi_bono_cumpleanos()` (paso 2): usa esa función en vez de
--      `en_planilla` a secas.
--   3. `fn_documento_registrar` (rama bono): ídem.
--   4. `fn_confirmar_mi_bono_cumpleanos()`: si quien firma es practicante, NO
--      crea la línea de boleta.
--
-- POR QUÉ POR TRANSFERENCIA Y NO POR BOLETA
--
--   La 0479 metió el bono a la boleta para quien está en planilla. Para un
--   practicante se descartó a propósito:
--     · su subvención no es remuneración (art. 47, Ley 28518) y su boleta no es
--       la de un trabajador (0322: hoy imprime un «Detalle de servicios
--       prestados»); mezclar ahí un pago extra es mezclar lo que el repo ha
--       cuidado en no mezclar (0119: no contar tardanzas ni abrir expedientes
--       a un practicante, por ser indicios de subordinación);
--     · evita preguntar, y auditar, qué hace `fn_planilla_calcular` con un
--       `bono` de un practicante (EsSalud, retención) — pregunta que, si CAYLA
--       lo decide con el contador, se responde en otra migración y con
--       prueba;
--     · el camino de respaldo ya existe y está probado (0478): el bono queda
--       «pedido» y DO lo ve en «por transferir».
--   NO SE TOCA `fn_planilla_calcular` NI NINGUNA FUNCIÓN DE CÁLCULO.
--
-- LO QUE FALTA CONFIRMAR (el contador / abogado laboral — el repo no lo decide)
--
--   1. ¿Puede CAYLA darle a un practicante un monto por cumpleaños sin que
--      cuente como parte de su subvención ni cambie su condición formativa?
--      No hallé norma que lo prohíba ni que lo autorice expresamente; que se
--      pueda es una inferencia.
--   2. ¿Qué texto debe llevar la constancia, y cómo debe constar el pago?
--      Para planilla cita el literal g) del art. 19 del TUO del D. Leg. 650 y
--      el art. 7 del D.S. 003-97-TR, que son del régimen laboral; para un
--      practicante NO se citan, y la constancia no lo llama «trabajador». El
--      texto nuevo (en `apps/web/components/papel-bono.tsx`) es provisional.
--   3. ¿Es gasto deducible para CAYLA?
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   · No toca `fn_documentos_tablero`: ya listaba al practicante (0424), y con
--     esta migración esa lista deja de contradecir a las otras dos puertas.
--   · No abre el bono a `rxh` ni `no_trabajador`: siguen fuera.
--   · No guarda el texto firmado: la constancia se pinta al mirarla, así que
--     si el vínculo cambia después (practicante → planilla) el papel cambia de
--     texto. Es el mismo límite que ya tiene el bono de planilla; se anota
--     aquí para quien lo busque.
--   · No toca a quien ya firmó: ninguna fila cambia al pegar esto.
--
-- MD5 DE PARTIDA — CONFIRMADOS EN PRODUCCIÓN EL 2026-10-13
--
--   fn_documento_registrar            0448   5319 caracteres
--   fn_mi_bono_cumpleanos()           0479   4414 caracteres
--   fn_confirmar_mi_bono_cumpleanos() 0479   4645 caracteres
--
--   Los cuerpos se copiaron del repo, y Felipe pidió el md5 a PRODUCCIÓN en el
--   SQL Editor el mismo día: los tres coinciden, tanto el tal cual
--   (b6706e42… · 5909cada… · 6a9d7307…) como el sin comentarios (e796c2b3… ·
--   47307a09… · 983554cf…), con 0 retornos `\r`. (Se pidió DESPUÉS de escribir
--   la migración y no antes, contra lo que dice CLAUDE.md; coincidió, así que
--   no hubo daño — pero el orden correcto es el otro.) Se comprobó además que
--   `main` no trajo migraciones sobre estas funciones desde que se escribió.
--   El bloque 0 lo vuelve a comprobar solo al pegar y aborta sin tocar nada si
--   alguna es otra versión; acepta el md5 tal cual, sin comentarios, y ambos
--   sin `\r` (pegar desde Windows, 0401).
--
-- CÓMO SE REVIERTE
--
--   drop function if exists fn_persona_le_corresponde_bono(uuid);
--   -- recrear fn_documento_registrar con el cuerpo de la 0448, y
--   -- fn_mi_bono_cumpleanos / fn_confirmar_mi_bono_cumpleanos con los de la
--   -- 0479 (`create or replace`, mismas firmas).
--   Los bonos de practicantes ya pedidos quedarían «pedido» y se transfieren
--   a mano: no hay datos que deshacer.
--
-- Idempotente: se puede pegar dos veces.
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
              where numero = 519
                and nombre = 'el_bono_de_cumpleanos_tambien_lo_recibe_el_practicante') then
    raise notice '0519 ya estaba aplicada: no se comprueban los md5 de partida.';
    return;
  end if;

  if not exists (select 1 from pg_proc where proname = 'fn_persona_le_corresponde_movilidad') then
    raise exception 'FALTA LA 0424. fn_persona_le_corresponde_movilidad no existe; pégala antes que esta.';
  end if;

  for v_fn, v_tal, v_sin in
    select * from (values
      ('fn_documento_registrar',            '5909cada98bc2f879fd8f30dffeaffbe', '47307a097a4fd667babdb721e5dbaf0e'),   -- 5319 caracteres (0448)
      ('fn_mi_bono_cumpleanos',             '6a9d7307f6fa7e4446da67117012736f', '983554cf53130f082aeb06f5f34224e5'),   -- 4414 caracteres (0479)
      ('fn_confirmar_mi_bono_cumpleanos',   'b6706e42305134b1eee243c71cbb271d', 'e796c2b32398dae48a1a72f5f9a70707')    -- 4645 caracteres (0479)
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


-- ── A · Un solo lugar para «¿le corresponde el bono?» ──────────────────────
create or replace function fn_persona_le_corresponde_bono(p_persona_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select en_planilla or tipo_vinculo = 'practicante' from personas where id = p_persona_id),
    false
  );
$$;

comment on function fn_persona_le_corresponde_bono(uuid) is
  'Quién puede recibir el bono de cumpleaños: en_planilla, o tipo_vinculo = '
  'practicante (0519). Hoy coincide con fn_persona_le_corresponde_movilidad '
  '(0424), pero es otra decisión de negocio y por eso es otra función. La usan '
  'fn_mi_bono_cumpleanos y fn_documento_registrar.';

grant execute on function fn_persona_le_corresponde_bono(uuid) to authenticated;
revoke execute on function fn_persona_le_corresponde_bono(uuid) from public, anon;


-- ── B · fn_documento_registrar — la rama del bono ──────────────────────────
-- Cuerpo de la 0448; el ÚNICO cambio es la marca CAMBIO 0519.
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
    -- ⇩ CAMBIO 0519 ⇩ El bono admite a quien le corresponde (en planilla, o
    -- practicante) y lo dice `fn_persona_le_corresponde_bono`, un solo lugar.
    if p_tipo = 'bono' and not fn_persona_le_corresponde_bono(p_persona_id) then
      raise exception 'Esa persona no está en planilla ni es practicante: no le corresponde ese documento.';
    end if;
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


-- ── C · fn_mi_bono_cumpleanos — a un practicante ya no le dice «no aplica» ──
-- Cuerpo de la 0479; el ÚNICO cambio es la marca CAMBIO 0519 (paso 2).
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
  -- CAMBIO 0519 (marcador): el paso 2 pregunta `fn_persona_le_corresponde_bono`.
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

  -- ⇩ CAMBIO 0519 ⇩ Antes: `exists (... p.en_planilla)`. Un practicante ya no
  -- cae aquí en «no_aplica»: sigue el mismo camino que cualquiera.
  if not found
     or not fn_persona_le_corresponde_bono(v_yo) then
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


-- ── D · fn_confirmar_mi_bono_cumpleanos — el practicante no va a la boleta ──
-- Cuerpo de la 0479; el ÚNICO cambio es la marca CAMBIO 0519.
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
  -- CAMBIO 0519 (marcador): `v_practicante` y el `if` que protege la boleta.
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
  -- ⇩ CAMBIO 0519 ⇩ UN PRACTICANTE NUNCA VA A LA BOLETA. Su convenio de
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


insert into migraciones_aplicadas (numero, nombre)
values (519, 'el_bono_de_cumpleanos_tambien_lo_recibe_el_practicante')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_persona_le_corresponde_bono') = 1 as tiene_la_pregunta,
  (select count(*) from pg_proc
    where proname in ('fn_documento_registrar', 'fn_mi_bono_cumpleanos', 'fn_confirmar_mi_bono_cumpleanos')
      and position('CAMBIO 0519' in prosrc) > 0) = 3 as tiene_las_tres,
  (select count(*) from pg_proc where proname = 'fn_mi_bono_cumpleanos') = 1 as sin_sobrecarga,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 519) as registro;
