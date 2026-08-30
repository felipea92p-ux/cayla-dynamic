-- ============================================================================
-- 0325 · Un convenio de prácticas también termina
-- ============================================================================
-- QUÉ PROMETE
--
--   Agrega 'fin_convenio_practicas' a los motivos válidos de
--   `personas.motivo_cese`, para que dar de baja a una practicante (0322) no
--   obligue a escribir un motivo que describe otra cosa.
--
-- QUÉ ASUME
--
--   Que la 0086 (fecha_cese, motivo_cese, el CHECK) y la 0143 (última que lo
--   reescribió) ya están aplicadas, y que la 0322 ya creó
--   `tipo_vinculo = 'practicante'`.
--
-- POR QUÉ SE ELIGIÓ ASÍ
--
--   Hoy `fn_cesar_persona` recibe el motivo como texto libre elegido a mano en
--   la pantalla de Equipo (no se deduce del `tipo_vinculo`), y el CHECK
--   `personas_motivo_cese_valido` (0143) todavía no tiene ninguna opción que le
--   quede bien a un convenio de modalidad formativa. Las que hay hoy describen
--   todas una relación LABORAL:
--
--     · 'fin_contrato' — la 0143 lo escribió a propósito para un CONTRATO a
--       plazo fijo que vence sin renovarse (D.Leg. 728, art. 16 inciso c). Un
--       convenio de prácticas no es un contrato de trabajo (0322: «no es una
--       relación laboral») — usarlo aquí declararía en la base un vínculo
--       laboral que nunca existió.
--     · 'fin_periodo_prueba' — es específico del periodo de prueba de UN
--       trabajador en planilla (art. 10, D.Leg. 728). Una practicante no tiene
--       periodo de prueba: tiene un convenio con plazo propio (Ley 28518,
--       art. 30 y ss.).
--     · 'fin_servicio_rxh' — es la salida de un locador por honorarios, cuyo
--       vínculo es una locación de servicios (Código Civil, art. 1764). La
--       0322 ya fue explícita en que un practicante NO es un prestador de
--       servicios: llamar a su salida «fin de servicio» repite el mismo error
--       de lenguaje que la 0322 evitó en la boleta.
--     · 'mutuo_acuerdo' / 'renuncia' / 'despido' — solo aplican si el
--       convenio termina antes de su plazo por decisión de una de las partes;
--       siguen sirviendo tal cual para ese caso puntual y no se tocan.
--
--   Sin un motivo propio, la salida menos mala era 'fin_contrato' — y por lo
--   mismo que la 0143 no dejó reciclar 'despido' para un vencimiento de plazo:
--   quien lea el legajo dentro de dos años, o conteste una fiscalización,
--   encontraría un «contrato» donde nunca lo hubo. El motivo de cese no es una
--   etiqueta administrativa (0143): es lo que sostiene qué expediente hace
--   falta y cuál no.
--
--   Y por lo mismo importa que exista: un convenio de prácticas que TERMINA no
--   genera liquidación de beneficios sociales (CTS, vacaciones truncas,
--   gratificación trunca) porque nunca los devengó (0322, art. 47 Ley 28518) —
--   a diferencia de 'fin_contrato', que si es de alguien en planilla, sí la
--   dispara. Guardar el motivo correcto es lo que permite, más adelante,
--   explicar por qué a esa persona no le corresponde liquidación sin tener que
--   revisar su `tipo_vinculo` aparte.
--
-- QUÉ NO HACE
--
--   No cambia `fn_cesar_persona`: sigue aceptando el motivo como parámetro de
--   texto libre validado solo por este CHECK, igual que desde la 0086. No
--   agrega ninguna deducción automática de motivo a partir de `tipo_vinculo`
--   (ni las cuatro migraciones anteriores que agregaron un motivo lo
--   hicieron) — sigue siendo una elección de quien da el cese, en la pantalla
--   de Equipo.
--
-- CÓMO SE REVIERTE
--   update personas set motivo_cese = null where motivo_cese = 'fin_convenio_practicas';
--   alter table personas drop constraint personas_motivo_cese_valido;
--   alter table personas add constraint personas_motivo_cese_valido
--     check (motivo_cese is null or motivo_cese in
--       ('renuncia','despido','fin_contrato','fin_periodo_prueba',
--        'fin_servicio_rxh','mutuo_acuerdo','por_revisar'));
-- ============================================================================

-- Idempotente: se reconstruye el CHECK completo, así pegarla dos veces no
-- rompe nada. Solo AGREGA un valor — todas las filas que ya existen siguen
-- siendo válidas, así que no hace falta tocar ni una.
alter table personas drop constraint if exists personas_motivo_cese_valido;

alter table personas add constraint personas_motivo_cese_valido
  check (motivo_cese is null or motivo_cese in (
    'renuncia',                -- se fue por decisión propia
    'despido',                 -- la empresa terminó el vínculo CON CAUSA, con su expediente
    'fin_contrato',            -- venció el plazo pactado y no se renovó
    'fin_periodo_prueba',      -- vino a probar y no continúa
    'fin_servicio_rxh',        -- terminó el servicio por recibo por honorarios
    'fin_convenio_practicas',  -- ⇦ 0325: terminó su convenio de modalidad formativa (Ley 28518)
    'mutuo_acuerdo',
    'por_revisar'              -- solo backfill: no se pudo deducir la fecha real
  ));

comment on column personas.motivo_cese is
  'Por que termino el vinculo. fin_contrato = vencio el plazo pactado y no se renovo (extincion por vencimiento, D.Leg. 728 art.16.c): NO requiere procedimiento previo. despido = la empresa termino con causa, y ese si exige carta de preaviso y descargo (D.S. 003-97-TR). fin_convenio_practicas = termino un convenio de modalidad formativa (Ley 28518): no es un cese laboral y no genera liquidacion de beneficios sociales. No son intercambiables.';

insert into migraciones_aplicadas (numero, nombre) values (325, 'un_convenio_de_practicas_tambien_termina')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $$
begin
  raise notice '0325 · motivo_cese acepta ahora fin_convenio_practicas. Motivos validos: renuncia, despido, fin_contrato, fin_periodo_prueba, fin_servicio_rxh, fin_convenio_practicas, mutuo_acuerdo, por_revisar.';
end $$;
