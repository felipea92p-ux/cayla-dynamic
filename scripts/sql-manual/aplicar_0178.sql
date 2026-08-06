-- ⚠️  LISTO PARA PEGAR EN EL SQL EDITOR DE SUPABASE (producción).
-- Copia exacta de supabase/migrations/0178_caylo_deja_de_poder_asignarse.sql
--
-- NO DEPENDE DE NINGUNA OTRA. No toca fn_planilla_calcular, así que puede
-- pegarse antes o después de la 0173 y la 0177 sin alterar nada de ellas.
-- Es idempotente: pegarla dos veces no hace daño.
--
-- ANTES de pegar, mira a quién le va a cambiar el rango:
--
--     select p.nombres || ' ' || p.apellidos as persona, a.rango, a.salario_mensual_soles
--       from asignaciones_salario a
--       join personas p on p.id = a.persona_id
--      where a.rango = 'caylo' and a.vigente_hasta is null;
--
--   Si no devuelve filas, no le cambia el rango a nadie: solo cierra el candado.
--   Si devuelve filas, a esas personas se les pasa a «cayla». NO cambia lo que
--   cobran —misma base declarada de S/1,185 y mismo techo de educación de
--   S/180—; lo que cambia es que pasan a TENER techo, que es lo que les faltaba.
--
-- DESPUÉS de pegar, comprueba que el candado quedó cerrado:
--
--     select conname, pg_get_constraintdef(oid)
--       from pg_constraint
--      where conname in ('asignaciones_salario_rango_check',
--                        'topes_educacion_rango_rango_check');
--
--   Ninguno de los dos debe nombrar 'caylo'. Si alguno lo nombra, no se aplicó.
--
--   Y que ninguna categoría quedó sin techo —es el estado que causó todo esto—:
--
--     select c.rango from categorias_laborales c
--      where not exists (select 1 from topes_educacion_rango t where t.rango = c.rango);
--
--   Tiene que devolver cero filas.

-- ============================================================================
-- 0178 — «Caylo» deja de poder asignarse
-- ============================================================================
--
-- QUÉ PROMETE
--   Que nadie pueda quedar en un rango que el catálogo de categorías ya retiró
--   — y que por estar retirado no tiene techo de educación, así que el sistema
--   le pagaría lo que el comprobante diga, sin límite.
--
-- QUÉ ASUME
--   Que `categorias_laborales` (0140) es el catálogo vigente. Tiene seis filas:
--   colibri, cayla, support, aurora, oraculo, archicaylo. `caylo` no está.
--
-- EL AGUJERO, MEDIDO
--   La 0140 retiró `caylo` a propósito: borró su fila de `topes_educacion_rango`
--   con el aviso «caylo retirado del catalogo de topes de educacion», y no lo
--   incluyó en `categorias_laborales`. Correcto.
--
--   Pero quedaron tres restos que nadie limpió:
--     · el CHECK de `asignaciones_salario` seguía aceptándolo;
--     · el CHECK de `topes_educacion_rango` también;
--     · y `apps/web/lib/rangos.ts` seguía OFRECIÉNDOLO en el desplegable de
--       Equipo, con un `topeEducacion: 180` que en la base ya no existía.
--
--   Medido contra el Postgres local el 2026-08-06, con el comprobante real de
--   S/ 727 que hay cargado en producción:
--
--     rango cayla  →  S/ 180.00   (su techo, correcto)
--     rango caylo  →  S/ 545.25   (TRES VECES el techo)
--
--   No es un descuido del cálculo: `fn_educacion_respeta_el_tope` dice, textual,
--   «rango sin techo cargado: falla abierto a propósito». Fallar abierto es
--   prudente cuando un rango NUEVO todavía no tiene su techo — DO no debería
--   quedarse bloqueada. Deja de serlo cuando el rango está RETIRADO: ahí la
--   ausencia de techo no significa «aún no lo cargamos», significa «esto no
--   debería existir».
--
-- POR QUÉ SE QUITA Y NO SE LE PONE TECHO
--   Un rango es un NIVEL, no un género. `cayla` y `caylo` nombraban el mismo
--   nivel —misma base declarada, mismo techo— y tener dos nombres para una cosa
--   es justo lo que produjo este agujero: uno de los dos se olvida. La política
--   salarial que se publica al equipo ya lista una sola categoría «Cayla».
--   Decisión de Felipe, 2026-08-06.
--
-- QUÉ PASA CON QUIEN LO TENGA HOY
--   Se le reasigna a `cayla`, que es el mismo nivel: misma base declarada
--   (S/ 1,185) y mismo techo de educación (S/ 180). **No cambia lo que cobra.**
--   Queda rastro en `correcciones_auditoria` con el motivo, porque tocar el
--   rango de alguien nunca debe ser silencioso aunque el monto no se mueva.
--
--   En el Postgres local no hay nadie en `caylo`; en producción hay que mirarlo,
--   y el aviso del final lo dice si encuentra a alguien.
--
-- CÓMO SE REVIERTE
--   Volver a poner 'caylo' en los dos CHECK. La reasignación NO se deshace sola:
--   habría que devolver el rango persona por persona, y la auditoría dice a
--   quiénes.
-- ============================================================================


-- ── A · Quien esté en el rango retirado pasa al que lo reemplaza ────────────
do $mig$
declare
  v_n int := 0;
  r   record;
begin
  for r in
    select a.persona_id, p.nombres || ' ' || p.apellidos as persona
    from asignaciones_salario a
    join personas p on p.id = a.persona_id
    where a.rango = 'caylo' and a.vigente_hasta is null
  loop
    update asignaciones_salario set rango = 'cayla'
     where persona_id = r.persona_id and vigente_hasta is null and rango = 'caylo';

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (r.persona_id, 'rango', 'caylo', 'cayla',
       coalesce(fn_persona_actual_id(), r.persona_id),
       'El rango «caylo» se retiró del catálogo (0140). Es el mismo nivel que «cayla»: '
       || 'misma base declarada y mismo techo de educación, así que no cambia lo que cobra.');

    v_n := v_n + 1;
    raise notice '0178 · % pasa de caylo a cayla (mismo nivel, mismo monto)', r.persona;
  end loop;

  if v_n = 0 then
    raise notice '0178 · nadie estaba en el rango caylo.';
  end if;
end $mig$;


-- ── B · Y deja de poder elegirse ───────────────────────────────────────────
-- Los CHECK se rehacen sin 'caylo'. Idempotente: si ya están así, el drop no
-- encuentra nada y el add vuelve a poner lo mismo.
alter table asignaciones_salario  drop constraint if exists asignaciones_salario_rango_check;
alter table asignaciones_salario
  add  constraint asignaciones_salario_rango_check
  check (rango in ('colibri','cayla','support','aurora','oraculo','archicaylo'));

alter table topes_educacion_rango drop constraint if exists topes_educacion_rango_rango_check;
alter table topes_educacion_rango
  add  constraint topes_educacion_rango_rango_check
  check (rango in ('colibri','cayla','support','aurora','oraculo','archicaylo'));


insert into migraciones_aplicadas (numero, nombre)
values (178, 'caylo_deja_de_poder_asignarse')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare
  v_cat   int;
  v_topes int;
  v_falta text;
begin
  select count(*) into v_cat   from categorias_laborales;
  select count(*) into v_topes from topes_educacion_rango;

  -- Cada categoría del catálogo tiene que tener su techo. Si alguna no lo tiene,
  -- vuelve el mismo agujero por otro nombre: el candado falla abierto.
  select string_agg(c.rango, ', ') into v_falta
  from categorias_laborales c
  where not exists (select 1 from topes_educacion_rango t where t.rango = c.rango);

  raise notice '0178 · categorias en el catalogo: % · con techo de educacion: %', v_cat, v_topes;
  if v_falta is not null then
    raise warning '0178 · ATENCION: estas categorias no tienen techo de educacion y pagarian sin limite: %', v_falta;
  else
    raise notice '0178 · todas las categorias vigentes tienen su techo cargado.';
  end if;
end $mig$;
