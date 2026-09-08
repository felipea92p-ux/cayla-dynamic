-- ============================================================================
-- 0386 · El tablero de contratos desempata como su hermana
-- ============================================================================
-- QUÉ PROMETE
--
--   Que `fn_contratos_tablero` elija SIEMPRE el mismo contrato como "el que
--   manda" para una persona, aunque dos contratos suyos empaten en
--   `generado_at`. Un solo cambio, de una línea: el `order by` del CTE
--   `ultimo` gana los tres desempates que la 0312 ya le puso a la función
--   hermana `fn_contrato_firmado_vigente_de`.
--
--     antes:  order by c.persona_id, c.generado_at desc
--     ahora:  order by c.persona_id, c.generado_at desc,
--                      c.fecha_inicio desc, c.fecha_fin desc, c.id desc
--
--   Nada más cambia. Mismos estados, mismas columnas, mismo orden de salida.
--
-- QUÉ ASUME
--
--   Que la 0347 es la versión vigente de `fn_contratos_tablero` — comprobado
--   con `./scripts/donde-vive.sh fn_contratos_tablero` (4 versiones repartidas:
--   0287, 0333, 0336, 0347) y con `git grep` sobre TODAS las ramas, ninguna de
--   las cuales la toca después de la 0347. El cuerpo de abajo es el de la 0347
--   íntegro, con esa única línea cambiada y marcada CAMBIO 0386.
--
--   md5 de partida, PEDIDO A PRODUCCIÓN en el SQL Editor (2026-09-06):
--     tal_cual        = d75f39c6dcdb66f06ef12eaac0272c36
--     sin_comentarios = 8efef61f4762ae36608ae6cbb35f1e47
--     caracteres      = 3989 · position('CAMBIO 0347' in prosrc) = 2047
--   Coincide byte por byte con el cuerpo de la 0347 en este repositorio —
--   producción tiene la 0347 puesta, con sus comentarios, y va al día hasta la
--   0385. No es el caso habitual (la mitad de las funciones de producción se
--   pegaron sin comentarios y su md5 nunca coincide): acá coincide el primero,
--   así que se sigue sin más.
--
-- POR QUÉ HACE FALTA, SI EN PRODUCCIÓN NUNCA HAY EMPATE
--
--   `contratos_generados.generado_at` es `default now()`, y `now()` dentro de
--   una misma transacción vale LO MISMO para todas las filas. Dos contratos
--   creados en una sola transacción empatan al microsegundo, y con un
--   `distinct on (persona_id) ... order by persona_id, generado_at desc` sin
--   desempate, cuál gana lo decide el orden físico que devuelva el `Sort`
--   —quicksort, que no es estable—, no el negocio.
--
--   Hoy la app nunca genera dos contratos en una transacción: cada uno entra
--   por su propia llamada a `fn_contrato_registrar` desde
--   `apps/web/app/(admin)/admin/contratos/page.tsx`, y cada RPC es su propia
--   transacción. Así que esta migración NO cambia ninguna fila de producción
--   ni ningún estado que se esté mostrando hoy en `/admin/contratos`.
--
--   Se hace igual por dos razones, y la segunda pesa más que la primera:
--
--   1. La prueba pgTAP `274_el_generador_hace_indefinidos.test.sql` sí crea
--      los dos contratos en una transacción — pgTAP corre entero dentro de
--      `begin … rollback`, no tiene otra forma. Sus aserciones 9 y 10 fallan
--      o pasan según el orden físico en que caigan las filas, que a su vez
--      depende del espacio libre que dejaron las transacciones revertidas de
--      las pruebas anteriores (272, 287, 312, 333, 336, 347 también insertan
--      en esta tabla). El 2026-09-06 la misma prueba PASÓ en la suite completa
--      y FALLÓ corriéndola sola, sin que la base se reconstruyera entre las
--      dos — y `db-tests` de GitHub Actions estaba verde en `main` al mismo
--      tiempo. Un rojo que va y viene solo es peor que un rojo fijo: se
--      aprende a ignorarlo.
--
--      Cuando gana el contrato equivocado, el síntoma es exactamente este:
--      `u.tipo` deja de ser 'indefinido', la rama del CAMBIO 0347 no se toca,
--      y como firmar un indefinido deja `personas.fecha_fin_contrato` en NULL,
--      la fila cae en `when g.fecha_efectiva is null then 'sin_vencimiento'` —
--      justo el falso positivo permanente que la 0347 existe para evitar.
--
--   2. Dos funciones estaban respondiendo la MISMA pregunta —"¿cuál de los
--      contratos de esta persona manda?"— de dos formas distintas.
--      `fn_contrato_firmado_vigente_de` desempata desde la 0312, con el
--      comentario ya escrito ahí ("Los tres desempates NO son adorno");
--      `fn_contratos_tablero` no. Una de las dos está mal, y no es la que
--      desempata.
--
-- POR QUÉ ESTOS DESEMPATES Y NO OTROS
--
--   Son los de la 0312, literalmente, y por eso mismo: el criterio dice lo que
--   diría una persona mirando dos papeles — manda el que EMPIEZA después, y a
--   igualdad, el que TERMINA después. `c.id desc` va al final solo como ancla
--   determinista: es un uuid, no significa nada, pero garantiza que nunca
--   quede un empate sin resolver.
--
--   Ojo con `c.fecha_fin desc` y un indefinido: su `fecha_fin` es NULL, y en
--   Postgres `desc` pone los NULL PRIMERO. O sea que a igualdad de
--   `generado_at` y `fecha_inicio`, gana el indefinido — que es lo correcto:
--   un contrato sin término no lo desplaza uno a plazo fijo que empieza el
--   mismo día.
--
-- QUÉ NO TOCA, Y POR QUÉ
--
--   `fn_contratos_historial` (0287) tiene el mismo `order by c2.generado_at
--   desc limit 1` sin desempate. No se toca acá a propósito: es una pantalla
--   de lectura que lista todos los contratos de una persona, no decide ningún
--   estado ni ninguna fecha que alimente el pago, y meterla en esta migración
--   mezclaría dos cambios en uno. Queda anotado como deuda, no como olvido.
--
-- CÓMO SE REVIERTE
--   Correr de nuevo el cuerpo de `fn_contratos_tablero` tal como quedó en
--   `supabase/migrations/0347_el_generador_de_contratos_hace_indefinidos.sql`.
--   No hay datos que deshacer: esta migración no escribe ninguna fila.
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
    -- ⇩⇩⇩ CAMBIO 0386 ⇩⇩⇩ Los tres desempates NO son adorno — son los mismos
    -- que la 0312 le puso a `fn_contrato_firmado_vigente_de`, y por el mismo
    -- motivo: `generado_at` es `now()`, que dentro de una misma transacción
    -- vale lo mismo para todas las filas. Sin desempate, «el más reciente» lo
    -- decidía el orden físico de la tabla. El criterio dice lo que diría una
    -- persona: manda el que empieza después, y a igualdad, el que termina
    -- después (un indefinido, con `fecha_fin` NULL, gana ahí — `desc` pone los
    -- NULL primero, que es lo correcto: un contrato sin término no lo desplaza
    -- uno a plazo fijo que empieza el mismo día). `c.id desc` cierra como
    -- ancla determinista.
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
      -- ⇩⇩⇩ CAMBIO 0347 ⇩⇩⇩ un indefinido se resuelve ACÁ, antes del chequeo
      -- genérico de vencimiento: su fecha efectiva es SIEMPRE null (no tiene
      -- fecha de término), así que si se dejara caer al chequeo de abajo
      -- quedaría en 'sin_vencimiento' para siempre, incluso con la copia ya
      -- entregada — un falso positivo permanente en "Necesitan atención". No
      -- exige `comunicado_mtpe_at`: ese registro ante la Autoridad
      -- Administrativa de Trabajo (art. 72-73, D.Leg. 728) es obligación
      -- propia de los contratos sujetos a modalidad, no del indefinido.
      when u.tipo = 'indefinido' and u.copia_entregada_at is null then 'tramite_pendiente'
      when u.tipo = 'indefinido'                        then 'ok'
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
  'Qué contrato o convenio necesita atención, y por qué (0287/0333/0336/0347/0386). '
  'Para una practicante, `fecha_fin_contrato` es la fecha EFECTIVA que gobierna: '
  'la más temprana entre su convenio y el tope legal de 12 meses desde que '
  'ingresó (Ley 28518 art. 30) — no necesariamente la que tiene escrita en su '
  'ficha. Un indefinido (0347) se resuelve antes del chequeo de vencimiento: '
  '"trámite pendiente" si falta la copia, si no "ok" — nunca exige '
  '`comunicado_mtpe_at` (esa obligación no le corresponde) y nunca queda '
  'atrapado en "sin_vencimiento", que sería un falso positivo permanente. '
  'El contrato que manda se elige con desempate explícito (0386), igual que en '
  'fn_contrato_firmado_vigente_de: dos contratos creados en una misma '
  'transacción empatan en `generado_at`, y sin desempate el ganador lo decidía '
  'el orden físico de la tabla.';

insert into migraciones_aplicadas (numero, nombre)
values (386, 'el_tablero_de_contratos_desempata_como_su_hermana')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $$
begin
  raise notice '0386 · fn_contratos_tablero desempata «el contrato que manda» igual que fn_contrato_firmado_vigente_de (0312). No cambia ninguna fila.';
end $$;
