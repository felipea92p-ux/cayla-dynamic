-- ============================================================================
-- 0190 — Quien ya se jubiló deja de aportar
-- ============================================================================
--
-- QUÉ PROMETE
--   Que una persona que ya percibe su pensión de jubilación y sigue trabajando
--   **no reciba descuento previsional**, y que su ficha DIGA por qué — en vez de
--   que haya que deducirlo de un campo vacío.
--
-- QUÉ ASUME
--   · `tasas_pension` es versionada por fecha (0114/0115): la tasa que se aplica
--     es la vigente al cierre del periodo, no la última cargada.
--   · El descuento sale de `aporte + comision + prima` de esa tabla. Con los
--     tres en cero, el descuento es cero.
--
-- ── EL CASO QUE LO ORIGINA ──────────────────────────────────────────────────
--
-- Judith ya se jubiló y sigue trabajando en CAYLA. El aporte previsional existe
-- para financiar una pensión, y ella ya la percibe: aportar de nuevo sería
-- descontarle de su sueldo para un fondo del que ya está cobrando. Confirmado
-- por el contador (Dante) y decidido por Felipe el 2026-08-08, con efecto desde
-- el periodo que se paga el 28/08/2026 — **ningún periodo pagado se toca**.
--
-- ── POR QUÉ UN VALOR PROPIO Y NO DEJAR EL CAMPO VACÍO ───────────────────────
--
-- Dejarlo vacío «funciona» hoy: sin régimen, el cálculo cae a
-- `configuracion.tasa_afp`, que vale 0. Pero eso es una coincidencia, no una
-- decisión, y falla de dos maneras:
--
--   1. El día que alguien ponga esa tasa global en algo distinto de 0 —para
--      cubrir a quien todavía no está clasificado, que es para lo que existe—
--      Judith volvería a tener descuento sin que nadie lo pidiera.
--   2. Un campo vacío se lee como «falta completar esto». Dentro de tres meses
--      alguien lo va a ver, va a pensar que es un dato pendiente y le va a poner
--      su AFP. La ficha tiene que DECIR por qué no aporta.
--
-- Es la misma regla que este repositorio viene aplicando toda la semana: **un
-- dato ausente y una decisión tomada no pueden verse iguales.**
--
-- ── LO QUE **NO** CAMBIA, Y ES IMPORTANTE ───────────────────────────────────
--
--   · **EsSalud sigue.** La empresa aporta su 9% igual que por cualquier otra
--     persona en planilla. Esto solo apaga el descuento PREVISIONAL.
--   · **La renta de quinta categoría sigue**, si su remuneración llega al tramo.
--   · **Gratificación, CTS y vacaciones siguen**: se es trabajadora en planilla
--     con o sin aporte previsional. `fn_devenga_beneficios` mira el tipo de
--     vínculo, no el régimen de pensión.
--
-- ── Y LO QUE NO HAY QUE HACER: PAGARLE EL APORTE COMO UN CONCEPTO APARTE ────
--
-- Al no descontarle, Judith ya recibe su remuneración bruta completa: el dinero
-- que antes se remitía a la AFP se queda con ella. **Eso ya es «pagárselo».**
-- Agregar además una línea que le sume ese porcentaje le pagaría un 13 % de más
-- todos los meses, y en la boleta no se vería como un error sino como un
-- concepto más. Queda escrito acá porque la frase «su AFP se la pagamos a ella»
-- admite las dos lecturas y solo una es correcta.
--
-- CÓMO SE REVIERTE
--   update personas set regimen_pension = '<su afp>' where id = '<uuid>';
--   y devolver el CHECK a los cinco valores anteriores. La fila de
--   `tasas_pension` puede quedarse: con nadie en 'jubilada' no hace nada.
-- ============================================================================

-- ── 1 · El valor nuevo ──────────────────────────────────────────────────────
alter table personas drop constraint if exists personas_regimen_pension_valido;
alter table personas
  add constraint personas_regimen_pension_valido
  check (regimen_pension is null
         or regimen_pension = any (array['onp','profuturo','prima','integra','habitat','jubilada']));

comment on column personas.regimen_pension is
  'A que sistema previsional aporta. `jubilada` = ya percibe pension de jubilacion y por eso NO aporta (0190); es una decision escrita, no un dato faltante. NULL sigue significando «todavia no se clasifico» y cae a configuracion.tasa_afp.';

-- ── 2 · Su tasa: cero, y con el sustento en la propia fila ──────────────────
-- Se escribe como una tasa más y no como un `if` en el cálculo: la tabla ya es
-- el único lugar donde vive «cuánto se descuenta», y meter una excepción en la
-- función crearía un segundo sitio que decide lo mismo.
insert into tasas_pension (regimen, nombre, aporte, comision, prima, vigente_desde, nota)
select 'jubilada',
       'Jubilada — ya percibe pensión, no aporta',
       0, 0, 0,
       '2026-07-29',
       'Quien ya percibe pension de jubilacion no aporta: el aporte financia una '
       || 'pension que ya se esta cobrando. Confirmado por el contador y decidido '
       || 'por Felipe el 2026-08-08. Vigente desde el periodo 29/07-28/08/2026; '
       || 'los periodos anteriores no se tocan. EsSalud y quinta categoria siguen.'
where not exists (select 1 from tasas_pension where regimen = 'jubilada');

insert into migraciones_aplicadas (numero, nombre)
values (190, 'quien_ya_se_jubilo_deja_de_aportar')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── 3 · La comprobación ─────────────────────────────────────────────────────
do $mig$
declare v_tasa numeric;
begin
  select aporte + comision + prima into v_tasa
  from tasas_pension where regimen = 'jubilada' and vigente_hasta is null;

  if v_tasa is null then
    raise warning '0190 · la tasa de jubilada NO quedo cargada. Revisa.';
  elsif v_tasa <> 0 then
    raise warning '0190 · OJO: la tasa de jubilada es %, deberia ser 0.', v_tasa;
  else
    raise notice '0190 · listo. Quien quede en regimen «jubilada» no recibe descuento previsional.';
    raise notice '0190 · FALTA el paso que mueve plata: asignarle el regimen a quien corresponda.';
    raise notice '0190 ·   update personas set regimen_pension = ''jubilada'' where id = ''<uuid>'';';
  end if;
end $mig$;
