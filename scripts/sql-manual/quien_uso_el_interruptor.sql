-- ############################################################################
-- ####  SOLO LEE. Diez segundos. Léela tú: lleva nombres.                  ####
-- ############################################################################
--
-- quien_uso_el_interruptor.sql
--
-- ¿Alguien apagó el devengo de beneficios de alguna persona creyendo que servía?
--
-- POR QUÉ IMPORTA, y por qué antes del 28
--   `fn_set_devenga_beneficios` escribe `personas.devenga_beneficios` y deja
--   rastro en `correcciones_auditoria`. Pero el 2026-08-08 se midió —en
--   producción, no en local— que NINGUNA función lee esa columna:
--   `fn_devenga_beneficios(p_tipo)` mira el tipo de vínculo y devuelve
--   `p_tipo = 'planilla'`, y sus cuatro consumidores la llaman con el tipo.
--
--   O sea que la pantalla de Equipo dice que el interruptor funciona y no hace
--   nada. Si alguien lo apagó para una persona, esa persona SIGUE acumulando
--   CTS, gratificación y vacaciones, y las provisiones del cierre lo van a
--   reflejar.
--
--   Esto no se puede saber mirando el código: hay que preguntarle a los datos si
--   alguien llegó a usar el botón.
--
-- CÓMO SE LEE
--   `veces_usado = 0`  → nadie lo tocó. No hay nada que corregir y la decisión
--                        de conectarlo o no puede esperar.
--   `veces_usado > 0`  → esas personas están provisionando como si el
--                        interruptor no existiera. Míralas una por una antes de
--                        cerrar el periodo.
--
-- ⚠️ LLEVA NOMBRES. Córrela y léela tú; no hace falta que salga de tu pantalla.
-- ############################################################################

select
  (select count(*) from correcciones_auditoria
    where campo_modificado = 'personas.devenga_beneficios') as veces_usado,

  -- Quién, a quién, cuándo y qué puso. Vacío si nadie lo usó.
  coalesce((
    select string_agg(
      to_char(ca.corregido_at at time zone 'America/Lima', 'DD/MM HH24:MI')
      || ' · ' || obj.nombres || ' ' || obj.apellidos
      || ' · de «' || coalesce(ca.valor_anterior, '—')
      || '» a «' || coalesce(ca.valor_nuevo, '—') || '»'
      || ' · lo hizo ' || coalesce(aut.nombres, '¿?'),
      E'\n' order by ca.corregido_at desc)
    from correcciones_auditoria ca
    join personas obj on obj.id = ca.persona_id
    left join personas aut on aut.id = ca.corregido_por
    where ca.campo_modificado = 'personas.devenga_beneficios'
  ), 'nadie lo ha usado') as el_detalle,

  -- Y el estado de HOY, que es lo que decide el cierre: quién tiene la bandera
  -- puesta ahora mismo, diga lo que diga la auditoría.
  coalesce((
    select string_agg(p.nombres || ' ' || p.apellidos
                      || ' → devenga=' || coalesce(p.devenga_beneficios::text, 'null')
                      || coalesce(' hasta ' || p.devenga_hasta::text, ''),
                      E'\n' order by p.apellidos)
    from personas p
    where p.devenga_beneficios is not null or p.devenga_hasta is not null
  ), 'nadie tiene la bandera puesta') as como_esta_hoy;
