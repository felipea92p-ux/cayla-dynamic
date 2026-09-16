-- ============================================================================
-- 0478 — El bono de cumpleaños se pide, y DO confirma la transferencia
-- ============================================================================
--
-- QUÉ PROMETE
--
--   1. Que cada persona pueda PEDIR su bono de cumpleaños desde su Info
--      (/mio), en el mes de su onomástico o después si se le pasó. Pedirlo es
--      firmar su constancia —la puerta de la 0477, sin cambios de forma—; lo
--      que cambia es CUÁNDO se puede: solo cuando de verdad le toca.
--
--   2. Que ese pedido LLEGUE a Desarrollo Organizacional y no se apague hasta
--      que alguien confirme que transfirió. Esta es la razón de ser de esta
--      migración, y conviene contarla con el caso concreto:
--
--        Con la 0477 sola, Melany firma el 16 de setiembre a las 10:00. A las
--        10:00 desaparece de la Bandeja de DO la única fila que recordaba su
--        bono («Bono de cumpleaños sin constancia firmada»): el tablero ya ve
--        una constancia vigente y dice `ok`. Nadie transfiere. El 30 de
--        setiembre el sistema dice «al día», y Melany tiene firmado «Recibí
--        conforme» por S/ 180 que no cobró.
--
--      Antes de la 0477 ese hueco no existía porque el papel lo subía DO: la
--      misma persona que entregaba el dinero era la que cerraba el aviso. Al
--      pasar la firma a la colaboradora, cerrar el aviso y pagar dejaron de
--      ser el mismo acto — y hace falta un segundo acto que lo diga. Ninguna
--      otra pantalla lleva la cuenta de este pago: no pasa por planilla (0165)
--      ni por el libro de desembolsos (0155/0273, que es de grati/CTS/vacaciones).
--
--   3. Que DO lo cierre con un clic, «Ya se lo transferí», con la fecha real.
--
--   Decidido con Felipe el 2026-09-16, entre tres opciones: (a) esta; (b) solo
--   poner el botón en Info sin aviso para DO —descartada: deja el hueco de
--   arriba abierto—; (c) pedir sin firmar y firmar recién después de cobrar
--   —descartada: vuelve el candado de secuencia que la 0477 retiró, y obliga a
--   la persona a entrar dos veces—.
--
-- CÓMO ESTÁ HECHO, Y POR QUÉ ASÍ
--
--   LA ENTREGA ES UN ATRIBUTO DE LA CONSTANCIA, NO UNA TABLA APARTE.
--   Tres columnas en `documentos_firmados` (`entrega_confirmada_el/_por/_at`),
--   con el mismo molde que `firma_persona_confirmada_at` (0423). Así el estado
--   imposible —«se confirmó una transferencia de un bono que nadie pidió»— no
--   se evita con un `if`: no hay dónde escribirlo. Una tabla aparte habría
--   permitido una fila de entrega sin constancia, y habría que haberla
--   prohibido a mano.
--
--   SOLO LA CONSTANCIA FIRMADA DESDE EL SISTEMA PIDE CONFIRMACIÓN.
--   El cargo en papel (`fn_documento_registrar`) no la necesita ni la admite:
--   lo sube DO después de entregar, y su `fecha_firma` ES la fecha de entrega
--   —la escribe quien recibe, el día que recibe (ver admin/documentacion,
--   «Entregada y recibida el ___»)—. Un constraint lo hace imposible, y por
--   eso `fn_mi_bono_cumpleanos` puede decir «entregado el X» de los dos
--   caminos sin tener dos reglas.
--
--   «¿QUÉ LE TOCA A ESTA PERSONA CON SU BONO?» SE RESPONDE UNA SOLA VEZ.
--   `fn_mi_bono_cumpleanos()` compone `fn_documentos_tablero(true)` —no copia
--   su lógica de fecha de arranque, ingreso y mes— y le agrega lo que el
--   tablero no sabe: `en_planilla` y si el pedido ya se transfirió. La leen
--   Info, la Bandeja mía y /mio/cumpleanos, y la usa el propio pedido como
--   puerta. Pantalla y servidor no pueden contestar distinto porque es la
--   misma función.
--
--   `en_planilla` VA ACÁ Y NO EN EL TABLERO, Y NO ES UN DESCUIDO.
--   Desde la 0424 el tablero también lista a quien es practicante (por la
--   ruta), y calcula `bono_estado` para ella aunque `fn_documento_registrar`
--   le niega el bono. Arreglarlo en el tablero es lo correcto, pero reescribe
--   una función vigente en producción, y eso exige su md5 de PRODUCCIÓN antes
--   de escribir (CLAUDE.md). Queda anotado en `docs/estado.md` como pendiente
--   aparte; esta función ya no se equivoca con ella.
--
--   EL PEDIDO SOLO EN SU MES O DESPUÉS (CAMBIO sobre la 0477).
--   La 0477 dejaba firmar en cualquier mes —«el escaneo tampoco lo exige»—.
--   Eso era inofensivo mientras firmar solo archivaba un papel. Desde esta
--   migración firmar es PEDIR PLATA, y un pedido en abril por un cumpleaños de
--   diciembre, o de quien cumplió antes de que existiera el bono (0165), le
--   llegaría a DO como una transferencia que no corresponde. La política y el
--   contrato dicen lo mismo: «en el mes de tu cumpleaños».
--
-- QUÉ ASUME
--
--   · La 0477 aplicada: `fn_confirmar_mi_bono_cumpleanos` y
--     `fn_bono_monto_vigente`. Al escribir esto la 0477 NO está en producción
--     (PR #422 sin fusionar), así que no hay md5 de producción que pedir para
--     `fn_confirmar_mi_bono_cumpleanos`: se parte del cuerpo del archivo 0477.
--     Pegar SIEMPRE la 0477 antes que esta.
--   · `fn_documentos_tablero(boolean)` de la 0424, sin cambios — solo se llama.
--   · `documentos_firmados` sin policy de UPDATE (0157): ningún cliente puede
--     escribir estas columnas directo. La única puerta es
--     `fn_confirmar_entrega_bono`, así que no hace falta el trigger guardián
--     de la 0295/0342 — la RLS ya cierra lo que ese trigger cerraría.
--
-- CONCURRENCIA
--
--   · Dos personas de DO confirman la misma transferencia en el mismo
--     segundo: `select … for update` las pone en fila; la segunda lee la
--     entrega ya confirmada y recibe «Ya estaba confirmada el X por Y».
--   · Dos clics de la colaboradora en «Pedir mi bono»: el índice único
--     `idx_documentos_bono_uno_por_anio` (0157) deja pasar uno solo.
--
-- LÍMITES CONOCIDOS
--
--   · Si un pedido de un año queda sin confirmar, bloquea el pedido del año
--     siguiente hasta que DO lo cierre. Se prefiere así: el pendiente viejo es
--     plata que se debe, y no puede quedar tapado por uno nuevo.
--   · El tablero no lista a quien termina contrato este mes (0161), así que
--     esa persona no puede pedirlo desde Info: lo registra DO en papel, como
--     hasta hoy.
--
-- CÓMO SE REVIERTE
--
--   drop function if exists fn_confirmar_entrega_bono(uuid, date);
--   drop function if exists fn_bonos_por_transferir();
--   drop function if exists fn_mi_bono_cumpleanos();
--   -- y volver a pegar `fn_confirmar_mi_bono_cumpleanos` de la 0477.
--   -- Las columnas NO se borran si ya tienen datos: son la prueba de qué
--   -- transferencias se confirmaron.
--   alter table documentos_firmados
--     drop constraint if exists chk_documento_entrega_coherente,
--     drop constraint if exists chk_documento_entrega_solo_bono_pedido;
-- ============================================================================


-- ── A · La entrega, como parte de la constancia ────────────────────────────
alter table documentos_firmados add column if not exists entrega_confirmada_el  date;
alter table documentos_firmados add column if not exists entrega_confirmada_por uuid references personas(id);
alter table documentos_firmados add column if not exists entrega_confirmada_at  timestamptz;

comment on column documentos_firmados.entrega_confirmada_el is
  'Fecha en que DO transfirió el bono de una constancia firmada desde el sistema (0478). '
  'Null en el cargo en papel: ahí fecha_firma ya es la fecha de entrega.';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'chk_documento_entrega_coherente') then
    alter table documentos_firmados add constraint chk_documento_entrega_coherente check (
      (entrega_confirmada_el is null) = (entrega_confirmada_por is null)
      and (entrega_confirmada_el is null) = (entrega_confirmada_at is null)
    );
  end if;
  -- Solo un bono que la persona firmó desde el sistema espera confirmación.
  -- Ni una ruta, ni una política, ni un cargo en papel pueden tenerla.
  if not exists (select 1 from pg_constraint where conname = 'chk_documento_entrega_solo_bono_pedido') then
    alter table documentos_firmados add constraint chk_documento_entrega_solo_bono_pedido check (
      entrega_confirmada_el is null
      or (tipo = 'bono' and firma_persona_confirmada_at is not null)
    );
  end if;
end $$;


-- ── B · Qué le toca a cada quien con su bono ───────────────────────────────
-- Estados, en el orden en que se preguntan:
--   pedido     firmó desde el sistema y DO todavía no confirma la transferencia
--              (de cualquier año: una deuda vieja no se tapa con una nueva)
--   no_aplica  no está en planilla, el tablero no la lista, o su cumpleaños de
--              este año cayó antes del bono o de su ingreso
--   sin_fecha  falta su fecha de nacimiento en la ficha
--   proximo    su cumpleaños es más adelante este año
--   este_mes   cumple este mes: puede pedirlo
--   vencido    ya cumplió este año y no lo pidió: todavía puede
--   entregado  ya se entregó este año (transferencia confirmada, o cargo en papel)
create or replace function fn_mi_bono_cumpleanos()
returns table (
  estado         text,
  mes_cumpleanos integer,
  anio           integer,
  monto          numeric,
  documento_id   uuid,
  pedido_el      date,
  entregado_el   date
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_yo   uuid := fn_persona_actual_id();
  v_mes  integer;
  v_doc  documentos_firmados%rowtype;
  v_tab  record;
begin
  if v_yo is null then
    return;
  end if;

  select extract(month from d.fecha_nacimiento)::int into v_mes
    from datos_personales d
   where d.persona_id = v_yo and d.fecha_nacimiento is not null;

  -- 1 · Un pedido sin transferir manda sobre todo lo demás.
  select d.* into v_doc
    from documentos_firmados d
   where d.persona_id = v_yo and d.tipo = 'bono'
     and d.anulado_at is null and not d.es_negativa
     and d.firma_persona_confirmada_at is not null
     and d.entrega_confirmada_el is null
   order by d.anio desc, d.fecha_firma desc, d.created_at desc, d.id desc
   limit 1;
  if found then
    return query select 'pedido'::text, v_mes, v_doc.anio, v_doc.monto_declarado,
                        v_doc.id, v_doc.fecha_firma, null::date;
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
                        null::numeric, null::uuid, null::date, null::date;
    return;
  end if;

  -- 3 · Ya se entregó este año. Si la firmó ella, la fecha es la que confirmó
  --     DO; si es papel, su fecha_firma ya es la de entrega (ver encabezado).
  if v_tab.bono_estado = 'ok' then
    select d.* into v_doc from documentos_firmados d where d.id = v_tab.bono_id;
    return query select 'entregado'::text, v_mes, v_doc.anio, v_doc.monto_declarado, v_doc.id,
                        case when v_doc.firma_persona_confirmada_at is not null then v_doc.fecha_firma end,
                        coalesce(v_doc.entrega_confirmada_el, v_doc.fecha_firma);
    return;
  end if;

  -- 4 · Todavía no hay constancia: el estado del tablero, con el monto que
  --     rige hoy — se muestra ANTES de pedir, nunca se firma a ciegas (0477).
  return query select v_tab.bono_estado::text, v_mes, extract(year from fn_hoy_lima())::int,
                      fn_bono_monto_vigente(), null::uuid, null::date, null::date;
end;
$$;

grant execute on function fn_mi_bono_cumpleanos() to authenticated;
revoke execute on function fn_mi_bono_cumpleanos() from public, anon;


-- ── C · Pedir = firmar, pero solo cuando le toca ───────────────────────────
-- Cuerpo de la 0477 (no pegada en producción al escribir esto). Un cambio,
-- marcado CAMBIO 0478: la puerta pasa a ser `fn_mi_bono_cumpleanos`, que ya
-- incluye `en_planilla` y «ya tiene su constancia este año».
create or replace function fn_confirmar_mi_bono_cumpleanos()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo     uuid := fn_persona_actual_id();
  v_imagen text;
  v_monto  numeric;
  v_anio   integer := extract(year from fn_hoy_lima())::int;
  v_id     uuid;
  v_ip     text;
  v_ua     text;
  v_estado text;
begin
  if v_yo is null then
    raise exception 'No se encontró tu persona.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0478 ⇩⇩⇩ Antes: `en_planilla` y «ya tiene constancia este
  -- año», y ninguna condición de mes. Ahora firmar es pedir plata: solo en el
  -- mes de su cumpleaños, o después si se le pasó.
  select b.estado into v_estado from fn_mi_bono_cumpleanos() b;

  if v_estado = 'pedido' then
    raise exception 'Ya pediste tu bono. Desarrollo Organizacional te avisa por aquí cuando lo transfiera.';
  elsif v_estado = 'entregado' then
    raise exception 'Tu bono de cumpleaños de este año ya se entregó.';
  elsif v_estado = 'proximo' then
    raise exception 'Tu bono se pide en el mes de tu cumpleaños.';
  elsif v_estado = 'sin_fecha' then
    raise exception 'Falta tu fecha de nacimiento en tu ficha. Avisa a Desarrollo Organizacional.';
  elsif v_estado is distinct from 'este_mes' and v_estado is distinct from 'vencido' then
    raise exception 'Este año no te corresponde el bono de cumpleaños. Si crees que es un error, avisa a Desarrollo Organizacional.';
  end if;
  -- ⇧⇧⇧ CAMBIO 0478 ⇧⇧⇧

  select imagen into v_imagen from firmas_escaneadas where persona_id = v_yo;
  if v_imagen is null then
    raise exception 'Todavía no configuraste tu firma. Ve a la pestaña «Firma» antes de confirmar.';
  end if;

  v_monto := fn_bono_monto_vigente();

  if v_monto is null then
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

  insert into documentos_firmados (
    alcance, persona_id, tipo, fecha_firma, monto_declarado, anio,
    registrado_por, firma_persona, firma_persona_confirmada_at,
    firma_persona_ip, firma_persona_user_agent
  ) values (
    'individual', v_yo, 'bono', fn_hoy_lima(), v_monto, v_anio,
    v_yo, v_imagen, now(), v_ip, v_ua
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_yo, 'documento_firmado', null, 'bono · firmado digitalmente el ' || fn_hoy_lima()::text, v_yo,
     'Firma digital de la constancia del bono de cumpleaños, reemplaza el escaneo físico.');

  return v_id;
end;
$$;

grant execute on function fn_confirmar_mi_bono_cumpleanos() to authenticated;
revoke execute on function fn_confirmar_mi_bono_cumpleanos() from public, anon;


-- ── D · Lo que DO tiene que transferir ─────────────────────────────────────
-- Todos los pedidos sin confirmar, de cualquier año. Solo DO: es plata del
-- equipo entero.
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
     order by d.firma_persona_confirmada_at, d.id;
end;
$$;

grant execute on function fn_bonos_por_transferir() to authenticated;
revoke execute on function fn_bonos_por_transferir() from public, anon;


-- ── E · «Ya se lo transferí» ───────────────────────────────────────────────
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
values (478, 'el_bono_de_cumpleanos_se_pide_y_do_confirma_la_transferencia')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.columns
    where table_name = 'documentos_firmados' and column_name like 'entrega_confirmada_%') = 3 as tiene_columnas,
  (select count(*) from pg_constraint
    where conname in ('chk_documento_entrega_coherente', 'chk_documento_entrega_solo_bono_pedido')) = 2 as tiene_constraints,
  (select count(*) from pg_proc
    where proname in ('fn_mi_bono_cumpleanos', 'fn_bonos_por_transferir', 'fn_confirmar_entrega_bono')) = 3 as tiene_funciones,
  (select count(*) from pg_proc where proname = 'fn_confirmar_mi_bono_cumpleanos') = 1 as sin_sobrecarga,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 478) as registro;
