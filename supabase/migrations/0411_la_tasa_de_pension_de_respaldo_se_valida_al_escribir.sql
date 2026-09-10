-- ============================================================================
-- 0411 · LA TASA DE PENSIÓN DE RESPALDO SE VALIDA AL ESCRIBIR
-- ============================================================================
--
-- RENUMERADA DE 0405 A 0411 (2026-09-08). Se escribió y se pegó en producción
-- como «0405», y mientras corría otra sesión fusionó a `main` dos migraciones
-- distintas (consentimiento de DNI) que tomaron el mismo número. El código de
-- abajo —el trigger, ya vivo y verificado en producción— no cambió ni una
-- letra; solo el número del archivo y el `insert` de `migraciones_aplicadas`.
--
-- QUÉ PROMETE
--   Que escribir `configuracion.tasa_afp` —el respaldo global que
--   `fn_planilla_calcular_nucleo` y `fn_vacaciones_truncas` usan cuando una
--   persona no tiene régimen de pensión asignado ni en `personas.regimen_
--   pension` ni en `asignaciones_regimen_pension`— exija un número positivo y
--   dentro de un rango plausible como tasa de pensión, en vez de aceptar
--   cualquier jsonb.
--
-- EL DEFECTO, ENCONTRADO EN UNA AUDITORÍA DEDICADA A AFP (2026-09-08)
--   `configuracion` no valida el CONTENIDO de ningún valor salvo
--   `firmante_empresa` (0147). `tasa_afp` se lee con un solo cast
--   `(valor->>'tasa')::numeric` dentro de `fn_planilla_calcular_nucleo`
--   (0397:291-293) para TODA la planilla del mes de una sola vez — no por
--   persona. Dos formas de que esto salga mal, y ninguna las frena hoy:
--
--     · Un valor que no castea a numeric (texto, null, un jsonb sin la clave
--       `tasa`) revienta el cálculo de planilla COMPLETO, no el de una
--       persona — es una excepción sin capturar en medio de la función.
--     · Un valor que sí castea pero es absurdo como tasa de pensión (negativo,
--       o un 12.92 escrito donde se esperaba 0.1292 — el clásico error de un
--       punto decimal al pegar SQL a mano) pasa sin que nada lo note, y
--       descuenta mal a TODA la gente que caiga en ese respaldo ese mes.
--
-- QUÉ NO HACE — a propósito
--   No corrige el valor ya sembrado. Confirmado en producción el 2026-09-08:
--   `configuracion.tasa_afp` sigue exactamente en `{"tasa": 0}`, el seed de la
--   0110, y hay al menos una persona activa y en planilla hoy sin ningún
--   régimen asignado — así que hoy mismo se le está descontando S/0 de
--   pensión. Ese es el hallazgo ya abierto en `docs/hallazgos-abiertos.md:71`
--   ("Sin régimen de pensión → aporte cero"), y decidir qué valor debería
--   tener el respaldo —o si en vez de un respaldo genérico el sistema
--   debería exigirle régimen a todos antes de dejar cerrar el mes— es una
--   decisión de negocio de Felipe, no algo que esta migración deba asumir.
--   Esta migración solo cierra la puerta a que un FUTURO update deje ahí un
--   valor imposible; no toca la fila que ya existe (un trigger `before
--   insert or update` no se dispara sobre filas que no se tocan).
--
-- POR QUÉ CERO QUEDA FUERA DE RANGO PARA ESCRITURAS NUEVAS
--   Ninguna tasa de pensión real en el Perú —ninguna AFP, tampoco la ONP— es
--   0 %. Un cero nuevo tampoco sería una decisión válida, sería el mismo
--   descuido que dejó la 0110: escribirlo como placeholder y que nadie
--   vuelva a mirarlo. El cero que ya existe no se toca por esta migración.
--
-- POR QUÉ UN TRIGGER APARTE Y NO EXTENDER `fn_valida_firmante_empresa` (0147)
--   Mismo criterio que ya usó la 0342 sobre `fn_bloquear_rol_directo`: un
--   trigger nuevo y angosto por clave protegida de `configuracion`, no una
--   función genérica — no exige pedir el md5 de producción de una función que
--   ya está viva y no hace falta tocar, y mantiene cada validación legible por
--   separado.
--
-- QUÉ ASUME
--   Que el rango 0 % – 20 % cubre con margen cualquier tasa de pensión real
--   hoy sembrada en `tasas_pension` (ONP 13,00 %; AFP en comisión por flujo
--   entre 12,84 % y 13,06 %; AFP en comisión mixta 11,37 %, 0114/0328) y deja
--   espacio para que suba sin que haya que tocar este trigger.
--
-- CÓMO SE REVIERTE
--   drop trigger if exists trg_valida_tasa_afp_respaldo on configuracion;
--   drop function if exists fn_valida_tasa_afp_respaldo();
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El select del final: `el_trigger_existe` tiene que dar 1.
-- ============================================================================

create or replace function fn_valida_tasa_afp_respaldo()
returns trigger
language plpgsql as $function$
declare
  v_tasa numeric;
begin
  if new.clave <> 'tasa_afp' then
    return new;
  end if;

  begin
    v_tasa := (new.valor ->> 'tasa')::numeric;
  exception when others then
    raise exception 'tasa_afp: «tasa» tiene que ser un número. Ninguna tasa de pensión real es texto ni queda vacía.';
  end;

  if v_tasa is null then
    raise exception 'tasa_afp: falta «tasa» dentro del valor. Sin ella, quien caiga en este respaldo quedaría con un descuento indefinido en vez de una tasa real.';
  end if;

  if v_tasa <= 0 or v_tasa > 0.20 then
    raise exception 'tasa_afp: % no es una tasa de pensión plausible. Ninguna AFP ni la ONP cobran 0%% ni más de 20%% — revisa el valor (¿lo escribiste como 12.92 en vez de 0.1292?) antes de guardarlo.', v_tasa;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_valida_tasa_afp_respaldo on configuracion;
create trigger trg_valida_tasa_afp_respaldo
  before insert or update on configuracion
  for each row execute function fn_valida_tasa_afp_respaldo();

insert into migraciones_aplicadas (numero, nombre)
values (411, '0411_la_tasa_de_pension_de_respaldo_se_valida_al_escribir')
on conflict (numero) do nothing;

-- ── COMPROBACION ────────────────────────────────────────────────────────────
select
  (select count(*) from pg_trigger where tgname = 'trg_valida_tasa_afp_respaldo'
     and tgrelid = 'configuracion'::regclass) as el_trigger_existe;
