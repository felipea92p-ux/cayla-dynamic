-- ============================================================================
-- encender_sexto_cts.sql — la CTS pasa a calcularse sobre sueldo + su sexto
-- ============================================================================
--
-- QUÉ HACE. Enciende la clave `sexto_cts` que la migración 0112 dejó apagada a
-- propósito. Desde ese momento, la base de la CTS deja de ser el sueldo pelado y
-- pasa a ser sueldo × 13/12, como manda el Art. 16 del D.S. 001-97-TR: la
-- remuneración computable de la CTS incluye «un sexto de lo percibido» por
-- gratificación, y en pequeña empresa la gratificación es MEDIA remuneración,
-- así que ese sexto vale sueldo/12.
--
-- QUÉ MUEVE, EN PLATA. La CTS SUBE. Nada baja, nadie cobra menos: sobre un
-- sueldo de S/1,130 la base pasa de 1,130 a 1,224.17, y la CTS del año de
-- S/565.00 a S/612.08 — S/47.08 más por persona, y proporcionalmente más en los
-- sueldos altos.
--
-- QUÉ NO TOCA. Ni la gratificación ni las vacaciones. El sexto es un requisito
-- exclusivo de la base de CTS, y que no se cuele en los otros dos conceptos es
-- justo lo que blinda `supabase/tests/126_el_sexto_entra_solo_en_la_cts.test.sql`
-- —comprobado el 2026-08-05 rompiendo la función a propósito: al colarlo en la
-- gratificación, la prueba falla nombrando el monto exacto—.
--
-- LO QUE HAY QUE SABER ANTES DE CORRERLO. No existe casación ni informe de
-- SUNAFIL que zanje este punto para el régimen MYPE: la conclusión es una
-- derivación del TUO de la Ley de CTS y del documento «Apuntes sobre la CTS» del
-- MTPE, con certeza alta pero no confirmada por autoridad. Provisionar de más no
-- es infracción; provisionar de menos sí. Decisión de Felipe, 2026-08-05.
--
-- CÓMO SE REVIERTE. Poner la clave en 0 — el multiplicador vuelve a 1 y la CTS
-- se calcula otra vez sobre el sueldo pelado:
--
--   update configuracion
--      set valor = valor || '{"sexto_cts": 0}'::jsonb
--    where clave = 'planilla_provisiones';
--
-- CÓMO SE CORRE. Va dentro de BEGIN … COMMIT a propósito: la primera consulta
-- muestra cómo está, la segunda cómo queda, y recién entonces se confirma. Si
-- algo no cuadra, se escribe ROLLBACK en vez de COMMIT y no pasó nada.
-- ============================================================================

begin;

-- ── 1 · Cómo está ahora ─────────────────────────────────────────────────────
select 'ANTES' as momento,
       valor->>'cts'        as factor_cts,
       valor->>'sexto_cts'  as sexto_cts,
       case when valor ? 'sexto_cts' and (valor->>'sexto_cts')::numeric > 0
            then 'YA ESTABA ENCENDIDO — este script no hace falta'
            else 'apagado: la CTS se calcula sobre el sueldo pelado'
       end as estado
  from configuracion
 where clave = 'planilla_provisiones';

-- ── 2 · Encender ────────────────────────────────────────────────────────────
-- 0.083333 = 1/12. Se guarda como multiplicador y no subiendo el factor de la
-- CTS de 4.167% a 4.514%, que daría el mismo número HOY pero se rompería en
-- cuanto la base incluyera otro concepto remunerativo —la asignación familiar,
-- por ejemplo—: el sexto debe salir de la gratificación real, no del sueldo
-- pelado. Multiplicando la base, el sexto sigue siendo un sexto de lo que sea.
update configuracion
   set valor = valor || '{"sexto_cts": 0.083333}'::jsonb
 where clave = 'planilla_provisiones';

-- ── 3 · Cómo queda ──────────────────────────────────────────────────────────
select 'DESPUES' as momento,
       valor->>'cts'       as factor_cts,
       valor->>'sexto_cts' as sexto_cts,
       valor->>'gratificacion' as factor_grati,
       valor->>'vacaciones'    as factor_vacaciones
  from configuracion
 where clave = 'planilla_provisiones';

-- ── 4 · La comprobación que decide si confirmar ─────────────────────────────
-- Si esto no devuelve exactamente una fila diciendo LISTO, escribe ROLLBACK.
select case
         when (valor->>'sexto_cts')::numeric = 0.083333
          and (valor->>'gratificacion')::numeric = 0.08333
          and (valor->>'vacaciones')::numeric    = 0.04167
          and (valor->>'cts')::numeric           = 0.04167
         then 'LISTO · el sexto quedó encendido y los otros tres factores intactos'
         else 'PARA — algo cambió que no debía. Escribe ROLLBACK.'
       end as resultado
  from configuracion
 where clave = 'planilla_provisiones';

-- Si la línea de arriba dice LISTO:
commit;

-- Si dice PARA:
-- rollback;
