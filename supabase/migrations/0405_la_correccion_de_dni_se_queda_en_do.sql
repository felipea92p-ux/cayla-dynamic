-- ============================================================================
-- 0405 — La corrección del número de DNI se queda en Desarrollo Organizacional
-- ============================================================================
--
-- QUÉ PROMETE
--   Una solicitud que cambia el NÚMERO de documento solo la puede aprobar
--   Desarrollo Organizacional. La encargada de sede la ve en su bandeja —para
--   que sepa que su equipo está esperando algo— pero con un aviso de que le
--   toca a DO, en vez de un botón que revienta al pulsarlo.
--
-- EL DEFECTO QUE CIERRA
--   La 0403 abrió `fn_resolver_solicitud_perfil` a la encargada de sede para
--   cualquier campo de su equipo. Pero aprobar un `correccion_identidad` que
--   trae `documento` pasa por `fn_set_documento` (0344), que sigue exigiendo
--   admin/líder y no sabe nada de sedes. Resultado hasta hoy: la encargada
--   pulsa «Aprobar» y la transacción entera se cae con «Solo un administrador
--   o líder puede cambiar el número de documento» — un permiso que la pantalla
--   acaba de decirle que tiene. La solicitud se queda pendiente y nada le dice
--   que hay que escalarla.
--
--   Se comprobaron las otras dos escrituras que `fn_aplicar_cambio_perfil`
--   delega: `fn_set_datos_personales` y `fn_set_derechohabiente` YA aceptan
--   `supervisor_sede` sobre su propia sede (0399). `fn_set_documento` es la
--   única que diverge, y por eso este arreglo es de un solo campo y no de una
--   familia entera.
--
-- POR QUÉ SE CIERRA LA PUERTA Y NO SE ABRE fn_set_documento
--   Abrir `fn_set_documento` a la encargada sería el otro arreglo posible, y
--   es el equivocado: ese número se imprime en memos y contratos (lo dice su
--   propio mensaje de error), y la 0403 declara en su cabecera que NO le abre
--   a la encargada nada de identidad. Este arreglo hace cierto lo que esa
--   cabecera ya prometía.
--
-- POR QUÉ UNA COLUMNA EN EL CATÁLOGO Y NO UN `if campo = '...'`
--   Regla de la casa: nunca una lista escrita a mano de algo que vive en una
--   tabla. Quién puede aprobar qué es un dato del catálogo, no una condición
--   repetida en la función y otra vez en la pantalla. Con la columna, el día
--   que otro campo necesite lo mismo se cambia una fila y no tres archivos.
--
-- QUÉ ASUME
--   0399 y 0403 aplicadas. `catalogo_campos_perfil`, `fn_es_admin_o_lider`,
--   `fn_rol_actual`, `fn_sede_actual_persona`, `fn_persona_actual_id`.
--
-- QUÉ NO HACE
--   No toca `fn_set_documento` ni `fn_aplicar_cambio_perfil`. El guard de
--   `fn_set_documento` sigue siendo la última red: si algún día otra ruta
--   llega hasta él sin ser DO, tiene que seguir negándose.
--
-- CÓMO SE REVIERTE
--   -- Volver a pegar fn_resolver_solicitud_perfil y fn_solicitudes_perfil_pendientes
--   -- con sus cuerpos de la 0403 (están completos en ese archivo), y luego:
--   alter table catalogo_campos_perfil drop column if exists solo_do;
--
-- md5 de partida (Postgres LOCAL, 2026-09-08 — esta sesión no tiene acceso al
-- SQL Editor). Las dos coinciden con lo que declaró la 0403, que todavía no
-- está pegada en producción: cuando se pegue, confirmarlas con donde-vive.sh
-- antes de pegar esta.
--   fn_resolver_solicitud_perfil:      b2f88d3ec735ec1cf5440af59e822c8b
--   fn_solicitudes_perfil_pendientes:  4882a874fcf823e29b977ac51acbee96
-- ============================================================================


-- ── A · El catálogo dice quién puede aprobar cada campo ─────────────────────
alter table catalogo_campos_perfil
  add column if not exists solo_do boolean not null default false;

comment on column catalogo_campos_perfil.solo_do is
  'Verdadero cuando aprobar este campo exige Desarrollo Organizacional y no '
  'basta con la encargada de sede (0403). Hoy solo `correccion_identidad`, '
  'porque aplicarlo pasa por fn_set_documento, que exige admin/líder.';

update catalogo_campos_perfil set solo_do = true  where campo = 'correccion_identidad';
update catalogo_campos_perfil set solo_do = false where campo <> 'correccion_identidad';


-- ── B · Resolver: la encargada no aprueba lo que es de DO ───────────────────
-- Mismo cuerpo que la 0403 con UN bloque nuevo, marcado CAMBIO 0405. Va
-- DESPUÉS del guard general y del de existencia, a propósito: quien no tiene
-- nada que ver con esa solicitud tiene que seguir viendo «sin permiso» y no
-- enterarse de qué campo es — la propiedad anti-sondeo que la 0403 se tomó el
-- trabajo de construir.
create or replace function fn_resolver_solicitud_perfil(
  p_id      uuid,
  p_aprobar boolean,
  p_motivo  text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_s      solicitudes_cambio_perfil%rowtype;
  v_existe boolean;
  v_sede   uuid;
  v_solo_do boolean;   -- CAMBIO 0405
begin
  -- Se lee la solicitud Y la sede de quien la pidió ANTES de decidir el
  -- permiso — para que a quien no tiene permiso el mensaje sea siempre "sin
  -- permiso", nunca "no existe" ni "sí existe": eso dejaría probar ids de
  -- solicitudes ajenas por el mensaje de error. Van en DOS consultas, no una
  -- sola con join: Postgres no deja mezclar una variable `%rowtype` con otro
  -- destino en el mismo `select ... into` (SQLSTATE 42601). `v_existe` guarda
  -- el `found` de la primera antes de que la segunda lo pise.
  select * into v_s from solicitudes_cambio_perfil where id = p_id;
  v_existe := found;

  select sede_base_id into v_sede from personas where id = v_s.persona_id;

  if (fn_es_admin_o_lider() is true
      or (fn_rol_actual() = 'supervisor_sede' and v_sede = fn_sede_actual_persona())) is not true then
    raise exception 'Solo un administrador, líder de Desarrollo Organizacional o la encargada de esa sede puede resolver una solicitud de perfil.';
  end if;

  if not v_existe then
    raise exception 'Esa solicitud ya no existe.';
  end if;
  if v_s.estado <> 'pendiente' then
    raise exception 'Esa solicitud ya fue % — no se puede resolver dos veces.', v_s.estado;
  end if;

  -- CAMBIO 0405: hay campos que solo aprueba DO. Antes esto no se comprobaba y
  -- la encargada llegaba hasta fn_set_documento, que la rechazaba con un
  -- mensaje que hablaba de otra cosa. Ahora se dice acá, y se dice qué hacer.
  select solo_do into v_solo_do from catalogo_campos_perfil where campo = v_s.campo;
  if coalesce(v_solo_do, false) and fn_es_admin_o_lider() is not true then
    raise exception 'Esta solicitud cambia el número de documento, y eso solo lo aprueba Desarrollo Organizacional. Avísales para que la revisen.';
  end if;

  if p_aprobar then
    perform fn_aplicar_cambio_perfil(p_id);
    update solicitudes_cambio_perfil
    set estado = 'aprobado', resuelta_at = now(), resuelta_por = fn_persona_actual_id(),
        motivo = nullif(trim(coalesce(p_motivo, '')), '')
    where id = p_id;
  else
    if coalesce(trim(p_motivo), '') = '' then
      raise exception 'Para rechazar hace falta decir por qué, aunque sea en una línea.';
    end if;
    update solicitudes_cambio_perfil
    set estado = 'rechazado', resuelta_at = now(), resuelta_por = fn_persona_actual_id(),
        motivo = trim(p_motivo)
    where id = p_id;
  end if;
end;
$fn$;
grant execute on function fn_resolver_solicitud_perfil(uuid, boolean, text) to authenticated;
revoke execute on function fn_resolver_solicitud_perfil(uuid, boolean, text) from public, anon;


-- ── C · La bandeja dice cuáles no le tocan ──────────────────────────────────
-- Mismo cuerpo que la 0403 con una columna más al final. `drop` + `create` y no
-- `create or replace`: Postgres no deja agregarle una columna al `returns
-- table` de una función existente.
--
-- La solicitud SE SIGUE MOSTRANDO a la encargada. Ocultarla sería peor: su
-- equipo estaría esperando algo que ella no ve, y nadie sabría por qué no
-- avanza. Lo que cambia es que la pantalla ya puede decir de quién es.
drop function if exists fn_solicitudes_perfil_pendientes();

create function fn_solicitudes_perfil_pendientes()
returns table (
  id uuid, persona_id uuid, nombre text, sede text, campo text, etiqueta text,
  valor_anterior jsonb, valor_propuesto jsonb, rutas_adjuntas text[], creada_at timestamptz,
  solo_do boolean   -- CAMBIO 0405
)
language sql stable security definer set search_path = public as $fn$
  select s.id, s.persona_id, pe.nombres || ' ' || pe.apellidos, sd.codigo,
         s.campo, c.etiqueta, s.valor_anterior, s.valor_propuesto, s.rutas_adjuntas, s.creada_at,
         c.solo_do
  from solicitudes_cambio_perfil s
  join personas pe on pe.id = s.persona_id
  join sedes sd on sd.id = pe.sede_base_id
  join catalogo_campos_perfil c on c.campo = s.campo
  where s.estado = 'pendiente'
    and (fn_es_admin_o_lider() is true
         or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona()))
  order by s.creada_at asc;
$fn$;
grant execute on function fn_solicitudes_perfil_pendientes() to authenticated;
revoke execute on function fn_solicitudes_perfil_pendientes() from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (405, 'la_correccion_de_dni_se_queda_en_do')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select solo_do from catalogo_campos_perfil where campo = 'correccion_identidad')
    is true as identidad_es_de_do,
  (select count(*)::int from catalogo_campos_perfil where solo_do) = 1 as solo_ese_campo,
  (select prosrc like '%CAMBIO 0405%' from pg_proc where proname = 'fn_resolver_solicitud_perfil')
    as resolver_al_dia,
  (select count(*)::int from information_schema.columns
     where table_name = 'catalogo_campos_perfil' and column_name = 'solo_do') = 1 as columna_puesta;
