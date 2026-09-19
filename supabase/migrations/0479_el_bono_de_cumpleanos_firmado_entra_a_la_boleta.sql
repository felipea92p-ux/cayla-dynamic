-- ============================================================================
-- 0479 — El bono de cumpleaños firmado entra a la boleta
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que cuando una persona firma su constancia del bono de cumpleaños desde
--   /mio, el incentivo aparezca en SU BOLETA del periodo que corre —como una
--   línea «Asignación por cumpleaños +S/ 180.00»— y se pague junto con el resto
--   de su planilla. Sin que Desarrollo Organizacional (DO) tenga que hacer nada
--   aparte: firmar y quedar en la boleta es UN solo acto.
--
--   Hasta la 0478 firmar solo creaba un PEDIDO: el bono no tocaba la planilla,
--   DO lo veía en su Bandeja «por transferir» y lo mandaba por fuera con su
--   fecha. La persona no veía nada en su boleta, y el mismo dinero se movía por
--   dos caminos que nadie cruzaba. Esta migración lo mete por el camino que ya
--   existe para todo lo que se suma a una boleta.
--
--   DECIDÍ:    al firmar, la MISMA transacción crea una línea `bono` en
--              `movimientos_planilla` del periodo que corre y la ata a la
--              constancia (`documentos_firmados.movimiento_id`). La planilla ya
--              suma esos bonos (`mov.bonos` en fn_planilla_calcular) y la boleta
--              ya los pinta (boleta-hoja.tsx): no se toca ninguna de las dos.
--   DESCARTÉ:  (a) que `fn_planilla_calcular` lea la constancia y agregue la
--              línea por su cuenta. Es una función de ~96 000 caracteres con 58
--              versiones repartidas; reescribirla ya costó dos accidentes en
--              producción (0276, 0261) y aquí no hace falta: el bucket de bonos
--              existe y es el camino que DO usa a mano hoy.
--              (b) que DO pase el bono a la boleta con un clic después de ver
--              el pedido. Deja abierto el hueco que la 0478 se escribió para
--              cerrar: una constancia con «Recibí conforme» firmado y ningún
--              paso obligatorio que garantice que alguien pague.
--   SE ROMPE SI: DO borra la línea desde Planilla sin pagar el bono por otro
--              lado. No se pierde en silencio: el vínculo se suelta
--              (`on delete set null`), la constancia vuelve a «pedido» y
--              reaparece en la Bandeja «por transferir». Y si un periodo se
--              marca pagado justo mientras ella firma, el `for share` de abajo
--              las pone en fila (ver CONCURRENCIA).
--
-- CÓMO ESTÁ HECHO, Y POR QUÉ ASÍ
--
--   EL VÍNCULO VIVE EN LA CONSTANCIA, NO EN LA PLANILLA. Una columna nueva,
--   `documentos_firmados.movimiento_id`, y no una columna en
--   `movimientos_planilla`: la planilla es el núcleo del pago y no tiene por qué
--   saber que existe un documento de cumpleaños. Es el mismo criterio de la
--   0478 —la entrega es un atributo de la constancia—, y con él los estados
--   imposibles los impide el esquema y no un `if`:
--
--     · un movimiento atado a algo que no es un bono pedido desde el sistema;
--     · «pagado dos veces»: un bono no puede tener a la vez un movimiento en
--       boleta Y una transferencia confirmada por DO (constraint);
--     · dos constancias sobre la misma línea de boleta (índice único).
--
--   ¿A QUÉ PERIODO VA? Al último que YA empezó (`fecha_ini <= hoy`), sea el que
--   contiene hoy o —entre el día 29 y el día en que DO crea el siguiente— el que
--   se está por cerrar. Si ese periodo ya está PAGADO para su grupo, o no hay
--   ninguno, el bono no se mete en ninguna boleta: la firma vale igual y la
--   constancia queda «pedido», que es exactamente el camino de la 0478 (DO lo
--   transfiere y lo confirma). Nunca se escribe en un periodo cerrado, y nunca
--   se bloquea a la persona por algo que ella no puede arreglar.
--
--   UNA SOLA PREGUNTA PARA «¿YA SE PAGÓ?»: `fn_fecha_en_periodo_pagado`, la que
--   ya usa `fn_agregar_movimiento` (0327). El candado por grupo (planilla, RxH,
--   practicante…) se respeta sin reescribirlo aquí.
--
--   EL PAGO SE CONTESTA UNA VEZ. `fn_mi_bono_cumpleanos()` sigue siendo la
--   única función que dice qué le toca a cada quien; gana un estado, `en_boleta`
--   (firmó, ya está en su boleta, el periodo todavía no se paga) y dos columnas:
--   `via` (boleta / transferencia / papel: por dónde le llegó o le va a llegar) y
--   `periodo_fin` (el cierre del periodo cuya boleta lo lleva). Cambian las
--   columnas de salida, así que la función se BORRA y se vuelve a crear:
--   `create or replace` no puede cambiar lo que devuelve.
--
--   NO SE INVENTA UNA FECHA DE PAGO. Para un bono pagado con la planilla, la
--   pantalla dice «en tu planilla del periodo que cerró el 28/09» y no «pagado
--   el 28/09»: `periodo_fin` es un hecho; el día exacto en que se transfirió
--   la planilla a cada persona no lo guarda nadie por persona.
--
-- QUÉ NO HACE, A PROPÓSITO
--
--   · No toca `fn_planilla_calcular` ni ninguna función de cálculo. Verificado
--     leyendo la vigente (0397): `mov.bonos` entra a tres sitios —el JSON, el
--     `total` a pagar y la base de la retención de 4.ª (que para quien está en
--     planilla vale 0)— y NO entra a la base de AFP/ONP, EsSalud ni a las
--     provisiones. La constancia dice «no constituye remuneración computable»
--     (art. 19 g) del D.S. 001-97-TR) y el cálculo lo respeta.
--   · No cambia la base de gratificación/CTS/vacaciones al cesar. Un bono solo
--     entra ahí si EL MISMO concepto se percibió en 3 o más meses de una
--     ventana (0278); este es de una vez al año, con un nombre fijo. El
--     candado `trg_bono_umbral` (0278) tampoco lo frena, por la misma razón.
--   · No toca a quien ya pidió su bono antes de esta migración: esas
--     constancias quedan `pedido`, sin línea en ninguna boleta, y DO las
--     transfiere como hasta hoy.
--   · No borra ni renombra `entrega_confirmada_*` (0478): son el camino de
--     respaldo, y son la prueba de qué transferencias se confirmaron.
--
-- QUÉ ASUME
--
--   · La 0478 aplicada. `fn_mi_bono_cumpleanos`, `fn_confirmar_mi_bono_
--     cumpleanos`, `fn_bonos_por_transferir` y `fn_confirmar_entrega_bono`
--     son las de ese archivo, sin otra migración encima (comprobado con git en
--     todas las ramas al escribir esto: ninguna otra las toca).
--   · MD5 DE PARTIDA. Se declara y se COMPRUEBA EN EL MOMENTO DE PEGAR: el
--     primer bloque de esta migración mide las cuatro funciones en la base
--     donde corre y, si alguna no es la de la 0478, se detiene sin aplicar nada
--     —el mismo patrón de la 0327—. Comparan contra el cuerpo del archivo 0478
--     sin `\r` (una pegada desde Windows los mete: ver CLAUDE.md, 0401):
--
--       fn_mi_bono_cumpleanos()            efe96a3a26608c6152635da3cb622245   2 373
--       fn_confirmar_mi_bono_cumpleanos()  e5e26a36b17350862b759c96abe5fdf9   2 786
--       fn_bonos_por_transferir()          287fc5dd42a809fe6b5f9696a85bb622     684
--       fn_confirmar_entrega_bono(uuid,date) 31cbae9ee5a96167f0ab370c90b75392 2 424
--
--     Re-pegarla ya aplicada es seguro: cada función lleva el marcador
--     «CAMBIO 0479» y el bloque lo reconoce.
--   · `movimientos_planilla` sin más candado que `trg_bono_umbral`, y
--     `fn_periodo_pagado` (0323) toma `for update` sobre la fila del periodo.
--
-- CONCURRENCIA
--
--   · DO marca el periodo pagado en el mismo segundo en que ella firma:
--     `fn_periodo_pagado` toma `for update` sobre la fila del periodo, y aquí se
--     toma `for share` sobre esa MISMA fila antes de preguntar si está pagado.
--     Una espera a la otra: o ella entra antes del pago (y el pago la cuenta) o
--     después (y ve el periodo pagado y no escribe nada). Nunca una línea que
--     aparece en un periodo ya pagado.
--   · Dos clics de ella: el índice `idx_documentos_bono_uno_por_anio` (0157)
--     deja pasar una sola constancia, y el movimiento se crea en la misma
--     transacción, así que el que pierde deshace también el suyo.
--   · DO confirma «ya lo transferí» sobre un bono que ya va en boleta: la
--     función lo rechaza, y el constraint lo rechazaría de todas formas.
--
-- CAÍDA EXTERNA
--
--   No hay dependencia externa: todo es esta base. La única dependencia que
--   puede faltar es un periodo de planilla, y el diseño dice qué pasa: la firma
--   se guarda igual y el bono queda por transferir, visible para DO.
--
-- LÍMITES CONOCIDOS
--
--   · Si DO quita la línea desde Planilla, el bono vuelve a «pedido» y DO tiene
--     que transferirlo o volver a ponerlo a mano: no hay botón «ponerlo en la
--     boleta» todavía. Es a propósito: nadie quita una línea de un periodo
--     abierto sin razón, y el aviso reaparece.
--   · El periodo se elige por la fecha en que se FIRMA, no por el mes del
--     cumpleaños: quien firma el 30/09 con el periodo ya cerrado por pagar cae
--     en ese; con el siguiente aún sin crear, y pagado el anterior, queda
--     «pedido».
--
-- CÓMO SE REVIERTE
--
--   drop function if exists fn_mi_bono_cumpleanos();
--   -- y volver a pegar las cuatro funciones de la 0478 (fn_mi_bono_cumpleanos,
--   -- fn_confirmar_mi_bono_cumpleanos, fn_bonos_por_transferir,
--   -- fn_confirmar_entrega_bono).
--   -- Las líneas de boleta ya creadas NO se borran solas: se quitan desde
--   -- Planilla, mientras su periodo esté abierto.
--   alter table documentos_firmados
--     drop constraint if exists chk_documento_boleta_solo_bono_pedido,
--     drop constraint if exists chk_documento_boleta_o_transferencia;
--   drop index if exists idx_documentos_movimiento_uno;
--   -- alter table documentos_firmados drop column movimiento_id;  -- solo si no
--   -- hay constancias con línea de boleta: es la prueba de qué se pagó y cómo.
-- ============================================================================


-- ── 0 · Se parte de la versión que dice el repositorio, o no se aplica nada ──
-- Va PRIMERO a propósito: si esto se detiene, no queda a medias ni una columna.
do $$
declare
  r      record;
  v_md5  text;
  v_src  text;
begin
  for r in
    select * from (values
      ('fn_mi_bono_cumpleanos',           0, 'efe96a3a26608c6152635da3cb622245'),
      ('fn_confirmar_mi_bono_cumpleanos', 0, 'e5e26a36b17350862b759c96abe5fdf9'),
      ('fn_bonos_por_transferir',         0, '287fc5dd42a809fe6b5f9696a85bb622'),
      ('fn_confirmar_entrega_bono',       2, '31cbae9ee5a96167f0ab370c90b75392')
    ) as t(nombre, nargs, md5_0478)
  loop
    select md5(replace(p.prosrc, chr(13), '')), p.prosrc into v_md5, v_src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = r.nombre and p.pronargs = r.nargs;

    if v_src is null then
      raise exception '0479 · PARA. %() no existe en esta base: ¿está pegada la 0478? No se aplicó nada.', r.nombre;
    end if;

    -- Ya es la de esta migración (se pegó antes): nada que comprobar.
    if position('CAMBIO 0479' in v_src) > 0 then
      continue;
    end if;

    if v_md5 is distinct from r.md5_0478 then
      raise exception '0479 · PARA. % en esta base es % (% caracteres) y se esperaba la de la 0478, %. No se aplicó nada: construir sobre otra versión revertiría en silencio lo que haya en medio.',
        r.nombre, v_md5, length(v_src), r.md5_0478;
    end if;
  end loop;
end
$$;


-- ── A · El vínculo entre la constancia y su línea de boleta ────────────────
alter table documentos_firmados
  add column if not exists movimiento_id uuid references movimientos_planilla(id) on delete set null;

comment on column documentos_firmados.movimiento_id is
  'La línea «Asignación por cumpleaños» de la boleta que paga este bono (0479). '
  'Solo un bono firmado desde el sistema la tiene, y excluye a entrega_confirmada_*: '
  'o se paga con la planilla o lo transfiere DO, nunca los dos. Si la línea se '
  'borra (o su periodo), el vínculo se suelta y la constancia vuelve a «pedido».';

-- Una línea de boleta no puede pagar dos constancias.
create unique index if not exists idx_documentos_movimiento_uno
  on documentos_firmados (movimiento_id) where movimiento_id is not null;

do $$
begin
  -- Solo un bono que la persona firmó desde el sistema puede estar en una boleta.
  if not exists (select 1 from pg_constraint where conname = 'chk_documento_boleta_solo_bono_pedido') then
    alter table documentos_firmados add constraint chk_documento_boleta_solo_bono_pedido check (
      movimiento_id is null
      or (tipo = 'bono' and firma_persona_confirmada_at is not null)
    );
  end if;
  -- El estado imposible que importa: pagar el mismo bono dos veces. Con la línea
  -- en la boleta no hay nada que DO transfiera aparte.
  if not exists (select 1 from pg_constraint where conname = 'chk_documento_boleta_o_transferencia') then
    alter table documentos_firmados add constraint chk_documento_boleta_o_transferencia check (
      movimiento_id is null or entrega_confirmada_el is null
    );
  end if;
end $$;


-- ── B · Qué le toca a cada quien con su bono ───────────────────────────────
-- Estados, en el orden en que se preguntan (0478, más `en_boleta`):
--   pedido     firmó y NO está en ninguna boleta: DO lo transfiere (respaldo)
--   en_boleta  firmó, está en su boleta y el periodo todavía no se paga
--   no_aplica  no está en planilla, el tablero no la lista, o su cumpleaños de
--              este año cayó antes del bono o de su ingreso
--   sin_fecha  falta su fecha de nacimiento en la ficha
--   proximo    su cumpleaños es más adelante este año
--   este_mes   cumple este mes: puede pedirlo
--   vencido    ya cumplió este año y no lo pidió: todavía puede
--   entregado  ya se pagó este año (planilla pagada, transferencia o papel)
-- `via` dice por dónde: 'boleta' | 'transferencia' | 'papel' (null si no hay
-- constancia todavía). `periodo_fin` solo se llena cuando la vía es la boleta.
drop function if exists fn_mi_bono_cumpleanos();

create function fn_mi_bono_cumpleanos()
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

  if not found
     or not exists (select 1 from personas p where p.id = v_yo and p.en_planilla) then
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


-- ── C · Pedir = firmar, y el bono entra a la boleta ────────────────────────
-- Cuerpo de la 0478 con UN bloque nuevo, marcado CAMBIO 0479: después de
-- validar y antes de guardar la constancia, se busca el periodo y se crea la
-- línea. Todo en la misma transacción: constancia + línea + rastro, o nada.
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
  select pp.id, pp.fecha_ini, pp.fecha_fin into v_periodo, v_periodo_ini, v_periodo_fin
    from periodos_planilla pp
   where pp.fecha_ini <= fn_hoy_lima()
   order by pp.fecha_ini desc
   limit 1
   for share;

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


-- ── D · Lo que DO todavía tiene que transferir ─────────────────────────────
-- Solo los pedidos que NO van en una boleta: esos ya los paga la planilla. Lo
-- que queda aquí es el respaldo (no había periodo abierto al firmar, o alguien
-- quitó la línea de la boleta). Solo DO: es plata del equipo entero.
create or replace function fn_bonos_por_transferir()
returns table (
  documento_id uuid,
  persona_id   uuid,
  persona      text,
  sede         text,
  anio         integer,
  monto        numeric,
  pedido_el    date,
  pedido_at    timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  -- CAMBIO 0479 (marcador): el filtro `movimiento_id is null` de abajo.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional ve los bonos por transferir.';
  end if;

  return query
    select d.id, p.id, p.nombres || ' ' || p.apellidos, coalesce(s.codigo, '?'),
           d.anio, d.monto_declarado, d.fecha_firma, d.firma_persona_confirmada_at
      from documentos_firmados d
      join personas p on p.id = d.persona_id
      left join sedes s on s.id = p.sede_base_id
     where d.tipo = 'bono'
       and d.anulado_at is null and not d.es_negativa
       and d.firma_persona_confirmada_at is not null
       and d.entrega_confirmada_el is null
       and d.movimiento_id is null
     order by d.firma_persona_confirmada_at, d.id;
end;
$$;

grant execute on function fn_bonos_por_transferir() to authenticated;
revoke execute on function fn_bonos_por_transferir() from public, anon;


-- ── E · «Ya se lo transferí» — nunca sobre un bono que ya va en boleta ─────
create or replace function fn_confirmar_entrega_bono(p_documento_id uuid, p_fecha date)
returns date
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo  uuid := fn_persona_actual_id();
  v_doc documentos_firmados%rowtype;
  v_quien text;
begin
  -- CAMBIO 0479 (marcador): el rechazo por `movimiento_id` de abajo.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional confirma una transferencia.';
  end if;

  if p_fecha is null then
    raise exception 'Falta la fecha en que se transfirió.';
  end if;
  if p_fecha > fn_hoy_lima() then
    raise exception 'La fecha de la transferencia no puede ser futura.';
  end if;

  -- `for update`: si otra persona de DO está confirmando la misma, esta espera
  -- y después lee lo que la otra dejó escrito.
  select * into v_doc from documentos_firmados where id = p_documento_id for update;

  if not found or v_doc.tipo <> 'bono' then
    raise exception 'Ese pedido de bono no existe.';
  end if;
  if v_doc.persona_id = v_yo then
    raise exception 'No puedes confirmar la transferencia de tu propio bono: que lo haga otra persona de Desarrollo Organizacional.';
  end if;
  if v_doc.anulado_at is not null then
    raise exception 'Esa constancia fue anulada: ya no hay nada que transferir.';
  end if;
  if v_doc.firma_persona_confirmada_at is null then
    raise exception 'Es un cargo en papel: su fecha de firma ya es la de entrega.';
  end if;
  -- ⇩ CAMBIO 0479 ⇩ Ya va en una boleta: transferirlo aparte lo pagaría dos veces.
  if v_doc.movimiento_id is not null then
    raise exception 'Ese bono ya va en la boleta de la persona y se paga con su planilla: transferirlo aparte lo pagaría dos veces. Si no debe ir en la boleta, quita la línea desde Planilla y vuelve a esta lista.';
  end if;
  if v_doc.entrega_confirmada_el is not null then
    select p.nombres || ' ' || p.apellidos into v_quien from personas p where p.id = v_doc.entrega_confirmada_por;
    raise exception 'Ya estaba confirmada: transferido el %, lo registró %.',
      to_char(v_doc.entrega_confirmada_el, 'DD/MM/YYYY'), coalesce(v_quien, 'otra persona');
  end if;
  -- Un error de tipeo en el año (2016 por 2026) no puede pasar como fecha real.
  if p_fecha < make_date(v_doc.anio, 1, 1) then
    raise exception 'La transferencia no puede ser anterior al año del bono (%).', v_doc.anio;
  end if;

  update documentos_firmados
     set entrega_confirmada_el  = p_fecha,
         entrega_confirmada_por = v_yo,
         entrega_confirmada_at  = now()
   where id = p_documento_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_doc.persona_id, 'bono_entrega_confirmada', null,
     'transferido el ' || p_fecha::text || ' · S/ ' || coalesce(v_doc.monto_declarado::text, '—'),
     v_yo, 'Se confirmó la transferencia del bono de cumpleaños ' || v_doc.anio || ' pedido desde el sistema.');

  return p_fecha;
end;
$$;

grant execute on function fn_confirmar_entrega_bono(uuid, date) to authenticated;
revoke execute on function fn_confirmar_entrega_bono(uuid, date) from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (479, 'el_bono_de_cumpleanos_firmado_entra_a_la_boleta')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.columns
    where table_name = 'documentos_firmados' and column_name = 'movimiento_id') = 1 as tiene_columna,
  (select count(*) from pg_constraint
    where conname in ('chk_documento_boleta_solo_bono_pedido', 'chk_documento_boleta_o_transferencia')) = 2 as tiene_constraints,
  (select count(*) from pg_proc
    where proname in ('fn_mi_bono_cumpleanos', 'fn_confirmar_mi_bono_cumpleanos',
                      'fn_bonos_por_transferir', 'fn_confirmar_entrega_bono')
      and position('CAMBIO 0479' in prosrc) > 0) = 4 as tiene_las_cuatro,
  (select count(*) from pg_proc where proname = 'fn_mi_bono_cumpleanos') = 1 as sin_sobrecarga,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 479) as registro;
