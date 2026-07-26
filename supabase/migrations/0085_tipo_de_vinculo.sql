-- ============================================================================
-- 0085 — Qué es cada persona para el sistema: el tipo de vínculo
-- ----------------------------------------------------------------------------
-- PROMETE: que el sistema sepa distinguir a una colaboradora en planilla de
--   alguien que vino a probar un día, de alguien que factura por recibo por
--   honorarios, y de un accionista que no trabaja acá — y que de esa distinción
--   salgan solas las respuestas a "¿se le mide asistencia?" y "¿devenga
--   beneficios sociales?".
-- ASUME: nada. Es la primera migración de la serie de liquidación por cese.
--
-- EL DEFECTO. Hoy `personas.en_planilla` es un solo interruptor que intenta
-- responder tres preguntas a la vez, y por eso no responde bien ninguna:
--   · ¿se le mide asistencia y disciplina?   ← para esto se creó (0046)
--   · ¿está formalmente en la planilla?      ← lo que su nombre sugiere
--   · ¿le corresponden grati, CTS y vacaciones al salir?  ← nadie lo pregunta
--
-- Con un solo booleano, Alice Vergara (un día de prueba) y Claudia Solórzano
-- (recibo por honorarios) quedaron indistinguibles de una colaboradora que
-- renunció después de dos años. Al construir la liquidación eso deja de ser
-- incómodo y pasa a ser caro: el sistema le calcularía CTS a quien no le
-- corresponde, o dejaría de calcularla a quien sí.
--
-- LAS CUATRO CATEGORÍAS Y POR QUÉ SON ESTAS:
--   planilla       — contrato de trabajo. Se le mide asistencia y devenga todo.
--   prueba         — vino a probar. Se le mide asistencia (marca en el
--                    terminal, se le pagan sus horas) pero NO devenga
--                    beneficios. ⚠ Ver la nota legal más abajo.
--   rxh            — recibo por honorarios. Contrato civil de locación de
--                    servicios: NO devenga beneficios, y muy importante, NO se
--                    le mide asistencia ni disciplina (ver más abajo).
--   no_trabajador  — accionistas y quien figura en el sistema sin prestar
--                    servicios. Ni asistencia ni beneficios.
--
-- POR QUÉ RXH NO SE MIDE. En Perú la frontera entre un recibo por honorarios
-- legítimo y un contrato de trabajo disfrazado la decide la SUBORDINACIÓN
-- (art. 9 del D.S. 003-97-TR), y el primer indicio que revisan SUNAFIL y los
-- juzgados es justamente el cumplimiento de horario y el control de asistencia.
-- Registrar horas para saber cuánto pagar es medir un resultado; generar
-- tardanzas, faltas y expedientes disciplinarios es fiscalizar una conducta —
-- y eso es la prueba de subordinación. Al dejar a `rxh` fuera de `en_planilla`,
-- el sistema sigue contando sus horas para pagarle (fn_planilla_calcular no
-- mira este campo) pero deja de fabricar la evidencia que lo perjudicaría.
--
-- ⚠ NOTA LEGAL SOBRE 'prueba' — DECISIÓN DE FELIPE, 26/07/2026.
-- En la ley peruana el periodo de prueba NO es un vínculo distinto: es un
-- contrato de trabajo común, y su única particularidad es que durante tres
-- meses no hay protección contra el despido arbitrario (art. 10 del D.S.
-- 003-97-TR). SUNAFIL es expresa: quien presta servicios va a planilla
-- electrónica desde el primer día, sin excepción para MYPE. Es decir, en
-- estricto 'prueba' debería devengar beneficios como cualquiera — que por los
-- mínimos legales casi siempre daría cero de todas formas.
-- Se le informó a Felipe y decidió que 'prueba' NO devengue. Queda registrado
-- acá con su fecha para que la decisión sea rastreable y reversible: cambiar
-- fn_devenga_beneficios es una línea.
--
-- POR QUÉ `en_planilla` NO SE BORRA. Catorce lugares en SQL y seis pantallas la
-- leen. Reescribirlos todos sería un cambio grande y arriesgado para un valor
-- que puede calcularse. Se convierte en columna GENERADA a partir de
-- `tipo_vinculo`: los catorce lugares siguen funcionando sin tocar una línea, y
-- de paso queda imposible que alguien la escriba y contradiga a su fuente.
-- (Verificado antes de hacerlo: ninguna vista ni política de seguridad depende
-- de esa columna, y la aplicación solo la lee, nunca la escribe.)
--
-- Reversible: soltar tipo_vinculo, volver en_planilla a columna normal con
-- default true, y soltar fn_devenga_beneficios.
-- ============================================================================

-- ── El campo que faltaba ────────────────────────────────────────────────────
alter table personas add column if not exists tipo_vinculo text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'personas_tipo_vinculo_valido') then
    alter table personas add constraint personas_tipo_vinculo_valido
      check (tipo_vinculo in ('planilla', 'prueba', 'rxh', 'no_trabajador'));
  end if;
end $$;

-- ── Backfill ────────────────────────────────────────────────────────────────
-- Todo el mundo es 'planilla' salvo quien hoy está marcado fuera. NO se
-- adivinan casos concretos: quién fue prueba y quién fue RXH lo marca Felipe
-- desde la pantalla de Equipo, porque es un hecho del negocio y no un dato
-- deducible del sistema. Además, escribir nombres de colaboradoras dentro de
-- una migración las metería en el historial de git para siempre.
update personas
   set tipo_vinculo = case when en_planilla is not true then 'no_trabajador' else 'planilla' end
 where tipo_vinculo is null;

alter table personas alter column tipo_vinculo set not null;
alter table personas alter column tipo_vinculo set default 'planilla';

comment on column personas.tipo_vinculo is
  'Naturaleza del vinculo: planilla (contrato de trabajo) · prueba (vino a probar) · rxh (recibo por honorarios, contrato civil) · no_trabajador (accionista). De aca salen en_planilla y fn_devenga_beneficios.';

-- ── `en_planilla` pasa de dato a consecuencia ───────────────────────────────
-- La pregunta que responde sigue siendo la misma que en 0046 ("¿se le mide
-- asistencia y disciplina?"), solo que ahora se deduce en vez de mantenerse a
-- mano. RXH queda fuera a propósito (ver el porqué en el encabezado).
alter table personas drop column if exists en_planilla;
alter table personas add column en_planilla boolean
  generated always as (tipo_vinculo in ('planilla', 'prueba')) stored;

comment on column personas.en_planilla is
  'DERIVADA de tipo_vinculo — no se puede escribir. Responde: ¿se le mide asistencia y disciplina? Es true para planilla y prueba; false para rxh y no_trabajador.';

-- ── La regla que mueve dinero ───────────────────────────────────────────────
-- Vive en una función y no en una condición suelta dentro de cada cálculo,
-- para que el día que Felipe cambie de criterio sobre 'prueba' se corrija en un
-- solo lugar y no en tres funciones que podrían divergir.
create or replace function fn_devenga_beneficios(p_tipo text)
returns boolean
language sql immutable as $$
  select p_tipo = 'planilla';
$$;
grant  execute on function fn_devenga_beneficios(text) to authenticated;
revoke execute on function fn_devenga_beneficios(text) from public, anon;

comment on function fn_devenga_beneficios(text) is
  'Que tipos de vinculo devengan gratificacion, CTS y vacaciones. Hoy solo planilla: prueba quedo fuera por decision de Felipe (26/07/2026), pese a que la ley peruana trata el periodo de prueba como contrato de trabajo comun. Cambiarlo es una linea.';

insert into migraciones_aplicadas (numero, nombre) values (85, 'tipo_de_vinculo')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
