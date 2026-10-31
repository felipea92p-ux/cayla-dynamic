-- ============================================================================
-- 0567 — La líder propone la suspensión, y DO la impone
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que el segundo peldaño de la escala del art. 54.1 exista para la causal
-- CONDUCTA, con la competencia del art. 54.4 c) respetada: la líder de equipo
-- que vio el hecho puede PEDIR por escrito que se suspenda, y solo Desarrollo
-- Organizacional o la Gerencia pueden imponerlo.
--
-- Hasta hoy la cadena de una líder terminaba en amonestación escrita. La 0510
-- lo dejó escrito en su «QUÉ NO HACE»: «No crea suspensiones por conducta […]
-- la suspensión necesita días, topes y días hábiles (0235, 0294) y la decide
-- DO. Queda para su propia entrega». Esta es esa entrega.
--
-- Dos piezas:
--
--   1. La PROPUESTA (`fn_conducta_proponer_suspension`): tres columnas nuevas y
--      una función guardián, con su trigger. Pedir no es imponer.
--   2. La IMPOSICIÓN (`fn_expediente_elevar_a_suspension`): el mismo documento
--      sube de nivel, atado a su antecedente.
--
-- ── DE QUIÉN ES LA DECISIÓN ─────────────────────────────────────────────────
--
-- De Felipe, el 2026-10-29, con las tres opciones y su costo a la vista:
-- «la líder propone, DO decide». Se descartaron las otras dos:
--
--   · Que la líder redacte la suspensión y DO solo firme. El art. 54.4 d) deja
--     sin efecto alguno —y fuera del legajo, y sin servir de escalón— la
--     sanción impuesta por quien no es competente, y graduar los días es parte
--     de imponerla.
--   · Que DO la cree de cero. La líder que vio el hecho dejaría de constar como
--     quien pidió más, y el art. 54.7 exige que la decisión de subir un peldaño
--     conste motivada por escrito.
--
-- ── POR QUÉ UN DOCUMENTO QUE SUBE, Y NO UNO NUEVO ───────────────────────────
--
-- El primer diseño creaba un documento de suspensión aparte, con el de
-- amonestación como `doc_previo_id`. Se descartó al mirar lo que sanciona cada
-- cosa: la suspensión por conducta no castiga otra vez el hecho ya amonestado
-- —eso sería dos sanciones por un hecho, contra el non bis in idem del 52.5—,
-- castiga el hecho NUEVO que, por haber un antecedente vigente, sube de peldaño
-- (56.4). Y el hecho nuevo ya está registrado: es el borrador que la líder
-- acaba de crear.
--
-- Así que lo que cambia es el NIVEL de ese borrador, y `doc_previo_id` pasa a
-- apuntar al antecedente que habilitó el escalón. Esa columna existe desde la
-- 0056 justo para esto: «la cadena: amonestación → suspensión → imputación →
-- despido». Un documento, una sanción, una cadena que se puede leer hacia atrás.
--
-- ── POR QUÉ NO SE REESCRIBE NINGUNA FUNCIÓN ─────────────────────────────────
--
-- Ni una. Las tres reglas que hacían falta ya estaban escritas y se LLAMAN:
--
--   · Quién puede imponer una suspensión: `fn_expediente_puede_actuar(persona,
--     'suspension')`. La 0510 ya le dio a la líder solo `verbal` y
--     `amonestacion`, así que una líder rebota aquí sin que esta migración
--     diga su nombre. Si mañana cambia la competencia, cambia en un sitio.
--   · Cuántos días caben: `fn_expediente_set_suspension` (0294), que topa en
--     TRES (54.5) y calcula los días laborables. No se duplica: se invoca.
--     Esa función ya existe porque una suspensión de 2 días apareció en
--     pantalla con 10 al rozar la rueda del mouse; escribir aquí una segunda
--     versión del tope sería pedir que las dos envejezcan distinto.
--   · Qué corresponde según el Reglamento: `fn_conducta_antecedentes` (0510),
--     que ya sabe de gravedad, de antecedente vigente por la MISMA falta
--     (56.4, 56.5) y de las tres amonestaciones leves que hacen significativa
--     la siguiente (53.2 a).
--
-- Y eso evita el accidente de la 0261: `fn_expediente_firmar` tiene ocho
-- versiones y no se toca aquí.
--
-- ── LO QUE SÍ COMPRUEBA ESTA MIGRACIÓN, Y POR QUÉ ───────────────────────────
--
--   · ART. 54.8 — UNA FALTA LEVE NO LLEGA A SUSPENSIÓN. «La falta leve se
--     sanciona, como máximo, con amonestación escrita.» Salvo que haya tres
--     amonestaciones leves vigentes, que la vuelven significativa (53.2 a).
--     Sin esto, un descuido de presentación personal podía costar tres días
--     sin sueldo.
--   · ART. 56.2 Y 56.3 — EL ANTECEDENTE TIENE QUE ESTAR ENTREGADO Y VIGENTE.
--     «Un documento firmado por la Empresa y no entregado no está vigente, no
--     agrava, no habilita el escalón siguiente.» Lo mide
--     `fn_conducta_antecedentes`, que solo mira `estado = 'entregado'` dentro
--     de doce meses.
--   · ART. 54.7 — SALTAR UN PELDAÑO SE MOTIVA POR ESCRITO. Si no hay
--     antecedente vigente, suspender es saltarse la amonestación: entonces el
--     motivo deja de ser opcional y queda en el documento que la persona lee.
--
-- ── POR QUÉ EL TRIGGER, SI HOY NADIE PODRÍA ESCRIBIR ESA COLUMNA ────────────
--
-- Medido al escribir la prueba 457: `expediente_disciplinario` tiene RLS activa
-- y solo TRES políticas, las tres de SELECT (`exp_select_admin_lider`,
-- `exp_select_propia`, `exp_select_supervisor`). No hay ninguna de UPDATE, así
-- que un cliente `authenticated` que escriba directo no recibe un error: no
-- alcanza ninguna fila y se va en silencio. La tabla se escribe solo por
-- funciones `SECURITY DEFINER`, y eso ya la protege.
--
-- El trigger se pone igual, por dos razones concretas y no por simetría:
--
--   · Quien lleva `bypassrls` —la clave de servicio— SÍ puede escribir, y la
--     prueba 457 lo comprueba contra `service_role`, no contra `authenticated`.
--   · El día que alguien agregue una política de UPDATE a esta tabla para otra
--     cosa, la columna quedaría abierta sin que nadie lo note. El candado ya
--     está puesto para entonces. Es el molde que la casa ya repitió tres veces
--     (fn_bloquear_rol_directo 0296, fn_bloquear_sede_directa 0342), y la razón
--     por la que se repite es justamente esta.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--
--   · Que `fn_expediente_set_suspension` sigue siendo la puerta de los días
--     (0294) y que `fn_conducta_antecedentes` sigue devolviendo `gravedad`,
--     `antecedente_vigente` y `significativa_por_acumulacion` (0510).
--   · Que `doc_previo_id` sigue existiendo en `expediente_disciplinario` (0056).
--   · Que el descargo previo está encendido (0566). No lo exige esta migración
--     ni le hace falta: la suspensión pasa por la misma `fn_expediente_firmar`
--     que todo lo demás, y ahí se exige.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   drop trigger if exists trg_bloquea_propuesta_suspension on expediente_disciplinario;
--   drop function if exists fn_bloquear_propuesta_suspension();
--   drop function if exists fn_expediente_elevar_a_suspension(uuid, int, date, text);
--   drop function if exists fn_conducta_proponer_suspension(uuid, text);
--   alter table expediente_disciplinario
--     drop constraint if exists chk_propuesta_suspension_completa,
--     drop column if exists suspension_propuesta_por,
--     drop column if exists suspension_propuesta_at,
--     drop column if exists suspension_propuesta_motivo;
--
-- Revertir pierde las propuestas registradas (son columnas nuevas); las
-- suspensiones ya impuestas quedan como documentos normales de nivel
-- `suspension`, que es lo que son.
-- ============================================================================

-- ── 1 · La propuesta, en el documento ───────────────────────────────────────
alter table expediente_disciplinario add column if not exists suspension_propuesta_por    uuid references personas(id);
alter table expediente_disciplinario add column if not exists suspension_propuesta_at     timestamptz;
alter table expediente_disciplinario add column if not exists suspension_propuesta_motivo text;

comment on column expediente_disciplinario.suspension_propuesta_por is
  'Quién pidió que este hecho se sancione con suspensión en vez de amonestación. Pedir no es imponer: la competencia del art. 54.4 c) del RIT es de DO y de la Gerencia. Se escribe solo por fn_conducta_proponer_suspension.';

-- ESTADO IMPOSIBLE: una propuesta a medias. Las tres juntas o ninguna.
alter table expediente_disciplinario drop constraint if exists chk_propuesta_suspension_completa;
alter table expediente_disciplinario add constraint chk_propuesta_suspension_completa check (
  (suspension_propuesta_por is null and suspension_propuesta_at is null and suspension_propuesta_motivo is null)
  or (suspension_propuesta_por is not null and suspension_propuesta_at is not null
      and length(btrim(suspension_propuesta_motivo)) >= 20));

-- ── 2 · Quien propone: la líder de la sede, o DO ────────────────────────────
create or replace function fn_conducta_proponer_suspension(p_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
declare
  r   expediente_disciplinario%rowtype;
  v_a jsonb;
begin
  select * into r from expediente_disciplinario where id = p_id for update;
  if not found then raise exception 'El documento no existe.'; end if;

  -- Proponer es parte de tramitar la amonestación que ya tiene delante, así que
  -- el permiso es el de su propio nivel. Una líder que no podría amonestar a
  -- esta persona tampoco puede pedir que la suspendan.
  if fn_expediente_puede_actuar(r.persona_id, 'amonestacion') is not true then
    raise exception 'Sin permiso sobre este documento.';
  end if;
  if r.tipo_causal <> 'conducta' then
    raise exception 'Esto se pide sobre una falta de conducta. Las suspensiones por tardanzas e inasistencias las propone el sistema con la gradación de los arts. 19 y 21.';
  end if;
  if r.estado <> 'borrador' then
    raise exception 'Solo se pide sobre un borrador (estado actual: %). Un documento firmado o entregado ya no cambia de nivel.', r.estado;
  end if;
  if r.nivel <> 'amonestacion' then
    raise exception 'Se pide sobre una amonestación escrita. Una llamada verbal no es sanción (54.2) y no tiene peldaño siguiente.';
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 20 then
    raise exception 'Escribe por qué una amonestación no basta, con al menos una frase completa: es lo que DO va a leer para decidir, y lo que se discute si la persona cuestiona la sanción (54.7).';
  end if;

  -- ART. 54.8 · Que no se pida lo que el Reglamento no permite. Se avisa al
  -- proponer y no al imponer, para que la líder no quede esperando una
  -- respuesta que DO va a tener que negar.
  v_a := fn_conducta_antecedentes(r.persona_id, r.falta_numeral, r.falta_literal, r.periodo_desde);
  if (v_a->>'gravedad') = 'leve' and (v_a->>'significativa_por_acumulacion')::boolean is not true then
    raise exception 'La falta %) del numeral % es LEVE, y el numeral 54.8 del Reglamento la topa en amonestación escrita. Solo sube a significativa con tres amonestaciones leves vigentes (53.2 a), y hoy tiene %.',
      r.falta_literal, r.falta_numeral, coalesce(v_a->>'amonestaciones_leves_vigentes', '0');
  end if;

  update expediente_disciplinario
     set suspension_propuesta_por    = fn_persona_actual_id(),
         suspension_propuesta_at     = now(),
         suspension_propuesta_motivo = btrim(p_motivo)
   where id = p_id;

  insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (r.persona_id, 'expediente.suspension_propuesta',
          coalesce(r.suspension_propuesta_motivo, '(sin propuesta)'), btrim(p_motivo),
          fn_persona_actual_id(),
          'Pide que el hecho se sancione con suspensión en vez de amonestación (art. 54.4 c del RIT: la impone DO).');
end $$;

comment on function fn_conducta_proponer_suspension(uuid, text) is
  'La líder de equipo —o DO— pide por escrito que una falta de conducta se sancione con suspensión. No impone nada: la competencia es de DO y de la Gerencia (RIT 54.4 c). Rechaza las faltas leves, que el 54.8 topa en amonestación.';

-- ── 3 · Y el candado, porque una función guardián sin trigger es un consejo ──
create or replace function fn_bloquear_propuesta_suspension()
returns trigger language plpgsql as $$
begin
  if (new.suspension_propuesta_por    is distinct from old.suspension_propuesta_por
   or new.suspension_propuesta_at     is distinct from old.suspension_propuesta_at
   or new.suspension_propuesta_motivo is distinct from old.suspension_propuesta_motivo)
    and current_user <> 'postgres' then
    raise exception 'La propuesta de suspensión se registra desde Disciplina, no con una escritura directa a la tabla.';
  end if;
  return new;
end $$;

-- `current_user <> 'postgres'` es como Postgres distingue «lo hizo una función
-- interna» de «lo hizo un cliente por PostgREST»: el rol de conexión es el
-- mismo (`authenticated`) en los dos casos. Mismo molde que
-- fn_bloquear_rol_directo (0296) y fn_bloquear_sede_directa (0342).
drop trigger if exists trg_bloquea_propuesta_suspension on expediente_disciplinario;
create trigger trg_bloquea_propuesta_suspension
  before update on expediente_disciplinario
  for each row execute function fn_bloquear_propuesta_suspension();

-- ── 4 · Quien impone: DO o la Gerencia, nunca la líder ──────────────────────
create or replace function fn_expediente_elevar_a_suspension(
  p_id uuid, p_dias int, p_desde date, p_motivo text default null)
returns table (fecha date)
language plpgsql security definer set search_path = public as $$
declare
  r      expediente_disciplinario%rowtype;
  v_a    jsonb;
  v_prev jsonb;
  v_mot  text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  select * into r from expediente_disciplinario where id = p_id for update;
  if not found then raise exception 'El documento no existe.'; end if;

  -- ART. 54.4 c) · La competencia. Una líder de equipo rebota aquí: la 0510
  -- solo le dio `verbal` y `amonestacion`.
  if fn_expediente_puede_actuar(r.persona_id, 'suspension') is not true then
    raise exception 'Una suspensión sin goce la imponen Desarrollo Organizacional o la Gerencia General (art. 54.4 c del RIT). Si crees que una amonestación no basta, pídela con el botón de proponer: la decisión queda registrada con tu nombre.';
  end if;
  if r.tipo_causal <> 'conducta' then
    raise exception 'Esto eleva una falta de conducta. Las suspensiones por tardanzas e inasistencias las genera el sistema con la gradación de los arts. 19 y 21.';
  end if;
  if r.estado <> 'borrador' then
    raise exception 'Solo se eleva un borrador (estado actual: %).', r.estado;
  end if;
  if r.nivel <> 'amonestacion' then
    raise exception 'Se eleva una amonestación escrita. Una llamada verbal no es sanción (54.2) y no tiene peldaño siguiente.';
  end if;

  v_a    := fn_conducta_antecedentes(r.persona_id, r.falta_numeral, r.falta_literal, r.periodo_desde);
  v_prev := v_a->'antecedente_vigente';

  -- ART. 54.8 · La falta leve se topa en amonestación escrita.
  if (v_a->>'gravedad') = 'leve' and (v_a->>'significativa_por_acumulacion')::boolean is not true then
    raise exception 'La falta %) del numeral % es LEVE, y el numeral 54.8 del Reglamento la topa en amonestación escrita.',
      r.falta_literal, r.falta_numeral;
  end if;

  -- ART. 54.7 · Sin antecedente vigente, suspender es saltarse un peldaño, y
  -- eso «consta motivado por escrito en el documento que se entrega».
  if v_prev is null or jsonb_typeof(v_prev) = 'null' then
    if v_mot is null or length(v_mot) < 20 then
      raise exception 'Esta persona no tiene antecedente entregado y vigente por esta misma falta (arts. 56.2 y 56.3), así que suspender es saltarse la amonestación. El numeral 54.7 lo permite cuando la gravedad lo justifica por sí sola, pero exige que la decisión conste MOTIVADA POR ESCRITO en el documento que ella va a leer. Escribe ese motivo.';
    end if;
  end if;

  -- El nivel sube, y la cadena queda atada a lo que habilitó el escalón.
  -- Los tres campos de la suspensión se escriben provisionales porque
  -- `chk_susp_completa` (0056) no admite una suspensión sin días: el número
  -- definitivo y las fechas hábiles los fija set_suspension a continuación, en
  -- la misma transacción, y si rechaza los días no queda nada de esto.
  update expediente_disciplinario
     set nivel            = 'suspension',
         doc_previo_id    = coalesce((v_prev->>'id')::uuid, doc_previo_id),
         suspension_dias  = greatest(coalesce(p_dias, 1), 1),
         suspension_desde = p_desde,
         suspension_hasta = p_desde,
         observacion      = btrim(concat_ws(E'\n',
                              observacion,
                              case when v_mot is not null
                                then 'Suspensión en vez de amonestación (art. 54.7 del RIT): ' || v_mot end))
   where id = p_id;

  insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (r.persona_id, 'expediente.nivel', 'amonestacion', 'suspension', fn_persona_actual_id(),
          coalesce(v_mot, 'Falta significativa con antecedente vigente por la misma falta (arts. 54.8 y 56.4 del RIT).'));

  -- ART. 54.5 · El tope de tres días y los días laborables, en su única puerta.
  -- Va al final a propósito: si rechaza los días, la excepción revierte también
  -- el cambio de nivel y el rastro de arriba. O sube entero, o no sube.
  return query select * from fn_expediente_set_suspension(p_id, p_dias, p_desde);
end $$;

comment on function fn_expediente_elevar_a_suspension(uuid, int, date, text) is
  'DO o la Gerencia suben una amonestación de conducta a suspensión sin goce (RIT 54.4 c). Comprueba el 54.8 (la leve no llega), el 56.2/56.3 (el antecedente debe estar entregado y vigente) y el 54.7 (saltar un peldaño se motiva por escrito). Los días y su tope los fija fn_expediente_set_suspension.';

revoke all on function fn_conducta_proponer_suspension(uuid, text) from public;
revoke all on function fn_expediente_elevar_a_suspension(uuid, int, date, text) from public;
grant execute on function fn_conducta_proponer_suspension(uuid, text) to authenticated;
grant execute on function fn_expediente_elevar_a_suspension(uuid, int, date, text) to authenticated;

insert into migraciones_aplicadas (numero, nombre) values (567, 'la_lider_propone_suspension_y_do_la_impone')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

-- ============================================================================
-- COMPROBACIÓN
-- ============================================================================
select
  (select count(*) from information_schema.columns
    where table_name = 'expediente_disciplinario'
      and column_name in ('suspension_propuesta_por','suspension_propuesta_at','suspension_propuesta_motivo')) as columnas_de_3,
  (select count(*) from pg_proc where proname in
    ('fn_conducta_proponer_suspension','fn_expediente_elevar_a_suspension','fn_bloquear_propuesta_suspension')) as funciones_de_3,
  (select count(*) from pg_trigger where tgname = 'trg_bloquea_propuesta_suspension')                          as trigger_de_1,
  (select nombre from migraciones_aplicadas where numero = 567)                                                as registro;
