-- ============================================================================
-- 0336 · El tablero avisa el tope de 12 meses del convenio
-- ============================================================================
-- QUÉ PROMETE
--
--   El último de los cinco pendientes que dejó la 0322 al crear la categoría
--   practicante: avisar antes de que una practicante llegue a los doce (12)
--   meses continuos de modalidad formativa (Ley N.° 28518, art. 30), el punto
--   en el que superar el plazo — sin que el centro de formación sustente por
--   escrito una extensión — arriesga que la relación se considere
--   desnaturalizada.
--
--   No agrega pantalla ni columna nueva: `fn_contratos_tablero` (0287,
--   ensanchada por la 0333 para admitir practicantes) ya es el lugar donde
--   este sistema junta "qué necesita atención" sobre un documento de
--   vínculo — el mismo criterio avisa, no una pantalla aparte que hay que
--   acordarse de mirar.
--
-- QUÉ ASUME
--
--   Decidido con Felipe por `AskUserQuestion` el 2026-08-31: el acumulado se
--   mide **desde `personas.fecha_ingreso`**, no sumando la duración de cada
--   convenio generado — una practicante no entra y sale del estatus, es
--   continua desde que ingresó. Más simple, y correcto para el caso real.
--
-- CÓMO SE MIDE, Y POR QUÉ ASÍ
--
--   Para cualquiera que NO sea practicante, nada cambia: la fecha que manda
--   sigue siendo `personas.fecha_fin_contrato`, tal cual.
--
--   Para una practicante, la fecha que de verdad gobierna es la MÁS TEMPRANA
--   entre dos:
--     · lo que diga su convenio (`fecha_fin_contrato`, si lo tiene puesto), y
--     · el tope legal — `fecha_ingreso + 12 meses` — que ninguna fecha escrita
--       a mano puede correr más allá sin sustento.
--
--   Si su convenio vence ANTES del tope (el caso normal, porque el generador
--   ya avisa en pantalla si se intenta poner una fecha más lejana — 0333),
--   nada cambia: sigue gobernando su propio documento. El tope legal solo
--   toma el mando cuando no hay documento con fecha (`fecha_fin_contrato` en
--   blanco) o cuando alguien puso una fecha más allá del tope a pesar del
--   aviso en pantalla — que es exactamente el caso que hay que agarrar antes
--   de que se cumpla en silencio.
--
--   La columna `fecha_fin_contrato` que devuelve la función pasa a mostrar
--   esa fecha EFECTIVA para una practicante, no necesariamente la que tiene
--   escrita en su ficha — es lo que sostiene que `dias_restantes` y `estado`
--   cuenten la misma historia que la fecha que se ve. Mostrar la de la ficha
--   mientras el estado se calcula contra el tope habría dejado un tablero que
--   dice "vencido" junto a "faltan 400 días", que es peor que no avisar nada.
--
--   Reutiliza los MISMOS estados que ya existían (`vencido`, `por_vencer`,
--   `ok`…) — no se inventa uno nuevo. La fila de una practicante cerca del
--   tope aparece como "por_vencer" igual que cualquier otro, y quien la mira
--   ya sabe qué hacer con esa palabra.
--
-- QUÉ NO HACE
--
--   No bloquea nada — ni acá ni en el generador. "Dynamic avisa, nunca
--   sanciona solo": la extensión con sustento del centro de formación es una
--   excepción legal real que este sistema no puede verificar solo (mismo
--   criterio que ya eligió la 0333 para el aviso al generar un convenio de
--   más de 12 meses, y la 0324 para la jornada 30h/48h).
--
--   No suma convenios ni mira `contratos_generados` para el cómputo del tope
--   — decisión explícita de Felipe, ver «QUÉ ASUME».
--
-- CÓMO SE REVIERTE
--   Correr de nuevo el cuerpo de `fn_contratos_tablero` tal como quedó en la
--   0333 — sin la fecha efectiva, con `p.fecha_fin_contrato` sin condicionar.
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
     order by c.persona_id, c.generado_at desc
  ),
  -- Marcó días DESPUÉS de su fecha de fin: el riesgo del art. 77 que la 0231
  -- ya sabe calcular y que hasta hoy no miraba ninguna pantalla.
  desn as (select * from fn_contratos_desnaturalizados()),
  -- ⇩⇩⇩ CAMBIO 0336 ⇩⇩⇩ la fecha que gobierna, para una practicante, nunca
  -- pasa del tope legal de 12 meses desde que ingresó — aunque su convenio
  -- diga otra cosa o no tenga fecha puesta.
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
      when g.fecha_efectiva is null                      then 'sin_vencimiento'
      when g.fecha_efectiva < fn_hoy_lima()               then 'vencido'
      when g.fecha_efectiva - fn_hoy_lima() <= 60         then 'por_vencer'
      when u.copia_entregada_at is null
        or u.comunicado_mtpe_at is null                 then 'tramite_pendiente'
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
  'Qué contrato o convenio necesita atención, y por qué (0287/0333/0336). '
  'Para una practicante, `fecha_fin_contrato` es la fecha EFECTIVA que gobierna: '
  'la más temprana entre su convenio y el tope legal de 12 meses desde que '
  'ingresó (Ley 28518 art. 30) — no necesariamente la que tiene escrita en su '
  'ficha.';

insert into migraciones_aplicadas (numero, nombre)
values (336, 'el_tablero_avisa_el_tope_de_12_meses_del_convenio')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $$
begin
  raise notice '0336 · fn_contratos_tablero avisa el tope de 12 meses de una practicante, midiendo desde fecha_ingreso.';
end $$;
