-- ============================================================================
-- 0143 · Un contrato que vence no es un despido
-- ============================================================================
--
-- QUÉ PROMETE. Que se pueda registrar el motivo de cese más frecuente de un
-- contrato a plazo fijo: llegó su fecha de término y no se renovó. Agrega
-- 'fin_contrato' a los motivos válidos de `personas.motivo_cese`.
--
-- QUÉ ASUME. Que la 0086 ya está aplicada (es la que creó `fecha_cese`,
-- `motivo_cese` y el CHECK `personas_motivo_cese_valido`).
--
-- POR QUÉ SE ELIGIÓ ASÍ.
--
-- La 0086 dejó seis motivos: renuncia · despido · fin_periodo_prueba ·
-- fin_servicio_rxh · mutuo_acuerdo · por_revisar. Falta justo el que más va a
-- usarse: en CAYLA los contratos son a plazo fijo, así que todos terminan
-- alguna vez, y cuando terminan no encajan en ninguno de los seis.
--
-- Sin este valor solo quedan salidas malas, y las dos son caras:
--
--   · 'despido' afirma en la base que la empresa terminó el vínculo CON CAUSA.
--     Un despido exige el procedimiento del D.S. 003-97-TR: carta de preaviso,
--     seis días de descargo, carta de despido. Un contrato que simplemente
--     llega a su fecha de término no exige NADA de eso — se extingue por
--     vencimiento del plazo (D.Leg. 728, art. 16 inciso c). Escribir 'despido'
--     donde hubo vencimiento pone al sistema a declarar un acto que después no
--     se puede sostener con papeles, y ese descuadre juega en contra de CAYLA,
--     no a favor: quien reclama solo tiene que señalar que el propio sistema
--     de la empresa lo llamó despido y que no existe el expediente que un
--     despido requiere.
--
--   · 'mutuo_acuerdo' es sencillamente falso cuando la persona no acordó nada.
--
-- El motivo de cese no es una etiqueta administrativa: es lo que va a leer
-- quien arme la liquidación y quien conteste una inspección dentro de dos años,
-- cuando ya nadie recuerde el caso. Tiene que decir lo que pasó.
--
-- NO se agrega un motivo para «no se renovó por conducta». La conducta que
-- justifica no renovar se documenta en el expediente disciplinario, que para
-- eso existe; meterla en `motivo_cese` la convertiría en una imputación sin
-- descargo — exactamente lo que este sistema evita por diseño («Dynamic avisa,
-- nunca sanciona solo»). Un contrato a plazo fijo puede no renovarse sin
-- expresar causa, y esa es su ventaja: no hay que probar nada.
--
-- CÓMO SE REVIERTE.
--   update personas set motivo_cese = null where motivo_cese = 'fin_contrato';
--   alter table personas drop constraint personas_motivo_cese_valido;
--   alter table personas add constraint personas_motivo_cese_valido
--     check (motivo_cese is null or motivo_cese in
--       ('renuncia','despido','fin_periodo_prueba','fin_servicio_rxh',
--        'mutuo_acuerdo','por_revisar'));
-- ============================================================================

-- Idempotente: se reconstruye el CHECK completo, así pegarla dos veces no
-- rompe nada. Solo AGREGA un valor — todas las filas que ya existen siguen
-- siendo válidas, así que no hace falta tocar ni una.
alter table personas drop constraint if exists personas_motivo_cese_valido;

alter table personas add constraint personas_motivo_cese_valido
  check (motivo_cese is null or motivo_cese in (
    'renuncia',            -- se fue por decisión propia
    'despido',             -- la empresa terminó el vínculo CON CAUSA, con su expediente
    'fin_contrato',        -- ⇦ 0137: venció el plazo pactado y no se renovó
    'fin_periodo_prueba',  -- vino a probar y no continúa
    'fin_servicio_rxh',    -- terminó el servicio por recibo por honorarios
    'mutuo_acuerdo',
    'por_revisar'          -- solo backfill: no se pudo deducir la fecha real
  ));

comment on column personas.motivo_cese is
  'Por que termino el vinculo. fin_contrato = vencio el plazo pactado y no se renovo (extincion por vencimiento, D.Leg. 728 art.16.c): NO requiere procedimiento previo. despido = la empresa termino con causa, y ese si exige carta de preaviso y descargo (D.S. 003-97-TR). No son intercambiables.';

insert into migraciones_aplicadas (numero, nombre) values (143, 'un_contrato_que_vence_no_es_un_despido')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $$
begin
  raise notice '0143 · motivo_cese acepta ahora fin_contrato. Motivos validos: renuncia, despido, fin_contrato, fin_periodo_prueba, fin_servicio_rxh, mutuo_acuerdo, por_revisar.';
end $$;
