-- ============================================================================
-- 0156 — La 0152 se anota, y desde ahora el olvido lo caza una prueba
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `migraciones_aplicadas` vuelva a leerse como «lo que hay aplicado», sin
--   la omisión de la 0152 adentro.
--
-- QUÉ ASUME
--   Que la 0152 ya corrió en esta base. Comprobado en producción el 2026-08-05:
--   `to_regprocedure('fn_movilidad_no_supera_el_techo()')` devuelve la función,
--   así que su contenido está. La comprobación de abajo lo vuelve a verificar
--   antes de dar el registro por bueno, para que esta migración no pueda
--   escribir una fila falsa en una base donde la 0152 no se haya aplicado.
--
-- POR QUÉ UNA MIGRACIÓN NUEVA Y NO UNA LÍNEA EN LA 0152
--   Porque la 0152 YA ESTÁ PEGADA EN PRODUCCIÓN. Agregarle el insert haría que
--   el archivo del repo dejara de ser lo que se aplicó — exactamente la clase de
--   divergencia que el registro existe para cerrar. Mismo criterio y mismo
--   procedimiento que la 0146 con las 0128, 0131 y 0132; si esto se repite una
--   tercera vez, el patrón deja de ser un descuido y pasa a ser el proceso.
--
-- CÓMO SE ENCONTRÓ, Y POR QUÉ NO VA A HACER FALTA BUSCARLO OTRA VEZ
--   No la encontró nadie mirando: la encontró la prueba
--   `122_toda_migracion_deja_su_rastro.test.sql`, en su primera corrida. Esa
--   prueba compara los dos registros que se escriben por caminos distintos —el
--   del CLI de Supabase, que es automático, y `migraciones_aplicadas`, que es a
--   mano— y falla cuando se separan. Con esta migración aplicada, la prueba pasa
--   a verde y de ahí en adelante cualquier olvido cae en CI el mismo día.
--
--   Lo que esa prueba NO puede ver son dos archivos con el mismo número:
--   `supabase db reset` aplica uno, saltea el otro EN SILENCIO y termina sin
--   error, así que el saltado nunca corre y Postgres jamás se entera de que
--   existió. Comprobado el 2026-08-05 con las dos migraciones 0154 que
--   convivieron unos minutos. De eso se encarga `scripts/hooks/numeracion.sh`,
--   que mira nombres de archivo antes de cada push.
--
-- CÓMO SE REVIERTE
--   `delete from migraciones_aplicadas where numero = 152;`
--   No hay cambio de esquema ni de datos de negocio: esto solo escribe en el
--   registro.
-- ============================================================================

insert into migraciones_aplicadas (numero, nombre)
values (152, 'la_movilidad_tiene_techo')
on conflict (numero) do nothing;

insert into migraciones_aplicadas (numero, nombre)
values (156, 'la_movilidad_con_techo_se_anota')
on conflict (numero) do nothing;

do $mig$
begin
  -- La 0152 deja esta función. Si no está, la fila que acabamos de escribir es
  -- mentira y hay que saberlo AHORA, no en la próxima auditoría de huecos.
  if to_regprocedure('fn_movilidad_no_supera_el_techo()') is null then
    raise warning '0156 · OJO: se anoto la 0152 y su funcion NO existe en esta base.';
    raise warning '0156 · revisa si se salteo, y borra su fila si no se aplico:';
    raise warning '0156 ·   delete from migraciones_aplicadas where numero = 152;';
  else
    raise notice '0156 · la 0152 esta aplicada de verdad: el registro quedo honesto.';
  end if;

  raise notice '0156 · migraciones anotadas ahora: %', (select count(*) from migraciones_aplicadas);
end $mig$;

notify pgrst, 'reload schema';
