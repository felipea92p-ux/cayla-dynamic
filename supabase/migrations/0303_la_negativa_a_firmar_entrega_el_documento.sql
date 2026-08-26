-- ============================================================================
-- 0303 — La negativa a firmar entrega el documento
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que un documento disciplinario que la colaboradora se negó a firmar quede
-- ENTREGADO, con su acta y su testigo, y agrave como cualquier otro.
--
-- El numeral 55.4 del Reglamento no deja margen:
--
--   «Si la colaboradora se niega a firmar, se levanta acta de negativa suscrita
--    por quien entrega y por un testigo. El acta produce los mismos efectos que
--    el cargo firmado y se archiva en el legajo.»
--
-- Y el 56.1 lo repite para el antecedente: agrava desde que se entregó «con
-- cargo de recepción firmado O CON ACTA DE NEGATIVA A FIRMAR».
--
-- ── QUÉ ESTABA MAL, Y POR QUÉ EMPEORÓ ESTE MES ─────────────────────────────
--
-- `medio_entrega` admitía tres valores desde la 0056 —fisico, correo,
-- notarial— y ninguno era la negativa. El acta se subía como un adjunto de tipo
-- `acta_negativa` (0074) y el documento se quedaba en estado `firmado`. La
-- propia pantalla lo dice: «Queda constancia de que se ofreció entregar; el
-- documento NO se marca entregado».
--
-- Mientras la escalera se medía por `firmado_at`, eso colaba por accidente. La
-- 0213 y la 0246 la pasaron a `estado = 'entregado'` y `entregado_at` —que es
-- lo correcto, el artículo 56 lo manda— y con ello este caso dejó de existir
-- para el sistema: un memo con acta de negativa no agrava, no cuenta como
-- peldaño y no aparece en el corte del non bis in idem. La siguiente sanción de
-- esa persona vuelve a salir desde abajo.
--
-- O sea: al arreglar una cosa se rompió esta. Se dice porque conviene saberlo.
--
-- ── UN TESTIGO, NO DOS ─────────────────────────────────────────────────────
--
-- El Reglamento dice las dos cosas, en sitios distintos, y hay que elegir bien:
--
--   art. 38 l)   dos testigos — es el DEBER GENÉRICO de la colaboradora de
--                suscribir cargos, para cualquier documento que reciba.
--   num. 60.x    dos testigos — es para la entrega del REGLAMENTO mismo.
--   num. 55.4    UN testigo   — es la NOTIFICACIÓN DE LA SANCIÓN, que es esto.
--
-- Manda el 55.4 por específico. Exigir dos habría frenado entregas que el
-- Reglamento admite con uno, y en una tienda de cuatro personas encontrar dos
-- testigos disponibles no siempre es posible.
--
-- ── POR QUÉ EL TESTIGO VA EN LA FILA Y NO EN EL ADJUNTO ────────────────────
--
-- Porque el acta es el hecho jurídico que arranca los doce meses, no un papel
-- que se archiva. Si el nombre del testigo solo vive dentro de un PDF escaneado,
-- ninguna consulta puede comprobar que el acta esté completa, y el sistema no
-- puede negarse a entregar sin él. El escaneo se sigue subiendo —eso no cambia—
-- pero el dato que decide vive en la tabla.
--
-- Se admite un testigo que NO esté en el sistema: `testigo_nombre` es lo
-- obligatorio y `testigo_id` es opcional. En una tienda el testigo suele ser
-- otra integrante, pero puede ser quien esté delante, y un acta que no se puede
-- levantar porque el testigo no tiene usuario no serviría de nada.
--
-- ── Y QUIÉN ENTREGA ────────────────────────────────────────────────────────
--
-- El 55.4 pide la firma de «quien entrega» además de la del testigo, y hasta
-- hoy no se guardaba: `fn_expediente_entregar` no dejaba rastro de quién la
-- ejecutó. Se añade `entregado_por` para todas las entregas, no solo para esta.
--
-- ── CÓMO SE REVIERTE ───────────────────────────────────────────────────────
--
-- Restaurando `fn_expediente_entregar` de la 0058, devolviendo el check de
-- `medio_entrega` a sus tres valores y soltando las tres columnas nuevas.
-- Revertir significa que un acta de negativa vuelva a no entregar nada.
--
-- md5 de partida (pedirlo a PRODUCCIÓN, no al Postgres local):
--   fn_expediente_entregar  860001cc15a127e2d305539ad09c23a6  (0058)
-- ============================================================================

alter table expediente_disciplinario
  add column if not exists entregado_por           uuid references personas(id),
  add column if not exists entrega_testigo_nombre  text,
  add column if not exists entrega_testigo_id      uuid references personas(id);

comment on column expediente_disciplinario.entrega_testigo_nombre is
  'Numeral 55.4: quien atestigua la negativa a firmar. Va en la fila y no solo en el acta escaneada porque es el dato que hace valida la entrega.';

-- El medio nuevo. Se reescribe el check entero: `add constraint` sobre una
-- columna que ya tiene uno deja los dos vivos y el viejo seguiría rechazando.
alter table expediente_disciplinario drop constraint if exists expediente_disciplinario_medio_entrega_check;
alter table expediente_disciplinario add constraint expediente_disciplinario_medio_entrega_check
  check (medio_entrega in ('fisico','correo','notarial','acta_negativa'));

-- Un acta sin testigo no es un acta. Se comprueba en la tabla y no solo en la
-- función porque el dato tiene que ser cierto venga por donde venga.
alter table expediente_disciplinario drop constraint if exists chk_acta_negativa_con_testigo;
alter table expediente_disciplinario add constraint chk_acta_negativa_con_testigo
  check (medio_entrega is distinct from 'acta_negativa'
         or (entrega_testigo_nombre is not null and btrim(entrega_testigo_nombre) <> ''));

create or replace function fn_expediente_entregar(
  p_id uuid,
  p_medio text,
  p_fecha timestamptz default now(),
  p_testigo_nombre text default null,
  p_testigo_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare r expediente_disciplinario%rowtype;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'firmado' then
    raise exception 'Solo se entrega un documento firmado (estado actual: %).', r.estado;
  end if;
  if not fn_expediente_puede_actuar(r.persona_id, r.nivel) then raise exception 'Sin permiso.'; end if;
  if p_medio not in ('fisico','correo','notarial','acta_negativa') then
    raise exception 'Medio de entrega inválido.';
  end if;
  if r.nivel in ('imputacion','despido') and p_medio = 'correo' then
    raise exception 'Nivel 4 (imputación/despido) no admite entrega por correo: usa físico o notarial.';
  end if;

  -- NUMERAL 55.4: «acta de negativa suscrita por quien entrega y por un
  -- testigo». Sin el testigo no hay acta, y sin acta no hay entrega — así que
  -- se para acá en vez de dejar el documento a medias.
  if p_medio = 'acta_negativa' and coalesce(btrim(p_testigo_nombre), '') = '' then
    raise exception
      'El acta de negativa la suscriben quien entrega y un testigo (numeral 55.4 del RIT). '
      'Escribe el nombre de quien atestigua la negativa.';
  end if;

  update expediente_disciplinario
    set estado                 = 'entregado',
        medio_entrega          = p_medio,
        entregado_at           = p_fecha,
        entregado_por          = fn_persona_actual_id(),
        entrega_testigo_nombre = case when p_medio = 'acta_negativa'
                                      then btrim(p_testigo_nombre) end,
        entrega_testigo_id     = case when p_medio = 'acta_negativa' then p_testigo_id end
    where id = p_id;
end;
$$;

grant  execute on function fn_expediente_entregar(uuid, text, timestamptz, text, uuid) to authenticated;
revoke execute on function fn_expediente_entregar(uuid, text, timestamptz, text, uuid) from public, anon;

-- La firma vieja de tres argumentos deja de existir: Postgres la mantendría
-- viva como sobrecarga, y una llamada de tres argumentos entregaría sin pasar
-- por el guard del testigo.
drop function if exists fn_expediente_entregar(uuid, text, timestamptz);

insert into migraciones_aplicadas (numero, nombre)
values (303, 'la_negativa_a_firmar_entrega_el_documento')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
-- Las cuatro deben decir true.
select
  (select count(*) from information_schema.columns
    where table_name = 'expediente_disciplinario'
      and column_name in ('entregado_por','entrega_testigo_nombre','entrega_testigo_id')) = 3
                                                          as estan_las_tres_columnas,
  (select pg_get_constraintdef(oid) ilike '%acta_negativa%' from pg_constraint
    where conname = 'expediente_disciplinario_medio_entrega_check')
                                                          as el_medio_admite_el_acta,
  (select count(*) from pg_constraint where conname = 'chk_acta_negativa_con_testigo') = 1
                                                          as un_acta_sin_testigo_no_entra,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_expediente_entregar') = 1
                                                          as solo_queda_una_version_de_entregar;
