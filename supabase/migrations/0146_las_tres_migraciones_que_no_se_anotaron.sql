-- ============================================================================
-- 0146 — Las tres migraciones que se aplicaron sin anotarse
-- ============================================================================
--
-- QUÉ PROMETE
--   Después de esta migración, `migraciones_aplicadas` vuelve a poder leerse
--   como «lo que hay aplicado», sin tres omisiones adentro. Y las tres
--   migraciones culpables quedan anotando su propio paso de aquí en adelante.
--
-- QUÉ ASUME
--   Que las 0128, 0131 y 0132 ya corrieron en esta base. Es cierto por
--   construcción cuando se aplica en orden —van 15 números antes— y es lo que
--   pasa tanto en `supabase db start` como al pegarlas a mano en orden.
--   Si alguien saltea una y aplica esta, el registro mentiría al revés; por eso
--   la comprobación de abajo avisa cuando el objeto que cada una crea no está.
--
-- POR QUÉ ASÍ, Y NO DE OTRA FORMA
--   La convención del repo es que cada migración escriba su propia fila en
--   `migraciones_aplicadas`. Estas tres no la escriben:
--
--     0128 · la_base_declarada_por_rango
--     0131 · reabrir_para_cambiar_firmante
--     0132 · el_tope_de_educacion_por_rango
--
--   No es un detalle de contabilidad. Ese registro es lo ÚNICO que se puede
--   consultar para saber qué hay en producción sin abrir el SQL Editor y mirar
--   función por función. Con tres omisiones adentro, cualquier auditoría de
--   huecos da un resultado falso — y este repositorio acaba de pagar una: la
--   0137 estuvo perdida un día entero porque el registro decía una cosa y los
--   archivos otra.
--
--   Se arregla acá, en una migración aparte, y NO editando las tres originales.
--   Una migración ya aplicada en producción no se toca: si se le agrega el
--   insert, el archivo del repo deja de ser lo que se pegó, que es justo la
--   clase de divergencia que esto viene a cerrar.
--
--   El insert es idempotente (`on conflict do nothing`), así que aplicar esto
--   dos veces, o aplicarlo en una base donde alguien ya las anotó a mano con
--   `scripts/sql-manual/aplicar_0137.sql`, no hace nada.
--
-- POR QUÉ NO ARREGLA EL PROBLEMA DE RAÍZ
--   Esto tapa tres omisiones concretas. Lo que no impide es la cuarta: nada
--   obliga hoy a que una migración nueva se anote. Mientras el registro dependa
--   de que quien escribe el archivo se acuerde, va a volver a fallar. La defensa
--   de verdad es una prueba que compare los archivos de `supabase/migrations`
--   contra `migraciones_aplicadas` después de un `db reset` y falle si alguno no
--   se anotó. Queda propuesto, no hecho.
--
-- CÓMO SE REVIERTE
--   `delete from migraciones_aplicadas where numero in (128, 131, 132);`
--   No hay cambio de esquema ni de datos de negocio: esta migración solo escribe
--   en el registro.
-- ============================================================================

insert into migraciones_aplicadas (numero, nombre) values
  (128, 'la_base_declarada_por_rango'),
  (131, 'reabrir_para_cambiar_firmante'),
  (132, 'el_tope_de_educacion_por_rango')
on conflict (numero) do nothing;

insert into migraciones_aplicadas (numero, nombre)
values (146, 'las_tres_migraciones_que_no_se_anotaron')
on conflict (numero) do nothing;

do $mig$
declare
  v_falta text := '';
begin
  -- Cada una deja un objeto reconocible. Si el objeto no está, la fila que
  -- acabamos de escribir es mentira y hay que saberlo AHORA, no en la próxima
  -- auditoría de huecos.
  if to_regprocedure('fn_fijar_base_declarada(text, numeric, date, uuid[])') is null then
    v_falta := v_falta || ' 0128';
  end if;
  if to_regprocedure('fn_expediente_reabrir(uuid)') is null then
    v_falta := v_falta || ' 0131';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_name = 'topes_educacion_rango') then
    v_falta := v_falta || ' 0132';
  end if;

  if v_falta <> '' then
    raise warning '0146 · OJO: se anotaron migraciones cuyo objeto NO existe en esta base:%', v_falta;
    raise warning '0146 · revisa si se saltearon, y borra su fila si no se aplicaron.';
  else
    raise notice '0146 · las tres estan aplicadas de verdad: el registro quedo honesto.';
  end if;

  raise notice '0146 · migraciones anotadas ahora: %', (select count(*) from migraciones_aplicadas);
end $mig$;

notify pgrst, 'reload schema';
