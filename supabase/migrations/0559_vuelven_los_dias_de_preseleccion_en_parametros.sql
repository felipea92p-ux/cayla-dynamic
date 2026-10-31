-- ============================================================================
-- 0559 · VUELVEN LOS «DÍAS DE PRESELECCIÓN» EN PARÁMETROS Y SE RETIRA LO QUE QUEDA SIN DUEÑO
-- ============================================================================
--
-- QUÉ PROMETE
--   En «Parámetros» (0552):
--     1. Vuelve la fila `prueba_dias`, ahora llamada «Días de preselección antes
--        del contrato»: los días trabajados que cumple quien está en preselección
--        antes de que se le haga el contrato (1–15, hoy 3). La lee
--        `fn_prueba_dias_plazo()`, que nunca dejó de existir.
--     2. Se retiran las tres filas que la semana pasada agregaron la 0553 y la
--        0557 y que, con el vínculo de vuelta, ningún código lee:
--          · `periodo_prueba_meses`            (0553, mostraba los 3 meses de la ley)
--          · `feriado_aviso_antiguedad_dias`   (0553, el aviso de feriado por antigüedad)
--          · `prueba_etiqueta_desde`           (0557, la fecha de corte de la etiqueta)
--        Se BORRAN si nunca se cambiaron; si ya tienen historial se quedan fijas y
--        dichas «(retirado)», porque `parametros_historial` es inmutable y
--        apunta a esa fila. El rastro nunca se borra.
--     3. Se sueltan las dos funciones de lectura que servían a esas filas:
--        `fn_feriado_aviso_dias()` y `fn_prueba_etiqueta_desde()`. No guardan
--        datos y ninguna pantalla las llama ya.
--
-- DE DÓNDE SALE (decidido con Felipe el 2026-10-27)
--   «Volvamos a ponerlo como prueba [ahora: preselección]; de momento mantengámoslo
--   así como era antes, toda la función.» El aviso de feriado vuelve a mirar a quien
--   está en preselección (vínculo + días trabajados), así que su parámetro por
--   antigüedad se queda sin quien lo use; y un número editable que nada lee es un
--   dato sin dueño: DO lo movería y no pasaría nada.
--
-- QUÉ ASUME
--   · La 0552 pegada: existen `parametros_catalogo`, `parametros_historial` y el
--     candado sobre `configuracion`. Se comprueba abajo y la migración se NIEGA a
--     entrar si no.
--
-- QUÉ NO HACE
--   · NO TOCA LA PLANILLA ni ninguna función de pago. Ni una línea de
--     `fn_planilla_calcular*`. No hay md5 de planilla que pedir a producción.
--   · NO CAMBIA A NADIE de vínculo (eso es la 0558).
--   · NO SUELTA `personas.prueba_pactada_dias`, `fn_set_prueba_pactada` ni su
--     candado (0556). La columna es de las que guardan datos, ninguna pantalla la
--     usa y dejarla no estorba; soltarla es otra decisión, y la 0556 ya dejó
--     escrito «antes de soltarla, exportarlos».
--   · NO TOCA `fn_prueba_dias_plazo()` ni `configuracion.prueba_dias`: la
--     maquinaria (0536) siempre los leyó.
--
-- POR QUÉ SE BORRAN LAS CLAVES DE `configuracion`
--   Cuando la fila del catálogo se borra, su clave de `configuracion` queda sin
--   nadie que la lea. Se borra con ella, igual que el candado de la 0552 trata
--   una clave que ningún parámetro usa: «se escribe como siempre».
--
-- CÓMO SE REVIERTE
--   Pegar de nuevo la 0553 y la 0557 (son idempotentes: vuelven las tres filas y
--   las dos funciones) y quitar la fila `prueba_dias` editable con el `update` de
--   la sección «retiro» de la 0553.
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final, y la prueba pgTAP 451.
-- ============================================================================

-- ── Guardia: la 0552 tiene que estar ────────────────────────────────────────
do $guardia$
begin
  if to_regclass('public.parametros_catalogo') is null
     or to_regclass('public.parametros_historial') is null
     or to_regprocedure('public.fn_parametro_numero_en(jsonb,text[])') is null then
    raise exception 'PARA. Falta la 0552 (Parámetros): no existe parametros_catalogo, parametros_historial o fn_parametro_numero_en. Pega primero la 0552.';
  end if;
end
$guardia$;

-- ── 1 · Vuelve «Días de preselección antes del contrato» ────────────────────
-- La clave primero y solo si falta: la siembra no es un cambio y no deja historial.
-- (Si la 0553 ya la dejó, no se toca: tiene el valor que alguien eligió.)
insert into configuracion (clave, valor, descripcion)
select 'prueba_dias', '3'::jsonb,
       'Días trabajados (con jornada cerrada) que cumple quien está en preselección antes de hacerle el contrato. 0552, 0559.'
 where not exists (select 1 from configuracion where clave = 'prueba_dias');

insert into parametros_catalogo
  (parametro, nombre, descripcion, unidad, clase, tipo_valor, valor_min, valor_max, valor_defecto,
   almacen_clave, ruta, editable, base, orden)
values
  ('prueba_dias',
   'Días de preselección antes del contrato',
   'Días trabajados, con la jornada cerrada, que cumple quien está en preselección antes de que se le haga el contrato. Si pasa el plazo sin que nadie decida, DO recibe la alerta. Más días es más tiempo trabajando sin contrato firmado.',
   'días', 'operativo', 'entero', 1, 15, 3,
   'prueba_dias', null, true,
   'Decisión de CAYLA (2026-10-19, migración 0536; vuelve el 2026-10-27, migración 0559)', 10)
on conflict (parametro) do update
   set nombre = excluded.nombre, descripcion = excluded.descripcion, unidad = excluded.unidad,
       clase = excluded.clase, tipo_valor = excluded.tipo_valor,
       valor_min = excluded.valor_min, valor_max = excluded.valor_max, valor_defecto = excluded.valor_defecto,
       almacen_clave = excluded.almacen_clave, ruta = excluded.ruta,
       editable = excluded.editable, base = excluded.base, orden = excluded.orden;

-- ── 2 · Se retiran las tres filas sin dueño ─────────────────────────────────
do $retiro$
declare
  v_p text;
begin
  foreach v_p in array array['periodo_prueba_meses', 'feriado_aviso_antiguedad_dias', 'prueba_etiqueta_desde'] loop
    if exists (select 1 from parametros_historial where parametro = v_p) then
      -- Ya la movió alguien: el historial es inmutable y apunta a esta fila. Se queda, fija y dicha.
      update parametros_catalogo
         set nombre      = case when nombre like '%(retirado)' then nombre else nombre || ' (retirado)' end,
             descripcion = 'Ya no se usa para nada: «prueba» volvió a ser un vínculo, con el nombre de «preselección» (0559). Se conserva solo porque tiene historial.',
             clase       = 'normativo',
             editable    = false,
             orden       = 900
       where parametro = v_p;
    else
      delete from parametros_catalogo where parametro = v_p;
      -- Sin fila de catálogo, la clave queda libre del candado: se borra sin pasar por la puerta.
      delete from configuracion where clave = v_p;
    end if;
  end loop;
end
$retiro$;

-- ── 3 · Se sueltan las dos funciones de lectura ─────────────────────────────
drop function if exists fn_feriado_aviso_dias();
drop function if exists fn_prueba_etiqueta_desde();

-- ── Registro ────────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (559, 'vuelven_los_dias_de_preseleccion_en_parametros')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Debe dar: true · 0 · true · 3 · «559 · vuelven_los_dias_de_preseleccion_…»
select
  (select count(*) = 1 from parametros_catalogo
    where parametro = 'prueba_dias' and editable and clase = 'operativo')       as los_dias_de_preseleccion_se_editan,
  (select count(*) from parametros_catalogo
    where parametro in ('periodo_prueba_meses', 'feriado_aviso_antiguedad_dias', 'prueba_etiqueta_desde')
      and editable)                                                             as filas_sin_dueno_que_se_editan,
  (select count(*) = 0 from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('fn_feriado_aviso_dias', 'fn_prueba_etiqueta_desde'))     as las_dos_funciones_ya_no_estan,
  fn_prueba_dias_plazo()                                                        as dias_de_preseleccion_hoy,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 559) as registro;
