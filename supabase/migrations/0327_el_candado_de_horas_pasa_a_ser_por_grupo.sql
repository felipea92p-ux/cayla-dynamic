-- ============================================================================
-- 0327 — El candado de horas pasa a ser por grupo (Entrega 2)
-- ============================================================================
--
-- QUÉ PROMETE
--
--   La 0323 (Entrega 1) separó el PAGO de planilla en 5 grupos independientes
--   por `personas.tipo_vinculo` (planilla, prueba, rxh, no_trabajador,
--   practicante) — RxH se paga más tarde que planilla, y ya no hace falta
--   fingir que se pagó todo el mismo día. Pero dejó, A PROPÓSITO y
--   documentado, el candado que BLOQUEA EDITAR horas/marcajes/jornadas como
--   un interruptor único para el periodo entero (`periodos_planilla.estado`).
--   Resultado: mientras un solo grupo del periodo siga sin pagar, las horas
--   de TODOS — incluida la gente de un grupo YA pagado, con su foto YA
--   congelada — seguían editables en Correcciones sin que nada lo impidiera.
--
--   Esta migración cierra ese hueco. Cada función que bloquea una edición
--   preguntando "¿esta fecha cae en un periodo YA PAGADO?" pasa a preguntar
--   "¿esta fecha cae en un periodo pagado PARA EL GRUPO DE ESTA PERSONA?".
--
-- QUÉ ASUME
--
--   · Que `periodo_grupo_pago` (0323) y su compatibilidad con periodos
--     pagados de antes de esa migración siguen como están — no se tocan.
--   · Que ninguna de las funciones tocadas aquí cambia su PROPIA firma de
--     argumentos: todas ya recibían (o podían derivar) el `persona_id` que
--     hacía falta. La única firma que sí cambia es la de la pieza central,
--     `fn_fecha_en_periodo_pagado`, que gana un segundo argumento.
--
-- ── EL DISEÑO, EN UN PÁRRAFO ─────────────────────────────────────────────────
--
--   `fn_fecha_en_periodo_pagado(p_fecha date)` (0203, un argumento) pasa a
--   `fn_fecha_en_periodo_pagado(p_fecha date, p_persona_id uuid)`: mira el
--   grupo (tipo_vinculo) de ESA persona en `periodo_grupo_pago`, no el
--   agregado del periodo — con la misma compatibilidad hacia atrás que ya
--   usa la 0323 (un periodo con `estado = 'pagado'` pero SIN ninguna fila en
--   `periodo_grupo_pago` es de antes de la 0323, y se sigue leyendo por el
--   agregado). 33 funciones que hoy preguntan lo mismo de una de estas dos
--   formas — llamando a la vieja `fn_fecha_en_periodo_pagado(fecha)`, o con
--   un `exists (select 1 from periodos_planilla where estado = 'pagado' ...)`
--   escrito a mano en 23 sitios distintos — pasan a llamar a la nueva de dos
--   argumentos. Ninguna otra línea de esas funciones cambia: mismos
--   comentarios, mismas variables, misma lógica de negocio.
--
--   Dos casos no encajan en "una fecha + una persona":
--
--     · `fn_set_feriado` / `fn_quitar_feriado` — un feriado es del
--       calendario entero, no de alguien en concreto. Se quedan bloqueadas
--       si CUALQUIER grupo de un periodo que contenga esa fecha ya está
--       pagado (más estricto que "todos", menos que "nadie" — es la mejor
--       aproximación sin una persona a la que atarle un grupo).
--     · `fn_eliminar_periodo` — recibe el periodo directo, no una fecha. Se
--       queda bloqueada con el mismo criterio ("cualquier grupo pagado"),
--       sin buscar por rango de fechas.
--
--   Una tercera función, `fn_calcular_bono_puntualidad`, NO se retrofitea:
--   se ELIMINA. El bono que calcula está en S/0.00 desde la migración 0121 —
--   agosto de 2026 — y su único botón en el panel se quitó hace semanas (el
--   código que lo llamaba quedó como función muerta, sin usar, marcada por
--   el linter). Nadie puede llamarla desde la pantalla hoy. Decisión de
--   Felipe: en vez de arrastrar un candado parcheado sobre una función que
--   ya no hace nada, se borra de raíz — junto con el código muerto del panel
--   que la invocaba.
--
-- MD5 DE PARTIDA — todos LOCALES, confirmados contra un `supabase db reset`
-- limpio hasta la 0326. PENDIENTE DE CONFIRMAR CONTRA PRODUCCIÓN antes de
-- pegar (regla de la casa: el árbol se mueve con ~20 sesiones activas). El
-- bloque 0 de esta migración los vuelve a comprobar EN PRODUCCIÓN antes de
-- tocar nada — si alguno no coincide, la migración entera no aplica NADA.
--
--   fn_fecha_en_periodo_pagado        f0b155a7d758f10e362a9992deb64eb4 ·   138
--   fn_calcular_bono_puntualidad      31e969d7639f093192d560dc7a986728 ·  4608  (se elimina)
--   fn_anular_marcaje                 0fdc89fc2ed1ecede07e7ff78dc5246e ·  2013
--   fn_reactivar_marcaje              d9317f97b6c7a1468e04ff7049072b45 ·  2597
--   fn_corregir_marca                 fccf25590bb096ddb30f63ad2a0045fd ·  3724
--   fn_corregir_marcaje               81ff1f3131236209745aeb48606dea3e ·  1994
--   fn_eliminar_marcaje               52bf088be176f381eac452648f55029a ·  1603
--   fn_confirmar_auto_cierre          cfee8e8b7ebc671bb951609ad595fe1b ·  1846
--   fn_agregar_marcaje                2ccd19eea088d590f54ca63d52c2b549 ·  1918
--   fn_registrar_marcaje              e60959ddd713cf10749fdaf12e3bfec2 · 13023
--   fn_recalcular_jornada             c50fa2ed18d61ef7ad304fd554fba4cc · 12561
--   fn_reabrir_dia                    291b5832218258c618e3434aa0634093 ·  4819
--   fn_set_turno                      052fddb606ab5b013dbd9653b7b3751b ·  2050
--   fn_quitar_turno                   1f5eb2bb741e5213164db46e9ecc0da4 ·  1300
--   fn_set_descanso                   e0c0f8363b8ffbe92b11584097b95daf ·  1646
--   fn_set_horario_semanal            68790773c6b7e54830e02ecbdec540bf ·  2514
--   fn_set_salario                    55f844f6a6268b4f7051aa25a0103c9c ·  2274
--   fn_set_fecha_ingreso              5f4a4aa7cdf3a16a53e1c42017e23108 ·   908
--   fn_otorgar_descanso_sustitutorio  86ee6818f55a89785999b6727490cce0 ·  2560
--   fn_quitar_descanso_sustitutorio   c8eb8b7854aab7536ddf0cefc40f02a0 ·   977
--   fn_agregar_movimiento             3246c0ffadb891a50effd8b589018b60 ·  2869
--   fn_quitar_movimiento              6acec517707973b4e7c7461c8678ce28 ·   575
--   fn_registrar_ausencia             b6251b8b32f76e51749a51d68821ed01 ·  2678
--   fn_anular_ausencia                5250204856581f5306fdbe9666df0870 ·   930
--   fn_cesar_persona                  727eb1ba7c62ead765c45e41c3357c92 ·  3476
--   fn_cambiar_regimen_pension        ed01ed0f903bf13800d3cf282919abe8 ·  4848
--   fn_reactivar_persona              765a20fce50fdce878c4f6c743a3fe64 ·  9704
--   fn_educacion_fecha_pagada         1d1a56ac5692e55b37d586d12e1f5339 ·   132
--   fn_auto_cierre                    bb26b6e431973704a557f1afec6a903a ·  4764
--   fn_set_feriado                    719d2dc02f9408322518c4b116d5775a ·   774
--   fn_quitar_feriado                 78c1592506fa7abe332bcbb7c9e06f49 ·   556
--   fn_eliminar_periodo               14acc43cf164ba17e9e7e6cf0f7dc228 ·   802
--
--   Y dos llamadoras de fn_educacion_fecha_pagada, descubiertas a mitad de
--   camino (ver bloque 34) — sin ellas la migración deja rota la firma vieja:
--   fn_educacion_registrar           a1f955999484a4bc764262ce62804c31 ·  9960
--   fn_educacion_cerrar(uuid,date)          9d6fef4c5564722e99d6fbbd3e13c2d5 ·   558  (se elimina, sobrecarga huérfana)
--   fn_educacion_cerrar(uuid,date,text)     63c3b66015d35f69b2fab2fe476325e6 ·  1114
--
--   fn_set_vacaciones, fn_quitar_vacaciones, fn_grati_trunca_bruta y
--   fn_liquidacion se investigaron y NO SE TOCAN: no bloquean ninguna
--   edición por periodo pagado (confirmado leyendo su cuerpo completo contra
--   Postgres local, con verificación independiente para cada una).
--
-- CÓMO SE REVIERTE
--
--   Volver a pegar los cuerpos vigentes de cada función de la lista de
--   arriba (están en las migraciones que dice cada bloque de abajo).
--   `fn_fecha_en_periodo_pagado` vuelve a su firma de 1 argumento (0203).
--   `fn_calcular_bono_puntualidad` se restaura desde la 0189 si hiciera
--   falta (no debería: está confirmado sin ningún llamador ni en el código
--   ni en pgTAP). Nada de esto toca datos ni tablas.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final.
-- ============================================================================


-- ── 0 · Comprobar ANTES de tocar nada ────────────────────────────────────────
-- Si producción no está en las versiones de partida declaradas arriba, esta
-- migración no aplica NADA. Mismo patrón que la 0313/0284/0323.
do $$
declare v_md5 text; v_len int; v_esperado text; v_esperado_len int; v_nombre text;
begin
  for v_nombre, v_esperado, v_esperado_len in
    select * from (values
      ('fn_fecha_en_periodo_pagado',       'f0b155a7d758f10e362a9992deb64eb4',   138),
      ('fn_calcular_bono_puntualidad',     '31e969d7639f093192d560dc7a986728',  4608),
      ('fn_anular_marcaje',                '0fdc89fc2ed1ecede07e7ff78dc5246e',  2013),
      ('fn_reactivar_marcaje',             'd9317f97b6c7a1468e04ff7049072b45',  2597),
      ('fn_corregir_marca',                'fccf25590bb096ddb30f63ad2a0045fd',  3724),
      ('fn_corregir_marcaje',              '81ff1f3131236209745aeb48606dea3e',  1994),
      ('fn_eliminar_marcaje',              '52bf088be176f381eac452648f55029a',  1603),
      ('fn_confirmar_auto_cierre',         'cfee8e8b7ebc671bb951609ad595fe1b',  1846),
      ('fn_agregar_marcaje',               '2ccd19eea088d590f54ca63d52c2b549',  1918),
      ('fn_registrar_marcaje',             'e60959ddd713cf10749fdaf12e3bfec2', 13023),
      ('fn_recalcular_jornada',            'c50fa2ed18d61ef7ad304fd554fba4cc', 12561),
      ('fn_reabrir_dia',                   '291b5832218258c618e3434aa0634093',  4819),
      ('fn_set_turno',                     '052fddb606ab5b013dbd9653b7b3751b',  2050),
      ('fn_quitar_turno',                  '1f5eb2bb741e5213164db46e9ecc0da4',  1300),
      ('fn_set_descanso',                  'e0c0f8363b8ffbe92b11584097b95daf',  1646),
      ('fn_set_horario_semanal',           '68790773c6b7e54830e02ecbdec540bf',  2514),
      ('fn_set_salario',                   '55f844f6a6268b4f7051aa25a0103c9c',  2274),
      ('fn_set_fecha_ingreso',             '5f4a4aa7cdf3a16a53e1c42017e23108',   908),
      ('fn_otorgar_descanso_sustitutorio', '86ee6818f55a89785999b6727490cce0',  2560),
      ('fn_quitar_descanso_sustitutorio',  'c8eb8b7854aab7536ddf0cefc40f02a0',   977),
      ('fn_agregar_movimiento',            '3246c0ffadb891a50effd8b589018b60',  2869),
      ('fn_quitar_movimiento',             '6acec517707973b4e7c7461c8678ce28',   575),
      ('fn_registrar_ausencia',            'b6251b8b32f76e51749a51d68821ed01',  2678),
      ('fn_anular_ausencia',               '5250204856581f5306fdbe9666df0870',   930),
      ('fn_cesar_persona',                 '727eb1ba7c62ead765c45e41c3357c92',  3476),
      ('fn_cambiar_regimen_pension',       'ed01ed0f903bf13800d3cf282919abe8',  4848),
      ('fn_reactivar_persona',             '765a20fce50fdce878c4f6c743a3fe64',  9704),
      ('fn_educacion_fecha_pagada',        '1d1a56ac5692e55b37d586d12e1f5339',   132),
      ('fn_auto_cierre',                   'bb26b6e431973704a557f1afec6a903a',  4764),
      ('fn_set_feriado',                   '719d2dc02f9408322518c4b116d5775a',   774),
      ('fn_quitar_feriado',                '78c1592506fa7abe332bcbb7c9e06f49',   556),
      ('fn_eliminar_periodo',              '14acc43cf164ba17e9e7e6cf0f7dc228',   802),
      -- Las dos siguientes se descubrieron A MITAD DE CAMINO: son las únicas
      -- dos llamadoras de fn_educacion_fecha_pagada fuera de esta lista, y se
      -- rompían con "function fn_educacion_fecha_pagada(date) does not
      -- exist" en cuanto esa cambiaba de firma (medido en pgTAP 109/114/218/
      -- 226 al aplicar esta migración sin cubrirlas). fn_educacion_registrar
      -- no tiene ambigüedad de sobrecarga — una sola versión — así que entra
      -- en este mismo loop.
      ('fn_educacion_registrar',           'a1f955999484a4bc764262ce62804c31',  9960)
    ) as t(nombre, esperado, esperado_len)
  loop
    select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_nombre;
    if v_md5 is distinct from v_esperado then
      raise exception '0327 · PARA. % en esta base es % (% caracteres), se esperaba % (%). No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh %.', v_nombre, v_md5, v_len, v_esperado, v_esperado_len, v_nombre;
    end if;
  end loop;

  -- fn_educacion_cerrar es distinta: tiene DOS sobrecargas vivas ahora mismo
  -- (hallazgo de esta migración — ver bloque 34, "fn_educacion_cerrar tenía
  -- DOS sobrecargas..."), así que hay que comprobar cada una por su cuenta,
  -- filtrando por pronargs — el loop de arriba, sin ese filtro, tomaría una
  -- de las dos al azar (select into sin strict no avisa de la ambigüedad).
  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_educacion_cerrar' and p.pronargs = 2;
  if v_md5 is distinct from '9d6fef4c5564722e99d6fbbd3e13c2d5' then
    raise exception '0327 · PARA. fn_educacion_cerrar(uuid,date) en esta base es % (% caracteres), se esperaba 9d6fef4c5564722e99d6fbbd3e13c2d5 (558). No se aplicó nada.', v_md5, v_len;
  end if;

  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_educacion_cerrar' and p.pronargs = 3;
  if v_md5 is distinct from '63c3b66015d35f69b2fab2fe476325e6' then
    raise exception '0327 · PARA. fn_educacion_cerrar(uuid,date,text) en esta base es % (% caracteres), se esperaba 63c3b66015d35f69b2fab2fe476325e6 (1114). No se aplicó nada.', v_md5, v_len;
  end if;
end
$$;


-- ── 1 · fn_fecha_en_periodo_pagado gana un segundo argumento ────────────────
-- La pieza central. Antes (0203, 1 argumento) miraba el periodo entero;
-- ahora mira el GRUPO (tipo_vinculo) de la persona dueña del dato.
drop function if exists fn_fecha_en_periodo_pagado(date);

create or replace function fn_fecha_en_periodo_pagado(p_fecha date, p_persona_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from periodos_planilla pp
    where p_fecha between pp.fecha_ini and pp.fecha_fin
      and (
        -- Compatibilidad: un periodo con estado='pagado' pero SIN ninguna fila
        -- en periodo_grupo_pago es de antes de la 0323 (el bucket único de
        -- siempre) — se sigue leyendo por el agregado.
        (pp.estado = 'pagado' and not exists (
           select 1 from periodo_grupo_pago g where g.periodo_id = pp.id
         ))
        or
        -- El caso normal desde la 0323: el GRUPO de esta persona, no el
        -- periodo entero.
        exists (
          select 1 from periodo_grupo_pago g
          join personas pe on pe.id = p_persona_id
          where g.periodo_id = pp.id
            and g.grupo = pe.tipo_vinculo
            and g.estado = 'pagado'
        )
      )
  );
$$;

comment on function fn_fecha_en_periodo_pagado(date, uuid) is
  '¿Esta fecha cae dentro de un periodo YA PAGADO, para el grupo (tipo_vinculo) de esta persona? — 0327 (Entrega 2), antes miraba el periodo entero (0203). La pregunta que decide si un dato de esa persona, ese día, se puede tocar.';

grant execute on function fn_fecha_en_periodo_pagado(date, uuid) to authenticated;
revoke execute on function fn_fecha_en_periodo_pagado(date, uuid) from public, anon;


-- ── 2 · fn_calcular_bono_puntualidad se elimina ─────────────────────────────
-- El bono que calcula está en S/0.00 desde la 0121 (agosto 2026), y su botón
-- en el panel ya no existe — el código que la llamaba quedó muerto, sin
-- usar, y se retiró junto con esta migración. Ninguna otra función ni prueba
-- pgTAP la referencia (confirmado con grep sobre todo el repositorio antes
-- de escribir esto). En vez de parchearle un candado a una función que nadie
-- puede llamar, se borra de raíz — decisión de Felipe, 2026-08-30.
drop function if exists fn_calcular_bono_puntualidad(uuid);


-- ── 4 · fn_anular_marcaje ─────────────────────────────────────────────────────────────
-- FUNCION: fn_anular_marcaje
-- VIGENTE EN: 0307_el_candado_del_mes_pagado_mide_la_jornada.sql
-- NECESITA_CAMBIO: si
-- NOTAS: El candado está escrito a mano (no llama a fn_fecha_en_periodo_pagado):
--   `if exists (select 1 from periodos_planilla where estado = 'pagado' and
--   v_fecha_jornada between fecha_ini and fecha_fin) then raise exception...`.
--   Se reemplazó ESE fragmento por `fn_fecha_en_periodo_pagado(v_fecha_jornada,
--   v_ant.persona_id)`. v_ant.persona_id es la persona dueña del marcaje que se
--   anula (viene de `select * into v_ant from marcajes where id = p_marcaje_id`),
--   no quien hace el clic. No se tocó el `perform ... for share` de la línea
--   anterior (bloquea el registro de periodos_planilla, no decide si está
--   pagado) ni el comentario "CAMBIO 0307" que documenta v_fecha_jornada — solo
--   se tocó la línea del exists, con su propio comentario "CAMBIO 0307" que
--   desaparece junto con la línea que reemplaza. Confirmado contra el cuerpo
--   exacto de producción local (pg_get_functiondef, Postgres del Docker) y
--   contra el texto del archivo 0307, que coinciden byte a byte.

CREATE OR REPLACE FUNCTION public.fn_anular_marcaje(p_marcaje_id uuid, p_motivo text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha date; v_fecha_jornada date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la anulación es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.anulada_at is not null then
    raise exception 'Esa marca ya está anulada.';
  end if;

  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;
  -- CAMBIO 0307 · El candado del mes pagado se mide contra la JORNADA, no
  -- contra el reloj. Una salida a las 00:30 del 29 que cierra el turno del 28
  -- pertenece —para la planilla— al 28. `v_fecha` sigue siendo el día del
  -- reloj porque de eso dependen el resellado y los mensajes de esta función;
  -- lo único que cambia de vara es el candado.
  v_fecha_jornada := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);

  perform 1 from periodos_planilla
   where v_fecha_jornada between fecha_ini and fecha_fin for share;   -- CAMBIO 0307
  if fn_fecha_en_periodo_pagado(v_fecha_jornada, v_ant.persona_id) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: anularla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  update marcajes
     set anulada_at = now(), anulada_por = v_corr, anulada_motivo = trim(p_motivo)
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'marcaje_anulado',
          v_ant.tipo::text || ' @ ' || v_ant.timestamp_marca::text, 'anulada', v_corr, trim(p_motivo));

  perform fn_levantar_sello_si_el_dia_cuadra(v_ant.persona_id, v_fecha);
  return v_nuevo;
end;
$function$;



-- ── 5 · fn_reactivar_marcaje ─────────────────────────────────────────────────────────────
-- FUNCION: fn_reactivar_marcaje
-- VIGENTE EN: 0307_el_candado_del_mes_pagado_mide_la_jornada.sql
-- NECESITA_CAMBIO: si
-- NOTAS: El cuerpo vigente (confirmado contra el Postgres local con
--   pg_get_functiondef, una sola fila) bloqueaba con un `exists (select 1
--   from periodos_planilla where estado = 'pagado' and v_fecha_jornada
--   between fecha_ini and fecha_fin)` escrito a mano — el candado de
--   periodo-entero, ya migrado en la 0307 para medir contra la JORNADA en
--   vez del reloj, pero todavía sin distinguir grupo. El único cambio es
--   reemplazar ese `if exists (...)` completo por
--   `if fn_fecha_en_periodo_pagado(v_fecha_jornada, v_ant.persona_id) then`.
--   v_ant.persona_id es la persona dueña del marcaje que se está
--   reactivando (viene de `select * into v_ant from marcajes where id =
--   p_marcaje_id`), no de quien hace el clic — v_corr (el corrector, de
--   fn_verificar_corrector) no se usa para esto. El `perform ... for
--   share` de la línea anterior es solo el lock de la fila de
--   periodos_planilla y no pregunta por `estado = 'pagado'`, así que se
--   deja intacto junto con su comentario "-- CAMBIO 0307". No hay
--   grant/revoke/comment on function propios de esta función en la 0307
--   (la línea 452 de esa migración es una consulta de verificación final,
--   no una sentencia sobre la función).

CREATE OR REPLACE FUNCTION public.fn_reactivar_marcaje(p_marcaje_id uuid, p_motivo text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha date; v_fecha_jornada date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la reactivación es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  -- Autorización primero: los mensajes de estado de abajo cuentan cosas de una
  -- marca que quien pregunta puede no tener derecho a conocer.
  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.anulada_at is null then
    raise exception 'Esa marca no está anulada.';
  end if;

  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;
  -- CAMBIO 0307 · El candado del mes pagado se mide contra la JORNADA, no
  -- contra el reloj. Una salida a las 00:30 del 29 que cierra el turno del 28
  -- pertenece —para la planilla— al 28. `v_fecha` sigue siendo el día del
  -- reloj porque de eso dependen el resellado y los mensajes de esta función;
  -- lo único que cambia de vara es el candado.
  v_fecha_jornada := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);

  perform 1 from periodos_planilla
   where v_fecha_jornada between fecha_ini and fecha_fin for share;   -- CAMBIO 0307
  if fn_fecha_en_periodo_pagado(v_fecha_jornada, v_ant.persona_id) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: reactivarla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  if v_ant.tipo = 'salida_final' and exists (
    select 1 from marcajes
    where persona_id = v_ant.persona_id
      and tipo = 'salida_final'
      and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
      and anulada_at is null
      and id <> p_marcaje_id
  ) then
    raise exception 'Ese día ya tiene otra salida final activa. Anula primero la que sobra: dos salidas finales el mismo día dejan el cálculo al azar.';
  end if;

  update marcajes
     set anulada_at = null, anulada_por = null, anulada_motivo = null
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'marcaje_reactivado',
          'anulada: ' || coalesce(v_ant.anulada_motivo, ''), v_ant.tipo::text, v_corr, trim(p_motivo));

  perform fn_levantar_sello_si_el_dia_cuadra(v_ant.persona_id, v_fecha);
  return v_nuevo;
end;
$function$;



-- ── 6 · fn_corregir_marca ─────────────────────────────────────────────────────────────
-- FUNCION: fn_corregir_marca
-- VIGENTE EN: 0307_el_candado_del_mes_pagado_mide_la_jornada.sql
-- NECESITA_CAMBIO: si
-- NOTAS: El candado está escrito a mano (caso "exists a mano" del diseño),
--   no como llamada a fn_fecha_en_periodo_pagado. El bloque
--   `if exists (select 1 from periodos_planilla where estado = 'pagado'
--   and v_fecha_jornada between fecha_ini and fecha_fin) then` se reemplaza
--   por `if fn_fecha_en_periodo_pagado(v_fecha_jornada, v_ant.persona_id) then`.
--   El persona_id es el dueño del marcaje que se corrige (v_ant, ya
--   bloqueado con `for update` más arriba), no quien hace el clic — v_corr
--   (fn_verificar_corrector) es de quien corrige, y no se usa aquí a
--   propósito. Se usa v_fecha_jornada (no v_fecha) porque así lo dejó la
--   0307 a propósito: el candado mide contra la jornada, el guard de "mismo
--   día" y el resellado siguen midiendo contra el reloj (v_fecha) — ver el
--   comentario "CAMBIO 0307" que ya estaba en el cuerpo, se conserva tal
--   cual. No se toca la línea `perform 1 from periodos_planilla ... for
--   share` que la precede: es un lock de concurrencia sobre el periodo, no
--   la comprobación de pagado, y el diseño pide no tocar otras líneas.
--   Cuerpo de partida verificado contra el Postgres LOCAL (ground truth),
--   no copiado a mano del .sql.

CREATE OR REPLACE FUNCTION public.fn_corregir_marca(p_marcaje_id uuid, p_nuevo_tipo tipo_marca DEFAULT NULL::tipo_marca, p_nuevo_ts timestamp with time zone DEFAULT NULL::timestamp with time zone, p_motivo text DEFAULT NULL::text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_tipo tipo_marca; v_ts timestamptz; v_fecha date; v_fecha_jornada date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.anulada_at is not null then
    raise exception 'Esa marca está anulada: reactívala antes de corregirla.';
  end if;

  v_tipo := coalesce(p_nuevo_tipo, v_ant.tipo);
  v_ts   := coalesce(p_nuevo_ts,   v_ant.timestamp_marca);
  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;
  -- CAMBIO 0307 · El candado del mes pagado se mide contra la JORNADA, no
  -- contra el reloj. Una salida a las 00:30 del 29 que cierra el turno del 28
  -- pertenece —para la planilla— al 28. `v_fecha` sigue siendo el día del
  -- reloj porque de eso dependen el resellado y los mensajes de esta función;
  -- lo único que cambia de vara es el candado.
  v_fecha_jornada := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);

  if v_tipo = v_ant.tipo and v_ts = v_ant.timestamp_marca then
    raise exception 'No hay nada que cambiar en esa marca.';
  end if;

  if fn_familia_marca(v_tipo) is distinct from fn_familia_marca(v_ant.tipo) then
    raise exception 'No se puede convertir % en %: una salida solo puede pasar a ser otra salida, y un retorno a otro retorno.',
      v_ant.tipo, v_tipo;
  end if;

  if (v_ts at time zone 'America/Lima')::date is distinct from v_fecha then
    raise exception 'Esa corrección movería la marca al %, y aquí solo se corrige la hora dentro de su mismo día. Si de verdad pertenece a otro día: anúlala y agrégala en el día correcto.',
      to_char((v_ts at time zone 'America/Lima')::date, 'DD/MM/YYYY');
  end if;

  perform 1 from periodos_planilla
   where v_fecha_jornada between fecha_ini and fecha_fin for share;   -- CAMBIO 0307
  if fn_fecha_en_periodo_pagado(v_fecha_jornada, v_ant.persona_id) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: corregirla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  update marcajes
     set tipo = v_tipo, timestamp_marca = v_ts, estado_revision = 'revisada'
   where id = p_marcaje_id
  returning * into v_nuevo;

  if v_tipo is distinct from v_ant.tipo then
    insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (p_marcaje_id, v_ant.persona_id, 'tipo', v_ant.tipo::text, v_tipo::text, v_corr, trim(p_motivo));
  end if;
  if v_ts is distinct from v_ant.timestamp_marca then
    insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (p_marcaje_id, v_ant.persona_id, 'timestamp_marca', v_ant.timestamp_marca::text, v_ts::text, v_corr, trim(p_motivo));
  end if;

  -- ¿La corrección dejó el día imposible? Se sella, igual que hace el terminal.
  -- Avisa sin impedir: el flujo normal pasa por aquí a mitad de camino.
  if fn_dia_incoherente(v_ant.persona_id, v_fecha) then
    update marcajes
       set estado_revision = 'pendiente_revision'
     where persona_id = v_ant.persona_id
       and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
       and anulada_at is null
       and estado_revision = 'normal';
  else
    perform fn_levantar_sello_si_el_dia_cuadra(v_ant.persona_id, v_fecha);
  end if;

  return v_nuevo;
end;
$function$;



-- ── 7 · fn_corregir_marcaje ─────────────────────────────────────────────────────────────
-- FUNCION: fn_corregir_marcaje
-- VIGENTE EN: 0307_el_candado_del_mes_pagado_mide_la_jornada.sql
-- NECESITA_CAMBIO: si
-- NOTAS: El candado estaba escrito a mano como un solo `exists (select 1
--   from periodos_planilla where estado = 'pagado' and (v_jornada_ant
--   between ... or v_jornada_nueva between ...))`, comprobando las DOS
--   fechas (la jornada de la marca antes de corregir y la de después) en
--   un solo exists. Lo reemplacé por dos llamadas a
--   fn_fecha_en_periodo_pagado(<fecha>, v_ant.persona_id) unidas con OR —
--   una por cada fecha que antes comprobaba el exists — porque la firma
--   nueva solo acepta una fecha a la vez. persona_id es v_ant.persona_id:
--   la dueña del marcaje que se está corrigiendo (la fila ya leída antes
--   del candado), no quien hace la corrección (ese es v_corr, calculado
--   DESPUÉS y con otro propósito). Los dos comentarios en línea
--   "-- CAMBIO 0307" iban pegados a las dos condiciones del exists que
--   este cambio reemplaza (documentaban por qué el exists miraba jornada
--   y no timestamp); como esas líneas concretas desaparecen, los quité
--   con ellas. El comentario de bloque de arriba (por qué v_jornada_ant/
--   v_jornada_nueva salen de fn_fecha_de_jornada) no lo toqué: sigue
--   siendo válido, no habla del exists sino del cálculo de jornada.
--   Nada más se tocó: nombres de variables, resto del cuerpo, mensaje de
--   la excepción, todo igual. No tenía grant/revoke/comment on detrás en
--   la 0307.

CREATE OR REPLACE FUNCTION public.fn_corregir_marcaje(p_marcaje_id uuid, p_nuevo_ts timestamp with time zone, p_motivo text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha_ant date; v_fecha_nueva date;
        v_jornada_ant date; v_jornada_nueva date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_fecha_ant := (v_ant.timestamp_marca at time zone 'America/Lima')::date;
  v_fecha_nueva := (p_nuevo_ts at time zone 'America/Lima')::date;

  -- CAMBIO 0307 · El candado mide la JORNADA. El `update` de abajo no toca
  -- `fecha_jornada`, así que la marca conserva la suya tanto antes como
  -- después de moverle la hora: las dos fechas salen de ese mismo valor.
  v_jornada_ant   := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);
  v_jornada_nueva := fn_fecha_de_jornada(p_nuevo_ts,            v_ant.fecha_jornada);

  if fn_fecha_en_periodo_pagado(v_jornada_ant, v_ant.persona_id)
     or fn_fecha_en_periodo_pagado(v_jornada_nueva, v_ant.persona_id) then
    raise exception 'Ese marcaje cae en un periodo ya PAGADO: corregirlo alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  update marcajes set timestamp_marca = p_nuevo_ts, estado_revision = 'revisada'
  where id = p_marcaje_id returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'timestamp_marca', v_ant.timestamp_marca::text, p_nuevo_ts::text, v_corr, trim(p_motivo));

  perform fn_resellar_dia(v_ant.persona_id, v_fecha_ant);
  if v_fecha_nueva <> v_fecha_ant then
    perform fn_resellar_dia(v_ant.persona_id, v_fecha_nueva);
  end if;

  return v_nuevo;
end;
$function$;



-- ── 8 · fn_eliminar_marcaje ─────────────────────────────────────────────────────────────
-- FUNCION: fn_eliminar_marcaje
-- VIGENTE EN: 0307_el_candado_del_mes_pagado_mide_la_jornada.sql
-- NECESITA_CAMBIO: si
-- NOTAS: El candado estaba escrito a mano: `exists (select 1 from
--         periodos_planilla where estado = 'pagado' and v_fecha_jornada
--         between fecha_ini and fecha_fin)`. Se reemplazó ESE fragmento
--         completo por `fn_fecha_en_periodo_pagado(v_fecha_jornada,
--         v_ant.persona_id)`, conservando el comentario trailing "-- CAMBIO
--         0307" que ya marcaba esa línea. `v_ant.persona_id` es la persona
--         dueña del marcaje que se va a borrar (leída con `select * into
--         v_ant from marcajes where id = p_marcaje_id` al principio de la
--         función) — no se usó `fn_persona_actual_id()` ni nada de quién
--         hace el clic. No se tocó ningún otro comentario, variable ni
--         línea. Md5 local (con comentarios) de esta función vigente:
--         52bf088be176f381eac452648f55029a — hay que volver a pedirlo a
--         producción antes de entregar el SQL final, como manda CLAUDE.md.

CREATE OR REPLACE FUNCTION public.fn_eliminar_marcaje(p_marcaje_id uuid, p_motivo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_corr uuid; v_fecha date; v_fecha_jornada date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;
  -- CAMBIO 0307 · El candado del mes pagado se mide contra la JORNADA, no
  -- contra el reloj. Una salida a las 00:30 del 29 que cierra el turno del 28
  -- pertenece —para la planilla— al 28. `v_fecha` sigue siendo el día del
  -- reloj porque de eso dependen el resellado y los mensajes de esta función;
  -- lo único que cambia de vara es el candado.
  v_fecha_jornada := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);

  if fn_fecha_en_periodo_pagado(v_fecha_jornada, v_ant.persona_id) then   -- CAMBIO 0307
    raise exception 'Ese marcaje cae en un periodo ya PAGADO: eliminarlo alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (null, v_ant.persona_id, 'marcaje_eliminado', v_ant.tipo::text || ' @ ' || v_ant.timestamp_marca::text, null, v_corr, trim(p_motivo));

  delete from marcajes where id = p_marcaje_id;

  perform fn_resellar_dia(v_ant.persona_id, v_fecha);
end;
$function$;



-- ── 9 · fn_confirmar_auto_cierre ─────────────────────────────────────────────────────────────
-- FUNCION: fn_confirmar_auto_cierre
-- VIGENTE EN: 0307_el_candado_del_mes_pagado_mide_la_jornada.sql
-- NECESITA_CAMBIO: si
-- NOTAS: Caso normal (con exists a mano, no con llamada de 1 argumento). El
--   cuerpo vigente en el Postgres local (md5 cfee8e8b7ebc671bb951609ad595fe1b,
--   confirmado con donde-vive.sh — una sola fila en pg_proc, sin ambigüedad)
--   tenía el candado escrito a mano:
--     if exists (
--       select 1 from periodos_planilla
--       where estado = 'pagado' and v_fecha between fecha_ini and fecha_fin
--     ) then
--   Lo reemplacé por `if fn_fecha_en_periodo_pagado(v_fecha, v_ant.persona_id) then`.
--   `v_fecha` ya viene fijada arriba (CAMBIO 0307) a la fecha de la JORNADA
--   del marcaje, no del reloj — eso no lo toqué. `v_ant.persona_id` es la
--   persona dueña del marcaje (`select * into v_ant from marcajes where id =
--   p_marcaje_id`), no quien hace el clic — es el dato correcto para el
--   candado por grupo. La fila `perform 1 from periodos_planilla ... for
--   share` que precede al chequeo se dejó intacta: es un lock de fila
--   separado del chequeo en sí, y no forma parte del `exists` que había que
--   sustituir. No se tocó ningún otro comentario ni línea; se añadió un
--   único comentario nuevo `CAMBIO 0327` junto al cambio, siguiendo la misma
--   convención que ya usa esta función para el `CAMBIO 0307` de arriba (el
--   número de migración 0327 es el que ya declaró la pieza central en
--   00_helper.sql — `comment on function fn_fecha_en_periodo_pagado`). No
--   hay grant/comment propios de fn_confirmar_auto_cierre en la 0307 (los
--   `grant`/`revoke` de esta función están fijados desde la 0083/0089 sobre
--   la firma `(uuid, text)`, que no cambia aquí), así que no hace falta
--   repetirlos.

CREATE OR REPLACE FUNCTION public.fn_confirmar_auto_cierre(p_marcaje_id uuid, p_motivo text DEFAULT NULL::text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha date;
begin
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.origen <> 'auto_cierre' then
    raise exception 'Solo se confirma una marca puesta por el auto-cierre.';
  end if;
  if v_ant.anulada_at is not null then
    raise exception 'Esa marca está anulada.';
  end if;
  if v_ant.estado_revision = 'revisada' then
    raise exception 'Ese auto-cierre ya está confirmado.';
  end if;

  -- CAMBIO 0307 · Acá `v_fecha` no lo usa nadie más que el candado, así que
  -- pasa a ser directamente la fecha de la JORNADA: una marca de madrugada
  -- pertenece al turno que cierra, no al día del calendario en que cae.
  v_fecha := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);

  perform 1 from periodos_planilla
   where v_fecha between fecha_ini and fecha_fin for share;
  -- CAMBIO 0327 · El candado mira el GRUPO (tipo_vinculo) de la persona
  -- dueña de la marca, no el periodo entero: si planilla ya pagó pero RxH
  -- todavía no, confirmar un auto-cierre de alguien de planilla sigue
  -- bloqueado aunque el grupo RxH de ese periodo siga abierto.
  if fn_fecha_en_periodo_pagado(v_fecha, v_ant.persona_id) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: confirmarla haría que ese día empiece a medir salida anticipada y tiempo adicional, cambiando una planilla ya pagada. Reabre el periodo primero.';
  end if;

  update marcajes set estado_revision = 'revisada'
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'auto_cierre_confirmado',
          'pendiente_revision', 'revisada', v_corr,
          coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'Confirmado: esa es su salida final.'));

  return v_nuevo;
end;
$function$;



-- ── 10 · fn_agregar_marcaje ─────────────────────────────────────────────────────────────
-- FUNCION: fn_agregar_marcaje
-- VIGENTE EN: 0188_el_resellado_del_dia_entra_al_repositorio.sql
-- NECESITA_CAMBIO: si
-- NOTAS: El candado estaba escrito a mano — `exists (select 1 from
--   periodos_planilla where estado = 'pagado' and v_fecha between fecha_ini
--   and fecha_fin)` — justo antes de insertar el marcaje. Se reemplazó ESE
--   fragmento completo por `fn_fecha_en_periodo_pagado(v_fecha, p_persona_id)`.
--   p_persona_id es el primer parámetro de la función misma: la persona
--   DUEÑA del marcaje que se está agregando (no hay ningún admin/lider de
--   por medio que confundir con el dueño del dato). Cuerpo verificado
--   contra el Postgres local (`pg_get_functiondef`, fila única) antes de
--   escribir; coincide byte a byte con lo que trae 0188. Ningún otro
--   cambio: mismo cuerpo, mismos comentarios, misma firma (no cambia
--   número ni tipo de argumentos), y esta función no tenía grant/revoke
--   propio en 0188 (el bloque `grant/revoke` de esa migración es de
--   fn_resellar_dia, la función anterior).

CREATE OR REPLACE FUNCTION public.fn_agregar_marcaje(p_persona_id uuid, p_tipo tipo_marca, p_ts timestamp with time zone, p_motivo text, p_motivo_otro text DEFAULT NULL::text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_sede uuid; v_nuevo marcajes; v_corr uuid; v_fecha date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;

  v_fecha := (p_ts at time zone 'America/Lima')::date;

  if fn_fecha_en_periodo_pagado(v_fecha, p_persona_id) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: agregar un marcaje ahí alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(p_persona_id);

  -- La sede la manda el DÍA, no el escritorio: si la persona ya marcó ese día
  -- (por ejemplo, de visita en otra tienda), la corrección se graba en esa misma
  -- sede. Solo si el día está vacío cae a su sede base. Sin esto, la jornada
  -- queda partida entre dos sedes y el terminal ve media verdad.
  select m.sede_id into v_sede
  from marcajes m
  where m.persona_id = p_persona_id
    and (m.timestamp_marca at time zone 'America/Lima')::date = v_fecha
    and m.sede_id is not null
  order by m.timestamp_marca, m.id
  limit 1;

  if v_sede is null then
    select sede_base_id into v_sede from personas where id = p_persona_id;
  end if;
  if v_sede is null then raise exception 'Persona no encontrada.'; end if;

  insert into marcajes (client_uuid, persona_id, sede_id, tipo, motivo_otro, timestamp_marca, origen, estado_revision)
  values (gen_random_uuid(), p_persona_id, v_sede, p_tipo, p_motivo_otro, p_ts, 'admin_correccion', 'revisada')
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (v_nuevo.id, p_persona_id, 'marcaje_agregado', null, p_tipo::text || ' @ ' || p_ts::text, v_corr, trim(p_motivo));

  perform fn_resellar_dia(p_persona_id, v_fecha);

  return v_nuevo;
end;
$function$;



-- ── 11 · fn_registrar_marcaje ─────────────────────────────────────────────────────────────
-- FUNCION: fn_registrar_marcaje
-- VIGENTE EN: 0320_la_marca_real_gana_a_la_que_adivino_el_robot.sql
-- NECESITA_CAMBIO: si
-- NOTAS: El candado está en el bloque "CAMBIO 0207" (¿esta marca cae dentro
--   de un periodo ya pagado?), que hoy escribe a mano
--   `exists (select 1 from periodos_planilla where estado = 'pagado' and
--   v_fecha between fecha_ini and fecha_fin) into v_en_pagado`. Ese booleano
--   `v_en_pagado` gobierna tres cosas: (1) si se retira la salida_final
--   sintética del auto-cierre cuando llega la marca real (0320: "not
--   v_en_pagado"), (2) si al reconciliar una salida_final existente del
--   auto-cierre se sella como pendiente_revision en vez de normal, y (3) si
--   el marcaje recién insertado se sella como pendiente_revision. Las tres
--   son del dueño de la marca, así que se reemplazó el `exists` a mano por
--   `fn_fecha_en_periodo_pagado(v_fecha, p_persona_id)` — p_persona_id es el
--   parámetro de la función, la persona dueña del marcaje que se está
--   registrando (no quien hace el clic: el terminal no tiene sesión).
--   No se tocó ninguna otra línea, comentario ni nombre de variable. La
--   migración 0320 no deja grant/revoke/comment on después de esta función
--   (comprobado con grep sobre el archivo), así que no hay nada más que
--   copiar.

CREATE OR REPLACE FUNCTION public.fn_registrar_marcaje(p_persona_id uuid, p_tipo tipo_marca, p_timestamp_cliente timestamp with time zone, p_client_uuid uuid, p_origen origen_marca DEFAULT 'terminal'::origen_marca, p_terminal_id uuid DEFAULT NULL::uuid, p_sede_id uuid DEFAULT NULL::uuid, p_motivo_otro text DEFAULT NULL::text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_sede_id uuid;
  v_marcaje marcajes;
  v_existente marcajes;
  v_fecha date;
  v_esperado tipo_marca;
  v_caller_rol rol_usuario;
  v_terminal_auth uuid;
  v_ultimo_ts timestamptz;
  v_atrasada boolean;
  v_en_pagado boolean;     -- 0207: ¿esta marca cae dentro de un periodo ya pagado?
  v_cruzo_medianoche boolean := false;  -- 0240: ¿cierra una jornada del día anterior?
  v_jornada_abierta date;               -- 0240: y de qué día es esa jornada
  v_jornada_estado text;                -- 0320: ¿la cerró el robot o sigue abierta?
  v_sintetica marcajes;                 -- 0320: la salida_final que puso el auto-cierre
begin
  -- Idempotencia: reintentos offline con el mismo client_uuid no duplican.
  select * into v_existente from marcajes where client_uuid = p_client_uuid;
  if found then
    return v_existente;
  end if;

  if p_origen = 'terminal' then
    if p_terminal_id is null then
      raise exception 'p_terminal_id es obligatorio cuando origen = terminal';
    end if;
    select sede_id, auth_user_id into v_sede_id, v_terminal_auth
    from terminales where id = p_terminal_id and activo;
    if v_sede_id is null then
      raise exception 'terminal % no encontrado o inactivo', p_terminal_id;
    end if;
    if auth.uid() is not null and v_terminal_auth is not null and auth.uid() <> v_terminal_auth then
      raise exception 'el terminal autenticado no coincide con p_terminal_id';
    end if;
  else
    if p_sede_id is null then
      raise exception 'p_sede_id es obligatorio cuando origen != terminal';
    end if;
    select rol into v_caller_rol from personas where auth_user_id = auth.uid();
    if v_caller_rol is null or v_caller_rol not in ('admin', 'lider_do', 'supervisor_sede') then
      raise exception 'no autorizado para registrar marcajes con origen %', p_origen;
    end if;
    if v_caller_rol = 'supervisor_sede' then
      if not exists (
        select 1 from personas
        where auth_user_id = auth.uid() and sede_base_id = p_sede_id
      ) then
        raise exception 'un supervisor_sede solo puede corregir marcajes de su propia sede';
      end if;
    end if;
    v_sede_id := p_sede_id;
  end if;

  if p_tipo = 'salida_otro' and (p_motivo_otro is null or length(trim(p_motivo_otro)) < 3) then
    raise exception 'motivo_otro es obligatorio para salida_otro';
  end if;

  v_fecha := (p_timestamp_cliente at time zone 'America/Lima')::date;

  -- ⇩⇩⇩ CAMBIO 0240 ⇩⇩⇩ LA JORNADA MANDA, NO EL CALENDARIO.
  --
  -- Quien cierra tienda a las 00:30 no podía marcar su salida: el sistema miraba
  -- el día NUEVO, no encontraba ninguna entrada y esperaba una `entrada`. La
  -- salida real se rechazaba en la puerta —medido: «tipo salida_final no válido
  -- en el estado actual (se esperaba entrada)»— y de ahí salían DOS errores de
  -- signo contrario: el día anterior lo cerraba el cron con la hora programada
  -- (le faltaban 1.5 h de las que trabajó) y nacía un día fantasma que el cron
  -- cerraba en 22.5 h. En una sola noche: 30.5 h registradas donde hubo 9.5.
  --
  -- Con esto, esa marca pertenece a la JORNADA que sigue abierta, aunque el
  -- calendario ya haya cambiado de día. No se inventa nada: se usan las dos
  -- marcas reales y se dice que son del mismo turno, que es como lo cuenta una
  -- persona — «anoche salí tarde».
  --
  -- SOLO PARA SALIDAS Y RETORNOS. Una `entrada` a las 00:30 abre un día nuevo
  -- como siempre: puede ser alguien empezando su turno, y confundir eso sería
  -- cambiar un error por otro.
  --
  -- EL TOPE DE 16 HORAS es lo que impide que una jornada que alguien olvidó
  -- cerrar se coma el día siguiente. Pasado ese tope, la marca vuelve a ser del
  -- día que dice el calendario y el auto-cierre hace su trabajo.
  if p_tipo::text like 'salida\_%' escape '\' or p_tipo::text like 'retorno\_%' escape '\' then
    -- ⇩⇩⇩ CAMBIO 0320 ⇩⇩⇩ TAMBIÉN SI EL ROBOT LLEGÓ PRIMERO.
    --
    -- Acá decía `j.estado in ('abierta', 'en_pausa')`, y con eso la promesa nº1
    -- de la 0240 —«que quien cierra tienda pasada la medianoche PUEDA marcar su
    -- salida»— solo se cumplía durante las 3 horas siguientes a su hora
    -- programada. `fn_auto_cierre` corre cada 15 minutos y cierra cualquier
    -- jornada abierta pasado ese plazo; a partir de ahí esta rama no encontraba
    -- nada y la salida REAL se rechazaba con el mismo error que la 0240 cita en
    -- su encabezado como lo que resuelve.
    --
    -- Medido el 2026-08-26 contra el Postgres local, horario 13:00–21:00:
    -- trabajó de 13:00 a 00:30 —11,50 h— y le quedaban 8,00 h puestas por el
    -- robot. Su salida: «tipo salida_final no válido en el estado actual (se
    -- esperaba entrada)». Y el agravante: el terminal le ofrecía ENTRADA, se
    -- aceptaba, y nacía el día fantasma que la 0240 existe para evitar.
    --
    -- `auto_cerrada_pendiente` se llama así justamente porque el robot ADIVINÓ:
    -- puso la hora programada, no la real. Una marca de una persona es mejor
    -- evidencia que una suposición, y por eso gana.
    select j.fecha, j.estado into v_jornada_abierta, v_jornada_estado
    from jornadas j
    where j.persona_id = p_persona_id
      and j.fecha < v_fecha
      and j.estado in ('abierta', 'en_pausa', 'auto_cerrada_pendiente')
      and j.entrada_ts is not null
      and p_timestamp_cliente <= j.entrada_ts + interval '16 hours'
    order by j.fecha desc
    limit 1;

    if found then
      v_fecha := v_jornada_abierta;
      v_cruzo_medianoche := true;
    end if;
  end if;

  -- ⇩⇩⇩ CAMBIO 0207 ⇩⇩⇩ ¿Cae dentro de un periodo ya pagado?
  -- Se calcula acá arriba, una sola vez, porque hace falta en los DOS caminos
  -- por los que esta función deja una marca: el insert del final y la
  -- reconciliación del auto-cierre, que retorna antes de llegar a él.
  --
  -- Lo que NO se hace con esto es rechazar. La 0068 ya lo dejó escrito: la
  -- terminal reintenta seis veces y acaba descartando la marca. Perder el
  -- registro de alguien que sí estuvo es peor que un día pagado que no cuadra.
  select fn_fecha_en_periodo_pagado(v_fecha, p_persona_id) into v_en_pagado;

  -- ⇩⇩⇩ CAMBIO 0320 ⇩⇩⇩ LA MARCA REAL GANA A LA QUE ADIVINÓ EL ROBOT.
  --
  -- Adoptar la jornada no basta: la `salida_final` sintética del auto-cierre
  -- sigue ahí, así que `fn_siguiente_tipo_esperado` volvería a esperar una
  -- `entrada` y la salida real se rechazaría igual. Hay que retirarla.
  --
  -- SE ANULA, NO SE BORRA — los marcajes son append-only, y esto deja su rastro
  -- en `correcciones_auditoria` como cualquier otra corrección.
  --
  -- ES MUY ACOTADO, y cada condición está por algo:
  --   · `origen = 'auto_cierre'`  → solo lo que puso el robot. Una marca de una
  --     persona no se toca nunca por esta vía.
  --   · `estado_revision <> 'revisada'` → si alguien de DO ya la confirmó, es
  --     una decisión humana y manda sobre esto.
  --   · `not v_en_pagado` → en un mes ya pagado no se cambia nada. Ahí se
  --     mantiene el comportamiento de antes, que rechaza: es preferible que la
  --     marca no entre a que cambie sola una planilla que ya salió del banco.
  --     Se corrige reabriendo el periodo, como todo lo demás.
  --   · el tope de 16 h de la 0240 sigue mandando: viene heredado del `select`
  --     de arriba, que es el único que puede poner `v_jornada_estado`.
  --
  -- `corregido_por` es la propia persona porque el terminal no tiene sesión
  -- —marca sin PIN, y es a propósito— y porque es honesto: su marca real es la
  -- evidencia que corrige la suposición.
  if v_jornada_estado = 'auto_cerrada_pendiente' and not v_en_pagado then
    select * into v_sintetica
    from marcajes m
    where m.persona_id = p_persona_id
      and m.tipo = 'salida_final'
      and m.origen = 'auto_cierre'
      and m.anulada_at is null
      and m.estado_revision is distinct from 'revisada'
      and fn_fecha_de_jornada(m.timestamp_marca, m.fecha_jornada) = v_fecha
    order by m.timestamp_marca desc
    limit 1
    for update;

    if found then
      update marcajes
         set anulada_at     = now(),
             anulada_por    = p_persona_id,
             anulada_motivo = 'La persona marcó su salida real: el auto-cierre había '
                              || 'supuesto la hora programada (0320).'
       where id = v_sintetica.id;

      insert into correcciones_auditoria
        (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo,
         corregido_por, motivo)
      values (v_sintetica.id, p_persona_id, 'auto_cierre_reemplazado',
              'salida_final @ ' || v_sintetica.timestamp_marca::text,
              'salida_final @ ' || p_timestamp_cliente::text,
              p_persona_id,
              'Cerró tienda después de la ventana del auto-cierre y marcó su '
              || 'salida real. La marca del robot se retira (0320).');
    end if;
  end if;

  -- ¿LLEGA ATRASADA? Su hora es anterior a la última ya registrada de ese día:
  -- viene de la cola offline. No se le puede aplicar la validación de secuencia
  -- (se juzgaría contra un presente que no le corresponde, se rechazaría, y la
  -- terminal acabaría borrándola tras 6 reintentos). Se acepta siempre.
  select max(timestamp_marca) into v_ultimo_ts
  from marcajes
  where persona_id = p_persona_id
    and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
    and anulada_at is null;

  v_atrasada := v_ultimo_ts is not null and p_timestamp_cliente < v_ultimo_ts;

  -- Marcas EN VIVO: candado anti-doble-marcado de siempre, intacto.
  if p_origen = 'terminal' and not v_atrasada then
    v_esperado := fn_siguiente_tipo_esperado(p_persona_id, v_fecha);
    if v_esperado is not null and v_esperado <> p_tipo then
      raise exception 'tipo % no válido en el estado actual (se esperaba %)', p_tipo, v_esperado;
    end if;
    if v_esperado is null and p_tipo not in (
      'salida_final', 'salida_almuerzo', 'salida_personal', 'salida_tramite', 'salida_medico', 'salida_otro'
    ) then
      raise exception 'tipo % no válido: la jornada ya está cerrada o requiere elegir un tipo de salida', p_tipo;
    end if;
  end if;

  -- Reconciliación: una salida_final real que llega después de un auto-cierre
  -- sintético del mismo día reemplaza el registro sintético, no lo duplica.
  if p_tipo = 'salida_final' then
    select * into v_existente
    from marcajes
    where persona_id = p_persona_id
      and tipo = 'salida_final'
      and origen = 'auto_cierre'
      and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
      and anulada_at is null;

    if found then
      update marcajes set
        timestamp_marca = p_timestamp_cliente,
        origen = p_origen,
        -- ⇩⇩⇩ CAMBIO 0207 ⇩⇩⇩ Este es el camino delicado, y el que se olvida:
        -- cambia la HORA de una marca que ya existía dentro del periodo pagado,
        -- y además ponía 'normal' a secas, borrando cualquier sello previo.
        estado_revision = case when v_en_pagado then 'pendiente_revision'::estado_revision
                               else 'normal'::estado_revision end,
        client_uuid = p_client_uuid,
        terminal_id = p_terminal_id,
        server_received_at = now()
      where id = v_existente.id
      returning * into v_marcaje;

      return v_marcaje;
    end if;
  end if;

  insert into marcajes (
    client_uuid, persona_id, sede_id, terminal_id, tipo, motivo_otro, timestamp_marca, origen,
    -- 0240: solo lleva valor cuando la marca pertenece a la jornada de OTRO día.
    -- Null en todo lo demás, que es el 99 % de los casos: así la columna dice
    -- «esto es una excepción» en vez de repetir lo que el timestamp ya sabe.
    fecha_jornada
  ) values (
    p_client_uuid, p_persona_id, v_sede_id, p_terminal_id, p_tipo, p_motivo_otro, p_timestamp_cliente, p_origen,
    case when v_cruzo_medianoche then v_fecha else null end
  )
  returning * into v_marcaje;

  -- ⇩⇩⇩ CAMBIO 0207 ⇩⇩⇩ La marca entra, pero no entra muda.
  -- Solo se sella ELLA y no el día entero: el día ya se pagó y su jornada es
  -- correcta como foto de lo que se pagó — lo anómalo es la recién llegada.
  if v_en_pagado then
    update marcajes set estado_revision = 'pendiente_revision' where id = v_marcaje.id;
    select * into v_marcaje from marcajes where id = v_marcaje.id;
  end if;

  -- ¿El día quedó IMPOSIBLE al ordenarlo por hora? Entonces se sella para que
  -- aparezca en Correcciones. No se pierde nada, pero deja de estar en silencio.
  -- Solo se sella si de verdad quedó roto: una marca atrasada que encaja bien
  -- en la secuencia no genera ninguna alarma.
  if fn_dia_incoherente(p_persona_id, v_fecha) then
    update marcajes
      set estado_revision = 'pendiente_revision'
    where persona_id = p_persona_id
      and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
      and estado_revision = 'normal';
    select * into v_marcaje from marcajes where id = v_marcaje.id;
  end if;

  return v_marcaje;
end;
$function$;



-- ── 12 · fn_recalcular_jornada ─────────────────────────────────────────────────────────────
-- FUNCION: fn_recalcular_jornada
-- VIGENTE EN: 0249_una_salida_real_siempre_se_puede_registrar.sql
-- NECESITA_CAMBIO: si
-- NOTAS: El cuerpo actual (confirmado contra el Postgres local, md5 idéntico
--   al que trae la 0249, sin necesidad de la variante "sin comentarios") tiene
--   el candado escrito a mano en el bloque "CANDADO DE PERIODO PAGADO":
--     if exists (
--       select 1 from periodos_planilla
--       where estado = 'pagado'
--         and p_fecha between fecha_ini and fecha_fin
--     ) then
--       return;
--     end if;
--   Se reemplazó ESE fragmento por
--     if fn_fecha_en_periodo_pagado(p_fecha, p_persona_id) then
--       return;
--     end if;
--   p_persona_id es el primer parámetro de la función y es la persona dueña
--   de la jornada que se recalcula — no hace falta leerlo de ningún lado, ya
--   viene como argumento. No se tocó ninguna otra línea, variable, ni
--   comentario del cuerpo original; el resto del CANDADO (el comentario largo
--   que explica por qué se sale en silencio en vez de lanzar excepción) se
--   deja intacto porque sigue siendo cierto con el candado por grupo. No hay
--   grant/revoke/comment on function para esta función en el repo.

CREATE OR REPLACE FUNCTION public.fn_recalcular_jornada(p_persona_id uuid, p_fecha date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare
  v_marcaje record;
  v_entrada_ts timestamptz;
  v_salida_final_ts timestamptz;
  v_salida_final_origen origen_marca;
  v_salida_final_revision estado_revision;
  v_ausencia_inicio timestamptz;
  v_total_ausencia interval := interval '0';
  v_horas_imposibles boolean := false;   -- 0249: la resta dio negativo
  v_abierta_temporal boolean := false;
  v_sede_id uuid;
  v_hora_entrada_prog time;
  v_hora_salida_prog time;
  v_refri_prog int := 0;
  v_es_descanso boolean := false;
  v_hpd jsonb;
  v_hora_entrada_legacy time;
  v_hora_salida_legacy time;
  v_dow text;
  v_minutos_tarde int;
  v_sujeta_a_horario boolean;   -- 0191: un locador no tiene hora de entrada
  v_minutos_temprano int;
  v_horas_prog numeric;
  v_horas_extra numeric(6,2) := 0;
  v_horas_trabajadas numeric(6,2);
  v_estado estado_jornada;
  v_hora_entrada_esperada timestamptz;
  v_hora_salida_esperada timestamptz;
  v_n_marcajes int;
begin
  -- ── CANDADO DE PERIODO PAGADO ──────────────────────────────────────────────
  -- Un día que cae dentro de un periodo con estado 'pagado' NO se vuelve a
  -- calcular. Ni por una marca que sube tarde desde la cola offline, ni porque
  -- alguien cambie un horario que abarca meses hacia atrás.
  --
  -- Se SALE en silencio en vez de lanzar excepción, y es a propósito: este
  -- cuerpo lo ejecuta un trigger sobre `marcajes`. Lanzar aquí abortaría el
  -- INSERT, la terminal reintentaría seis veces y acabaría descartando una
  -- marca REAL de una persona que sí estuvo. Perder el registro de un hecho es
  -- peor que tener un día pagado que no coincide con él: los marcajes son la
  -- fuente de verdad y son append-only. La marca entra; lo que no se mueve es
  -- el número que ya se pagó.
  --
  -- El día no queda mudo: la marca atrasada rompe la secuencia del día,
  -- fn_dia_incoherente lo sella y aparece en Correcciones. Probado en la 110.
  --
  -- El candado se levanta solo: lee el estado del periodo en cada llamada, así
  -- que revertir el pago (fn_revertir_pago, con motivo obligatorio) devuelve el
  -- recálculo sin tocar nada más.
  if fn_fecha_en_periodo_pagado(p_fecha, p_persona_id) then
    return;
  end if;

  select count(*) into v_n_marcajes
  from marcajes
  where persona_id = p_persona_id
    -- 0240 · La jornada manda, no el calendario. `fecha_jornada` solo trae
    -- valor cuando una marca cierra una jornada abierta del día anterior —
    -- alguien que cruzó la medianoche—; en todo lo demás es null y esto se
    -- comporta exactamente igual que antes.
    and coalesce(fecha_jornada, (timestamp_marca at time zone 'America/Lima')::date) = p_fecha
    and anulada_at is null;

  if v_n_marcajes = 0 then
    delete from jornadas where persona_id = p_persona_id and fecha = p_fecha;
    return;
  end if;

  for v_marcaje in
    select * from marcajes
    where persona_id = p_persona_id
    -- 0240 · La jornada manda, no el calendario. `fecha_jornada` solo trae
    -- valor cuando una marca cierra una jornada abierta del día anterior —
    -- alguien que cruzó la medianoche—; en todo lo demás es null y esto se
    -- comporta exactamente igual que antes.
    and coalesce(fecha_jornada, (timestamp_marca at time zone 'America/Lima')::date) = p_fecha
      and anulada_at is null
    order by timestamp_marca asc
  loop
    v_sede_id := coalesce(v_sede_id, v_marcaje.sede_id);
    if v_marcaje.tipo = 'entrada' then
      v_entrada_ts := coalesce(v_entrada_ts, v_marcaje.timestamp_marca);
    elsif v_marcaje.tipo = 'salida_final' then
      v_salida_final_ts := v_marcaje.timestamp_marca;
      v_salida_final_origen := v_marcaje.origen;
      v_salida_final_revision := v_marcaje.estado_revision;
    elsif v_marcaje.tipo::text like 'salida\_%' escape '\' then
      v_ausencia_inicio := v_marcaje.timestamp_marca;
      v_abierta_temporal := true;
    elsif v_marcaje.tipo::text like 'retorno\_%' escape '\' then
      if v_abierta_temporal and v_ausencia_inicio is not null then
        v_total_ausencia := v_total_ausencia + (v_marcaje.timestamp_marca - v_ausencia_inicio);
      end if;
      v_abierta_temporal := false;
      v_ausencia_inicio := null;
    end if;
  end loop;

  -- horario programado del día: turno → horario por día (jsonb) → hora única legacy.
  -- ¿Esta persona está sujeta a un horario? Un locador (rxh) presta un
  -- servicio, no cumple una jornada: la ley no le fija hora de entrada, y el
  -- sistema tampoco debe medírsela. Ver el encabezado de la 0191.
  select p.en_planilla into v_sujeta_a_horario from personas p where p.id = p_persona_id;

  v_dow := extract(dow from p_fecha)::int::text; -- 0=domingo … 6=sábado
  select hora_entrada, hora_salida, es_descanso
    into v_hora_entrada_prog, v_hora_salida_prog, v_es_descanso
  from turnos where persona_id = p_persona_id and fecha = p_fecha;
  if not found then
    select horario_por_dia, hora_entrada, hora_salida
      into v_hpd, v_hora_entrada_legacy, v_hora_salida_legacy
    from horarios_asignados
    where persona_id = p_persona_id and vigente_desde <= p_fecha
      and (vigente_hasta is null or vigente_hasta >= p_fecha)
    order by vigente_desde desc limit 1;
    if found then
      if v_hpd is not null then
        v_hora_entrada_prog := (v_hpd -> v_dow ->> 'e')::time; -- null si ese día es descanso
        v_hora_salida_prog  := (v_hpd -> v_dow ->> 's')::time;
        v_refri_prog        := coalesce((v_hpd -> v_dow ->> 'r')::int, 0);
      else
        v_hora_entrada_prog := v_hora_entrada_legacy;
        v_hora_salida_prog  := v_hora_salida_legacy;
      end if;
    end if;
  elsif v_es_descanso then
    v_hora_entrada_prog := null; -- descanso del turno: no se mide nada
    v_hora_salida_prog := null;
  end if;

  -- tardanza de entrada (SIN tolerancia, pero por MINUTO: los segundos dentro del
  -- minuto de entrada no cuentan — 07:45:00–07:45:59 es puntual, 07:46:00 es 1 min).
  v_minutos_tarde := null;
  if coalesce(v_sujeta_a_horario, false)
     and v_entrada_ts is not null and v_hora_entrada_prog is not null then
    v_hora_entrada_esperada := (p_fecha + v_hora_entrada_prog) at time zone 'America/Lima';
    v_minutos_tarde := greatest(0, floor(extract(epoch from (v_entrada_ts - v_hora_entrada_esperada)) / 60)::int);
    -- Acá se ponía `v_minutos_tarde := null`. Ya no: el número se guarda
    -- siempre y quién puede sancionar con él lo decide fn_tardanza_es_medible.
  end if;

  v_horas_trabajadas := null;
  if v_entrada_ts is not null and v_salida_final_ts is not null then
    v_horas_trabajadas := round(extract(epoch from ((v_salida_final_ts - v_entrada_ts) - v_total_ausencia)) / 3600.0, 2);

    -- ⇩⇩⇩ CAMBIO 0249 ⇩⇩⇩ UN NEGATIVO NO SE GUARDA, PERO TAMPOCO TUMBA LA MARCA.
    --
    -- Hasta acá, un negativo llegaba al `insert` de abajo y `chk_horas_no_negativas`
    -- (0095) lo rechazaba. Pero el `insert` de la jornada NO va solo: cuelga del
    -- trigger de `marcajes`, así que la excepción sube y se lleva por delante EL
    -- MARCAJE ENTERO. O sea que un día con las pausas descuadradas hacía que la
    -- salida de esa persona fuera IMPOSIBLE de registrar — el terminal le seguía
    -- ofreciendo «Salida» toda la noche y cada intento se iba a la cola hasta
    -- apartarse. Medido el 2026-08-14 contra el Postgres local, y visto antes en
    -- producción: dos salidas apartadas con este mismo error.
    --
    -- Es la regla que la 0068 ya dejó escrita y que la 0207 repite: perder el
    -- registro de alguien que sí estuvo es peor que un día que no cuadra.
    --
    -- NULL Y NO CERO, y la diferencia importa: cero dice «no trabajó», null dice
    -- «no se sabe cuánto». Es lo mismo que hizo la 0095 al limpiar los negativos
    -- que ya existían. La planilla lee `coalesce(horas_trabajadas, 0)`, así que
    -- de momento paga igual — por eso el día NO puede quedarse callado, y de eso
    -- se encarga el sello del final.
    if v_horas_trabajadas < 0 then
      v_horas_imposibles := true;
      v_horas_trabajadas := null;
    end if;
  end if;

  -- salida anticipada: cerró el día antes de su hora de salida programada.
  -- Tolerancia de 15 min: dentro de 15 min de su hora no se marca (queda en 0).
  -- No se mide mientras el auto-cierre siga SIN REVISAR: esa hora la inventó el
  -- sistema y medir contra ella sería acusar con un dato falso. En cuanto una
  -- persona la confirma o la corrige, la hora es real y el día se mide entero.
  v_minutos_temprano := null;
  if coalesce(v_sujeta_a_horario, false)
     and v_salida_final_ts is not null and v_hora_salida_prog is not null
     and not (v_salida_final_origen = 'auto_cierre'
              and v_salida_final_revision = 'pendiente_revision') then
    v_hora_salida_esperada := (p_fecha + v_hora_salida_prog) at time zone 'America/Lima';
    v_minutos_temprano := greatest(0, round(extract(epoch from (v_hora_salida_esperada - v_salida_final_ts)) / 60)::int);
    -- Misma corrección en la salida temprana. Esta segunda instancia no
    -- estaba en el hallazgo: arreglar solo la de la entrada dejaba la mitad.
    if v_minutos_temprano <= 15 then v_minutos_temprano := 0; -- dentro de la tolerancia
    end if;
  end if;

  -- tiempo adicional: trabajó más que sus horas programadas del día (neto de refrigerio).
  -- Tolerancia de 15 min (0.25 h): dentro de eso no se marca (queda en 0).
  -- Misma regla que arriba: sin revisar no se mide; revisada, sí.
  v_horas_extra := 0;
  if v_horas_trabajadas is not null and v_hora_entrada_prog is not null and v_hora_salida_prog is not null
     and not (v_salida_final_origen = 'auto_cierre'
              and v_salida_final_revision = 'pendiente_revision') then
    v_horas_prog := greatest(0, (extract(epoch from (v_hora_salida_prog - v_hora_entrada_prog)) / 3600.0) - (v_refri_prog / 60.0));
    v_horas_extra := greatest(0, round((v_horas_trabajadas - v_horas_prog)::numeric, 2));
    if v_horas_extra <= 0.25 then v_horas_extra := 0; end if; -- dentro de la tolerancia
  end if;

  if v_salida_final_ts is not null then
    if v_salida_final_origen = 'auto_cierre' and v_salida_final_revision = 'pendiente_revision' then
      v_estado := 'auto_cerrada_pendiente';
    elsif v_salida_final_origen = 'auto_cierre' and v_salida_final_revision = 'revisada' then
      v_estado := 'revisada';
    else
      v_estado := 'cerrada';
    end if;
  elsif v_abierta_temporal then
    v_estado := 'en_pausa';
  else
    v_estado := 'abierta';
  end if;

  insert into jornadas (
    persona_id, fecha, sede_id, entrada_ts, salida_final_ts,
    minutos_tarde, minutos_salida_temprana, horas_trabajadas, horas_extra_detectadas,
    estado, tiene_salida_no_retornada, updated_at
  ) values (
    p_persona_id, p_fecha, v_sede_id, v_entrada_ts, v_salida_final_ts,
    v_minutos_tarde, v_minutos_temprano, v_horas_trabajadas, v_horas_extra,
    v_estado, v_abierta_temporal, now()
  )
  on conflict (persona_id, fecha) do update set
    sede_id = excluded.sede_id,
    entrada_ts = excluded.entrada_ts,
    salida_final_ts = excluded.salida_final_ts,
    minutos_tarde = excluded.minutos_tarde,
    minutos_salida_temprana = excluded.minutos_salida_temprana,
    horas_trabajadas = excluded.horas_trabajadas,
    horas_extra_detectadas = excluded.horas_extra_detectadas,
    estado = excluded.estado,
    tiene_salida_no_retornada = excluded.tiene_salida_no_retornada,
    updated_at = now();

  -- ── 0249 · Y el día imposible se señala, en vez de pagarse como cero ───────
  -- Sin esto el arreglo de arriba sería peor que el problema: la marca entraría,
  -- la jornada quedaría sin horas y la planilla la pagaría como 0 h sin que nadie
  -- se entere. Un descuento silencioso es exactamente lo que este sistema no
  -- puede hacer.
  --
  -- Se usa el mismo sello que ya existe para el día incoherente (0068), así que
  -- el día aparece en Correcciones sin pantalla nueva ni concepto nuevo.
  --
  -- `estado_revision = 'normal'` NO es un filtro de cortesía: es lo que corta la
  -- recursión. Este update dispara el trigger de `marcajes`, que vuelve a llamar
  -- a esta función; en esa segunda vuelta las marcas ya están selladas, el update
  -- toca 0 filas y no hay tercera. La profundidad es 2, siempre.
  if v_horas_imposibles then
    update marcajes
      set estado_revision = 'pendiente_revision'
    where persona_id = p_persona_id
      and coalesce(fecha_jornada, (timestamp_marca at time zone 'America/Lima')::date) = p_fecha
      and anulada_at is null
      and estado_revision = 'normal';
  end if;
end;
$function$;



-- ── 13 · fn_reabrir_dia ─────────────────────────────────────────────────────────────
-- FUNCION: fn_reabrir_dia
-- VIGENTE EN: 0318_reabrir_el_dia_no_toca_la_salida_de_anoche.sql (confirmado con
--             ./scripts/donde-vive.sh fn_reabrir_dia; hay una versión anterior en
--             0137 pero esa no es la vigente). El cuerpo de abajo se copió del
--             pg_get_functiondef del Postgres local, que coincide byte a byte con
--             lo escrito en 0318 (md5 tal cual 291b5832218258c618e3434aa0634093,
--             igual al "MD5 DE LLEGADA" que la propia 0318 declara en su
--             encabezado).
-- NECESITA_CAMBIO: si
-- NOTAS: El candado por periodo pagado estaba escrito a mano:
--   `if exists (select 1 from periodos_planilla where estado = 'pagado' and
--   v_hoy between fecha_ini and fecha_fin) then raise exception ...`.
--   Se reemplazó ESE `exists` completo por
--   `fn_fecha_en_periodo_pagado(v_hoy, p_persona_id)`. `p_persona_id` es el
--   parámetro de la función y es la persona DUEÑA del marcaje que se reabre
--   (la salida final que se anula y se reemplaza por salida_otro/retorno_otro
--   le pertenece a ella) — es el candado correcto, no `auth.uid()` ni ningún
--   id de quien opera el terminal. No se tocó ninguna otra línea, comentario
--   ni variable; no hay grant/revoke/comment on que copiar (0318 no los
--   declara para esta función).

CREATE OR REPLACE FUNCTION public.fn_reabrir_dia(p_persona_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_term_id   uuid;
  v_term_sede uuid;
  v_cierre    marcajes;
  v_hoy       date;
  v_retorno   uuid;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo del regreso es obligatorio.';
  end if;

  -- El terminal se deriva de la sesión (ver punto 3 del encabezado).
  select t.id, t.sede_id into v_term_id, v_term_sede
  from terminales t
  where t.auth_user_id = auth.uid()
    and t.activo is true;
  if v_term_id is null then
    raise exception 'Esta operación solo se hace desde una terminal activa.';
  end if;

  -- `fn_hoy_lima()` y no `current_date`: el servidor corre en UTC, y a partir de
  -- las 19:00 de Lima `current_date` ya devuelve el día siguiente. Lo blinda la
  -- prueba 92.
  v_hoy := fn_hoy_lima();

  select * into v_cierre
  from marcajes m
  where m.persona_id = p_persona_id
    and m.tipo = 'salida_final'
    and m.anulada_at is null
    -- ⇩⇩⇩ CAMBIO 0318 ⇩⇩⇩ LA JORNADA MANDA SOBRE EL CALENDARIO.
    --
    -- Acá decía solo `(m.timestamp_marca at time zone 'America/Lima')::date =
    -- v_hoy`, y con eso esta función ANULABA LA SALIDA REAL DE ANOCHE.
    --
    -- Quien cierra tienda a las 00:30 tiene su salida guardada con la
    -- `fecha_jornada` del día anterior — eso lo hace bien la 0240. Pero por
    -- calendario esa marca ES de hoy, así que era la que encontraba este
    -- `select`, y el `update` de abajo la anulaba.
    --
    -- Medido contra el Postgres local, con el caso del informe de agosto: Ana
    -- entra el martes 15:00 y cierra a las 00:30 del miércoles. Jornada del
    -- martes: 9,50 h cerradas, S/109,62. Tras pulsar «Sí, volví a entrar»: sin
    -- horas, abierta, S/0,00.
    --
    -- `coalesce` y no `fecha_jornada = v_hoy` a secas: las marcas normales NO
    -- llevan esa columna —solo la lleva la salida que cruza medianoche— así que
    -- exigirla dejaría sin poder reabrir a todo el mundo. El caso corriente es
    -- el null.
    --
    -- ESTA ES LA SEGUNDA BARRERA, no la primera. El terminal ya no muestra esa
    -- pantalla desde que reparte por `fecha_jornada`
    -- (`jornadaEnCursoPorPersona`), así que el botón no se pulsa. Esto cubre lo
    -- que quede: una pestaña vieja abierta desde ayer, o la cola offline
    -- reenviando algo. Las dos mitades del par se arreglan juntas, que es la
    -- lección que este repo lleva pagando todo agosto.
    and coalesce(m.fecha_jornada,
                 (m.timestamp_marca at time zone 'America/Lima')::date) = v_hoy
  order by m.timestamp_marca desc
  limit 1
  for update;

  if not found then
    raise exception 'No hay una salida final de hoy para reabrir.';
  end if;

  -- Cada sede reabre lo suyo. Se compara contra la sede DEL MARCAJE y no contra
  -- la sede base de la persona: quien viaja entre sedes marcó su salida donde
  -- estaba, y es esa terminal la que puede corregirla.
  if v_cierre.sede_id <> v_term_sede then
    raise exception 'Esa marca es de otra sede: se reabre desde la terminal donde se marcó.';
  end if;

  if fn_fecha_en_periodo_pagado(v_hoy, p_persona_id) then
    raise exception 'Ese día cae en un periodo ya PAGADO: reabrirlo alteraría una planilla pagada. Reabre el periodo primero.';
  end if;

  update marcajes
     set anulada_at     = now(),
         anulada_por    = p_persona_id,
         anulada_motivo = 'Día reabierto desde terminal: ' || trim(p_motivo)
   where id = v_cierre.id;

  -- La salida vuelve a emitirse como temporal, en el MISMO instante que la
  -- original: el rato de afuera tiene que descontarse desde que se fue, no desde
  -- que el sistema se enteró.
  insert into marcajes
    (client_uuid, persona_id, sede_id, terminal_id, tipo, motivo_otro, timestamp_marca, origen)
  values
    (gen_random_uuid(), p_persona_id, v_cierre.sede_id, v_term_id,
     'salida_otro', trim(p_motivo), v_cierre.timestamp_marca, 'terminal');

  insert into marcajes
    (client_uuid, persona_id, sede_id, terminal_id, tipo, timestamp_marca, origen)
  values
    (gen_random_uuid(), p_persona_id, v_cierre.sede_id, v_term_id,
     'retorno_otro', now(), 'terminal')
  returning id into v_retorno;

  insert into correcciones_auditoria
    (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_cierre.id, p_persona_id, 'dia_reabierto_desde_terminal',
     'salida_final @ ' || v_cierre.timestamp_marca::text,
     'salida_otro (mismo instante) + retorno_otro',
     p_persona_id, trim(p_motivo));

  -- El trigger de marcajes ya recalcula; esto lo deja explícito para quien lea
  -- la función sin conocerlo, y es idempotente.
  perform fn_recalcular_jornada(p_persona_id, v_hoy);

  return jsonb_build_object('ok', true, 'marcaje_retorno_id', v_retorno);
end;
$function$;



-- ── 14 · fn_auto_cierre ─────────────────────────────────────────────────────────────
-- FUNCION: fn_auto_cierre
-- VIGENTE EN: 0203_lo_que_se_congela_al_pagar_se_descongela_al_reabrir.sql
-- NECESITA_CAMBIO: si
-- NOTAS: El candado está en la línea
--   `and fn_fecha_en_periodo_pagado(j.fecha) is not true`
--   dentro del cursor `for v_candidata in ... from jornadas j ...` que
--   decide qué jornadas abiertas/en_pausa son candidatas a auto-cierre. Es
--   el caso fácil: solo se le agrega el segundo argumento. La persona dueña
--   de la jornada que se está tocando es `j.persona_id` (columna propia de
--   `jornadas` en esa misma consulta) — no `fn_persona_actual_id()` (no
--   aplica: este cron no lo dispara ninguna sesión logueada) ni ningún otro
--   id. Único cambio: `fn_fecha_en_periodo_pagado(j.fecha)` pasa a
--   `fn_fecha_en_periodo_pagado(j.fecha, j.persona_id)`. Ninguna otra línea,
--   comentario o nombre de variable se tocó. El cuerpo de partida se trajo
--   con `pg_get_functiondef` contra el Postgres local y es carácter por
--   carácter idéntico al de la migración 0203 (confirmado con `docker exec`
--   + `Read` del archivo), así que no hay divergencia que declarar.

CREATE OR REPLACE FUNCTION public.fn_auto_cierre()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_horas int;
  v_hoy_lima date := (now() at time zone 'America/Lima')::date;
  v_candidata record;
  v_ts_cierre timestamptz;
  v_cerradas int := 0;
begin
  select (valor #>> '{}')::int into v_horas from configuracion where clave = 'auto_cierre_horas';
  v_horas := coalesce(v_horas, 3);

  for v_candidata in
    select
      j.id as jornada_id,
      j.persona_id,
      j.fecha,
      j.sede_id,
      h.hora_salida
    from jornadas j
    -- cascada turno del día → horario_por_dia → legacy, igual que
    -- fn_recalcular_jornada, en vez de leer horarios_asignados.hora_salida directo
    left join lateral (
      select case
        when t.fecha is not null and t.es_descanso then null
        when t.fecha is not null then t.hora_salida
        when ha.horario_por_dia is not null
          then (ha.horario_por_dia -> extract(dow from j.fecha)::int::text ->> 's')::time
        else ha.hora_salida
      end as hora_salida
      from (select 1) uno
      left join turnos t on t.persona_id = j.persona_id and t.fecha = j.fecha
      left join lateral (
        select horario_por_dia, hora_salida
        from horarios_asignados
        where persona_id = j.persona_id
          and vigente_desde <= j.fecha
          and (vigente_hasta is null or vigente_hasta >= j.fecha)
        order by vigente_desde desc limit 1
      ) ha on true
    ) h on true
    where j.estado in ('abierta', 'en_pausa')
      -- 0203 · Un día de un mes ya PAGADO no se auto-cierra. Este cron corre de
      -- madrugada, sin que nadie lo pulse: inventarle una salida a un día ya
      -- pagado es escribir en un mes cerrado sin nadie mirando. Y encima no
      -- serviría de nada — fn_recalcular_jornada tampoco lo recalcularía (candado
      -- de la 0138, hoy en la 0191): quedaría una marca sintética que no cambia
      -- ninguna cifra y una alerta que nadie puede atender. La jornada se queda
      -- abierta y visible en Correcciones, que es donde una persona decide.
      and fn_fecha_en_periodo_pagado(j.fecha, j.persona_id) is not true
      and (
        (h.hora_salida is not null
          and now() >= ((j.fecha + h.hora_salida) at time zone 'America/Lima') + make_interval(hours => v_horas))
        or (h.hora_salida is null and j.fecha < v_hoy_lima)
      )
  loop
    if v_candidata.hora_salida is not null then
      -- La salida inventada NUNCA puede caer antes de una marca real. Si la
      -- persona entró después de su hora programada de salida (turno cambiado,
      -- evento nocturno, cierre de inventario) el auto-cierre ponía la salida
      -- ANTES de la entrada, y fn_recalcular_jornada restaba sin ningún piso:
      -- horas NEGATIVAS que fn_planilla_calcular suma tal cual. El día trabajado
      -- le RESTABA horas del mes a quien sí lo trabajó.
      v_ts_cierre := greatest(
        (v_candidata.fecha + v_candidata.hora_salida) at time zone 'America/Lima',
        (select max(m.timestamp_marca) from marcajes m
          where m.persona_id = v_candidata.persona_id
            and (m.timestamp_marca at time zone 'America/Lima')::date = v_candidata.fecha
            and m.anulada_at is null));
    else
      select max(timestamp_marca) into v_ts_cierre
      from marcajes
      where persona_id = v_candidata.persona_id
        and (timestamp_marca at time zone 'America/Lima')::date = v_candidata.fecha
        and anulada_at is null;
    end if;

    if v_ts_cierre is null then
      continue;
    end if;

    -- Nunca poner una segunda salida final donde ya hay una viva.
    -- El caso: se anula la salida_final de un día y la jornada vuelve a estado
    -- 'abierta', que es justo lo que este bucle recoge — así que por la noche el
    -- cron le inventaba otra. Y si después alguien reactivaba la original, el día
    -- acababa con DOS salidas finales y el recálculo se quedaba con la última por
    -- hora, con desempate arbitrario cuando coinciden.
    if exists (
      select 1 from marcajes
      where persona_id = v_candidata.persona_id
        and tipo = 'salida_final'
        and (timestamp_marca at time zone 'America/Lima')::date = v_candidata.fecha
        and anulada_at is null
    ) then
      continue;
    end if;

    insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision)
    values (gen_random_uuid(), v_candidata.persona_id, v_candidata.sede_id, 'salida_final', v_ts_cierre, 'auto_cierre', 'pendiente_revision');

    insert into alertas (persona_id, tipo, canal, payload)
    values (
      v_candidata.persona_id,
      'auto_cierre',
      'push',
      jsonb_build_object('fecha', v_candidata.fecha, 'jornada_id', v_candidata.jornada_id, 'ts_cierre', v_ts_cierre)
    );

    v_cerradas := v_cerradas + 1;
  end loop;

  return v_cerradas;
end;
$function$;

grant execute on function fn_auto_cierre() to authenticated;
revoke execute on function fn_auto_cierre() from public, anon;



-- ── 15 · fn_set_turno ─────────────────────────────────────────────────────────────
-- FUNCION: fn_set_turno
-- VIGENTE EN: 0298_un_turno_que_cambia_deja_rastro.sql
-- NECESITA_CAMBIO: si
-- NOTAS: El candado estaba escrito a mano — `exists (select 1 from
--   periodos_planilla where estado = 'pagado' and p_fecha between fecha_ini
--   and fecha_fin)` — mirando el periodo entero. Se reemplazó ese `exists`
--   completo por `fn_fecha_en_periodo_pagado(p_fecha, p_persona_id)`, usando
--   `p_persona_id` (el primer parámetro de la función: la persona dueña del
--   turno que se está editando, no quien hace el clic — eso es v_editor,
--   que sale de fn_verificar_corrector y no se toca). Ningún otro cambio: se
--   conserva el mensaje de la excepción, el comentario "CAMBIO 0298" y todo
--   lo demás tal cual. La firma de la función no cambia (sigue siendo
--   (uuid, date, time, time)), así que el `grant execute` de la 0014 sigue
--   siendo válido sin reescribirlo.

create or replace function fn_set_turno(p_persona_id uuid, p_fecha date, p_hora_entrada time, p_hora_salida time)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_editor uuid;
  v_antes  turnos;
  v_txt_antes text;
  v_txt_ahora text;
begin
  v_editor := fn_verificar_corrector(p_persona_id); -- valida permiso o lanza excepción
  if p_hora_entrada is null then
    raise exception 'La hora de entrada del turno es obligatoria.';
  end if;
  if fn_fecha_en_periodo_pagado(p_fecha, p_persona_id) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: cambiar el turno alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  -- CAMBIO 0298 — se guarda lo que había ANTES de pisarlo.
  select * into v_antes from turnos where persona_id = p_persona_id and fecha = p_fecha;

  insert into turnos (persona_id, fecha, hora_entrada, hora_salida, es_descanso, origen,
                      created_at, creado_por)
  values (p_persona_id, p_fecha, p_hora_entrada, p_hora_salida, false, 'panel',
          now(), v_editor)
  on conflict (persona_id, fecha) do update set
    hora_entrada = excluded.hora_entrada,
    hora_salida  = excluded.hora_salida,
    es_descanso  = false,
    origen       = 'panel',
    created_at   = now(),
    creado_por   = v_editor;

  v_txt_antes := case when v_antes.persona_id is null then '(sin turno)'
                      else fn_turno_texto(v_antes.es_descanso, v_antes.hora_entrada, v_antes.hora_salida) end;
  v_txt_ahora := fn_turno_texto(false, p_hora_entrada, p_hora_salida);

  if v_txt_antes is distinct from v_txt_ahora then
    insert into correcciones_auditoria
      (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (null, p_persona_id, 'turnos.horario', v_txt_antes, v_txt_ahora, v_editor,
            'Turno del ' || to_char(p_fecha, 'DD/MM/YYYY')
            || ' cambiado desde la pantalla de Turnos. El turno del día manda sobre el horario base, '
            || 'así que esto cambia lo que se esperaba de esa persona ese día.');
  end if;

  perform fn_recalcular_jornada(p_persona_id, p_fecha);
end;
$$;



-- ── 16 · fn_quitar_turno ─────────────────────────────────────────────────────────────
-- FUNCION: fn_quitar_turno
-- VIGENTE EN: 0298_un_turno_que_cambia_deja_rastro.sql
-- NECESITA_CAMBIO: si
-- NOTAS: El candado estaba escrito a mano (`exists (select 1 from
--         periodos_planilla where estado = 'pagado' and p_fecha between
--         fecha_ini and fecha_fin)`), no como llamada a
--         fn_fecha_en_periodo_pagado. Se reemplazó ese `exists` completo por
--         `fn_fecha_en_periodo_pagado(p_fecha, p_persona_id)` — el
--         persona_id es directamente el parámetro de la función (el dueño
--         del turno que se está quitando), no hizo falta leerlo de ninguna
--         tabla. Confirmado contra el cuerpo vigente en el Postgres local vía
--         pg_get_functiondef (una sola fila, coincide con 0298 byte a byte
--         salvo el estilo de $$ que usa pg_get_functiondef). No hay
--         grant/revoke/comment on function que copiar: el único grant de
--         esta función vive en la 0014 con la firma (uuid, date), que no
--         cambia. Ningún otro comentario ni variable se tocó.

create or replace function fn_quitar_turno(p_persona_id uuid, p_fecha date)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_editor uuid;
  v_antes  turnos;
begin
  v_editor := fn_verificar_corrector(p_persona_id);
  if fn_fecha_en_periodo_pagado(p_fecha, p_persona_id) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: quitar el turno alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  -- CAMBIO 0298 — Esta es la que más lo necesitaba: BORRA la fila, así que sin
  -- esto no quedaba ni el valor anterior en ningún sitio.
  select * into v_antes from turnos where persona_id = p_persona_id and fecha = p_fecha;

  if v_antes.persona_id is not null then
    insert into correcciones_auditoria
      (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (null, p_persona_id, 'turnos.horario',
            fn_turno_texto(v_antes.es_descanso, v_antes.hora_entrada, v_antes.hora_salida),
            '(sin turno)', v_editor,
            'Turno del ' || to_char(p_fecha, 'DD/MM/YYYY') || ' quitado desde la pantalla de Turnos. '
            || 'Ese día vuelve a medirse contra el horario base de la persona.');
  end if;

  delete from turnos where persona_id = p_persona_id and fecha = p_fecha;
  perform fn_recalcular_jornada(p_persona_id, p_fecha);
end;
$function$;



-- ── 17 · fn_set_descanso ─────────────────────────────────────────────────────────────
-- FUNCION: fn_set_descanso
-- VIGENTE EN: 0298_un_turno_que_cambia_deja_rastro.sql
-- NECESITA_CAMBIO: si
-- NOTAS: Caso normal. El cuerpo vigente (confirmado byte a byte contra el
--   Postgres local con pg_get_functiondef, una sola fila) tenía el candado
--   escrito a mano: `exists (select 1 from periodos_planilla where estado =
--   'pagado' and p_fecha between fecha_ini and fecha_fin)`. Se reemplazó ESE
--   fragmento completo por `fn_fecha_en_periodo_pagado(p_fecha, p_persona_id)`
--   — p_persona_id es un parámetro directo de la función y es la persona
--   dueña del turno que se está tocando (no quien hace clic; fn_verificar_corrector
--   ya se llama aparte para el permiso de quien edita). Ningún otro
--   fragmento del cuerpo se tocó: mismas variables, mismo comentario de
--   auditoría, mismo mensaje de excepción.

create or replace function fn_set_descanso(p_persona_id uuid, p_fecha date)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_editor uuid;
  v_antes  turnos;
  v_txt_antes text;
begin
  v_editor := fn_verificar_corrector(p_persona_id);
  if fn_fecha_en_periodo_pagado(p_fecha, p_persona_id) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: marcar descanso ahí alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  select * into v_antes from turnos where persona_id = p_persona_id and fecha = p_fecha;

  insert into turnos (persona_id, fecha, hora_entrada, hora_salida, es_descanso, origen,
                      created_at, creado_por)
  values (p_persona_id, p_fecha, null, null, true, 'panel', now(), v_editor)
  on conflict (persona_id, fecha) do update set
    hora_entrada = null,
    hora_salida  = null,
    es_descanso  = true,
    origen       = 'panel',
    created_at   = now(),
    creado_por   = v_editor;

  v_txt_antes := case when v_antes.persona_id is null then '(sin turno)'
                      else fn_turno_texto(v_antes.es_descanso, v_antes.hora_entrada, v_antes.hora_salida) end;

  if v_txt_antes is distinct from 'descanso' then
    insert into correcciones_auditoria
      (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (null, p_persona_id, 'turnos.horario', v_txt_antes, 'descanso', v_editor,
            'El ' || to_char(p_fecha, 'DD/MM/YYYY') || ' pasa a descanso desde la pantalla de Turnos. '
            || 'Ese día deja de esperarse trabajo, así que deja de poder contarse como falta.');
  end if;

  perform fn_recalcular_jornada(p_persona_id, p_fecha);
end;
$function$;



-- ── 18 · fn_set_horario_semanal ─────────────────────────────────────────────────────────────
-- FUNCION: fn_set_horario_semanal
-- VIGENTE EN: 0180_el_candado_de_pagado_vuelve_a_las_seis_que_lo_perdieron.sql
-- NECESITA_CAMBIO: si
-- NOTAS: Caso normal, pero NO calza en ninguno de los dos moldes del diseño.
--   El cuerpo vigente (confirmado byte a byte contra el Postgres local con
--   pg_get_functiondef, una sola fila, idéntico línea a línea al archivo
--   0180) tiene el candado escrito a mano así:
--     exists (select 1 from periodos_planilla
--             where estado = 'pagado' and fecha_fin >= p_vigente_desde)
--   Esto NO es "la fecha cae entre fecha_ini y fecha_fin" (no hay tope
--   inferior): es "existe algún periodo, desde el que contiene
--   p_vigente_desde en adelante, que ya está pagado" — a propósito, porque
--   este horario nuevo puede recalcular jornadas de VARIOS periodos futuros
--   (el bucle final recorre `jornadas ... where fecha >= p_vigente_desde`
--   sin techo). Reemplazarlo por una sola llamada a
--   fn_fecha_en_periodo_pagado(p_vigente_desde, p_persona_id) habría
--   angostado el candado al periodo que contiene esa fecha nada más,
--   dejando pasar el caso real de este sistema (reabrir un periodo viejo
--   para corregir mientras uno posterior ya se pagó). Así que se conservó
--   EXACTO el alcance original (`fecha_fin >= p_vigente_desde`, sin
--   fecha_ini) y solo se sustituyó qué cuenta como "pagado": de
--   `periodos_planilla.estado = 'pagado'` (periodo entero) al mismo criterio
--   por grupo que usa fn_fecha_en_periodo_pagado por dentro (grupo de
--   personas.tipo_vinculo en periodo_grupo_pago, con el mismo respaldo de
--   compatibilidad para periodos de antes de la 0323 sin ninguna fila en
--   periodo_grupo_pago). p_persona_id es el primer parámetro de la función
--   y es la persona dueña del horario que se está tocando — no quien hace
--   clic; fn_verificar_corrector ya resuelve el permiso de quien edita
--   aparte, en la línea de arriba. Ningún otro fragmento del cuerpo se
--   tocó: mismas variables, mismo mensaje de excepción, mismos comentarios.

CREATE OR REPLACE FUNCTION public.fn_set_horario_semanal(p_persona_id uuid, p_vigente_desde date, p_horario jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_editor uuid; r record;
  k text; v jsonb;
  v_dias int[]; v_min_entrada time; v_max_salida time;
  v_refri_min int; v_refri_max int;
begin
  v_editor := fn_verificar_corrector(p_persona_id); -- valida permiso o lanza excepción

  if exists (
    select 1 from periodos_planilla pp
    where pp.fecha_fin >= p_vigente_desde
      and (
        -- Compatibilidad: un periodo con estado='pagado' pero SIN ninguna fila
        -- en periodo_grupo_pago es de antes de la 0323 (el bucket único de
        -- siempre) — se sigue leyendo por el agregado.
        (pp.estado = 'pagado' and not exists (
           select 1 from periodo_grupo_pago g where g.periodo_id = pp.id
         ))
        or
        -- El caso normal desde la 0323: el GRUPO de esta persona, no el
        -- periodo entero.
        exists (
          select 1 from periodo_grupo_pago g
          join personas pe on pe.id = p_persona_id
          where g.periodo_id = pp.id
            and g.grupo = pe.tipo_vinculo
            and g.estado = 'pagado'
        )
      )
  ) then
    raise exception 'Ese horario tocaría un periodo ya PAGADO (recalcula las jornadas desde esa fecha en adelante). Reabre el periodo primero.';
  end if;

  if p_horario is null or jsonb_typeof(p_horario) <> 'object'
     or (select count(*) from jsonb_object_keys(p_horario)) = 0 then
    raise exception 'Debe trabajar al menos un día a la semana.';
  end if;
  -- validar claves (0-6) y que cada día tenga hora de entrada
  for k, v in select * from jsonb_each(p_horario) loop
    if k !~ '^[0-6]$' then raise exception 'Día de la semana inválido: %', k; end if;
    if coalesce(v->>'e', '') = '' then raise exception 'Falta la hora de entrada del día %.', k; end if;
  end loop;

  -- resumen para columnas legacy: min entrada / max salida / días / refrigerio (min-max por día).
  -- nullif protege el casteo si 's' llegara vacío (cae a la hora de entrada).
  select array_agg((t.k)::int order by (t.k)::int),
         min((t.v->>'e')::time),
         max(coalesce(nullif(t.v->>'s', '')::time, (t.v->>'e')::time)),
         min(coalesce((t.v->>'r')::int, 0)),
         max(coalesce((t.v->>'r')::int, 0))
    into v_dias, v_min_entrada, v_max_salida, v_refri_min, v_refri_max
  from jsonb_each(p_horario) as t(k, v);

  -- reemplazar tramos que empiezan en/después de la fecha, cerrar el anterior
  delete from horarios_asignados where persona_id = p_persona_id and vigente_desde >= p_vigente_desde;
  update horarios_asignados set vigente_hasta = p_vigente_desde - 1
    where persona_id = p_persona_id and vigente_hasta is null and vigente_desde < p_vigente_desde;

  insert into horarios_asignados (
    persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
    almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horario_por_dia
  )
  values (
    p_persona_id, p_vigente_desde, null, v_min_entrada, coalesce(v_max_salida, v_min_entrada),
    v_refri_min, v_refri_max, v_dias, p_horario
  );

  -- recalcular tardanzas desde la fecha de vigencia
  for r in select fecha from jornadas where persona_id = p_persona_id and fecha >= p_vigente_desde loop
    perform fn_recalcular_jornada(p_persona_id, r.fecha);
  end loop;
end;
$function$;



-- ── 19 · fn_set_salario ─────────────────────────────────────────────────────────────
-- FUNCION: fn_set_salario
-- VIGENTE EN: 0037_candado_periodo_pagado.sql (donde-vive.sh confirmó: única
--             otra definición es la 0019, más vieja; local coincide con la
--             0037 — pg_get_functiondef devolvió una sola fila).
-- NECESITA_CAMBIO: si
-- NOTAS: El candado está en:
--   if exists (
--     select 1 from periodos_planilla where estado = 'pagado' and fecha_fin >= p_vigente_desde
--   ) then
--     raise exception 'Ese cambio de salario tocaría un periodo ya PAGADO. ...';
--   end if;
--
--   No es el patrón "between fecha_ini and fecha_fin" del caso normal: el
--   propio comentario de la migración 0037 ("el candado va sobre cualquier
--   periodo pagado que termine en o después de p_vigente_desde") lo dice a
--   propósito — un salario nuevo es de vigencia ABIERTA (vigente_hasta =
--   null), así que además del periodo que contiene p_vigente_desde hay que
--   bloquear cualquier periodo POSTERIOR que ya esté pagado, no solo uno.
--   Por eso no encaja en fn_fecha_en_periodo_pagado(fecha, persona_id), que
--   solo resuelve "¿esta fecha puntual cae dentro de un periodo pagado?".
--   Repliqué el mismo criterio interno de grupo que usa
--   fn_fecha_en_periodo_pagado (compatibilidad con periodos pre-0323 sin
--   fila en periodo_grupo_pago, y si no, el grupo de la persona vía
--   personas.tipo_vinculo) pero conservando la condición de rango original
--   (fecha_fin >= p_vigente_desde) en vez de "between". p_persona_id ya es
--   un parámetro de la función — es la persona dueña del salario que se
--   está tocando, no quien hace el clic (v_yo/fn_persona_actual_id() no se
--   usan para esto). Nada más cambió: mismos comentarios, mismo orden,
--   mismo mensaje de error.

create or replace function fn_set_salario(
  p_persona_id uuid,
  p_rango text,
  p_salario numeric,
  p_vigente_desde date,
  p_nota text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_yo uuid;
begin
  -- "is not true": fn_es_admin_o_lider() devuelve NULL para identidades autenticadas
  -- sin fila en personas (terminales) — "if not NULL" NO lanza (falla abierto).
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede asignar salarios.';
  end if;
  v_yo := fn_persona_actual_id();

  if p_persona_id is null or not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'Persona inválida.';
  end if;
  if p_rango is null or p_rango not in ('colibri','cayla','caylo','support','aurora','oraculo','archicaylo') then
    raise exception 'Rango inválido: %', coalesce(p_rango, '(vacío)');
  end if;
  if p_salario is null or p_salario <= 0 then
    raise exception 'El salario debe ser mayor a 0.';
  end if;
  if p_vigente_desde is null then
    raise exception 'La fecha de vigencia es obligatoria.';
  end if;
  if exists (
    select 1
    from periodos_planilla pp
    where pp.fecha_fin >= p_vigente_desde
      and (
        -- Compatibilidad: un periodo con estado='pagado' pero SIN ninguna fila
        -- en periodo_grupo_pago es de antes de la 0323 (el bucket único de
        -- siempre) — se sigue leyendo por el agregado.
        (pp.estado = 'pagado' and not exists (
           select 1 from periodo_grupo_pago g where g.periodo_id = pp.id
         ))
        or
        -- El caso normal desde la 0323: el GRUPO de esta persona, no el
        -- periodo entero.
        exists (
          select 1 from periodo_grupo_pago g
          join personas pe on pe.id = p_persona_id
          where g.periodo_id = pp.id
            and g.grupo = pe.tipo_vinculo
            and g.estado = 'pagado'
        )
      )
  ) then
    raise exception 'Ese cambio de salario tocaría un periodo ya PAGADO. Reabre el periodo primero si de verdad hace falta.';
  end if;

  -- serializar cambios concurrentes por persona: dos llamadas simultáneas chocarían
  -- contra el índice único de tramo abierto (unique_violation); con el lock, la
  -- segunda espera y aplica limpio.
  perform pg_advisory_xact_lock(hashtext('salario:' || p_persona_id::text));

  -- versionado: borra tramos que arrancan en/después de la fecha y recorta CUALQUIER
  -- tramo previo (abierto o cerrado) que se extienda hasta la nueva vigencia — así un
  -- cambio retro-fechado dentro de un tramo ya cerrado no deja tramos solapados.
  delete from asignaciones_salario
    where persona_id = p_persona_id and vigente_desde >= p_vigente_desde;
  update asignaciones_salario set vigente_hasta = p_vigente_desde - 1
    where persona_id = p_persona_id
      and vigente_desde < p_vigente_desde
      and (vigente_hasta is null or vigente_hasta >= p_vigente_desde);

  insert into asignaciones_salario
    (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta, asignado_por, nota)
  values
    (p_persona_id, p_rango, p_salario, p_vigente_desde, null, v_yo, nullif(trim(p_nota), ''));
end;
$$;



-- ── 20 · fn_set_fecha_ingreso ─────────────────────────────────────────────────────────────
-- FUNCION: fn_set_fecha_ingreso
-- VIGENTE EN: 0091_la_hora_de_lima_en_todo_el_sistema.sql
-- NECESITA_CAMBIO: si
-- NOTAS: Caso normal, pero el candado no llama a fn_fecha_en_periodo_pagado
--   (esta función es de antes de la 0203, cuando ese helper ni existía): el
--   cuerpo vigente (confirmado byte a byte contra el Postgres local con
--   pg_get_functiondef, una sola fila, y contra el texto de la migración
--   0091 — idénticos) trae el candado escrito a mano como un JOIN:
--   `select 1 from periodos_planilla pp join jornadas j on j.fecha between
--   pp.fecha_ini and pp.fecha_fin where pp.estado = 'pagado' and
--   j.persona_id = p_persona_id and j.horas_trabajadas is not null`. Es la
--   variante "comparando contra una variable ya leída antes" del punto 3 del
--   diseño: el join entero a periodos_planilla + su `pp.estado = 'pagado'`
--   es exactamente lo que fn_fecha_en_periodo_pagado ya resuelve por dentro,
--   así que se retira ese join y se reemplaza por una llamada a
--   `fn_fecha_en_periodo_pagado(j.fecha, p_persona_id)` sobre las jornadas
--   de la propia persona. p_persona_id es un parámetro directo de la
--   función y es la persona dueña del dato que se edita (su fecha_ingreso),
--   no quien hace clic — fn_es_admin_o_lider() sigue intacto, es la
--   comprobación de permiso de quien edita, no el candado. Ningún otro
--   fragmento del cuerpo se tocó: mismas validaciones, mismo mensaje de
--   excepción, mismo update final.

CREATE OR REPLACE FUNCTION public.fn_set_fecha_ingreso(p_persona_id uuid, p_fecha date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar la fecha de ingreso.';
  end if;
  if p_fecha is null then raise exception 'La fecha de ingreso es obligatoria.'; end if;
  if p_fecha > fn_hoy_lima() then raise exception 'La fecha de ingreso no puede ser futura.'; end if;
  if exists (
    select 1 from jornadas j
    where j.persona_id = p_persona_id
      and j.horas_trabajadas is not null
      and fn_fecha_en_periodo_pagado(j.fecha, p_persona_id)
  ) then
    raise exception 'Esta persona ya tiene un periodo PAGADO con jornadas trabajadas: cambiar su fecha de ingreso podría alterar los feriados de esa planilla. Reabre el periodo primero.';
  end if;
  update personas set fecha_ingreso = p_fecha where id = p_persona_id;
  if not found then raise exception 'Persona inválida.'; end if;
end;
$function$;



-- ── 21 · fn_cesar_persona ─────────────────────────────────────────────────────────────
-- FUNCION: fn_cesar_persona
-- VIGENTE EN: 0176_quien_ya_se_fue_deja_de_tener_sueldo_vigente.sql
-- NECESITA_CAMBIO: si
-- NOTAS: el candado estaba escrito a mano —
--   `exists (select 1 from periodos_planilla pp where pp.estado = 'pagado'
--   and p_fecha_cese between pp.fecha_ini and pp.fecha_fin)` — bloqueando
--   por PERIODO ENTERO. Se reemplazó ese `exists` completo por una llamada
--   a `fn_fecha_en_periodo_pagado(p_fecha_cese, p_persona_id)`, usando
--   `p_persona_id` (parámetro directo de la función: es la persona a la que
--   se le está registrando el cese, la dueña del dato) como segundo
--   argumento. Ningún otro cambio: mismo comentario arriba del bloque,
--   mismo mensaje de excepción, misma firma (uuid, date, text, text) — así
--   que el grant/revoke se copian tal cual, sin tocar.

create or replace function fn_cesar_persona(
  p_persona_id uuid,
  p_fecha_cese date,
  p_motivo text,
  p_tipo_vinculo text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_p personas%rowtype; v_hoy date := (now() at time zone 'America/Lima')::date;
        v_desde date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar un cese.';
  end if;

  -- 0174: toma el candado de la fila ANTES de mirar el estado, para que un
  -- segundo cese simultáneo espere aquí, relea la fila ya cesada y rebote.
  select * into v_p from personas where id = p_persona_id for update;
  if not found then raise exception 'La persona no existe.'; end if;
  if v_p.estado <> 'activo' then
    raise exception 'Esa persona ya está inactiva (cesó el %).', to_char(v_p.fecha_cese, 'DD/MM/YYYY');
  end if;

  -- La fecha tiene que ser posible.
  if p_fecha_cese > v_hoy then
    raise exception 'El último día trabajado no puede ser futuro (pusiste %).', to_char(p_fecha_cese, 'DD/MM/YYYY');
  end if;
  if p_fecha_cese < v_p.fecha_ingreso then
    raise exception 'El último día trabajado (%) no puede ser anterior a su ingreso (%).',
      to_char(p_fecha_cese, 'DD/MM/YYYY'), to_char(v_p.fecha_ingreso, 'DD/MM/YYYY');
  end if;

  -- No se cesa dentro de un periodo ya pagado: eso cambiaría el cálculo de una
  -- planilla cerrada. Mismo criterio que fn_set_fecha_ingreso (0037), acotado a
  -- esta persona para no congelar al equipo entero.
  if fn_fecha_en_periodo_pagado(p_fecha_cese, p_persona_id) then
    raise exception 'El % cae dentro de un periodo de planilla ya PAGADO. Reabre ese periodo primero (queda rastro) o corrige la fecha.',
      to_char(p_fecha_cese, 'DD/MM/YYYY');
  end if;

  -- 0176: no se puede cerrar un tramo que todavía no empezó. Se avisa acá, con
  -- la fecha concreta y qué hacer, en vez de dejar que reviente el constraint.
  select min(vigente_desde) into v_desde from asignaciones_salario
   where persona_id = p_persona_id and vigente_desde > p_fecha_cese;
  if v_desde is not null then
    raise exception 'Esta persona tiene un salario que empieza el %, después del último día que pusiste (%). Corrige ese salario antes de darla de baja, o usa una fecha de cese igual o posterior al %.',
      to_char(v_desde, 'DD/MM/YYYY'), to_char(p_fecha_cese, 'DD/MM/YYYY'), to_char(v_desde, 'DD/MM/YYYY');
  end if;

  select min(vigente_desde) into v_desde from horarios_asignados
   where persona_id = p_persona_id and vigente_desde > p_fecha_cese;
  if v_desde is not null then
    raise exception 'Esta persona tiene un horario que empieza el %, después del último día que pusiste (%). Corrige ese horario antes de darla de baja, o usa una fecha de cese igual o posterior al %.',
      to_char(v_desde, 'DD/MM/YYYY'), to_char(p_fecha_cese, 'DD/MM/YYYY'), to_char(v_desde, 'DD/MM/YYYY');
  end if;

  -- Sus tramos se cierran. Hoy quedan abiertos para siempre y eso hace que un
  -- salario "vigente" siga apareciendo años después de que la persona se fue.
  update asignaciones_salario set vigente_hasta = p_fecha_cese
   where persona_id = p_persona_id and vigente_hasta is null;
  update horarios_asignados  set vigente_hasta = p_fecha_cese
   where persona_id = p_persona_id and vigente_hasta is null;

  update personas
     set estado = 'inactivo',
         fecha_cese = p_fecha_cese,
         motivo_cese = p_motivo,
         tipo_vinculo = coalesce(p_tipo_vinculo, tipo_vinculo),
         fecha_estado_cambio = now()
   where id = p_persona_id;
end;
$function$;

grant  execute on function fn_cesar_persona(uuid, date, text, text) to authenticated;
revoke execute on function fn_cesar_persona(uuid, date, text, text) from public, anon;



-- ── 22 · fn_cambiar_regimen_pension ─────────────────────────────────────────────────────────────
-- FUNCION: fn_cambiar_regimen_pension
-- VIGENTE EN: 0277_cambiar_el_regimen_de_pension_vuelve_a_mover_el_descuento.sql
-- NECESITA_CAMBIO: si
-- NOTAS: Caso normal (el fácil). El candado vive en una sola línea:
--   `if fn_fecha_en_periodo_pagado(p_desde) is true then`. p_desde es la fecha
--   desde la que rige el cambio de régimen, y p_persona_id (parámetro directo
--   de la función, ya validado antes con `select 1 from personas where id =
--   p_persona_id`) es la persona dueña de ese dato. Único cambio: agregar
--   p_persona_id como segundo argumento de fn_fecha_en_periodo_pagado. No se
--   tocó ninguna otra línea del cuerpo. La firma de la función no cambia
--   (sigue uuid, text, date, text), así que el comment/revoke/grant que la
--   0277 dejó después se copian tal cual, incluido el texto del comment
--   (menciona la 0277 y no la 0323/Entrega 2, pero el diseño pide no
--   reescribir comentarios existentes).
--   md5 local de partida (ground truth, docker exec sobre esta Mac, con
--   comentarios): ed01ed0f903bf13800d3cf282919abe8 — aún no verificado
--   contra producción; eso se hace en el mensaje en que se entregue el SQL,
--   no en este borrador.

create or replace function fn_cambiar_regimen_pension(
  p_persona_id uuid,
  p_regimen    text,
  p_desde      date,
  p_nota       text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_nuevo         text;
  v_abierta       uuid;
  v_desde_abierta date;
  v_antes         text;
  v_quien         uuid;
  v_tasa          numeric;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar el régimen de pensión.';
  end if;

  -- null y '' son el mismo estado: «todavía no se sabe».
  v_nuevo := nullif(btrim(lower(coalesce(p_regimen, ''))), '');

  -- La lista verdadera vive en `tasas_pension`, no acá. Ver punto 3 de la
  -- cabecera.
  if v_nuevo is not null and not exists (
       select 1 from tasas_pension where regimen = v_nuevo) then
    raise exception 'Régimen «%» desconocido. Los cargados son: %.',
      v_nuevo,
      (select string_agg(distinct regimen, ', ' order by regimen) from tasas_pension);
  end if;

  if p_desde is null then
    raise exception 'Hace falta decir desde cuándo rige el régimen nuevo.';
  end if;

  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'La persona no existe.';
  end if;

  -- El freno de la 0203, intacto: un cambio con efecto dentro de un mes ya
  -- pagado cambiaría lo que ese mes calcula.
  if fn_fecha_en_periodo_pagado(p_desde, p_persona_id) is true then
    raise exception 'El % cae dentro de un periodo YA PAGADO. Un cambio con esa fecha movería lo que ese mes calcula. Elige la primera fecha del periodo abierto.', to_char(p_desde,'DD/MM/YYYY');
  end if;

  select id, vigente_desde, regimen
    into v_abierta, v_desde_abierta, v_antes
    from asignaciones_regimen_pension
   where persona_id = p_persona_id and vigente_hasta is null;

  -- Sin tramo abierto, lo que la planilla venía usando es la columna: ese es el
  -- valor anterior honesto, y el que hay que escribir en la auditoría.
  if v_abierta is null then
    select regimen_pension into v_antes from personas where id = p_persona_id;
  end if;

  if v_abierta is not null and v_desde_abierta >= p_desde then
    raise exception 'Ya hay un régimen vigente desde el %, que es igual o posterior al % que pides.', to_char(v_desde_abierta,'DD/MM/YYYY'), to_char(p_desde,'DD/MM/YYYY');
  end if;

  -- Igual que en la 0125: un guardado que no cambia nada no ensucia la
  -- auditoría. Se compara contra el TRAMO, que es lo que la planilla lee — así
  -- que a quien tenga la columna divergente, esta llamada SÍ lo corrige.
  if coalesce(v_antes, '∅') = coalesce(v_nuevo, '∅') then
    return jsonb_build_object(
      'ok', true, 'regimen', v_nuevo, 'desde', p_desde, 'sin_cambios', true
    );
  end if;

  v_quien := fn_persona_actual_id();
  if v_quien is null then
    raise exception 'No puedo identificar quién hace el cambio, así que no puedo auditarlo. Iniciá sesión con tu usuario.';
  end if;

  if v_abierta is not null then
    update asignaciones_regimen_pension
       set vigente_hasta = p_desde - 1
     where id = v_abierta;
  end if;

  -- Con `null` se cierra el tramo y no se abre otro: sin fila vigente, el
  -- respaldo de `fn_planilla_calcular` cae a la columna, que también queda en
  -- null, y de ahí a la tasa genérica. Ver punto 2 de la cabecera.
  if v_nuevo is not null then
    insert into asignaciones_regimen_pension
      (persona_id, regimen, vigente_desde, asignado_por, nota)
    values (p_persona_id, v_nuevo, p_desde, v_quien, p_nota);
  end if;

  update personas set regimen_pension = v_nuevo where id = p_persona_id;

  select tp.aporte + tp.comision + tp.prima into v_tasa
    from tasas_pension tp
   where tp.regimen = v_nuevo
     and tp.vigente_desde <= p_desde
     and (tp.vigente_hasta is null or tp.vigente_hasta >= p_desde)
   order by tp.vigente_desde desc
   limit 1;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'asignaciones_regimen_pension.regimen',
          coalesce(v_antes, '(sin régimen)'), coalesce(v_nuevo, '(sin régimen)'),
          case
            when v_nuevo is null
              then 'Se quita el régimen desde el ' || to_char(p_desde,'DD/MM/YYYY')
                   || ': el descuento vuelve a la tasa genérica hasta que se sepa el verdadero.'
            -- round()::text y NO to_char, por lo mismo que la 0125: 'FM99D99'
            -- deja el separador colgando y el símbolo depende del locale.
            else 'Régimen de pensión desde el ' || to_char(p_desde,'DD/MM/YYYY')
                 || '. Se le descuenta el ' || round(coalesce(v_tasa, 0) * 100, 2)::text
                 || ' por ciento de su remuneración asegurable.'
          end
          || coalesce(' · ' || nullif(btrim(p_nota), ''), ''),
          v_quien);

  return jsonb_build_object(
    'ok', true,
    'regimen', v_nuevo,
    'desde', p_desde,
    'tasa', coalesce(v_tasa, 0),
    'cerro_la_anterior', v_abierta is not null,
    'sin_cambios', false
  );
end;
$fn$;

comment on function fn_cambiar_regimen_pension(uuid, text, date, text) is
  'Única forma de cambiar el régimen de pensión. Cierra el tramo vigente, abre '
  'el nuevo desde la fecha dada, mantiene `personas.regimen_pension` en sintonía '
  'y deja fila en `correcciones_auditoria` nombrando la tasa que va a regir. Con '
  'regimen null cierra el tramo y no abre otro: «todavía no se sabe». Se niega si '
  'la fecha cae en un periodo ya pagado (0277).';

revoke all on function fn_cambiar_regimen_pension(uuid,text,date,text) from public;
grant execute on function fn_cambiar_regimen_pension(uuid,text,date,text) to authenticated;



-- ── 23 · fn_reactivar_persona ─────────────────────────────────────────────────────────────
-- FUNCION: fn_reactivar_persona
-- VIGENTE EN: 0209_reactivar_devuelve_el_sueldo_desde_el_dia_que_vuelve.sql
-- NECESITA_CAMBIO: si
-- NOTAS: El único candado de "periodo pagado" que hay en esta función es el
--   de la asignación familiar (comentado en la cabecera de la 0209 como "EL
--   CANDADO DE PERIODO PAGADO"): `exists (select 1 from periodos_planilla
--   where estado = 'pagado' and fecha_fin >= v_cese)`. No usa la forma
--   `fecha between fecha_ini and fecha_fin` porque es una comprobación de
--   RANGO deliberada — cualquier periodo desde el cese en adelante que ya
--   esté pagado, no solo el que contiene v_cese — igual al patrón que ya
--   existe en 0037/0180 para `fecha_fin >= p_vigente_desde`. El segundo
--   candado de la función (sueldo fijo, línea "fecha_fin >= v_cese and
--   fecha_ini <= v_hoy") NO comprueba estado='pagado' en absoluto — es una
--   regla distinta (el periodo en curso paga completo aunque NO esté
--   pagado) y no se toca.
--   Para no angostar el candado (dejar de ver un periodo YA pagado que no
--   contiene v_cese pero sí es posterior), mantengo el `exists` sobre el
--   RANGO tal cual, y solo reemplazo el fragmento `estado = 'pagado'` por
--   una llamada a `fn_fecha_en_periodo_pagado(fecha_fin, p_persona_id)`:
--   para cada periodo con fecha_fin >= v_cese, pregunta si ESE periodo (vía
--   su propio fecha_fin, que siempre cae dentro de sí mismo) está pagado
--   PARA EL GRUPO de esta persona — en vez de para el periodo entero. Así
--   se preserva exactamente el mismo alcance de fechas que tenía el
--   candado original, con el candado ahora resuelto por grupo.
--   El persona_id correcto es `p_persona_id`, el parámetro de la propia
--   función: es la persona dueña de la reactivación, no quien hace el clic
--   (eso sería `fn_persona_actual_id()`, usado más abajo solo para
--   `v_actor` en la auditoría, y no se toca).
--   No se cambia nada más: ni el segundo candado, ni el resto del cuerpo,
--   ni el `comment on function` (su firma sigue siendo (uuid), no cambió).

create or replace function public.fn_reactivar_persona(p_persona_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_cese      date;
  v_hijos     boolean;
  v_fijo      boolean;
  v_hoy       date := (now() at time zone 'America/Lima')::date;
  v_actor     uuid;
  v_desde     date;
  v_sal       record;
  v_hor       record;
  v_n_sal     int := 0;
  v_n_hor     int := 0;
  r           record;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede reactivar a una persona.';
  end if;

  -- La fecha de cese se LEE ANTES del update, porque el update la borra. Es la
  -- llave con la que se reconoce qué tramos cerró ese cese. El orden importa:
  -- si algún día un refactor mueve el update arriba, esto compararía contra
  -- null, no encontraría nada y fallaría EN SILENCIO.
  select fecha_cese, con_hijos, sueldo_fijo into v_cese, v_hijos, v_fijo
    from personas
   where id = p_persona_id and estado = 'inactivo'
   for update;
  if not found then
    raise exception 'Esa persona no existe o ya está activa.';
  end if;

  -- ── Los dos candados: donde reactivar movería plata que no se trabajó ─────
  -- Ver la cabecera. Los dos son ESTRECHOS a propósito: de las 8 personas
  -- inactivas de producción, seis tienen un periodo pagado detrás y para las
  -- seis el daño es cero. Un candado ancho rechazaría seis reactivaciones
  -- legítimas de ocho, y eso no protege: prohíbe.

  -- 1 · La asignación familiar se paga por tener hijos, sin mirar tramos ni
  --     jornadas. Volver a 'activo' basta para que aparezca en una planilla ya
  --     pagada. Medido: S/98.31 por periodo.
  if v_hijos is true and exists (
       select 1 from periodos_planilla
        where fn_fecha_en_periodo_pagado(fecha_fin, p_persona_id) and fecha_fin >= v_cese) then
    raise exception
      'Reactivarla ahora cambiaría el total de una planilla YA PAGADA: cobra asignación familiar, '
      'y esa se paga por tener hijos, sin depender de si trabajó. Reabre primero el periodo con '
      'Revertir pago, que deja constancia del motivo.';
  end if;

  -- 2 · El sueldo fijo cobra el periodo COMPLETO con que un tramo suyo roce el
  --     periodo: `fn_planilla_calcular` no prorratea esa rama. Reactivar a
  --     mitad de mes le entrega el mes entero — medido, S/1,130.00 sin un solo
  --     día trabajado, más S/196.81 de provisiones y S/101.70 de EsSalud.
  --     No se prorratea aquí: eso es un cambio en `fn_planilla_calcular` que
  --     movería también a quien INGRESA a mitad de periodo, y esa es una
  --     decisión aparte (Crítico 1 del catálogo, que Felipe ya evaluó una vez).
  --     Aquí se para y se dice qué hacer.
  if v_fijo is true and exists (
       select 1 from periodos_planilla
        where fecha_fin >= v_cese and fecha_ini <= v_hoy) then
    raise exception
      'Tiene sueldo fijo, y el sueldo fijo se paga por periodo completo en cuanto tiene un tramo '
      'que lo toque: reactivarla hoy le pagaría el periodo entero sin haberlo trabajado. '
      'Reactívala el primer día del periodo siguiente, o hazlo igual y registra el ajuste como '
      'movimiento con su motivo.';
  end if;

  update personas
     set estado = 'activo', fecha_cese = null, motivo_cese = null,
         fecha_estado_cambio = now()
   where id = p_persona_id;

  v_actor := coalesce(fn_persona_actual_id(), p_persona_id);

  -- ── El salario vuelve, desde hoy ──────────────────────────────────────────
  -- Solo si NO tiene ya un tramo abierto: entre el cese y la reactivación
  -- alguien pudo asignarle salario —`fn_set_salario` no mira `personas.estado`,
  -- pese a lo que dice la cabecera de la 0176, que en eso es una errata—. Si ya
  -- lo tiene, el suyo manda y aquí no se toca nada.
  -- La pregunta es «¿le llega algún tramo hasta hoy?», NO «¿tiene alguno
  -- abierto?». No es lo mismo, y la diferencia la cazó la prueba 173: un tramo
  -- CERRADO el 2099-12-31 está vigente hoy igual que uno sin fecha de fin, y es
  -- así como `fn_planilla_calcular` elige el suyo. Preguntando solo por
  -- `vigente_hasta is null` no se veía, y se le creaba un tramo encima que —para
  -- no chocar con el antisolape— arrancaba en el año 2100: no le devolvía el
  -- sueldo, se lo prometía para dentro de setenta y seis años.
  --
  -- Con esta condición, si nada le llega a hoy es que todos sus tramos
  -- terminaron ANTES de hoy, así que uno nuevo desde hoy no puede solaparse con
  -- ninguno y el EXCLUDE `asignacion_salario_sin_solape` no tiene nada que decir.
  if not exists (select 1 from asignaciones_salario
                  where persona_id = p_persona_id
                    and (vigente_hasta is null or vigente_hasta > v_hoy)) then

    select a.rango, a.salario_mensual_soles, a.base_provision
      into v_sal
      from asignaciones_salario a
     where a.persona_id = p_persona_id and a.vigente_hasta = v_cese
     order by a.vigente_desde desc
     limit 1;

    if found then
      -- Nunca encima de un tramo que ya termina hoy. Cuando el cese es de HOY
      -- —el caso más probable, porque un cese por error se nota el mismo día—
      -- `fn_cesar_persona` acaba de cerrar el tramo con `vigente_hasta = hoy`,
      -- y el EXCLUDE `asignacion_salario_sin_solape` usa un daterange con los
      -- dos extremos cerrados: arrancar hoy chocaría contra él. Se restituye
      -- desde MAÑANA, y el día del cese queda cubierto por el tramo viejo, que
      -- es lo correcto: ese día sí trabajó.
      select greatest(v_hoy, max(a.vigente_hasta) + 1)
        into v_desde
        from asignaciones_salario a
       where a.persona_id = p_persona_id;

      insert into asignaciones_salario
        (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta,
         asignado_por, nota, base_provision)
      values
        (p_persona_id, v_sal.rango, v_sal.salario_mensual_soles, v_desde, null,
         v_actor, 'Reactivación: vuelve con el salario que tenía al cesar.', v_sal.base_provision);
      v_n_sal := 1;

      insert into correcciones_auditoria
        (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
      values
        (p_persona_id, 'salario_al_reactivar',
         'sin tramo vigente desde el cese del ' || v_cese::text,
         'S/ ' || v_sal.salario_mensual_soles::text || ' vigente desde ' || v_desde::text,
         v_actor,
         'Reactivación: se le devuelve el salario desde el día que vuelve, no desde el cese.');
    end if;
  end if;

  -- ── El horario vuelve, desde hoy ──────────────────────────────────────────
  -- Se copian las columnas en vez de delegar en `fn_set_horario_semanal`:
  -- esa función exige un jsonb, y `horario_por_dia` es NULLABLE — los tramos
  -- viejos la tienen vacía y delegar fallaría justo con los más antiguos.
  -- Misma pregunta que con el salario, y por el mismo motivo.
  if not exists (select 1 from horarios_asignados
                  where persona_id = p_persona_id
                    and (vigente_hasta is null or vigente_hasta > v_hoy)) then

    select h.hora_entrada, h.hora_salida, h.almuerzo_min_minutos, h.almuerzo_max_minutos,
           h.dias_laborables, h.horas_semana_objetivo, h.horario_por_dia
      into v_hor
      from horarios_asignados h
     where h.persona_id = p_persona_id and h.vigente_hasta = v_cese
     order by h.vigente_desde desc
     limit 1;

    if found then
      select greatest(v_hoy, max(h.vigente_hasta) + 1)
        into v_desde
        from horarios_asignados h
       where h.persona_id = p_persona_id;

      insert into horarios_asignados
        (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
         almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables,
         horas_semana_objetivo, horario_por_dia)
      values
        (p_persona_id, v_desde, null, v_hor.hora_entrada, v_hor.hora_salida,
         v_hor.almuerzo_min_minutos, v_hor.almuerzo_max_minutos, v_hor.dias_laborables,
         v_hor.horas_semana_objetivo, v_hor.horario_por_dia);
      v_n_hor := 1;

      -- Devolver el horario sin recalcular es devolver la mitad del hecho: si
      -- ya marcó hoy, su jornada se midió contra un horario que no existía.
      -- Solo desde `v_desde` hacia adelante — el hueco NO se toca a propósito.
      for r in select j.fecha from jornadas j
                where j.persona_id = p_persona_id and j.fecha >= v_desde loop
        perform fn_recalcular_jornada(p_persona_id, r.fecha);
      end loop;

      insert into correcciones_auditoria
        (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
      values
        (p_persona_id, 'horario_al_reactivar',
         'sin horario vigente desde el cese del ' || v_cese::text,
         'horario restituido desde ' || v_desde::text,
         v_actor,
         'Reactivación: se le devuelve el horario desde el día que vuelve, no desde el cese.');
    end if;
  end if;

  -- ── Cero filas es un resultado legítimo, y también es el resultado roto ────
  -- Legítimo: le corrigieron el sueldo estando inactiva, o nunca tuvo horario
  -- (los RxH no llevan, desde la 0191). Roto: se cesó, se reactivó sin que esto
  -- existiera, y se volvió a cesar — el segundo cese no cerró nada, así que no
  -- hay nada que copiar. Los dos casos se ven iguales desde aquí, y callarse
  -- sería apagar la sospecha. Queda escrito para que alguien lo mire.
  if v_n_sal = 0 then
    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (p_persona_id, 'reactivacion_sin_salario_que_devolver',
       'cese del ' || coalesce(v_cese::text, '—'), 'sigue sin salario vigente', v_actor,
       'Reactivación: no se encontró un tramo cerrado por ese cese. Hay que asignarle salario a mano.');
  end if;
end;
$function$;

comment on function public.fn_reactivar_persona(uuid) is
  'Reactiva a quien se cesó y le devuelve salario y horario DESDE EL DÍA QUE VUELVE, con un tramo '
  'nuevo — nunca reabriendo el viejo, que cubriría el hueco hacia atrás y reescribiría planillas ya '
  'pagadas. No devuelve la educación: el cese no guardó su vigencia original. Deja rastro en '
  'correcciones_auditoria, incluso cuando no encuentra nada que devolver.';



-- ── 24 · fn_otorgar_descanso_sustitutorio ─────────────────────────────────────────────────────────────
-- FUNCION: fn_otorgar_descanso_sustitutorio
-- VIGENTE EN: 0238_un_dia_compensatorio_que_no_compensa_deja_de_entrar.sql
-- NECESITA_CAMBIO: si
-- NOTAS: Es el caso normal. La función ya recibe `p_persona_id` como parámetro
--         directo (la persona dueña del feriado/descanso), así que se usa tal
--         cual. Tenía DOS candados escritos a mano —uno para p_fecha_feriado y
--         otro para p_fecha_descanso, comentados como "el candado de la 0093,
--         intacto"— porque el feriado y el día compensatorio pueden caer en
--         periodos distintos. Se reemplazaron los dos `exists (select 1 from
--         periodos_planilla where estado = 'pagado' and <fecha> between
--         fecha_ini and fecha_fin)` por `fn_fecha_en_periodo_pagado(<fecha>,
--         p_persona_id)`, sin tocar el comentario ni ninguna otra línea. La
--         firma (uuid, date, date, text, text, text) no cambia, así que el
--         grant/revoke se copian idénticos. Cuerpo verificado contra
--         pg_get_functiondef en el Postgres local (ground truth), no copiado
--         a mano del .sql.

create or replace function fn_otorgar_descanso_sustitutorio(
  p_persona_id uuid,
  p_fecha_feriado date,
  p_fecha_descanso date,
  p_estado text default 'PENDIENTE',
  p_acta_ref text default null,
  p_motivo_fuera_de_plazo text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar un descanso sustitutorio.';
  end if;

  if p_estado not in ('PENDIENTE', 'OTORGADO', 'NO_OTORGADO') then
    raise exception 'Estado inválido: %. Debe ser PENDIENTE, OTORGADO o NO_OTORGADO.', p_estado;
  end if;

  if not exists (select 1 from feriados where fecha = p_fecha_feriado) then
    raise exception 'El % no está registrado como feriado.', to_char(p_fecha_feriado, 'DD/MM/YYYY');
  end if;

  -- El candado de la 0093, intacto: se miran LAS DOS fechas, porque el feriado y
  -- el día libre pueden caer en periodos distintos y basta con que uno esté
  -- cerrado para no tocar nada.
  if fn_fecha_en_periodo_pagado(p_fecha_feriado, p_persona_id) then
    raise exception 'El feriado del % cae en un periodo ya PAGADO: otorgar un descanso ahí cambiaría una planilla pagada. Reabre el periodo primero.',
      to_char(p_fecha_feriado, 'DD/MM/YYYY');
  end if;

  if fn_fecha_en_periodo_pagado(p_fecha_descanso, p_persona_id) then
    raise exception 'El día compensatorio del % cae en un periodo ya PAGADO: reabre el periodo primero.',
      to_char(p_fecha_descanso, 'DD/MM/YYYY');
  end if;

  -- El feriado tiene que haberse LABORADO: si no hay horas marcadas, no hay
  -- sobretasa que compensar y este registro no tiene sentido.
  if not exists (
    select 1 from jornadas j
    where j.persona_id = p_persona_id and j.fecha = p_fecha_feriado
      and coalesce(j.horas_trabajadas, 0) > 0
  ) then
    raise exception 'Esa persona no tiene horas marcadas el % : el feriado no fue laborado.',
      to_char(p_fecha_feriado, 'DD/MM/YYYY');
  end if;

  insert into feriados_descanso_sustitutorio (
    persona_id, fecha_feriado, fecha_descanso_sustitutorio, estado, acta_ref,
    otorgado_por, motivo_fuera_de_plazo
  )
  values (
    p_persona_id, p_fecha_feriado, p_fecha_descanso, p_estado,
    nullif(trim(p_acta_ref), ''), fn_persona_actual_id(),
    nullif(trim(p_motivo_fuera_de_plazo), '')
  )
  on conflict (persona_id, fecha_feriado) do update set
    fecha_descanso_sustitutorio = excluded.fecha_descanso_sustitutorio,
    estado = excluded.estado,
    acta_ref = excluded.acta_ref,
    otorgado_por = excluded.otorgado_por,
    motivo_fuera_de_plazo = excluded.motivo_fuera_de_plazo,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function fn_otorgar_descanso_sustitutorio(uuid, date, date, text, text, text) to authenticated;
revoke execute on function fn_otorgar_descanso_sustitutorio(uuid, date, date, text, text, text) from public, anon;



-- ── 25 · fn_quitar_descanso_sustitutorio ─────────────────────────────────────────────────────────────
-- FUNCION: fn_quitar_descanso_sustitutorio
-- VIGENTE EN: 0093_el_descanso_sustitutorio_no_toca_lo_pagado.sql
-- NECESITA_CAMBIO: si
-- NOTAS: Caso normal. La función ya trae persona_id a mano: `v_fila` es una
--   fila completa de `feriados_descanso_sustitutorio`, tabla que tiene
--   columna `persona_id not null` (dueña del descanso). El candado original
--   era un `exists (select 1 from periodos_planilla where estado = 'pagado'
--   and (fecha_feriado between ... or fecha_descanso_sustitutorio between
--   ...))` escrito a mano, mirando el periodo entero. Lo reemplacé por
--   `fn_fecha_en_periodo_pagado(v_fila.fecha_feriado, v_fila.persona_id) or
--   fn_fecha_en_periodo_pagado(v_fila.fecha_descanso_sustitutorio,
--   v_fila.persona_id)`, conservando el mismo criterio de origen (bloquea si
--   CUALQUIERA de las dos fechas cae en un periodo pagado) pero ahora
--   evaluado contra el grupo de pago de esa persona, no contra el periodo
--   entero. No toqué ningún otro comentario ni línea. La función no tiene
--   grant/revoke/comment on propios en la 0093 (solo el insert en
--   migraciones_aplicadas y el notify, que son de la migración, no de la
--   función), así que la entrega es solo el CREATE OR REPLACE.

CREATE OR REPLACE FUNCTION public.fn_quitar_descanso_sustitutorio(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_fila feriados_descanso_sustitutorio;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede quitar un descanso sustitutorio.';
  end if;

  select * into v_fila from feriados_descanso_sustitutorio where id = p_id for update;
  if not found then
    raise exception 'Ese descanso sustitutorio ya no existe.';
  end if;

  -- Quitarlo devuelve la sobretasa del feriado y sube el total del periodo, así
  -- que hace falta el mismo candado que para otorgarlo.
  if fn_fecha_en_periodo_pagado(v_fila.fecha_feriado, v_fila.persona_id)
     or fn_fecha_en_periodo_pagado(v_fila.fecha_descanso_sustitutorio, v_fila.persona_id)
  then
    raise exception 'Ese descanso sustitutorio toca un periodo ya PAGADO: quitarlo alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  delete from feriados_descanso_sustitutorio where id = p_id;
end;
$function$;



-- ── 26 · fn_agregar_movimiento ─────────────────────────────────────────────────────────────
-- FUNCION: fn_agregar_movimiento
-- VIGENTE EN: 0305_un_retroactivo_dice_de_que_mes_viene.sql
-- NECESITA_CAMBIO: si
-- NOTAS: El candado NO llama a fn_fecha_en_periodo_pagado ni escribe un
--   `exists (... between fecha_ini and fecha_fin)` — es la variante "por
--   variable ya leída": trae `estado, fecha_ini` del periodo por su
--   p_periodo_id (`select estado, fecha_ini into v_estado, v_ini from
--   periodos_planilla where id = p_periodo_id`) y compara `if v_estado =
--   'pagado' then raise exception 'Este periodo ya está PAGADO...'`. Es el
--   caso normal: la función ya recibe p_persona_id (la persona DUEÑA del
--   bono/descuento que se inserta — no quien hace el clic, eso lo cubre
--   fn_es_admin_o_lider() aparte) así que se reemplaza la comparación por
--   `fn_fecha_en_periodo_pagado(v_ini, p_persona_id)`, usando v_ini (ya
--   leído, es el fecha_ini de ESE periodo) como la fecha. Único cambio: esa
--   línea. `v_estado` queda declarado y seleccionado sin usarse después —no
--   se tocó esa línea para no ampliar el diff; Postgres solo lo marcaría
--   como aviso, no como error. Firma, comentario, revoke y grant no
--   cambian de tipos (sigue siendo (uuid,uuid,text,text,numeric,text,uuid)),
--   así que se copian tal cual.

CREATE OR REPLACE FUNCTION public.fn_agregar_movimiento(p_periodo_id uuid, p_persona_id uuid, p_tipo text, p_concepto text, p_monto numeric, p_categoria text DEFAULT NULL::text, p_periodo_origen_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if fn_fecha_en_periodo_pagado(v_ini, p_persona_id) then
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



-- ── 27 · fn_quitar_movimiento ─────────────────────────────────────────────────────────────
-- FUNCION: fn_quitar_movimiento
-- VIGENTE EN: 0181_los_mensajes_rotos_vuelven_a_decir_lider.sql
-- NECESITA_CAMBIO: si
-- NOTAS: El candado no llamaba a fn_fecha_en_periodo_pagado ni tenía un
--   `exists` a mano: comparaba directo `v_estado = 'pagado'`, con v_estado
--   leído antes con `select pp.estado into v_estado from movimientos_planilla
--   m join periodos_planilla pp ...`. movimientos_planilla SÍ tiene
--   persona_id (columna propia, not null, FK a personas) — es el dueño del
--   bono/descuento que se está quitando, no quien hace el clic. La función
--   no tenía ninguna fecha a mano (solo conocía el periodo_id ya resuelto),
--   así que en vez de reintroducir un `exists` a mano se cambió el select
--   para traer también `pp.fecha_ini` (además de m.persona_id) — cualquier
--   fecha dentro del periodo sirve para que fn_fecha_en_periodo_pagado
--   ubique el mismo periodo, porque periodos_planilla tiene la restricción
--   `periodos_sin_solape` (exclude gist sobre daterange) que impide que dos
--   periodos se crucen. v_estado ya no hace falta: fn_fecha_en_periodo_pagado
--   trae su propio fallback de compatibilidad (estado='pagado' sin filas en
--   periodo_grupo_pago) para periodos de antes de la 0323, así que no hay
--   que conservarlo aparte. No tiene grant/revoke/comment on después en la
--   0181 (se confirmó en el archivo de la migración) y el cuerpo local
--   coincide md5 6acec517707973b4e7c7461c8678ce28 con lo que la 0181 declara
--   como "md5 correcto", así que no hace falta declarar un md5 de producción
--   distinto en el encabezado de esta migración.

CREATE OR REPLACE FUNCTION public.fn_quitar_movimiento(p_movimiento_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_persona_id uuid;
  v_fecha date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede quitar bonos o descuentos.';
  end if;
  select m.persona_id, pp.fecha_ini into v_persona_id, v_fecha
  from movimientos_planilla m join periodos_planilla pp on pp.id = m.periodo_id
  where m.id = p_movimiento_id;
  if not found then raise exception 'Movimiento inexistente.'; end if;
  if fn_fecha_en_periodo_pagado(v_fecha, v_persona_id) then
    raise exception 'Este periodo ya está PAGADO: reábrelo para modificarlo.';
  end if;
  delete from movimientos_planilla where id = p_movimiento_id;
end;
$function$;



-- ── 28 · fn_registrar_ausencia ─────────────────────────────────────────────────────────────
-- FUNCION: fn_registrar_ausencia
-- VIGENTE EN: 0101_ausencias_un_solo_lugar.sql (única definición encontrada por
--   donde-vive.sh; confirmado también con pg_get_functiondef contra el
--   Postgres local — una sola fila devuelta, cuerpo idéntico al del archivo)
-- NECESITA_CAMBIO: si
-- NOTAS: El candado de esta función NO es el patrón simple del diseño
--   (comparar UNA fecha contra periodos_planilla). fn_registrar_ausencia
--   recibe un RANGO (p_fecha_inicio..p_fecha_fin) — una ausencia puede durar
--   varios días (ej. descanso médico, maternidad) — y el candado original
--   comprueba SOLAPE de rangos con daterange(...) && daterange(...), no
--   contención de una fecha puntual. fn_fecha_en_periodo_pagado(fecha,
--   persona_id) toma UNA fecha, así que no se puede llamar directo aquí sin
--   cambiar la semántica (habría que iterar día por día, lo cual además
--   perdería el FOR SHARE de una sola sentencia). En su lugar inline la MISMA
--   lógica de grupo que tiene fn_fecha_en_periodo_pagado (comentarios
--   incluidos, para que quede trazable) pero adaptada a solape de rango en
--   vez de contención de fecha única, y conservando el FOR SHARE original
--   (bloquea las mismas filas de periodos_planilla que antes, ahora sujetas
--   a la condición de grupo). El persona_id dueño del dato es el propio
--   parámetro p_persona_id de la función — NO v_editor, que es quien hace el
--   clic (admin/líder/encargada), resuelto por fn_verificar_corrector y usado
--   solo para registrada_por/aprobada_por. Nada más del cuerpo cambió: mismo
--   mensaje de error, mismos comentarios de negocio, mismo orden de
--   validaciones, mismo bloque exception. grant/revoke se copian tal cual —
--   la firma de fn_registrar_ausencia no cambia (sigue siendo
--   (uuid, text, date, date, text, text, text, date)).

CREATE OR REPLACE FUNCTION public.fn_registrar_ausencia(p_persona_id uuid, p_tipo text, p_fecha_inicio date, p_fecha_fin date, p_motivo text DEFAULT NULL::text, p_doc_profesional text DEFAULT NULL::text, p_doc_colegiatura text DEFAULT NULL::text, p_doc_fecha date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_t tipos_ausencia%rowtype;
  v_editor uuid;
  v_id uuid;
  v_tarde boolean;
begin
  -- Quién puede: admin, líder o la encargada de la sede de esa persona. Como
  -- ningún permiso paga por sí solo (los que pagan exigen aprobación de DO más
  -- abajo), que la encargada registre no mueve dinero.
  v_editor := fn_verificar_corrector(p_persona_id);

  select * into v_t from tipos_ausencia where codigo = p_tipo and activo;
  if not found then raise exception 'Ese tipo de ausencia no existe o está desactivado.'; end if;

  if p_fecha_fin < p_fecha_inicio then
    raise exception 'La fecha de fin no puede ser anterior a la de inicio.';
  end if;

  if v_t.requiere_documento and (
       coalesce(trim(p_doc_profesional), '') = ''
    or coalesce(trim(p_doc_colegiatura), '') = ''
    or p_doc_fecha is null)
  then
    raise exception '% exige el documento: profesional o institución, número de colegiatura y fecha de emisión. Si no hay documento, regístralo como «Descanso por salud», que no paga pero tampoco cuenta como falta.', v_t.nombre;
  end if;

  -- Candado de planilla pagada: registrar una ausencia dentro de un periodo ya
  -- cerrado cambiaría lo que se pagó (los tipos que pagan) o el conteo de
  -- faltas de un periodo cerrado (todos los demás).
  -- CAMBIO 0NNN: el candado ya no mira el periodo entero, mira el GRUPO
  -- (tipo_vinculo) de la persona dueña de la ausencia — misma lógica que
  -- fn_fecha_en_periodo_pagado, adaptada aquí a solape de RANGO (esta función
  -- recibe fecha_inicio/fecha_fin, no una fecha suelta) para no perder el
  -- FOR SHARE de una sola sentencia.
  if exists (
    select 1 from periodos_planilla pp
    where daterange(pp.fecha_ini, pp.fecha_fin, '[]') && daterange(p_fecha_inicio, p_fecha_fin, '[]')
      and (
        -- Compatibilidad: un periodo con estado='pagado' pero SIN ninguna fila
        -- en periodo_grupo_pago es de antes de la 0323 (el bucket único de
        -- siempre) — se sigue leyendo por el agregado.
        (pp.estado = 'pagado' and not exists (
           select 1 from periodo_grupo_pago g where g.periodo_id = pp.id
         ))
        or
        -- El caso normal desde la 0323: el GRUPO de esta persona, no el
        -- periodo entero.
        exists (
          select 1 from periodo_grupo_pago g
          join personas pe on pe.id = p_persona_id
          where g.periodo_id = pp.id
            and g.grupo = pe.tipo_vinculo
            and g.estado = 'pagado'
        )
      )
    for share
  ) then
    raise exception 'Esas fechas caen en un periodo de planilla ya PAGADO. Reabre el periodo primero.';
  end if;

  -- Registrar hacia atrás se permite —el caso real es enterarse el lunes de algo
  -- del jueves— pero por encima de 15 días queda dicho que se registró tarde.
  v_tarde := p_fecha_inicio < fn_hoy_lima() - 15;

  insert into ausencias (
    persona_id, tipo, fecha_inicio, fecha_fin, motivo,
    doc_profesional, doc_colegiatura, doc_fecha,
    registrada_por, registrada_tarde,
    -- Lo que no exige aprobación nace aprobado: pedir un visto bueno que nadie
    -- va a dar sería dejar el registro en un limbo permanente.
    aprobada_por, aprobada_at
  )
  values (
    p_persona_id, p_tipo, p_fecha_inicio, p_fecha_fin, nullif(trim(p_motivo), ''),
    nullif(trim(p_doc_profesional), ''), nullif(trim(p_doc_colegiatura), ''), p_doc_fecha,
    v_editor, v_tarde,
    case when v_t.requiere_aprobacion then null else v_editor end,
    case when v_t.requiere_aprobacion then null else now() end
  )
  returning id into v_id;

  return v_id;
exception
  when exclusion_violation then
    raise exception 'Esa persona ya tiene otra ausencia registrada que se cruza con esas fechas.';
end;
$function$;

grant execute on function fn_registrar_ausencia(uuid, text, date, date, text, text, text, date) to authenticated;
revoke execute on function fn_registrar_ausencia(uuid, text, date, date, text, text, text, date) from public, anon;



-- ── 29 · fn_anular_ausencia ─────────────────────────────────────────────────────────────
-- FUNCION: fn_anular_ausencia
-- VIGENTE EN: 0101_ausencias_un_solo_lugar.sql
-- NECESITA_CAMBIO: si
-- NOTAS: El candado no llama a fn_fecha_en_periodo_pagado(fecha) — está escrito
--   a mano contra un RANGO de fechas, no una fecha suelta:
--     exists (select 1 from periodos_planilla where estado = 'pagado'
--             and daterange(fecha_ini, fecha_fin, '[]')
--                 && daterange(v_a.fecha_inicio, v_a.fecha_fin, '[]')
--             for share)
--   (una ausencia puede durar varios días — vacaciones, descanso médico —, así
--   que fecha_inicio/fecha_fin son un rango, no un punto; por eso no encaja en
--   el patrón "un solo fn_fecha_en_periodo_pagado(fecha, persona_id)"). Se
--   reescribió ese `exists` con la MISMA lógica de compatibilidad y de grupo
--   que fn_fecha_en_periodo_pagado (periodo sin filas en periodo_grupo_pago →
--   se sigue leyendo por pp.estado='pagado'; si tiene filas, se mira el
--   estado del grupo de v_a.persona_id), pero contra el traslape de rangos en
--   vez de un `between` de una sola fecha. persona_id usado: v_a.persona_id
--   (dueña de la ausencia que se anula, no fn_verificar_corrector ni quien
--   hace el clic). Se conserva el `for share` sobre periodos_planilla —
--   bloqueaba concurrencia antes y sigue siendo necesario. No se tocó nada
--   más: ni fn_verificar_corrector, ni las validaciones de motivo/anulada_at,
--   ni el grant/revoke (la firma (uuid, text) no cambia).

create or replace function fn_anular_ausencia(p_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = public as $fn$
declare v_a ausencias%rowtype; v_editor uuid;
begin
  select * into v_a from ausencias where id = p_id;
  if not found then raise exception 'Esa ausencia ya no existe.'; end if;
  v_editor := fn_verificar_corrector(v_a.persona_id);

  if v_a.anulada_at is not null then raise exception 'Esa ausencia ya estaba anulada.'; end if;
  if p_motivo is null or length(trim(p_motivo)) < 4 then
    raise exception 'El motivo de la anulación es obligatorio (mínimo 4 caracteres).';
  end if;

  if exists (
    select 1
    from periodos_planilla pp
    where daterange(pp.fecha_ini, pp.fecha_fin, '[]') && daterange(v_a.fecha_inicio, v_a.fecha_fin, '[]')
      and (
        -- Compatibilidad: un periodo con estado='pagado' pero SIN ninguna fila
        -- en periodo_grupo_pago es de antes de la 0323 (el bucket único de
        -- siempre) — se sigue leyendo por el agregado.
        (pp.estado = 'pagado' and not exists (
           select 1 from periodo_grupo_pago g where g.periodo_id = pp.id
         ))
        or
        -- El caso normal desde la 0323: el GRUPO de esta persona, no el
        -- periodo entero.
        exists (
          select 1 from periodo_grupo_pago g
          join personas pe on pe.id = v_a.persona_id
          where g.periodo_id = pp.id
            and g.grupo = pe.tipo_vinculo
            and g.estado = 'pagado'
        )
      )
    for share
  ) then
    raise exception 'Esas fechas caen en un periodo de planilla ya PAGADO. Reabre el periodo primero.';
  end if;

  update ausencias
     set anulada_at = now(), anulada_por = v_editor, anulada_motivo = trim(p_motivo)
   where id = p_id;
end;
$fn$;
grant execute on function fn_anular_ausencia(uuid, text) to authenticated;
revoke execute on function fn_anular_ausencia(uuid, text) from public, anon;



-- ── 30 · fn_educacion_fecha_pagada ─────────────────────────────────────────────────────────────
-- FUNCION: fn_educacion_fecha_pagada
-- VIGENTE EN: 0149_la_educacion_con_todas_sus_reglas.sql (única versión; no
--   fue redefinida después. md5 local (tal cual = sin comentarios, no tiene
--   comentarios internos) 1d1a56ac5692e55b37d586d12e1f5339 — pídelo a
--   producción con la consulta que imprime donde-vive.sh antes de pegar.)
-- NECESITA_CAMBIO: si
-- NOTAS:
--   Esta función SÍ es un candado (la llaman fn_educacion_registrar y
--   fn_educacion_cerrar con "if fn_educacion_fecha_pagada(...) is true then
--   raise exception"), pero su cuerpo de HOY es literalmente el mismo que
--   tenía fn_fecha_en_periodo_pagado ANTES de la 0323 (periodo entero, sin
--   grupo) — es una copia escrita en la 0149, antes de que existiera
--   fn_fecha_en_periodo_pagado (0203). No tiene ningún persona_id propio:
--   solo recibe p_fecha.
--
--   Los tres sitios que la llaman SÍ tienen el persona_id a mano (p_persona_id
--   en fn_educacion_registrar; v_vieja.persona_id y r.persona_id en la
--   corrección y en fn_educacion_cerrar), simplemente no se lo pasan porque la
--   función nunca lo pedía. Así que el arreglo fiel al patrón central es
--   agregarle el segundo argumento a ELLA MISMA (igual que se hizo con
--   fn_fecha_en_periodo_pagado) y que delegue en fn_fecha_en_periodo_pagado
--   (p_fecha, p_persona_id) en vez de repetir la consulta a periodos_planilla.
--
--   ⚠ ESTO ES UN CAMBIO DE FIRMA (date) → (date, uuid), y por eso hace falta
--   un `drop function` de la firma vieja antes del `create or replace` — un
--   create-or-replace con distinta lista de argumentos NO reemplaza la
--   función anterior, crea una segunda sobrecargada al lado (el mismo
--   accidente que la 0297/0299 con fn_vacaciones_por_vencer, documentado en
--   CLAUDE.md). Lo incluyo abajo.
--
--   ⚠ COORDINACIÓN NECESARIA CON OTRAS PIEZAS DE ESTA ENTREGA: al dejar de
--   existir fn_educacion_fecha_pagada(date), los tres call sites que hoy la
--   llaman con un solo argumento se rompen si no se actualizan en la misma
--   migración final:
--     · fn_educacion_registrar — vigente en 0290_un_comprobante_por_mes_y_no_uno_por_asignacion.sql
--       — línea "if fn_educacion_fecha_pagada(p_vigente_desde) is true then"
--       (alta) y "if fn_educacion_fecha_pagada(v_desde) is true then"
--       (corrección) → pasan a fn_educacion_fecha_pagada(p_vigente_desde,
--       p_persona_id) y fn_educacion_fecha_pagada(v_desde, p_persona_id)
--       (o v_vieja.persona_id en la corrección, que es la misma persona).
--     · fn_educacion_cerrar — vigente en 0149_la_educacion_con_todas_sus_reglas.sql
--       — línea "if fn_educacion_fecha_pagada(p_hasta) is true then" → pasa a
--       fn_educacion_fecha_pagada(p_hasta, r.persona_id).
--   Si esas dos funciones no están cubiertas por otra pieza de esta entrega,
--   avísalo antes de pegar: pegar solo este archivo deja la migración sin
--   aplicar limpio (los tres call sites fallarían con "function
--   fn_educacion_fecha_pagada(date) does not exist").
--
--   No toqué el cuerpo de fn_fecha_en_periodo_pagado (ya la escribiste tú),
--   ni ninguna otra línea de fn_educacion_fecha_pagada más allá de la firma y
--   la consulta interna. El comentario original de la función se conserva.

drop function if exists fn_educacion_fecha_pagada(date);

-- ¿Esta fecha cae en un periodo ya pagado? Se pregunta al registrar y al
-- corregir, y la respuesta tiene que ser la misma en los dos. Escrita una vez.
-- Entrega 2: delega en fn_fecha_en_periodo_pagado, que mira el GRUPO de pago
-- de esta persona (planilla, prueba, rxh, no_trabajador, practicante) y no el
-- periodo entero — antes de esto, si planilla ya estaba pagada pero RxH
-- todavía no, una asignación por educación de alguien de planilla seguía
-- pareciendo "editable" porque el periodo entero no estaba 100% cerrado.
create or replace function fn_educacion_fecha_pagada(p_fecha date, p_persona_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select fn_fecha_en_periodo_pagado(p_fecha, p_persona_id);
$$;

grant execute on function fn_educacion_fecha_pagada(date, uuid) to authenticated;



-- ── 31 · fn_set_feriado ─────────────────────────────────────────────────────────────
-- FUNCION: fn_set_feriado
-- VIGENTE EN: 0180_el_candado_de_pagado_vuelve_a_las_seis_que_lo_perdieron.sql
-- NECESITA_CAMBIO: si
-- NOTAS: Caso especial sin persona_id (un feriado es del calendario, no de
--   alguien en concreto). El cuerpo vigente sí bloquea por periodo pagado
--   -- "if exists (select 1 from periodos_planilla where estado = 'pagado'
--   and p_fecha between fecha_ini and fecha_fin)" -- y ese `exists` es
--   exactamente el que el candado de periodo-entero deja huérfano tras la
--   0323 (mira solo `periodos_planilla.estado`, nunca `periodo_grupo_pago`).
--   Lo reemplacé por el patrón de "cualquier grupo pagado" del diseño,
--   adaptando la variable de fecha a `p_fecha` y el alias de la subconsulta
--   a `pp` para no chocar con nada del cuerpo. No toqué ninguna otra línea:
--   ni el guard de admin/líder, ni la validación de nombre, ni el insert,
--   ni el mensaje de error (sigue siendo verdad: la fecha SÍ cae en un
--   periodo con algún grupo pagado). Comparé pg_get_functiondef de esta Mac
--   contra el archivo de la 0180 y son idénticos byte a byte, y el md5 local
--   de ambas formas (tal cual / sin comentarios) coincide con el que
--   donde-vive.sh reporta como esperado en producción
--   (719d2dc02f9408322518c4b116d5775a) -- falta confirmarlo en el SQL
--   Editor de producción antes de pegar, como pide el diseño.

CREATE OR REPLACE FUNCTION public.fn_set_feriado(p_fecha date, p_nombre text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede gestionar feriados.';
  end if;
  if p_fecha is null then raise exception 'La fecha es obligatoria.'; end if;
  if p_nombre is null or length(trim(p_nombre)) < 2 then
    raise exception 'El nombre del feriado es obligatorio.';
  end if;
  if exists (
    select 1 from periodos_planilla pp
    where p_fecha between pp.fecha_ini and pp.fecha_fin
      and (
        (pp.estado = 'pagado' and not exists (select 1 from periodo_grupo_pago g where g.periodo_id = pp.id))
        or exists (select 1 from periodo_grupo_pago g where g.periodo_id = pp.id and g.estado = 'pagado')
      )
  ) then
    raise exception 'Esa fecha cae dentro de un periodo ya PAGADO: cambiar sus feriados alteraría una planilla pagada. Reabre el periodo primero.';
  end if;
  insert into feriados (fecha, nombre) values (p_fecha, trim(p_nombre))
  on conflict (fecha) do update set nombre = excluded.nombre;
end;
$function$;



-- ── 32 · fn_quitar_feriado ─────────────────────────────────────────────────────────────
-- FUNCION: fn_quitar_feriado
-- VIGENTE EN: 0180_el_candado_de_pagado_vuelve_a_las_seis_que_lo_perdieron.sql
-- NECESITA_CAMBIO: si
-- NOTAS: Caso especial (sin persona_id) — un feriado es del calendario
--         entero, no de alguien en concreto. El candado estaba escrito a
--         mano (`exists (select 1 from periodos_planilla where estado =
--         'pagado' and p_fecha between fecha_ini and fecha_fin)`). Se
--         reemplazó ese `exists` completo por la expresión de "cualquier
--         grupo pagado" del diseño (bloquea si el periodo es de antes de la
--         0323 y está 'pagado' en el agregado, O si CUALQUIER grupo de ese
--         periodo en periodo_grupo_pago ya está 'pagado') — no se llama a
--         fn_fecha_en_periodo_pagado(fecha, persona_id) porque esta función
--         no tiene a quién atarle un grupo. Confirmado contra el cuerpo
--         vigente en el Postgres local vía pg_get_functiondef (una sola
--         fila, coincide con 0180 exactamente, md5 78c1592506fa7abe332bcbb
--         7c9e06f49). No hay grant/revoke/comment on function propios de
--         fn_quitar_feriado en la 0180 ni en migraciones posteriores que
--         copiar. Ningún otro comentario, variable ni mensaje se tocó.

CREATE OR REPLACE FUNCTION public.fn_quitar_feriado(p_fecha date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede gestionar feriados.';
  end if;
  if exists (
    select 1 from periodos_planilla pp
    where p_fecha between pp.fecha_ini and pp.fecha_fin
      and (
        (pp.estado = 'pagado' and not exists (select 1 from periodo_grupo_pago g where g.periodo_id = pp.id))
        or exists (select 1 from periodo_grupo_pago g where g.periodo_id = pp.id and g.estado = 'pagado')
      )
  ) then
    raise exception 'Esa fecha cae dentro de un periodo ya PAGADO: cambiar sus feriados alteraría una planilla pagada. Reabre el periodo primero.';
  end if;
  delete from feriados where fecha = p_fecha;
  if not found then raise exception 'No hay feriado en esa fecha.'; end if;
end;
$function$;



-- ── 33 · fn_eliminar_periodo ─────────────────────────────────────────────────────────────
-- FUNCION: fn_eliminar_periodo
-- VIGENTE EN: 0183_los_periodos_vuelven_a_la_version_que_dice_el_repositorio.sql
-- NECESITA_CAMBIO: si
-- NOTAS: Caso especial (sin persona_id) — patrón "cualquier grupo pagado" del
--   diseño, no fn_fecha_en_periodo_pagado(fecha, persona_id). El candado
--   actual es `if v_estado = 'pagado' then raise exception ...` sobre
--   v_estado leído de periodos_planilla.estado (el AGREGADO de los 5 grupos
--   desde la 0323: solo llega a 'pagado' cuando TODOS los grupos están
--   pagados). Eso es exactamente el hueco que describe el diseño y que la
--   propia 0323 documenta en su cabecera ("fn_set_feriado/fn_quitar_feriado/
--   fn_eliminar_periodo... se quedan con la regla de siempre: bloqueados si
--   CUALQUIER grupo del periodo ya está pagado. Sin cambios" — la 0323 dejó
--   escrita la intención pero no tocó el cuerpo). Cambié la única condición
--   `if v_estado = 'pagado' then` por la disyunción de compatibilidad que
--   pide el diseño: sigue bloqueando por el agregado cuando el periodo no
--   tiene NINGUNA fila en periodo_grupo_pago (periodos de antes de la 0323),
--   y además bloquea si CUALQUIER grupo de periodo_grupo_pago para este
--   periodo ya está 'pagado' — sin esperar a que los 5 lo estén. No toqué
--   ninguna otra línea (el candado del ÚLTIMO periodo, el advisory lock, el
--   mensaje de error, todo igual). La firma `(uuid)` no cambia, y 0183 no
--   traía grant/revoke/comment on después del cuerpo (ya quedaron fijados en
--   la 0025/0026 y CREATE OR REPLACE no los toca), así que no hace falta
--   repetirlos aquí.
--   Cuerpo verificado contra el Postgres local (ground truth):
--   md5(prosrc) = 14acc43cf164ba17e9e7e6cf0f7dc228 (tal cual y sin
--   comentarios coinciden — no tenía comentarios internos), 754 caracteres,
--   idéntico byte a byte al de 0183. Solo hay una fila para
--   proname='fn_eliminar_periodo' en pg_proc.
--   PENDIENTE (no lo hice yo, lo hace quien consolide/entregue): pedir el
--   md5 de fn_eliminar_periodo a PRODUCCIÓN justo antes de pegar, por la
--   regla de la casa — este md5 es del local, foto de hoy, no garantía.

CREATE OR REPLACE FUNCTION public.fn_eliminar_periodo(p_periodo_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_fin date; v_estado text; v_max date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede eliminar periodos.';
  end if;
  perform pg_advisory_xact_lock(hashtext('periodos_planilla'));
  select fecha_fin, estado into v_fin, v_estado from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
  select max(fecha_fin) into v_max from periodos_planilla;
  if v_fin <> v_max then
    raise exception 'Solo se puede eliminar el ÚLTIMO periodo (para no romper la cadena).';
  end if;
  if (v_estado = 'pagado' and not exists (
        select 1 from periodo_grupo_pago g where g.periodo_id = p_periodo_id
      ))
     or exists (
        select 1 from periodo_grupo_pago g where g.periodo_id = p_periodo_id and g.estado = 'pagado'
      )
  then
    raise exception 'Un periodo pagado no se elimina; reábrelo primero si de verdad hace falta.';
  end if;
  delete from periodos_planilla where id = p_periodo_id;
end;
$function$;



-- ── 34 · fn_educacion_registrar y fn_educacion_cerrar — llamadores de
--        fn_educacion_fecha_pagada que hay que actualizar en la MISMA
--        migración, porque esa función cambió de firma en el bloque 3 ─────
-- fn_educacion_fecha_pagada pasó de (date) a (date, uuid) en el bloque 3.
-- Estas dos son sus ÚNICAS dos llamadoras en todo el repositorio (confirmado
-- con grep sobre supabase/migrations — las demás coincidencias son
-- migraciones históricas, no la vigente). Sin este bloque, la migración
-- entera queda con la firma vieja rota: "function fn_educacion_fecha_pagada
-- (date) does not exist" en cuanto alguien intente registrar o cerrar una
-- asignación por educación — medido en pgTAP (109, 114, 218, 226) al probar
-- esta migración sin este bloque. Único cambio en las dos: agregar el
-- persona_id que ya tenían a mano a la llamada del candado.
CREATE OR REPLACE FUNCTION public.fn_educacion_registrar(p_persona_id uuid, p_institucion text, p_costo_declarado numeric, p_beneficiario text, p_vigente_desde date, p_vigente_hasta date, p_beneficiario_nombre text DEFAULT NULL::text, p_comprobante_url text DEFAULT NULL::text, p_nota text DEFAULT NULL::text, p_id uuid DEFAULT NULL::uuid, p_motivo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id       uuid;
  v_yo       uuid := fn_persona_actual_id();
  v_monto    numeric;
  v_vieja    asignaciones_educacion%rowtype;
  v_mueve    boolean;
  v_desde    date;
  v_papeles  jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional registra asignaciones por educación.';
  end if;

  if p_institucion is null or length(trim(p_institucion)) < 3 then
    raise exception 'Falta la institución que emite el comprobante.';
  end if;
  if p_beneficiario not in ('trabajador', 'hijo') then
    raise exception 'El beneficiario es «trabajador» o «hijo» (llegó «%»).', p_beneficiario;
  end if;
  if p_beneficiario = 'hijo'
     and (p_beneficiario_nombre is null or length(trim(p_beneficiario_nombre)) < 3) then
    raise exception 'Si el comprobante es de un hijo, escribe a nombre de quién está.';
  end if;
  if p_costo_declarado is null or p_costo_declarado <= 0 then
    raise exception 'El costo que dice el comprobante tiene que ser mayor que cero.';
  end if;
  if p_vigente_hasta is null then
    raise exception 'Falta hasta cuándo vale el comprobante. Una matrícula cubre un ciclo, no la eternidad.';
  end if;
  if p_vigente_hasta < p_vigente_desde then
    raise exception 'La fecha de fin (%) es anterior a la de inicio (%).', p_vigente_hasta, p_vigente_desde;
  end if;

  if not exists (select 1 from personas where id = p_persona_id and estado = 'activo') then
    raise exception 'Esa persona no existe o no está activa.';
  end if;

  -- ⇩ CAMBIO 0281 ⇩ con las fechas y excluyendo la fila que se corrige.
  v_monto := fn_educacion_monto(p_persona_id, p_costo_declarado,
                                p_vigente_desde, p_vigente_hasta, p_id);

  if v_monto <= 0 then
    raise exception
      'No queda techo libre para esas fechas: las asignaciones que ya tiene vigentes '
      'agotan el tope de su rango. Cierra o acorta la otra asignación, mueve estas '
      'fechas, o sube el tope en topes_educacion_rango si la política cambió.';
  end if;

  -- ── Alta ────────────────────────────────────────────────────────────────
  if p_id is null then
    if fn_educacion_fecha_pagada(p_vigente_desde, p_persona_id) is true then
      raise exception
        'Esa fecha de inicio (%) cae en un periodo ya PAGADO: registrarla cambiaría una '
        'planilla cerrada. Registra desde el periodo abierto, o reabre el periodo primero.',
        p_vigente_desde;
    end if;

    insert into asignaciones_educacion (
      persona_id, monto, institucion, costo_declarado, cobertura_pct,
      beneficiario, beneficiario_nombre, vigente_desde, vigente_hasta,
      nota, registrado_por
    ) values (
      p_persona_id, v_monto, trim(p_institucion), p_costo_declarado, 75,
      p_beneficiario, nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
      p_vigente_desde, p_vigente_hasta,
      nullif(trim(coalesce(p_nota, '')), ''), v_yo
    )
    returning id into v_id;

    -- ⇩ CAMBIO 0290 ⇩ El papel ya no se escribe en la columna —es derivada— sino
    -- que entra en educacion_comprobantes, respaldando el mes del periodo en que
    -- empieza la vigencia. El trigger espejo pone la columna al día.
    if p_comprobante_url is not null then
      insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, subido_por)
      values (v_id, p_comprobante_url, fn_educacion_mes_del_periodo(p_vigente_desde), v_yo)
      on conflict do nothing;
    end if;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (p_persona_id, 'educacion_alta', null,
       trim(p_institucion) || ' · S/' || to_char(v_monto, 'FM999999.00') ||
       ' · ' || p_vigente_desde::text || ' a ' || p_vigente_hasta::text,
       v_yo, coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'Alta de asignación por educación'));

    return v_id;
  end if;

  -- ── Corrección ──────────────────────────────────────────────────────────
  select * into v_vieja from asignaciones_educacion where id = p_id;
  if not found then raise exception 'Esa asignación no existe.'; end if;

  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Escribe por qué se corrige. Esto mueve lo que cobra una persona.';
  end if;

  -- ¿La corrección mueve plata? Sólo el costo y las fechas lo hacen. Cambiar el
  -- nombre de la institución o subir el comprobante que faltaba no cambia un
  -- céntimo, y obligar a abrir vigencia nueva por eso llenaría la lista de filas
  -- cerradas por erratas.
  v_mueve := (v_vieja.costo_declarado is distinct from p_costo_declarado)
          or (v_vieja.vigente_desde   is distinct from p_vigente_desde)
          or (v_vieja.vigente_hasta   is distinct from p_vigente_hasta)
          or (v_vieja.persona_id      is distinct from p_persona_id);

  if not v_mueve then
    update asignaciones_educacion set
      institucion         = trim(p_institucion),
      beneficiario        = p_beneficiario,
      beneficiario_nombre = nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
      nota                = nullif(trim(coalesce(p_nota, '')), '')
    where id = p_id;

    -- El comprobante se enlaza en un segundo paso, cuando el archivo terminó de
    -- subir. Desde la 0290 eso es una fila más, no un update de la columna.
    if p_comprobante_url is not null then
      insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, subido_por)
      values (p_id, p_comprobante_url, fn_educacion_mes_del_periodo(v_vieja.vigente_desde), v_yo)
      on conflict do nothing;
    end if;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (v_vieja.persona_id, 'educacion_datos', v_vieja.institucion,
       trim(p_institucion), v_yo, trim(p_motivo));

    return p_id;
  end if;

  -- Mueve plata: la fila vieja se cierra el día anterior al que rige el cambio y
  -- nace una nueva. Lo ya pagado queda escrito tal como se pagó.
  v_desde := greatest(fn_educacion_desde_cuando_puede_regir(), v_vieja.vigente_desde);

  if fn_educacion_fecha_pagada(v_desde, p_persona_id) is true then
    raise exception
      'No hay ningún periodo abierto desde el que aplicar esta corrección: todos los que '
      'tocan esta asignación están pagados. Reabre el periodo primero.';
  end if;

  -- ⇩ CAMBIO 0281 ⇩ el tramo que de verdad va a regir, no el que se escribió.
  v_monto := fn_educacion_monto(p_persona_id, p_costo_declarado,
                                greatest(v_desde, p_vigente_desde), p_vigente_hasta, p_id);

  if v_monto <= 0 then
    raise exception
      'No queda techo libre para esas fechas: las asignaciones que ya tiene vigentes '
      'agotan el tope de su rango. Cierra o acorta la otra asignación, mueve estas '
      'fechas, o sube el tope en topes_educacion_rango si la política cambió.';
  end if;

  -- ⇩ CAMBIO 0290 ⇩ Los papeles se copian a la vigencia nueva ANTES de tocar la
  -- vieja: si la vieja se borra, se los llevaría por delante (la tabla cuelga de
  -- ella con `on delete cascade`), y la nueva nacería sin sustento — o sea, sin
  -- devengar. Se COPIAN y no se mueven: los de la vieja siguen sosteniendo lo
  -- que ya se pagó con ella.
  select coalesce(jsonb_agg(jsonb_build_object(
           'ruta', c.storage_path, 'mes', c.mes_cubierto,
           'nota', c.nota, 'quien', c.subido_por)), '[]'::jsonb)
    into v_papeles
    from educacion_comprobantes c
   where c.asignacion_id = p_id;

  if v_desde > v_vieja.vigente_desde then
    update asignaciones_educacion
       set vigente_hasta = v_desde - 1
     where id = p_id;
  else
    -- La fila vieja nunca llegó a devengar en un periodo pagado: se reemplaza
    -- entera en vez de dejar un tramo de un día que no significa nada.
    delete from asignaciones_educacion where id = p_id;
  end if;

  -- ⇩ CAMBIO 0281 ⇩ `created_at` viaja con la fila. Desde esta migración ese
  -- campo decide el orden en que las asignaciones se reparten el techo, así que
  -- corregir una no puede mandarla al final de la cola.
  insert into asignaciones_educacion (
    persona_id, monto, institucion, costo_declarado, cobertura_pct,
    beneficiario, beneficiario_nombre, vigente_desde, vigente_hasta,
    nota, registrado_por, created_at
  ) values (
    p_persona_id, v_monto, trim(p_institucion), p_costo_declarado, 75,
    p_beneficiario, nullif(trim(coalesce(p_beneficiario_nombre, '')), ''),
    greatest(v_desde, p_vigente_desde), p_vigente_hasta,
    nullif(trim(coalesce(p_nota, '')), ''), v_yo, v_vieja.created_at
  )
  returning id into v_id;

  -- Los papeles de la vigencia anterior, y el nuevo si vino uno. Sólo los meses
  -- que la vigencia nueva de verdad paga: un recibo de un mes que ya no cobra no
  -- sostiene nada.
  insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, nota, subido_por)
  select v_id, x->>'ruta', (x->>'mes')::date, x->>'nota', nullif(x->>'quien', '')::uuid
    from jsonb_array_elements(v_papeles) x
   where exists (
     select 1 from fn_educacion_meses_del_tramo(greatest(v_desde, p_vigente_desde), p_vigente_hasta) m
      where m = (x->>'mes')::date)
  on conflict do nothing;

  if p_comprobante_url is not null then
    insert into educacion_comprobantes (asignacion_id, storage_path, mes_cubierto, subido_por)
    values (v_id, p_comprobante_url,
            fn_educacion_mes_del_periodo(greatest(v_desde, p_vigente_desde)), v_yo)
    on conflict do nothing;
  end if;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'educacion_nueva_vigencia',
     'S/' || to_char(v_vieja.monto, 'FM999999.00') || ' desde ' || v_vieja.vigente_desde::text,
     'S/' || to_char(v_monto, 'FM999999.00') || ' desde ' || greatest(v_desde, p_vigente_desde)::text,
     v_yo, trim(p_motivo));

  return v_id;
end;
$function$

;


-- fn_educacion_cerrar tenía DOS sobrecargas viviendo a la vez en la base —
-- hallazgo de esta migración, no algo que introduce: la 0149 agregó
-- `p_motivo` y el candado con `create or replace function
-- fn_educacion_cerrar(p_id uuid, p_hasta date, p_motivo text default null)`
-- sin soltar antes la firma vieja de 2 argumentos de la 0136, así que las
-- dos quedaron coexistiendo desde entonces — el mismo accidente que la
-- 0297/0299 con fn_vacaciones_por_vencer, documentado en CLAUDE.md. La
-- pantalla (admin/educacion/page.tsx) siempre llama con los 3 argumentos,
-- así que la de 2 nunca se ejecuta — pero seguía ahí SIN el candado de
-- periodo pagado, una puerta trasera silenciosa a la misma tabla. Se
-- aprovecha esta migración, ya que la tocaba de todos modos, para cerrarla.
drop function if exists fn_educacion_cerrar(uuid, date);

CREATE OR REPLACE FUNCTION public.fn_educacion_cerrar(p_id uuid, p_hasta date, p_motivo text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r asignaciones_educacion%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional cierra asignaciones por educación.';
  end if;

  select * into r from asignaciones_educacion where id = p_id;
  if not found then raise exception 'Esa asignación no existe.'; end if;

  if p_hasta < r.vigente_desde then
    raise exception 'La fecha de cierre (%) es anterior al inicio (%).', p_hasta, r.vigente_desde;
  end if;

  if fn_educacion_fecha_pagada(p_hasta, r.persona_id) is true then
    raise exception
      'Esa fecha de cierre (%) cae en un periodo ya PAGADO: acortar la vigencia ahí '
      'cambiaría una planilla cerrada.', p_hasta;
  end if;

  update asignaciones_educacion set vigente_hasta = p_hasta where id = p_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (r.persona_id, 'educacion_cierre', r.vigente_hasta::text, p_hasta::text,
     fn_persona_actual_id(),
     coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'Cierre de asignación por educación'));
end;
$function$

;


-- ── 35 · Rastro ──────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (327, 'el_candado_de_horas_pasa_a_ser_por_grupo')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
