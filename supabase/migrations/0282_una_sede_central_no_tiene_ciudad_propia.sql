-- ============================================================================
-- 0282 — Una sede «central» no tiene ciudad propia
-- ============================================================================
--
-- QUÉ PROMETE
--   Que Central deje de declarar una ciudad que no le corresponde, y que el
--   contrato de una persona administrativa pregunte en qué ciudad se firma en
--   vez de deducirla de su sede.
--
-- QUÉ CORRIGE, Y POR QUÉ ERA UN ERROR DE CONCEPTO
--   La 0279 agregó `sedes.ciudad` y rellenó Central con «Trujillo», deducido
--   del domicilio legal de CAYLA. La deducción era razonable y estaba mal:
--   **Central no es un local, es una clasificación** (aclarado por Felipe el
--   2026-08-23). Distingue al personal administrativo del de tienda y taller
--   —para que no cuente en el tablero de operación— y esa gente puede estar en
--   Arequipa, en Lima o en Trujillo indistintamente.
--
--   Tienda y taller sí son locales: su ciudad es un hecho de la sede y se
--   queda donde está. Lo que no existe es «la ciudad de Central».
--
--   El daño concreto de dejarlo: el contrato de una administrativa de Arequipa
--   habría dicho «En la ciudad de Trujillo» —el lugar de celebración de un
--   contrato de trabajo, escrito mal, en un documento que se firma— y nadie lo
--   habría notado, porque se ve perfectamente plausible.
--
-- POR QUÉ VA POR `tipo` Y NO POR EL CÓDIGO 'CCO'
--   Porque lo que hace que una sede no tenga ciudad propia no es llamarse CCO:
--   es ser de tipo `central` (0099). Si mañana se crea otra sede central desde
--   la pantalla, tiene que comportarse igual sin que nadie se acuerde de esta
--   migración.
--
-- QUÉ PASA DESPUÉS
--   `ciudad` en null significa «este dato no lo sabe la sede». El generador de
--   contratos ya trata el null como dato faltante; con este cambio, la pantalla
--   pide la ciudad al generar el contrato de alguien de Central, y no deja
--   generar hasta que se elija. Para tienda y taller sigue viniendo sola.
--
-- CÓMO SE REVIERTE
--   update sedes set ciudad = 'Trujillo' where tipo = 'central';
--   (pero eso repone el error que esta migración corrige)
-- ============================================================================

update sedes set ciudad = null where tipo = 'central';

comment on column sedes.ciudad is
  'La ciudad donde opera la sede, para los documentos legales que la nombran '
  '(«En la ciudad de …»). Solo la tienen las sedes que SON un local: tienda y '
  'taller. Una sede de tipo `central` la deja en null a proposito (0282) — '
  'central es una clasificacion de personal administrativo, no un lugar, y su '
  'gente puede estar en cualquier ciudad: la ciudad se elige por persona al '
  'generar el contrato.';

insert into migraciones_aplicadas (numero, nombre)
values (282, 'una_sede_central_no_tiene_ciudad_propia')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare r record;
begin
  raise notice '0282 · ciudad por sede, tal como quedo:';
  for r in select codigo, tipo, nombre, coalesce(ciudad, '(se elige por persona)') as ciudad
             from sedes order by codigo loop
    raise notice '0282 ·   % [%] (%) -> %', r.codigo, r.tipo, r.nombre, r.ciudad;
  end loop;
end $mig$;
