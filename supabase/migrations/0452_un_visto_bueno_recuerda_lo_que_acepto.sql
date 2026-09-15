-- ============================================================================
-- 0452_un_visto_bueno_recuerda_lo_que_acepto.sql
-- ============================================================================
-- QUÉ PROMETE
--
--   1. Un visto bueno de Incidencias («Dar por válida», «Trabajó de corrido»,
--      «Marcar revisada») guarda el NÚMERO que se dio por bueno: los minutos
--      de una salida anticipada, las horas de un exceso, los días de una
--      racha. Si después una corrección cambia ese número, el aviso vuelve a
--      salir: el visto bueno era sobre otro hecho.
--   2. Deshacer un visto bueno ya no BORRA la fila: la anula con motivo
--      obligatorio, quién y cuándo. Igual que un marcaje (0081) y una
--      ausencia (0101).
--   3. Volver a aceptar lo mismo no pisa al anterior: lo anula como
--      «reemplazado» y crea uno nuevo. El historial conserva a los dos.
--
-- EL DEFECTO, MEDIDO EN LA AUDITORÍA DE INCIDENCIAS (2026-09-15)
--
--   La clave de `incidencias_aceptadas` era (persona, fecha, tipo), sin el
--   valor. Una «Salida anticipada (20 min)» aceptada seguía oculta después de
--   que una corrección la llevara a 142 min: nadie había visto esos 142.
--   Además, `fn_quitar_aceptacion` hacía `delete` —el rastro de quién la
--   aceptó desaparecía con el clic de «Deshacer»— y `fn_aceptar_incidencia`
--   hacía `on conflict do update`, así que un segundo visto bueno
--   sobrescribía el autor y la nota del primero.
--
-- QUÉ ASUME
--
--   · Que las filas que ya existen (valor null) siguen valiendo para cualquier
--     número. No hay forma de saber qué minutos se aceptaron entonces, y
--     reabrirlas todas sería volver a pedir revisión de lo que alguien ya
--     miró. Solo las nuevas se comparan.
--   · Que la pantalla manda el valor tal como lo muestra (minutos enteros,
--     horas con un decimal, días enteros) y que la comparación la hace
--     `apps/web/lib/admin/incidencias.ts`, donde vive la detección. La base
--     guarda el hecho; no recalcula la incidencia.
--   · Que nadie escribe esta tabla por fuera de estas dos funciones: desde la
--     0052 no tiene políticas de insert, update ni delete para `authenticated`.
--
-- POR QUÉ ASÍ
--
--   · Índice único PARCIAL (solo vigentes) en vez del unique de siempre. Con
--     anulación, la misma incidencia puede tener varias filas en su historia y
--     una sola vigente. Si dos personas aceptan en el mismo segundo, una gana
--     y la otra recibe un mensaje: lo impide el índice, no un `if`.
--   · Un check exige anulada_at, anulada_por y anulada_motivo juntos:
--     «anulada sin motivo» o «anulada sin autor» no pueden existir.
--   · `drop` + `create` de las dos funciones y no `create or replace`: cambian
--     de firma (p_valor, p_motivo), y dejar la vieja al lado sería una
--     sobrecarga — el accidente de la 0297/0299, que falló al abrir la
--     pantalla y no al pegar.
--   · `fn_aceptar_incidencia` acepta solo los cuatro tipos que la pantalla
--     ofrece. Antes aceptaba cualquier texto.
--
-- MD5 DE PARTIDA (cuerpo vigente de ambas: 0052)
--
--   fn_aceptar_incidencia   local 555ebacee3040e94f6a139e648919824
--   fn_quitar_aceptacion    local 44da7f2c66b272d34aa79553f981026f
--
--   ⚠ Confirmar contra PRODUCCIÓN antes de pegar. Las dos se reemplazan
--   enteras, así que si producción tiene otra versión no se pierde un
--   arreglo en silencio — pero hay que saber cuál era, y decirlo acá.
--
-- CÓMO SE REVIERTE
--
--   No es un solo paso, porque el unique viejo no admite la historia que esta
--   migración empieza a guardar. En orden:
--     1. decidir qué hacer con las filas anuladas (son rastro: no borrarlas
--        sin copiarlas antes);
--     2. drop function fn_aceptar_incidencia(uuid, date, text, text, numeric);
--        drop function fn_quitar_aceptacion(uuid, date, text, text);
--     3. drop index uq_incidencia_aceptada_vigente;
--        alter table incidencias_aceptadas drop constraint chk_inc_acept_anulacion_completa;
--        alter table incidencias_aceptadas add constraint
--          incidencias_aceptadas_persona_id_fecha_tipo_key unique (persona_id, fecha, tipo);
--     4. volver a pegar las dos funciones tal como están en la 0052.
--   Las columnas nuevas pueden quedarse: nada las lee si la pantalla vuelve atrás.
-- ============================================================================

alter table incidencias_aceptadas
  add column if not exists valor          numeric,
  add column if not exists anulada_at     timestamptz,
  add column if not exists anulada_por    uuid references personas(id),
  add column if not exists anulada_motivo text;

comment on column incidencias_aceptadas.valor is
  'El número que se dio por bueno (minutos, horas o días). null en las filas anteriores a la 0452: valen para cualquier valor.';

alter table incidencias_aceptadas drop constraint if exists chk_inc_acept_anulacion_completa;
-- `anulada_motivo is not null` va escrito aunque parezca redundante con el
-- length: con motivo null, `length(trim(null)) >= 4` da NULL, y un CHECK que da
-- NULL PASA. Sin esa línea, «anulada sin motivo» era posible — lo cazó la
-- prueba 357 al escribir la tabla a mano.
alter table incidencias_aceptadas add constraint chk_inc_acept_anulacion_completa check (
  (anulada_at is null and anulada_por is null and anulada_motivo is null)
  or (anulada_at is not null and anulada_por is not null
      and anulada_motivo is not null and length(trim(anulada_motivo)) >= 4)
);

-- Una sola vigente por incidencia; las anuladas son su historia.
alter table incidencias_aceptadas drop constraint if exists incidencias_aceptadas_persona_id_fecha_tipo_key;
create unique index if not exists uq_incidencia_aceptada_vigente
  on incidencias_aceptadas (persona_id, fecha, tipo)
  where anulada_at is null;

-- ── Dar el visto bueno ──────────────────────────────────────────────────────
drop function if exists fn_aceptar_incidencia(uuid, date, text, text);
drop function if exists fn_aceptar_incidencia(uuid, date, text, text, numeric);
create function fn_aceptar_incidencia(
  p_persona_id uuid, p_fecha date, p_tipo text, p_nota text default null, p_valor numeric default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_editor uuid;
  v_tipo text := trim(coalesce(p_tipo, ''));
begin
  -- Permiso: admin/líder a cualquiera; encargada solo su sede, ni a sí misma.
  v_editor := fn_verificar_corrector(p_persona_id);

  if v_tipo not in ('salida_anticipada', 'sin_retorno_almuerzo', 'racha_sin_descanso', 'jornada_excedida') then
    raise exception 'Tipo de incidencia inválido: «%».', v_tipo;
  end if;

  -- El visto bueno anterior no se pisa: queda en la historia como reemplazado.
  update incidencias_aceptadas
     set anulada_at = now(), anulada_por = v_editor,
         anulada_motivo = 'Reemplazado por un nuevo visto bueno'
   where persona_id = p_persona_id and fecha = p_fecha and tipo = v_tipo
     and anulada_at is null;

  insert into incidencias_aceptadas (persona_id, fecha, tipo, nota, aceptado_por, valor)
  values (p_persona_id, p_fecha, v_tipo, nullif(trim(coalesce(p_nota, '')), ''), v_editor, p_valor);
exception
  -- Dos vistos buenos en el mismo instante: el índice parcial deja pasar uno.
  when unique_violation then
    raise exception 'Otra persona acaba de dar este visto bueno. Recarga la pantalla para ver el suyo.';
end;
$$;

comment on function fn_aceptar_incidencia(uuid, date, text, text, numeric) is
  'Visto bueno de una incidencia, con el valor que se dio por bueno. Reemplaza al vigente anulándolo, nunca lo pisa. Desde la 0452.';

-- ── Deshacer el visto bueno ─────────────────────────────────────────────────
drop function if exists fn_quitar_aceptacion(uuid, date, text);
drop function if exists fn_quitar_aceptacion(uuid, date, text, text);
create function fn_quitar_aceptacion(p_persona_id uuid, p_fecha date, p_tipo text, p_motivo text)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_editor uuid;
begin
  v_editor := fn_verificar_corrector(p_persona_id);

  if p_motivo is null or length(trim(p_motivo)) < 4 then
    raise exception 'Escribe por qué deshaces este visto bueno (mínimo 4 caracteres): queda en el historial.';
  end if;

  update incidencias_aceptadas
     set anulada_at = now(), anulada_por = v_editor, anulada_motivo = trim(p_motivo)
   where persona_id = p_persona_id and fecha = p_fecha and tipo = trim(p_tipo)
     and anulada_at is null;

  if not found then
    raise exception 'Ese visto bueno ya no está vigente: alguien lo deshizo o lo reemplazó. Recarga la pantalla.';
  end if;
end;
$$;

comment on function fn_quitar_aceptacion(uuid, date, text, text) is
  'Anula (no borra) el visto bueno vigente de una incidencia, con motivo obligatorio. Desde la 0452.';

grant execute on function fn_aceptar_incidencia(uuid, date, text, text, numeric) to authenticated;
revoke execute on function fn_aceptar_incidencia(uuid, date, text, text, numeric) from public, anon;
grant execute on function fn_quitar_aceptacion(uuid, date, text, text) to authenticated;
revoke execute on function fn_quitar_aceptacion(uuid, date, text, text) from public, anon;

insert into migraciones_aplicadas (numero, nombre) values (452, 'un_visto_bueno_recuerda_lo_que_acepto')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';
