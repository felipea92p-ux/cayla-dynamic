-- ============================================================================
-- 0470 · El MTPE ya no es trámite para nadie
-- ============================================================================
-- QUÉ PROMETE
--
--   Que `fn_contratos_tablero` deje de exigir `comunicado_mtpe_at` para llegar
--   a 'ok' en CUALQUIER tipo de contrato — no solo el indefinido, que la 0347
--   ya eximió. Un solo cambio en el `case` final:
--
--     antes:  when u.copia_entregada_at is null
--               or u.comunicado_mtpe_at is null   then 'tramite_pendiente'
--     ahora:  when u.copia_entregada_at is null    then 'tramite_pendiente'
--
--   Nada más cambia: mismas columnas, mismo shape, mismo orden de salida.
--   `comunicado_mtpe_at` sigue existiendo en `contratos_generados` y
--   `fn_contrato_marcar_tramite('mtpe', …)` sigue funcionando por si alguien
--   quiere anotar una fecha ahí — pero ya no bloquea nada.
--
-- POR QUÉ: EL REGISTRO ANTE LA AAT NO EXISTE DESDE 2016
--
--   La 0347 ya había eximido al indefinido razonando "esa obligación es de
--   los contratos sujetos a modalidad, no del indefinido" — cierto, pero
--   dejó la exigencia puesta para plazo fijo y convenio de prácticas
--   asumiendo que a ELLOS sí les tocaba. No: el Decreto Legislativo N.° 1246
--   ("medidas de simplificación administrativa", vigente desde el
--   2016-11-11) eliminó la obligación para TODOS:
--
--     - Modificó el artículo 73 del D.S. 003-97-TR (TUO del D. Leg. 728):
--       ya no hay que presentar copia de los contratos sujetos a modalidad
--       (plazo fijo) a la Autoridad Administrativa de Trabajo. Lo que antes
--       se presentaba en papel hoy ya se declara solo con la Planilla
--       Electrónica (PLAME/T-Registro) — que este sistema no reemplaza ni
--       necesita duplicar.
--     - Derogó el último párrafo del artículo 46 de la Ley N.° 28518: la
--       misma eliminación, para los convenios de modalidad formativa
--       (`convenio_practicas`) — dejaba 15 días para comunicar el convenio a
--       la AAT, y ese párrafo ya no existe.
--
--   O sea: para NINGÚN tipo de contrato que este sistema genera queda una
--   comunicación al MTPE que alguien tenga que ir a hacer. La cláusula
--   DÉCIMA OCTAVA de plazo fijo y convenio prometía ese trámite —se corrige
--   en la misma sesión, en `apps/web/lib/admin/contrato-texto.ts`— y la
--   pantalla dejaba "Falta trámite" a gente que no tenía nada pendiente:
--   un falso positivo real, no cosmético, en la bandeja de Desarrollo
--   Organizacional.
--
--   Se detectó porque Felipe leyó que el trámite no era necesario y pidió
--   confirmarlo antes de tocar nada — quedó confirmado con tres fuentes
--   independientes (ver PR).
--
-- QUÉ ASUME
--
--   Que la 0386 es la versión vigente de `fn_contratos_tablero` — comprobado
--   con `./scripts/donde-vive.sh fn_contratos_tablero` (6 versiones
--   repartidas: 0287, 0333, 0336, 0347, 0386, con la 0386 como la última). El
--   cuerpo de abajo es el de la 0386 íntegro, con esa única línea cambiada y
--   marcada CAMBIO 0470.
--
--   md5 de partida: NO se pudo pedir a producción en esta sesión (sin acceso
--   al SQL Editor). Local (`npx supabase start`, sin drift en esta función):
--     tal_cual = 34df0321b7abfdc7cf030e23d8c8543b · 4780 caracteres
--   Felipe: correr esto ANTES de pegar, y si no coincide ninguno, parar y
--   avisar en vez de pegar:
--     select md5(prosrc), md5(regexp_replace(prosrc, '--[^\n]*', '', 'g')),
--            length(prosrc)
--       from pg_proc where proname = 'fn_contratos_tablero';
--
--   md5 de llegada (medido en local DESPUÉS de renumerar 0469→0470 — el
--   marcador CAMBIO cambia con el número, así que medir antes habría dado un
--   valor que ya no es el de este archivo): 85d99e5aafcfdc5737f7f142284e1a8a
--   · 4288 caracteres. Sirve para confirmar que lo pegado quedó igual a lo
--   que se probó acá, no para decidir si pegar — eso lo decide el md5 de
--   partida de arriba.
--
-- CÓMO SE REVIERTE
--   Correr de nuevo el cuerpo de `fn_contratos_tablero` tal como quedó en
--   `supabase/migrations/0386_el_tablero_de_contratos_desempata_como_su_hermana.sql`.
--   No hay datos que deshacer: esta migración no escribe ninguna fila, solo
--   cambia qué estado deriva de las que ya existen.
-- ============================================================================

create or replace function fn_contratos_tablero()
returns table (
  persona_id            uuid,
  persona               text,
  sede                  text,
  fecha_fin_contrato    date,
  dias_restantes        int,
  contrato_id           uuid,
  tipo                  text,
  fecha_firma           date,
  copia_entregada_at    date,
  comunicado_mtpe_at    date,
  copia_vence           date,
  mtpe_vence            date,
  dias_marcados_despues int,
  estado                text
)
language sql
stable
security definer
set search_path = public
as $$
  with ultimo as (
    -- El contrato que manda por persona: el más reciente sin anular.
    select distinct on (c.persona_id)
           c.persona_id, c.id, c.tipo, c.fecha_firma, c.fecha_inicio,
           c.copia_entregada_at, c.comunicado_mtpe_at
      from contratos_generados c
     where c.anulado_at is null
     order by c.persona_id, c.generado_at desc,
              c.fecha_inicio desc, c.fecha_fin desc, c.id desc
  ),
  -- Marcó días DESPUÉS de su fecha de fin: el riesgo del art. 77 que la 0231
  -- ya sabe calcular y que hasta hoy no miraba ninguna pantalla.
  desn as (select * from fn_contratos_desnaturalizados()),
  -- La fecha que gobierna, para una practicante, nunca pasa del tope legal de
  -- 12 meses desde que ingresó — aunque su convenio diga otra cosa o no tenga
  -- fecha puesta (0336).
  gobierna as (
    select p.id as persona_id,
           case
             when p.tipo_vinculo <> 'practicante' then p.fecha_fin_contrato
             when p.fecha_fin_contrato is null
               then (p.fecha_ingreso + interval '12 months')::date
             else least(p.fecha_fin_contrato, (p.fecha_ingreso + interval '12 months')::date)
           end as fecha_efectiva
      from personas p
  )
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '—'),
    g.fecha_efectiva,
    (g.fecha_efectiva - fn_hoy_lima())::int,
    u.id, u.tipo, u.fecha_firma,
    u.copia_entregada_at, u.comunicado_mtpe_at,
    -- Los dos plazos de la cláusula décima octava. El de la copia corre desde
    -- el inicio de la prestación y es en días HÁBILES; se aproxima con días
    -- calendario + 2, que es lo que puede hacer una consulta sin calendario de
    -- feriados delante — y para avisar con tiempo basta.
    (u.fecha_inicio + 5)::date,
    (u.fecha_firma + 15)::date,
    coalesce(d.dias_marcados_despues, 0),
    case
      when d.persona_id is not null                     then 'desnaturalizado'
      when u.id is null                                 then 'sin_contrato'
      when u.fecha_firma is null                        then 'sin_firmar'
      -- Un indefinido se resuelve ACÁ, antes del chequeo genérico de
      -- vencimiento: su fecha efectiva es SIEMPRE null (no tiene fecha de
      -- término), así que si se dejara caer al chequeo de abajo quedaría en
      -- 'sin_vencimiento' para siempre — un falso positivo permanente.
      when u.tipo = 'indefinido' and u.copia_entregada_at is null then 'tramite_pendiente'
      when u.tipo = 'indefinido'                        then 'ok'
      when g.fecha_efectiva is null                      then 'sin_vencimiento'
      when g.fecha_efectiva < fn_hoy_lima()               then 'vencido'
      when g.fecha_efectiva - fn_hoy_lima() <= 60         then 'por_vencer'
      -- ⇩⇩⇩ CAMBIO 0470 ⇩⇩⇩ ya no exige `comunicado_mtpe_at`: el Decreto
      -- Legislativo N.° 1246 (vigente desde 2016-11-11) eliminó esa
      -- comunicación a la Autoridad Administrativa de Trabajo tanto para
      -- contratos sujetos a modalidad (modificó el art. 73, D.S. 003-97-TR)
      -- como para convenios de modalidad formativa (derogó el último párrafo
      -- del art. 46, Ley 28518). No queda ningún tipo de contrato al que
      -- este trámite le corresponda — la columna sigue existiendo por si se
      -- quiere anotar algo ahí, pero ya no bloquea 'ok'.
      when u.copia_entregada_at is null                 then 'tramite_pendiente'
      else 'ok'
    end
  from personas p
  join gobierna g on g.persona_id = p.id
  left join sedes s on s.id = p.sede_base_id
  left join ultimo u on u.persona_id = p.id
  left join desn d on d.persona_id = p.id
  where p.estado = 'activo'
    -- Una practicante también entra al tablero (0333). El guarda es
    -- `tipo_vinculo = 'practicante'` y NO `not en_planilla`: un locador RxH no
    -- tiene contrato ni convenio que generar y sigue fuera, igual que antes.
    and (p.en_planilla or p.tipo_vinculo = 'practicante')
    and fn_es_admin_o_lider() is true
  -- Lo que urge primero: quien ya está en riesgo, y después por vencimiento.
  order by
    case
      when d.persona_id is not null then 0
      when u.id is null then 1
      when u.fecha_firma is null then 2
      else 3
    end,
    g.fecha_efectiva nulls last,
    p.apellidos;
$$;

grant execute on function fn_contratos_tablero() to authenticated;

comment on function fn_contratos_tablero() is
  'Qué contrato o convenio necesita atención, y por qué (0287/0333/0336/0347/0386/0470). '
  'Para una practicante, `fecha_fin_contrato` es la fecha EFECTIVA que gobierna: '
  'la más temprana entre su convenio y el tope legal de 12 meses desde que '
  'ingresó (Ley 28518 art. 30) — no necesariamente la que tiene escrita en su '
  'ficha. Un indefinido (0347) se resuelve antes del chequeo de vencimiento: '
  '"trámite pendiente" si falta la copia, si no "ok". Desde la 0470, NINGÚN '
  'tipo exige `comunicado_mtpe_at`: el D. Leg. 1246 (2016-11-11) eliminó esa '
  'comunicación a la AAT tanto para plazo fijo (art. 73, D.S. 003-97-TR) como '
  'para convenios de prácticas (art. 46, Ley 28518). El contrato que manda se '
  'elige con desempate explícito (0386), igual que en '
  'fn_contrato_firmado_vigente_de: dos contratos creados en una misma '
  'transacción empatan en `generado_at`, y sin desempate el ganador lo decidía '
  'el orden físico de la tabla.';

comment on column contratos_generados.comunicado_mtpe_at is
  'Cuando se comunico el contrato a la Autoridad Administrativa de Trabajo — '
  'obligacion derogada desde el 2016-11-11 (D. Leg. 1246: modifico el art. 73 '
  'del D.S. 003-97-TR para plazo fijo, y derogo el ultimo parrafo del art. 46 '
  'de la Ley 28518 para convenios de practicas). Desde la 0470 esta columna ya '
  'no bloquea ningun estado del tablero (fn_contratos_tablero); se deja sin '
  'borrar porque puede tener fechas historicas anotadas de buena fe bajo la '
  'creencia anterior.';

insert into migraciones_aplicadas (numero, nombre)
values (470, 'el_mtpe_ya_no_es_tramite_para_nadie')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

do $$
begin
  raise notice '0470 · fn_contratos_tablero ya no exige comunicado_mtpe_at a ningún tipo de contrato (D. Leg. 1246, derogado desde 2016-11-11). No cambia ninguna fila.';
end $$;
