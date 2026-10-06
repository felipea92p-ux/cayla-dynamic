-- ============================================================================
-- 0510 — La líder de equipo registra una falta de conducta
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que una falta que no es de asistencia —tratar mal a una clienta, apartarse
-- del procedimiento de caja, usar el teléfono atendiendo— se pueda registrar en
-- Dynamic como llamada verbal o amonestación escrita, por la líder de equipo de
-- la sede de esa persona o por DO, citando la falta EXACTA del catálogo del
-- Reglamento. Y que ninguna sanción la imponga quien no puede imponerla.
--
-- Cinco piezas, en este orden:
--
--   1. `faltas_catalogo`: los 20 literales de los numerales 53.1 (leves) y 53.2
--      (significativas) del RIT v4.0, inmutables. Una versión nueva del RIT
--      AGREGA sus filas; nunca edita las de otra.
--   2. El expediente aprende la causal `conducta`: qué falta se cita, cuándo
--      supo la empresa del hecho (52.6) y qué pasó. Su forma la exige el
--      esquema, no la pantalla.
--   3. Quién ACTÚA (`fn_expediente_puede_actuar`): la líder, solo si está en
--      planilla, solo sobre integrantes de su sede y nunca sobre sí misma.
--   4. Quién FIRMA (`fn_expediente_firmante_motivo`): nadie que no esté en
--      planilla, nadie sobre sí misma, y una líder nunca sobre otra líder.
--   5. `fn_expediente_crear_conducta` y `fn_conducta_antecedentes`: registrar
--      la falta, y saber antes qué antecedentes pesan.
--
-- ── DE QUIÉN ES CADA DECISIÓN ───────────────────────────────────────────────
--
-- Las tomó la usuaria el 2026-10-06, con las opciones y su costo a la vista:
--
--   · Amonesta quien tiene el ROL de líder de equipo, no quien tiene «líder»
--     escrito en el cargo. Medido ese día en producción: el cargo dice «Lider
--     de equipo», «Lider de Equipo» y «Encargada de Tienda AQP» para el mismo
--     rol, y una regla por texto habría dejado fuera a Arequipa.
--   · Y solo si está en planilla. Ese día tenían el rol de líder una asesora
--     por honorarios (LIM) y un practicante (OTRU). El RIT 2.9 lo dice: nada
--     del Reglamento «se interpretará como sometimiento al poder de dirección
--     de quien no esté vinculada a ella por un contrato de trabajo». Firmar
--     sanciones es el poder de dirección en su forma más visible, y es justo
--     el indicio que convierte una locación de servicios en un contrato de
--     trabajo (0182).
--   · «Estar en planilla» vale para TODA firma, no solo la de las líderes. Ese
--     día firmaban suspensiones y despidos, según el sistema, la Socia, el
--     Asesor y el Contador (los tres por honorarios), y suspensiones la
--     practicante con rol de líder DO. Ella sigue pudiendo instruir y tramitar
--     (54.4 c: «DO instruye el procedimiento»); lo que deja de poder es
--     imponer. La competencia del 54.4 es sobre IMPONER, y la 0214 ya dejó
--     escrito que imponer es firmar.
--   · A una líder la amonesta DO, nunca otra líder. El RIT no lo prohíbe (el
--     54.4 b habla de «las personas cuya sede base es la suya»): es más
--     estricto que el Reglamento a propósito. En Trujillo hay cuatro líderes;
--     sin esto, un roce entre dos de ellas podía terminar en el legajo como si
--     fuera una relación de mando.
--   · El descargo previo, como hoy: la política `disciplina_descargo_previo`
--     sigue en false (0267) y esta migración no la toca. La conducta pasa por
--     la misma `fn_expediente_firmar` que todo lo demás, así que el día que se
--     encienda la exige también para la conducta, sin otra migración.
--   · La prueba, como hoy: opcional (`fn_expediente_adjuntar`).
--
-- ── POR QUÉ ASÍ ─────────────────────────────────────────────────────────────
--
-- EL CATÁLOGO ES UNA TABLA, NO UNA LISTA EN EL CÓDIGO. Las reglas que dependen
-- de la gravedad corren aquí —«tres amonestaciones por faltas leves en doce
-- meses hacen significativa la siguiente» (53.2 a)—, y una lista en
-- TypeScript no deja a la base comprobar que el literal citado existe. Y ya
-- costó una vez: al renumerarse el RIT de la v3 a la v4, el memo siguió
-- citando el «artículo 7» —que en la v4 es el periodo de prueba— siete
-- semanas. Una cita escrita a mano se queda vieja en silencio.
--
-- LA FILA DEL CATÁLOGO NO SE EDITA NUNCA, Y POR ESO EL EXPEDIENTE NO COPIA EL
-- TEXTO. Un documento entregado cita una versión del RIT que la persona
-- recibió con constancia. Si alguien corrigiera una coma en la fila, el legajo
-- pasaría a citar un texto que nadie firmó. En vez de congelar una copia en
-- cada documento, se congela la fuente: un trigger rechaza UPDATE y DELETE, y
-- la clave foránea ata cada documento a su (versión, numeral, literal).
--
-- LA PERSONA A LA QUE SE LE REGISTRA CONDUCTA ES LA QUE EL RIT ALCANZA. Activa
-- y con contrato de trabajo (`en_planilla`: planilla o periodo de prueba). Las
-- locadoras están fuera del régimen disciplinario (2.5) y las practicantes
-- también (2.6). A diferencia de las tardanzas, el sueldo fijo NO excluye: su
-- pago no depende de horas, pero la obligación de tratar bien a una clienta es
-- la misma. Por eso `fn_expediente_crear_conducta` inserta por su cuenta y no
-- pasa por `fn_expediente_crear_borrador`, que sí excluye el sueldo fijo.
--
-- QUIÉN ACTÚA Y QUIÉN FIRMA SON DOS PREGUNTAS, Y CADA UNA SE RESPONDE UNA VEZ.
-- `fn_expediente_puede_actuar` la llaman casi todas las funciones del
-- expediente —generar, editar, firmar, entregar, comunicar cargos—: cambiarla
-- una vez las alcanza a todas, tardanzas e inasistencias incluidas. La firma se
-- valida en `fn_expediente_firmante_motivo`, que consultan la lista de
-- firmantes que ofrece la pantalla y un trigger sobre la fila. Así no se
-- reescribe `fn_expediente_firmar`, que tiene ocho versiones y es la función
-- más cara de revertir por accidente (el de la 0261).
--
-- EL MISMO HECHO NO SE REGISTRA DOS VECES. Una persona, una falta, un día: un
-- índice único parcial lo hace imposible mientras el documento no esté
-- anulado. Cubre el doble clic y a dos líderes de la misma sede registrando el
-- mismo incidente en el mismo segundo (52.5, non bis in idem).
--
-- ── QUÉ NO HACE ─────────────────────────────────────────────────────────────
--
--   · No crea suspensiones por conducta. Una falta significativa con
--     antecedente vigente puede sancionarse con amonestación o con suspensión
--     (54.8); `fn_conducta_antecedentes` lo dice, pero la suspensión necesita
--     días, topes y días hábiles (0235, 0294) y la decide DO. Queda para su
--     propia entrega.
--   · No registra faltas graves (53.3): esas abren el procedimiento del
--     artículo 57, que no es de una líder.
--   · No registra los literales a), b) y c) del 53.2: el a) es una suma que
--     calcula el sistema, y los b) y c) los miden los motores de tardanzas e
--     inasistencias.
--   · No dibuja el memo de conducta ni el formulario: eso es la entrega 3.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
--   · Que `docs/reglamento-interno-de-trabajo.md` v4.0 es el texto vigente y
--     entregado. Los 20 textos del catálogo se copiaron de ahí, literal.
--   · Que `personas.en_planilla` es la columna calculada
--     `tipo_vinculo in ('planilla','prueba')`.
--   · Que en producción no existe ningún documento con causal `conducta`
--     (ningún camino los creaba). Si existiera, el bloque 2 se niega a seguir
--     antes de tocar nada.
--
-- md5 de partida (pedidos a PRODUCCIÓN el 2026-10-06, idénticos a esta Mac):
--   fn_expediente_puede_actuar  9364c2070cd8e6b7d839093c8ac3ec4b  (0076, 288 caracteres)
--   fn_expediente_firmantes     d31d1510aeedf8cd9fbd3ac2f6923847  (0214, 933 caracteres)
-- Ese mismo día: 0 documentos vivos creados por una líder que con estas reglas
-- pasarían a DO.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   · Restaurar `fn_expediente_puede_actuar` de la 0076 y
--     `fn_expediente_firmantes` de la 0214.
--   · Restaurar las políticas `exp_select_supervisor` (0056) y
--     `expediente_adjuntos_select` (0074).
--   · drop trigger trg_expediente_firmante_elegible on expediente_disciplinario;
--     drop function fn_expediente_firmante_elegible_trg();
--     drop function fn_expediente_firmante_motivo(uuid, uuid, text);
--     drop function fn_expediente_crear_conducta(uuid, text, text, text, date, date, text);
--     drop function fn_conducta_antecedentes(uuid, text, text, date);
--   · Las columnas y el catálogo solo se retiran si no hay documentos de
--     conducta: son el legajo de alguien.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · El catálogo de faltas del RIT
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists faltas_catalogo (
  -- numeric y no texto: «3.10» tiene que ordenar después de «3.9», y «10.0»
  -- después de «4.0». La versión vigente es la mayor.
  rit_version        numeric(4,1) not null check (rit_version > 0),
  numeral            text not null check (numeral in ('53.1', '53.2')),
  literal            text not null check (literal ~ '^[a-z]$'),
  gravedad           text not null check (gravedad in ('leve', 'significativa')),
  texto              text not null check (length(btrim(texto)) > 0),
  -- false = no la registra una persona a mano: la calcula el sistema (53.2 a)
  -- o la miden los motores de tardanzas e inasistencias (53.2 b y c).
  se_registra_a_mano boolean not null,
  primary key (rit_version, numeral, literal),
  -- La gravedad no se elige: la da el numeral. Que pudiera escribirse aparte
  -- es la forma de que algún día un 53.1 diga «significativa».
  constraint chk_gravedad_del_numeral check ((numeral = '53.1') = (gravedad = 'leve'))
);

comment on table faltas_catalogo is
  'Las faltas leves (53.1) y significativas (53.2) del RIT, por versión. Inmutable: una versión nueva agrega sus filas. Cada documento de conducta del expediente apunta a la suya.';

create or replace function fn_faltas_catalogo_inmutable()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'El catálogo de faltas de una versión del Reglamento no se edita ni se borra: hay documentos entregados que lo citan. Una versión nueva del RIT agrega sus propias filas.';
end;
$$;

drop trigger if exists trg_faltas_catalogo_inmutable on faltas_catalogo;
create trigger trg_faltas_catalogo_inmutable
  before update or delete on faltas_catalogo
  for each row execute function fn_faltas_catalogo_inmutable();

alter table faltas_catalogo enable row level security;
-- Es el Reglamento: lo lee cualquiera con sesión. Nadie escribe por la API.
drop policy if exists faltas_catalogo_select on faltas_catalogo;
create policy faltas_catalogo_select on faltas_catalogo
  for select to authenticated using (true);
grant select on faltas_catalogo to authenticated;

-- Textos literales de docs/reglamento-interno-de-trabajo.md, v4.0, art. 53.
-- `on conflict do nothing` y no `do update`: la fila es inmutable, y repegar
-- esta migración no debe ni intentar tocarla.
insert into faltas_catalogo (rit_version, numeral, literal, gravedad, se_registra_a_mano, texto) values
  (4.0, '53.1', 'a', 'leve', true, $t$Omitir el registro de ingreso o de salida por olvido, cuando la jornada puede reconstruirse por otros medios, conforme al artículo 16.$t$),
  (4.0, '53.1', 'b', 'leve', true, $t$Descuido en el orden, la limpieza o la presentación del puesto de trabajo, del taller o de la sala de ventas.$t$),
  (4.0, '53.1', 'c', 'leve', true, $t$Presentarse a laborar sin observar el estándar de presentación personal del artículo 39.$t$),
  (4.0, '53.1', 'd', 'leve', true, $t$Usar el teléfono personal o las redes sociales durante la atención a una clienta, sin perjuicio para el servicio.$t$),
  (4.0, '53.1', 'e', 'leve', true, $t$No mantener actualizados ante la Empresa los datos que esta necesita para la relación laboral: domicilio, teléfono, contacto de emergencia y cuenta de abono.$t$),
  (4.0, '53.1', 'f', 'leve', true, $t$Ausentarse del puesto dentro del centro de trabajo sin avisar a quien lidera el equipo, sin abandono del servicio.$t$),
  (4.0, '53.1', 'g', 'leve', true, $t$Retirarse antes de la hora de salida programada sin autorización, cuando el hecho no sea reiterado, en los términos del artículo 20.$t$),
  (4.0, '53.2', 'a', 'significativa', false, $t$Acumular tres (3) o más amonestaciones escritas por faltas leves, entregadas con cargo de recepción firmado o con acta de negativa, dentro de los doce (12) meses anteriores al nuevo hecho. Las llamadas de atención verbales no se cuentan para este umbral.$t$),
  (4.0, '53.2', 'b', 'significativa', false, $t$Las tardanzas reiteradas, en los umbrales y con la gradación del artículo 19.$t$),
  (4.0, '53.2', 'c', 'significativa', false, $t$La inasistencia injustificada, en los umbrales y con la gradación del artículo 21.$t$),
  (4.0, '53.2', 'd', 'significativa', true, $t$Omitir de forma reiterada el registro de asistencia, o registrarlo de modo que impida medir la jornada efectivamente laborada.$t$),
  (4.0, '53.2', 'e', 'significativa', true, $t$Incumplir sin causa razonable una instrucción lícita y expresa de quien lidera el equipo o de la encargada de sede, relacionada con el trabajo.$t$),
  (4.0, '53.2', 'f', 'significativa', true, $t$Incumplir las normas de seguridad y salud en el trabajo cuando no se produzca daño ni riesgo grave: no usar el equipo de protección personal, no reportar una condición insegura, no atender una instrucción de seguridad. Se evalúa conforme al artículo 35.$t$),
  (4.0, '53.2', 'g', 'significativa', true, $t$Apartarse del procedimiento establecido para el manejo de caja, cobros, inventario, cierre de tienda o traslado de mercadería. Comprende el faltante de caja o de mercadería cuando no se acredite apropiación, retención ni utilización indebida en beneficio propio o de terceros.$t$),
  (4.0, '53.2', 'h', 'significativa', true, $t$Tratar de forma descortés o desconsiderada a una clienta, a una compañera o a un tercero. Comprende también los actos de violencia, injuria o faltamiento de palabra en agravio de una clienta o de un tercero que, por su entidad, no lleguen a quebrantar la buena fe laboral en los términos del literal a) del numeral 53.3.$t$),
  (4.0, '53.2', 'i', 'significativa', true, $t$Divulgar dentro de la Empresa información reservada a quien no le corresponde conocerla, sin entregarla a terceros, en los términos del artículo 41.$t$),
  (4.0, '53.2', 'j', 'significativa', true, $t$Usar bienes, herramientas, sistemas o accesos de la Empresa para fines ajenos al trabajo, sin perjuicio económico, en los términos del artículo 40.$t$),
  (4.0, '53.2', 'k', 'significativa', true, $t$No asistir sin causa justificada a una capacitación obligatoria, en particular las de seguridad y salud en el trabajo y las de prevención del hostigamiento sexual.$t$),
  (4.0, '53.2', 'l', 'significativa', true, $t$Omitir la comunicación de un conflicto de intereses en los supuestos del artículo 43, cuando no haya derivado en perjuicio ni en beneficio propio.$t$),
  (4.0, '53.2', 'm', 'significativa', true, $t$No comunicar un accidente o un incidente de trabajo del que se tuvo conocimiento, conforme al artículo 37.$t$)
on conflict (rit_version, numeral, literal) do nothing;


-- ════════════════════════════════════════════════════════════════════════════
-- 2 · El expediente aprende la causal «conducta»
-- ════════════════════════════════════════════════════════════════════════════
do $pre$
begin
  -- Ningún camino creaba documentos de conducta. Si alguno existe, alguien lo
  -- insertó a mano y no tiene la forma que esta migración exige: mejor parar
  -- aquí, con el motivo dicho, que a mitad de un ALTER.
  if exists (select 1 from expediente_disciplinario where tipo_causal = 'conducta'
               and not exists (select 1 from information_schema.columns
                                where table_name = 'expediente_disciplinario'
                                  and column_name = 'falta_numeral')) then
    raise exception 'Hay documentos con causal conducta creados antes de la 0510. Revísalos con DO antes de pegar esta migración.';
  end if;
end;
$pre$;

alter table expediente_disciplinario add column if not exists falta_rit_version numeric(4,1);
alter table expediente_disciplinario add column if not exists falta_numeral     text;
alter table expediente_disciplinario add column if not exists falta_literal     text;
-- 52.6: la fecha en que la empresa tomó conocimiento comprobado del hecho. Es
-- desde donde corre la inmediatez, y no es la fecha del hecho ni la de hoy.
alter table expediente_disciplinario add column if not exists conocido_el       date;

comment on column expediente_disciplinario.conocido_el is
  'Conducta: fecha en que la empresa tomó conocimiento comprobado del hecho (RIT 52.6). La inmediatez corre desde aquí.';

do $mig$
begin
  if not exists (select 1 from pg_constraint where conname = 'fk_expediente_falta_catalogo') then
    alter table expediente_disciplinario
      add constraint fk_expediente_falta_catalogo
      foreign key (falta_rit_version, falta_numeral, falta_literal)
      references faltas_catalogo (rit_version, numeral, literal);
  end if;

  -- ESTADOS IMPOSIBLES. Un documento de conducta sin falta citada, sin fecha
  -- de conocimiento o sin relato no es un documento: es una acusación sin
  -- contenido, y el 55.3 exige hechos, fechas y norma. Y al revés: una
  -- tardanza que cita un literal de conducta mezclaría dos escaleras que el
  -- 56.5 manda mantener separadas.
  --
  -- El `coalesce(…, false)` de fuera no es adorno: un CHECK que da NULL deja
  -- pasar la fila. Sin él, un relato sin fecha haría NULL la comparación y el
  -- documento entraría. Y el `case` interior protege `jsonb_array_length`, que
  -- revienta sobre algo que no es una lista: un AND no garantiza el orden.
  if not exists (select 1 from pg_constraint where conname = 'chk_conducta_completa') then
    alter table expediente_disciplinario
      add constraint chk_conducta_completa check (coalesce(
        case when tipo_causal = 'conducta' then
               num_nonnulls(falta_rit_version, falta_numeral, falta_literal, conocido_el) = 4
           and periodo_desde is not null
           and periodo_hasta = periodo_desde
           and conocido_el >= periodo_desde
           and case when jsonb_typeof(hechos) = 'array' then jsonb_array_length(hechos) = 1 else false end
           and (hechos->0->>'fecha')::date = periodo_desde
           and length(btrim(coalesce(hechos->0->>'relato', ''))) >= 20
         else num_nulls(falta_rit_version, falta_numeral, falta_literal, conocido_el) = 4
        end, false));
  end if;
end;
$mig$;

-- 52.5 · El mismo hecho no se documenta dos veces.
create unique index if not exists uq_conducta_un_hecho_un_documento
  on expediente_disciplinario (persona_id, falta_numeral, falta_literal, periodo_desde)
  where tipo_causal = 'conducta' and estado <> 'anulado';


-- ════════════════════════════════════════════════════════════════════════════
-- 3 · Quién ACTÚA sobre un documento
-- ════════════════════════════════════════════════════════════════════════════
-- Copiada de la 0076 (la vigente). Lo que cambia es solo la rama de la líder:
-- antes bastaba con que la persona fuera de su sede.
create or replace function fn_expediente_puede_actuar(p_persona_id uuid, p_nivel text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(fn_es_admin_o_lider(), false)
      or coalesce(
           fn_rol_actual() = 'supervisor_sede'
           and p_nivel in ('verbal','amonestacion')
           and (select sede_base_id from personas where id = p_persona_id) = fn_sede_actual_persona()
           -- CAMBIO 0510 · A una líder la amonesta DO: la líder solo actúa
           -- sobre integrantes. Cubre también «a sí misma», porque ella no es
           -- integrante; se dice aparte para que nadie lo tenga que deducir.
           and (select rol from personas where id = p_persona_id) = 'integrante'
           and p_persona_id <> fn_persona_actual_id()
           -- CAMBIO 0510 · Solo con contrato de trabajo (RIT 2.9). Una líder
           -- por honorarios o en prácticas no ejerce poder disciplinario.
           and (select en_planilla from personas where id = fn_persona_actual_id())
         , false);
$$;
grant execute on function fn_expediente_puede_actuar(uuid, text) to authenticated;
revoke execute on function fn_expediente_puede_actuar(uuid, text) from public, anon;

-- Lo que la líder VE sigue a lo que puede tramitar: los documentos de
-- integrantes de su sede. Sin esto, si DO amonesta a una líder de Trujillo, las
-- otras tres lo leerían en su pantalla de Disciplina. Lo suyo propio lo sigue
-- viendo por `exp_select_propia`, que no se toca.
drop policy if exists exp_select_supervisor on expediente_disciplinario;
create policy exp_select_supervisor on expediente_disciplinario
  for select to authenticated using (
    fn_rol_actual() = 'supervisor_sede'
    and persona_id in (select id from personas
                        where sede_base_id = fn_sede_actual_persona()
                          and rol = 'integrante'));

drop policy if exists expediente_adjuntos_select on expediente_adjuntos;
create policy expediente_adjuntos_select on expediente_adjuntos
  for select to authenticated
  using (
    exists (
      select 1 from expediente_disciplinario d
      join personas p on p.id = d.persona_id
      where d.id = expediente_adjuntos.documento_id
        and (
          fn_es_admin_o_lider()
          or (fn_rol_actual() = 'supervisor_sede'
              and p.sede_base_id = fn_sede_actual_persona()
              and p.rol = 'integrante')
          or d.persona_id = fn_persona_actual_id()
        )
    )
  );


-- ════════════════════════════════════════════════════════════════════════════
-- 4 · Quién FIRMA
-- ════════════════════════════════════════════════════════════════════════════
-- Devuelve null si `p_firmante` puede suscribir un documento de `p_nivel` sobre
-- `p_persona`, y si no, el motivo dicho para quien lo lee en pantalla. Un
-- texto y no un booleano porque las dos que la consultan lo necesitan: la
-- lista lo descarta, el trigger lo muestra.
create or replace function fn_expediente_firmante_motivo(p_firmante uuid, p_persona uuid, p_nivel text)
returns text language sql stable security definer set search_path = public as $$
  select case
    when f.id is null then 'El firmante elegido no existe.'
    when f.estado <> 'activo' then 'El firmante elegido no está activo.'
    when f.en_planilla is not true then
      'Solo suscribe una sanción quien tiene contrato de trabajo con CAYLA: quien presta servicios por honorarios o en prácticas puede tramitarla, pero no imponerla (RIT 2.9).'
    when f.id = p_persona then 'Nadie suscribe una sanción sobre sí misma.'
    when fn_expediente_puede_suscribir(f.rol::text, p_nivel) is not true then
      coalesce(fn_cargo_de_rol(f.rol), 'El firmante elegido') || ' no puede suscribir un documento de nivel ' || p_nivel || ' (art. 54.4 del RIT).'
    when f.rol = 'supervisor_sede' and f.sede_base_id is distinct from t.sede_base_id then
      'El firmante elegido no pertenece a la sede de esta persona.'
    when f.rol = 'supervisor_sede' and t.rol is distinct from 'integrante' then
      'A una líder de equipo la amonesta DO, no otra líder.'
    else null
  end
  from (select 1) uno
  left join personas f on f.id = p_firmante
  left join personas t on t.id = p_persona;
$$;
grant execute on function fn_expediente_firmante_motivo(uuid, uuid, text) to authenticated, service_role;
revoke execute on function fn_expediente_firmante_motivo(uuid, uuid, text) from public, anon;

-- El trigger es la red: `fn_expediente_firmar` ya comprueba rol, nivel y sede,
-- y no se reescribe. Esto agrega lo que no comprueba, sobre cualquier camino
-- que deje un firmante en la fila.
create or replace function fn_expediente_firmante_elegible_trg()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_motivo text;
begin
  v_motivo := fn_expediente_firmante_motivo(new.firmante_id, new.persona_id, new.nivel);
  if v_motivo is not null then
    raise exception '%', v_motivo;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_expediente_firmante_elegible on expediente_disciplinario;
create trigger trg_expediente_firmante_elegible
  before update on expediente_disciplinario
  for each row
  when (new.firmante_id is not null
        and (new.firmante_id is distinct from old.firmante_id
             or (old.estado = 'borrador' and new.estado = 'firmado')))
  execute function fn_expediente_firmante_elegible_trg();

-- La lista que ofrece la pantalla. Copiada de la 0214 (la vigente): el filtro
-- de rol y sede se reemplaza por la misma regla que aplica el trigger, para que
-- la pantalla nunca ofrezca a alguien cuya firma después se rechaza.
create or replace function fn_expediente_firmantes(p_id uuid)
returns table(persona_id uuid, nombre text, cargo text, tiene_firma boolean)
language plpgsql stable security definer set search_path = public as $$
declare r expediente_disciplinario%rowtype;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if fn_expediente_puede_actuar(r.persona_id, r.nivel) is not true then
    raise exception 'Sin permiso sobre este documento.';
  end if;

  return query
  select p.id,
         (p.nombres || ' ' || p.apellidos)::text,
         fn_cargo_de_rol(p.rol),
         exists (select 1 from firmas_escaneadas f where f.persona_id = p.id)
  from personas p
  where p.estado = 'activo'
    and fn_cargo_de_rol(p.rol) is not null
    -- CAMBIO 0510 · Art. 54.4, planilla, sede y «nunca sobre sí misma»:
    -- la misma regla que el trigger, escrita una sola vez.
    and fn_expediente_firmante_motivo(p.id, r.persona_id, r.nivel) is null
  order by 2;
end;
$$;

grant execute on function fn_expediente_firmantes(uuid) to authenticated, service_role;
revoke execute on function fn_expediente_firmantes(uuid) from public;


-- ════════════════════════════════════════════════════════════════════════════
-- 5 · Registrar la falta, y saber antes qué pesa
-- ════════════════════════════════════════════════════════════════════════════
create or replace function fn_expediente_crear_conducta(
  p_persona_id  uuid,
  p_numeral     text,
  p_literal     text,
  p_nivel       text,
  p_fecha_hecho date,
  p_conocido_el date,
  p_relato      text
)
returns uuid language plpgsql volatile security definer set search_path = public as $$
declare
  v_falta faltas_catalogo%rowtype;
  v_p     personas%rowtype;
  v_id    uuid;
begin
  if fn_expediente_puede_actuar(p_persona_id, p_nivel) is not true then
    raise exception 'Sin permiso para registrar una falta de nivel % sobre esta persona. La líder de equipo registra llamadas verbales y amonestaciones de integrantes de su sede; a una líder la amonesta DO.', p_nivel;
  end if;

  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;
  -- RIT 2.5 y 2.6: locadoras y practicantes no están en el régimen disciplinario.
  if v_p.estado <> 'activo' or v_p.en_planilla is not true then
    raise exception 'A esta persona no le alcanza el régimen disciplinario del Reglamento: no está activa o no tiene contrato de trabajo (RIT 2.5 y 2.6).';
  end if;

  if p_nivel not in ('verbal', 'amonestacion') then
    raise exception 'Por conducta se registra una llamada verbal o una amonestación escrita. Una suspensión la decide DO.';
  end if;

  -- La falta, del catálogo de la versión vigente del RIT.
  select * into v_falta from faltas_catalogo
   where rit_version = (select max(rit_version) from faltas_catalogo)
     and numeral = p_numeral and literal = p_literal;
  if not found then
    raise exception 'La falta %) del numeral % no está en el catálogo del Reglamento vigente (art. 53): solo se sanciona lo que está escrito ahí (52.3).', p_literal, p_numeral;
  end if;
  if not v_falta.se_registra_a_mano then
    raise exception 'El literal %) del numeral % no se registra a mano: lo calcula el sistema o lo miden los motores de tardanzas e inasistencias.', p_literal, p_numeral;
  end if;

  if p_fecha_hecho is null or p_fecha_hecho > fn_hoy_lima() then
    raise exception 'La fecha del hecho es obligatoria y no puede ser futura.';
  end if;
  if p_conocido_el is null or p_conocido_el > fn_hoy_lima() then
    raise exception 'La fecha en que se supo del hecho es obligatoria y no puede ser futura (RIT 52.6).';
  end if;
  if p_conocido_el < p_fecha_hecho then
    raise exception 'No se puede saber de un hecho antes de que ocurra: la fecha en que se supo es anterior a la del hecho.';
  end if;
  if length(btrim(coalesce(p_relato, ''))) < 20 then
    raise exception 'Describe qué pasó, con al menos una frase completa: es lo que la persona va a leer y lo que se discute si lo cuestiona (RIT 55.3).';
  end if;

  insert into expediente_disciplinario (
    persona_id, tipo_causal, nivel, estado, hechos, periodo_desde, periodo_hasta,
    falta_rit_version, falta_numeral, falta_literal, conocido_el, creado_por)
  values (
    p_persona_id, 'conducta', p_nivel, 'borrador',
    -- La fecha en ISO a mano y no con ::text, que depende del DateStyle de
    -- la sesión: los demás hechos del expediente se guardan así y el memo la
    -- lee así.
    jsonb_build_array(jsonb_build_object('fecha', to_char(p_fecha_hecho, 'YYYY-MM-DD'), 'relato', btrim(p_relato))),
    p_fecha_hecho, p_fecha_hecho,
    v_falta.rit_version, v_falta.numeral, v_falta.literal, p_conocido_el, fn_persona_actual_id())
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception 'Ese hecho ya está registrado: esta persona ya tiene un documento por la misma falta en la misma fecha. Un mismo hecho no se documenta dos veces (RIT 52.5).';
end;
$$;

grant execute on function fn_expediente_crear_conducta(uuid, text, text, text, date, date, text) to authenticated;
revoke execute on function fn_expediente_crear_conducta(uuid, text, text, text, date, date, text) from public, anon;

-- Lo que la pantalla necesita saber ANTES de registrar: la gravedad de la falta,
-- si hay un antecedente vigente por la misma falta (56.4 y 56.5) y cuántas
-- amonestaciones por faltas leves pesan (53.2 a). No decide nada: informa a
-- quien decide (52.9).
--
-- «Vigente» se mide con el criterio de `fn_tardanza_escalon_al` (0311), la
-- función hermana de la escalera de tardanzas: entregado, y con la entrega
-- dentro de los doce meses anteriores al cierre del día del hecho en Lima.
-- Dos mitades del sistema disciplinario contestando distinto a «¿esto sigue
-- pesando?» es el defecto que la 0237 vino a cerrar.
create or replace function fn_conducta_antecedentes(
  p_persona_id  uuid,
  p_numeral     text,
  p_literal     text,
  p_fecha_hecho date default null
)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_falta faltas_catalogo%rowtype;
  v_ts    timestamptz := fn_cierre_lima(coalesce(p_fecha_hecho, fn_hoy_lima()));
  v_prev  jsonb;
  v_leves int;
begin
  if fn_expediente_puede_actuar(p_persona_id, 'amonestacion') is not true then
    raise exception 'Sin permiso sobre esta persona.';
  end if;

  select * into v_falta from faltas_catalogo
   where rit_version = (select max(rit_version) from faltas_catalogo)
     and numeral = p_numeral and literal = p_literal;
  if not found then
    raise exception 'La falta %) del numeral % no está en el catálogo del Reglamento vigente.', p_literal, p_numeral;
  end if;

  -- 56.4 y 56.5: el antecedente que agrava es el de la MISMA falta. Una
  -- amonestación por presentación personal no es escalón para una por caja.
  -- La llamada verbal no es antecedente (54.2).
  select jsonb_build_object('id', e.id, 'correlativo', e.correlativo, 'nivel', e.nivel,
                            'entregado_at', e.entregado_at)
    into v_prev
    from expediente_disciplinario e
   where e.persona_id = p_persona_id
     and e.tipo_causal = 'conducta'
     and e.falta_numeral = p_numeral and e.falta_literal = p_literal
     and e.estado = 'entregado'
     and e.nivel in ('amonestacion', 'suspension')
     and e.entregado_at <= v_ts
     and e.entregado_at >= v_ts - interval '12 months'
   order by e.entregado_at desc, e.periodo_hasta desc, e.id desc
   limit 1;

  -- 53.2 a): amonestaciones ESCRITAS por faltas LEVES, entregadas, en los doce
  -- meses anteriores al nuevo hecho. Con tres o más, el hecho nuevo es falta
  -- significativa aunque su literal sea leve.
  select count(*) into v_leves
    from expediente_disciplinario e
    join faltas_catalogo c on c.rit_version = e.falta_rit_version
                          and c.numeral = e.falta_numeral and c.literal = e.falta_literal
   where e.persona_id = p_persona_id
     and e.tipo_causal = 'conducta'
     and c.gravedad = 'leve'
     and e.estado = 'entregado'
     and e.nivel = 'amonestacion'
     and e.entregado_at <= v_ts
     and e.entregado_at >= v_ts - interval '12 months';

  return jsonb_build_object(
    'gravedad', v_falta.gravedad,
    'texto', v_falta.texto,
    'antecedente_vigente', v_prev,
    'amonestaciones_leves_vigentes', v_leves,
    'significativa_por_acumulacion', v_falta.gravedad = 'leve' and v_leves >= 3,
    -- 54.8. Lo que corresponde según el Reglamento, en una frase. La decisión
    -- es de quien firma: la medida menos gravosa que baste (52.10).
    'que_corresponde',
      case
        when v_falta.gravedad = 'leve' and v_leves < 3 then
          'Falta leve: como máximo amonestación escrita. También puede bastar una llamada verbal o ninguna medida (54.8).'
        when v_prev is null then
          'Falta significativa sin antecedente vigente por la misma falta: amonestación escrita (54.8).'
        else
          'Falta significativa con antecedente vigente por la misma falta: amonestación escrita, o suspensión si DO la decide (54.8).'
      end);
end;
$$;

grant execute on function fn_conducta_antecedentes(uuid, text, text, date) to authenticated;
revoke execute on function fn_conducta_antecedentes(uuid, text, text, date) from public, anon;


insert into migraciones_aplicadas (numero, nombre) values (510, 'la_lider_registra_una_falta_de_conducta')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
