-- ============================================================================
-- 0305 — Un retroactivo dice de qué mes viene
-- ============================================================================
--
-- QUÉ PROMETE
--   Que un bono o descuento que corrige un mes YA PAGADO deje escrito de qué
--   mes viene, y que eso se pueda consultar.
--
-- QUÉ ASUME
--   · Que `fn_agregar_movimiento` es la de la **0181**, confirmada con
--     `./scripts/donde-vive.sh fn_agregar_movimiento`. Su cuerpo se extrajo de
--     la base con `pg_get_functiondef()` y se le agregan un parámetro y dos
--     comprobaciones; el resto no se toca.
--   · Que `fn_calcular_bono_puntualidad` inserta directo en
--     `movimientos_planilla`. Por eso la columna nueva es NULLABLE: si no lo
--     fuera, ese insert dejaría de funcionar.
--
-- ── EL DEFECTO ──────────────────────────────────────────────────────────────
--
-- Cuando algo se corrige después de haber pagado un mes —una marca que llegó
-- tarde, un feriado que faltaba, un descanso médico registrado a destiempo—, el
-- mes cerrado NO se toca: eso es correcto y lo protegen los candados de la
-- 0037. Lo que se hace es pagar la diferencia en el periodo siguiente, como un
-- movimiento.
--
-- Pero `movimientos_planilla` guarda tipo, concepto, monto y poco más. **Nada
-- dice de qué mes viene esa corrección.** El único rastro es lo que alguien
-- haya escrito a mano en el texto del concepto.
--
-- Las consecuencias son tres, y las tres se notan al mes siguiente:
--
--   · No se puede responder «¿qué retroactivos pagamos este mes y de dónde
--     salieron?». Hay que leer conceptos escritos a mano, uno por uno.
--   · No se puede comprobar que se pagaron TODOS los que se debían. La deuda
--     solo existe mientras alguien la recuerde.
--   · Cuando el contador pregunta por qué el neto de una persona subió S/100 en
--     un mes, la respuesta está en la memoria de quien lo registró.
--
-- Casos ya ocurridos y anotados en `docs/estado.md`: S/11.55 de la 0269, y
-- S/100.03 repartidos en ocho personas.
--
-- ── QUÉ CAMBIA ──────────────────────────────────────────────────────────────
--
-- 1 · `movimientos_planilla` gana `periodo_origen_id`. NULL —que es lo normal—
--     significa «esto no corrige nada, es de este mes».
--
-- 2 · `fn_agregar_movimiento` lo acepta, y comprueba tres cosas antes de
--     aceptarlo, porque un origen mal puesto es peor que ninguno:
--       · que el periodo de origen exista;
--       · que NO sea el mismo que se está pagando —eso no es un retroactivo,
--         es un movimiento normal, y decir lo contrario ensucia el registro;
--       · que sea ANTERIOR y esté PAGADO. Un retroactivo viene de un mes que ya
--         se cerró; si el mes de origen sigue abierto, lo que corresponde es
--         arreglarlo ahí, no arrastrarlo.
--
-- ── POR QUÉ SE BORRAN LAS DOS FIRMAS Y SE DEJA UNA ──────────────────────────
--
-- Hoy hay DOS `fn_agregar_movimiento`: la de cinco argumentos (0025) y la de
-- seis con `p_categoria` (0044/0049). La de cinco no la llama nadie —medido
-- sobre `apps/`, `packages/` y el `prosrc` de todas las funciones de la base;
-- la única mención en SQL está dentro de un comentario de
-- `fn_planilla_congelar`— pero sigue con su permiso vivo.
--
-- Agregar el parámetro nuevo con un `default` sobre la de seis crearía una
-- TERCERA firma, y entonces una llamada de seis argumentos encajaría en dos a
-- la vez: **«function … is not unique»**. Es exactamente el fallo que tuvo el
-- CI en rojo con `fn_vacaciones_por_vencer` y que arregló la 0301.
--
-- Así que se borran las dos y queda una sola, con los dos últimos parámetros
-- por defecto. La pantalla sigue llamándola con seis argumentos con nombre y no
-- hay que tocarla para que siga funcionando.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ───────────────────────────────────────────
--
-- No detecta retroactivos que se DEBAN y no se hayan pagado. Eso es otra cosa y
-- más grande: exige comparar la foto congelada de un mes contra lo que ese mes
-- daría hoy, y `fn_planilla_foto_diferencias` hoy es ciega a la marca que llega
-- tarde a un periodo pagado, porque los dos lados leen la misma jornada
-- congelada. Esto hace trazable lo que SÍ se pagó, que es la mitad que hoy no
-- se puede responder de ninguna forma.
--
-- Tampoco rellena hacia atrás: los movimientos ya registrados se quedan con su
-- origen en NULL. Inventar de qué mes venían leyendo su texto sería adivinar.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   `drop function fn_agregar_movimiento(uuid,uuid,text,text,numeric,text,uuid);`
--   y pegar de nuevo los cuerpos de la 0025 y la 0181. La columna puede
--   quedarse: es nullable y nadie la exige.
--
-- ============================================================================


-- ── 1 · La columna, y el índice para poder preguntarle ──────────────────────

alter table movimientos_planilla
  add column if not exists periodo_origen_id uuid references periodos_planilla(id);

comment on column movimientos_planilla.periodo_origen_id is
  'De qué periodo YA PAGADO viene esta corrección. NULL —lo normal— significa '
  'que el movimiento es de este mes y no corrige nada (0305).';

-- Solo las filas que son retroactivas: el índice parcial no paga por el 95 % de
-- movimientos que no lo son.
create index if not exists idx_movimientos_origen
  on movimientos_planilla (periodo_origen_id)
  where periodo_origen_id is not null;


-- ── 2 · Una sola función, sin sobrecargas ───────────────────────────────────

drop function if exists fn_agregar_movimiento(uuid, uuid, text, text, numeric);
drop function if exists fn_agregar_movimiento(uuid, uuid, text, text, numeric, text);

create or replace function fn_agregar_movimiento(
  p_periodo_id        uuid,
  p_persona_id        uuid,
  p_tipo              text,
  p_concepto          text,
  p_monto             numeric,
  p_categoria         text default null,
  p_periodo_origen_id uuid default null
) returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_estado text;
  v_ini    date;
  v_org    record;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar movimientos.';
  end if;
  select estado, fecha_ini into v_estado, v_ini from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
  if v_estado = 'pagado' then
    raise exception 'Este periodo ya está PAGADO: reábrelo para modificarlo.';
  end if;
  if p_tipo is null or p_tipo not in ('bono', 'descuento') then
    raise exception 'Tipo inválido (bono o descuento).';
  end if;
  if p_categoria is not null and p_categoria not in ('vacaciones','otros','gratificacion','cts') then
    raise exception 'Categoría inválida.';
  end if;
  if p_concepto is null or length(trim(p_concepto)) < 2 then
    raise exception 'El concepto es obligatorio.';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'El monto debe ser mayor a 0.';
  end if;
  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'Persona inválida.';
  end if;
  if p_categoria in ('gratificacion','cts') and exists (
    select 1 from movimientos_planilla
    where periodo_id = p_periodo_id and persona_id = p_persona_id and categoria = p_categoria
  ) then
    raise exception 'Esta persona ya tiene % en este periodo. Quítalo antes de volver a agregarlo.', p_categoria;
  end if;

  -- ── CAMBIO 0305 · el origen, si lo hay ────────────────────────────────────
  -- Un origen mal puesto es peor que ninguno: haría creer que una diferencia
  -- quedó saldada cuando vino de otro sitio. Por eso las tres comprobaciones.
  if p_periodo_origen_id is not null then
    if p_periodo_origen_id = p_periodo_id then
      raise exception 'El periodo de origen no puede ser este mismo: eso no es un retroactivo, es un movimiento normal de este periodo. Déjalo en blanco.';
    end if;
    select estado, fecha_fin into v_org
      from periodos_planilla where id = p_periodo_origen_id;
    if not found then
      raise exception 'El periodo de origen no existe.';
    end if;
    if v_org.estado <> 'pagado' then
      raise exception 'El periodo del que dices que viene todavía no está PAGADO. Si sigue abierto, la corrección va ahí y no acá: se arregla en su mes, no se arrastra a este.';
    end if;
    if v_org.fecha_fin >= v_ini then
      raise exception 'El periodo de origen tiene que ser ANTERIOR a este. Un retroactivo corrige un mes que ya se cerró.';
    end if;
  end if;

  insert into movimientos_planilla
    (periodo_id, persona_id, tipo, concepto, monto, categoria, creado_por, periodo_origen_id)
  values (p_periodo_id, p_persona_id, p_tipo, trim(p_concepto), round(p_monto, 2),
          nullif(trim(coalesce(p_categoria, '')), ''), fn_persona_actual_id(),
          p_periodo_origen_id);
end;
$function$;

comment on function fn_agregar_movimiento(uuid, uuid, text, text, numeric, text, uuid) is
  'Única puerta para agregar un bono o descuento a un periodo. Desde la 0305 '
  'acepta `p_periodo_origen_id`: de qué mes ya pagado viene la corrección. Antes '
  'había DOS firmas —la de la 0025 sin categoría y la de la 0181 con ella— y '
  'agregar un parámetro con default sobre la segunda habría hecho ambigua la '
  'llamada de seis argumentos, que es el fallo que la 0301 tuvo que arreglar en '
  'fn_vacaciones_por_vencer.';

revoke all on function fn_agregar_movimiento(uuid, uuid, text, text, numeric, text, uuid) from public, anon;
grant execute on function fn_agregar_movimiento(uuid, uuid, text, text, numeric, text, uuid) to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (305, 'un_retroactivo_dice_de_que_mes_viene')
on conflict (numero) do nothing;
