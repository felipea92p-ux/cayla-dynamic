-- ============================================================================
-- 0544 · Una cuenta de servicio deja de figurar como persona en planilla
-- ============================================================================
--
-- ── QUÉ PASÓ ────────────────────────────────────────────────────────────────
--
-- El 2026-10-21, cruzando los certificados del Seguro de Vida Ley contra quién
-- está en planilla, «ESTACIÓN — Producción» (Lima, alta 2026-10-09) salió como
-- una persona a asegurar: la consulta 4 de quienes_van_al_seguro_de_vida_ley.sql
-- dio 21 «a cubrir» cuando eran 20 personas.
--
-- La causa: la 0490 hizo de `cuenta_de_servicio` una marca aparte y la 0491
-- sacó a las cuentas de servicio de la planilla FILTRANDO por esa marca en
-- cada sitio (`and not p.cuenta_de_servicio`). Pero la marca no tocaba el
-- VÍNCULO, que sigue siendo el que dice quién es una persona en planilla
-- (`en_planilla` es columna generada de `tipo_vinculo`, 0085). Una estación
-- nace con los defaults de la tabla —`planilla`, en planilla, S/ 1230— y solo
-- después se marca. Las seis anteriores estaban en `no_trabajador` porque
-- alguien las cambió a mano; la de Producción no. Medido en la app: 12 de 24
-- archivos que leen `en_planilla` no mencionan `cuenta_de_servicio`, y lo mismo
-- pasa con muchas consultas de scripts/sql-manual. Cada una que se escriba
-- sin el filtro repite el caso.
--
-- ── QUÉ PROMETE ─────────────────────────────────────────────────────────────
--
-- `fn_set_cuenta_de_servicio`, al MARCAR, deja el vínculo en `no_trabajador`
-- en la misma transacción. Dos cosas que eran la misma verdad dicha en dos
-- sitios pasan a decirse en uno: una estación no es una persona, y por tanto no
-- está en planilla.
--
--   1. Por qué esta función y no el alta: las DOS entradas pasan por ella.
--      El alta de Equipo (`fn_crear_persona` con `p_es_estacion`, 0513) la llama
--      justo después del insert; el interruptor de la ficha de una persona ya
--      existente (personas/[id]) la llama directo. Arreglar solo el alta dejaría
--      la ficha produciendo el mismo caso.
--   2. El vínculo no se escribe aquí: se pasa por `fn_set_tipo_vinculo` (0119),
--      que es SU puerta, y deja SU rastro en correcciones_auditoria. Así la
--      regla «al salir de practicante se borra la modalidad» sigue viviendo en
--      un solo sitio. Si ya es `no_trabajador` (las seis anteriores) no se
--      llama: no hay nada que cambiar ni rastro que ensuciar.
--   3. Una ficha ya cesada NO se puede marcar si su vínculo es otro: la 0504
--      se niega a cambiar el vínculo de quien ya salió («su liquidación se
--      calculó con el vínculo anterior»). Antes se podía; ahora se dice con
--      palabras de esta pantalla en vez de con las de otra. Las estaciones
--      cesadas que ya estén en `no_trabajador` se marcan igual.
--   4. DESMARCAR no cambia el vínculo. Antes «Desmarcar» devolvía a la
--      planilla porque la exclusión venía solo de la marca; ahora el vínculo
--      también se movió y no hay de dónde saber a cuál volver (¿planilla,
--      prueba, honorarios?). Se decide en Equipo, y el texto del rastro, el de
--      la ficha y la prueba 388 dejan de prometer «vuelve a la planilla».
--
-- ── QUÉ NO HACE ─────────────────────────────────────────────────────────────
--
--   · No corrige la fila que ya está mal en producción. Una cuenta que ya está
--     marcada no pasa otra vez por la puerta (`v_antes = p_valor` sale primero,
--     igual que en la 0490), así que «ESTACIÓN — Producción» se pasa a
--     `no_trabajador` desde Equipo (Vínculo → «Sin vínculo laboral»). La comprobación
--     del final la nombra mientras siga así.
--   · No quita el `and not p.cuenta_de_servicio` de la 0491. Siguen ahí como
--     segunda red; sacarlos es otra decisión.
--   · No pone candado en la tabla. Un `check (not cuenta_de_servicio or
--     tipo_vinculo = 'no_trabajador')` haría imposible que alguien deje a una
--     estación en planilla desde Equipo, pero exige antes corregir la fila de
--     Producción y mezclaría dos cambios en uno. Va aparte, cuando esa fila ya
--     esté bien.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
--   · `fn_set_cuenta_de_servicio` es la de la 0490: una sola versión, tres
--     argumentos. Cuerpo del repositorio, calculado del archivo (NO de una
--     base): md5 b9b3eb85073483a49cb1b0f8ba36548c, 2512 caracteres; sin
--     comentarios c1af7d990a88997fed1d160d925aca15. md5 de PRODUCCIÓN:
--     PENDIENTE — se pide a Felipe con la consulta de «ANTES DE PEGAR» y se
--     anota aquí. El freno de abajo comprueba PRESENCIA de lo que importa (los
--     cuatro textos de la 0490 y que ninguna versión posterior haya dejado un
--     marcador `CAMBIO 0NNN` distinto del de esta), no un md5: una base armada
--     desde cero no tiene el md5 de producción.
--   · `fn_set_tipo_vinculo(uuid, text)` existe y acepta `no_trabajador`. Es la
--     de la 0504 (md5 en repositorio da6490ac5d12722e38fcba0a2d47dea9; si
--     producción aún tiene la 0324 el efecto es el mismo). Esta migración la
--     LLAMA, no la reescribe: si alguien le cambia la firma, marcar una
--     estación fallará con «function does not exist» y el freno de abajo lo
--     avisa antes de pegar.
--   · Repegar esta migración es seguro: reemplaza la función por el mismo
--     cuerpo. Lo que NO es seguro es repegar la 0490 encima: devolvería la
--     función a la versión que deja la estación en planilla.
--
-- ── POR QUÉ ASÍ ─────────────────────────────────────────────────────────────
--
--   DECIDÍ:     Que la puerta de marcar fije el vínculo (opción 2, elegida por
--               Felipe el 2026-10-21).
--   DESCARTÉ:   Solo el alta (`fn_crear_persona` nace `no_trabajador`): dejaba
--               la ficha de una persona existente marcada y en planilla, y
--               tocaba la función más editada del alta (6 versiones).
--               También descarté el candado en la tabla de entrada: exige
--               corregir antes la fila de Producción y mezcla dos cambios.
--   SE ROMPE SI: Alguien pasa a `planilla` el vínculo de una estación ya
--               marcada desde Equipo (nada lo impide hasta el candado); o si
--               alguien desmarca por error a una persona y espera que vuelva
--               a cobrar sin tocar el vínculo (la ficha ahora lo dice en
--               voz alta); o si `fn_set_tipo_vinculo` cambia de firma.
--
-- ── ANTES DE PEGAR (solo lectura, en el SQL Editor) ─────────────────────────
--
--   select p.proname, p.pronargs, md5(p.prosrc), length(p.prosrc)
--     from pg_proc p where p.pronamespace = 'public'::regnamespace
--      and p.proname in ('fn_set_cuenta_de_servicio', 'fn_set_tipo_vinculo');
--
--   select numero, nombre from migraciones_aplicadas where numero in (490, 504);
--
--   select nombres, apellidos, tipo_vinculo, en_planilla, estado
--     from personas where cuenta_de_servicio;
--   → esperado ANTES: una fila con tipo_vinculo = 'planilla' (Producción); las
--     demás en 'no_trabajador'. Después de pegar esto esa fila SIGUE así: se
--     corrige desde Equipo.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   Pegar el cuerpo de `fn_set_cuenta_de_servicio` de la 0490. Ningún dato se
--   pierde; las estaciones que se marcaron en el intervalo quedan en
--   `no_trabajador` (que es lo correcto) y habría que repasar a mano a
--   cualquiera que se haya desmarcado esperando volver a la planilla.
-- ============================================================================


-- ── 0 · Freno: no se escribe sobre una versión que no es la que se espera ───
do $freno$
declare
  v_n   int;
  v_src text;
begin
  select count(*) into v_n
    from pg_proc
   where proname = 'fn_set_cuenta_de_servicio'
     and pronamespace = 'public'::regnamespace;
  if v_n <> 1 then
    raise exception 'PARA. fn_set_cuenta_de_servicio tiene % versiones (se esperaba 1, la de la 0490). Falta la 0490, o alguien le cambió la firma: reconstruir desde la vigente con ./scripts/donde-vive.sh fn_set_cuenta_de_servicio.', v_n;
  end if;

  select prosrc into v_src
    from pg_proc
   where proname = 'fn_set_cuenta_de_servicio'
     and pronamespace = 'public'::regnamespace
     and pronargs = 3;
  if v_src is null then
    raise exception 'PARA. fn_set_cuenta_de_servicio ya no tiene tres argumentos: alguien la cambió después de la 0490. Esta migración copiaría la 0490 y la revertiría en silencio.';
  end if;

  if v_src !~ 'Esta ficha tiene marcajes'
     or v_src !~ 'ya se le pagó dinero'
     or v_src !~ 'rol de líder ni de administración'
     or v_src !~ 'correcciones_auditoria' then
    raise exception 'PARA. fn_set_cuenta_de_servicio ya no es la de la 0490 (le faltan sus comprobaciones). Esta migración la reemplazaría con una copia de la 0490.';
  end if;

  -- Toda reescritura de este repo deja un marcador «CAMBIO 0NNN». Si hay uno
  -- que no es el de esta migración, hay una versión POSTERIOR a la 0490 y
  -- pegar esto la revertiría. (Repegar la propia 0544 sí pasa.)
  if v_src ~ 'CAMBIO 0[0-9]{3}' and v_src !~ 'CAMBIO 0544' then
    raise exception 'PARA. fn_set_cuenta_de_servicio trae un marcador CAMBIO 0NNN que no es el de la 0544: hay una versión posterior a la 0490 y esta migración la pisaría. Reconstruir desde la vigente.';
  end if;

  -- La función que esta LLAMA tiene que estar, con dos argumentos.
  if to_regprocedure('public.fn_set_tipo_vinculo(uuid, text)') is null then
    raise exception 'PARA. fn_set_tipo_vinculo(uuid, text) no existe: marcar una cuenta de servicio fallaría. Falta la 0119 (o la 0324/0504) o alguien le cambió la firma.';
  end if;
end
$freno$;


-- ── 1 · La puerta, ahora también dueña del vínculo ──────────────────────────
-- Igual a la de la 0490 salvo lo marcado «CAMBIO 0544».
create or replace function fn_set_cuenta_de_servicio(
  p_persona_id uuid,
  p_valor      boolean,
  p_motivo     text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes   boolean;
  v_rol     text;
  v_estado  text;    -- CAMBIO 0544
  v_vinculo text;    -- CAMBIO 0544
  v_quien   uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder DO puede marcar una cuenta de servicio.';
  end if;

  if p_valor is null then
    raise exception 'Hay que decir sí o no.';
  end if;

  select cuenta_de_servicio, rol::text, estado, tipo_vinculo
    into v_antes, v_rol, v_estado, v_vinculo
    from personas where id = p_persona_id;
  if not found then
    raise exception 'Persona inválida.';
  end if;

  if v_antes = p_valor then
    return;
  end if;

  -- Marcar saca de la planilla (0491). Si esto le pasa a una persona real,
  -- deja de cobrar en silencio: por eso se niega ante cualquier señal de que
  -- ahí trabaja alguien. Desmarcar no tiene condiciones.
  if p_valor then
    if v_rol <> 'integrante' then
      raise exception 'Una cuenta de servicio no puede tener rol de líder ni de administración. Cámbiale el rol a integrante primero.';
    end if;
    if exists (select 1 from marcajes where persona_id = p_persona_id)
       or exists (select 1 from jornadas where persona_id = p_persona_id) then
      raise exception 'Esta ficha tiene marcajes: alguien trabajó con ella. Una cuenta de servicio no marca asistencia, y marcarla así la sacaría de la planilla.';
    end if;
    -- `total > 0` y no «tiene una fila»: ver la 0490. Una estación congelada en
    -- un periodo tiene su fila con S/ 0; una persona, no.
    if exists (select 1 from planilla_pagada_detalle
                where persona_id = p_persona_id and coalesce(total, 0) > 0) then
      raise exception 'A esta ficha ya se le pagó dinero en al menos un mes. No se puede marcar como cuenta de servicio.';
    end if;
    -- CAMBIO 0544 · marcar también pasa el vínculo a «No trabajador»
    -- (fn_set_tipo_vinculo), y esa puerta se niega a tocar el de quien ya
    -- salió. Se dice aquí, con las palabras de esta pantalla, antes de llegar
    -- allá y que el mensaje hable de una «liquidación» que no se ve.
    if v_estado = 'inactivo' and v_vinculo <> 'no_trabajador' then
      raise exception 'Esta ficha ya está cesada y su vínculo no es «Sin vínculo laboral»: su liquidación se calculó con ese vínculo, así que no se puede marcar como cuenta de servicio.';
    end if;
  end if;

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Inicia sesión con tu usuario.';
  end if;

  update personas set cuenta_de_servicio = p_valor where id = p_persona_id;

  -- CAMBIO 0544 · una cuenta de servicio no es una persona en planilla. El
  -- vínculo se cambia por su propia puerta, que deja su propio rastro y borra
  -- la modalidad si venía de practicante. Si ya es «No trabajador» (las
  -- estaciones que se corrigieron a mano) no hay nada que hacer.
  if p_valor and v_vinculo <> 'no_trabajador' then
    perform fn_set_tipo_vinculo(p_persona_id, 'no_trabajador');
  end if;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'personas.cuenta_de_servicio', v_antes::text, p_valor::text,
          coalesce(nullif(btrim(p_motivo), ''),
                   case when p_valor
                        then 'Marcada como cuenta de servicio: su vínculo pasa a «Sin vínculo laboral» y sale de la planilla y de las listas del equipo.'
                        else 'Deja de ser cuenta de servicio: vuelve a las listas del equipo. Su vínculo no cambia: se decide en Equipo.' end),
          v_quien);
end;
$$;

comment on function fn_set_cuenta_de_servicio(uuid, boolean, text) is
  'Marca o desmarca una fila de personas como cuenta de servicio (una estación de retail, no '
  'una persona). Solo admin o líder DO. Se niega a marcar a quien tiene marcajes, jornadas o un '
  'mes cobrado (total > 0), un rol distinto de integrante, o está cesada con otro vínculo. Al '
  'marcar deja el vínculo en no_trabajador (fn_set_tipo_vinculo, con su propio rastro); al '
  'desmarcar NO lo cambia. Deja rastro en correcciones_auditoria. 0490, 0544.';

revoke all on function fn_set_cuenta_de_servicio(uuid, boolean, text) from public, anon;
grant execute on function fn_set_cuenta_de_servicio(uuid, boolean, text) to authenticated;


insert into migraciones_aplicadas (numero, nombre)
values (544, 'una_cuenta_de_servicio_no_queda_en_planilla')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();


-- ── Comprobación ────────────────────────────────────────────────────────────
-- Las booleanas deben dar `true`. `estaciones_en_planilla` debe quedar vacío
-- DESPUÉS de corregir a mano la fila de Producción desde Equipo; antes de eso
-- la nombra, y es lo esperado.
select
  (select count(*) = 1 and bool_and(prosrc like '%CAMBIO 0544%') from pg_proc
    where proname = 'fn_set_cuenta_de_servicio' and pronamespace = 'public'::regnamespace)
    as una_sola_version_nueva,
  not has_function_privilege('anon', 'fn_set_cuenta_de_servicio(uuid,boolean,text)', 'execute')
    as anon_no_marca,
  (select string_agg(nombres || ' ' || apellidos || ' (' || tipo_vinculo || ')', ' · ' order by apellidos)
     from personas where cuenta_de_servicio and tipo_vinculo <> 'no_trabajador')
    as estaciones_en_planilla,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 544)
    as registro,
  (select md5(prosrc) from pg_proc
    where proname = 'fn_set_cuenta_de_servicio' and pronamespace = 'public'::regnamespace)
    as md5_llegada;
