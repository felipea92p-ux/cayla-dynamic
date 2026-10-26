-- ============================================================================
-- 0551 — Los practicantes también reciben las Normas
-- ----------------------------------------------------------------------------
-- PROMETE: que Normas cuente y muestre a los practicantes activos igual que al
--   resto del equipo, y en los tres estados en que puede estar su acceso:
--   con cuenta y ya entró, invitado que todavía no abrió el correo, o sin
--   cuenta (su constancia se registra en papel).
--
-- EL PEDIDO (Felipe, 2026-10-26, con la captura de Normas → Constancias):
--   «en normas también deberían aparecerme los practicantes, deben aparecer
--   todos incluyendo los que cuenten con su correo dentro del sistema y los
--   que fueron invitados».
--
-- ── LO QUE PASABA ───────────────────────────────────────────────────────────
-- «A quién obliga el Reglamento» tiene una sola respuesta desde la 0265:
-- `fn_poblacion_obligada()`. Esa respuesta era «activo, con contrato de
-- trabajo» (`tipo_vinculo = 'planilla'`), y el practicante —que es un vínculo
-- propio desde la 0322: modalidad formativa, Ley 28518— quedaba fuera.
--
-- Lo raro es que quedaba fuera SOLO de la lista, no del proceso:
--   · `fn_acusar_documento` (0208) no mira la población, así que un practicante
--     con cuenta ya podía dejar su constancia;
--   · el aviso «te falta el RIT» de «Lo mío» tampoco la mira
--     (`lib/acuses-pendientes.ts` lee `mi_acuse_at`, que es por persona).
-- O sea: el practicante recibía el aviso, firmaba, y DO no lo veía en ninguna
-- lista ni en ningún contador. Y quien no tenía cuenta no tenía por dónde
-- recibir el cargo en papel: el botón «registrar en papel» vive en la fila de
-- esa misma lista.
--
-- El Reglamento mismo los contempla (numeral 47.7: la investigación de los
-- casos de locadoras y practicantes). Que Normas no los viera era un hueco de
-- la lista, no una decisión escrita en ningún sitio.
--
-- ── POR QUÉ SE TOCA LA FUNCIÓN DE POBLACIÓN Y NO UNA COPIA PARA NORMAS ──────
-- Porque la misma pregunta la contestan cuatro funciones y la 0265 y la 0270
-- costaron mucho para que contestaran lo mismo:
--
--   · fn_documentos_vigentes()            el «N/M» de Normas (numerador y
--                                          denominador) y la insignia roja de
--                                          Constancias, y las constancias
--                                          pendientes de la Bandeja
--   · fn_acuses_documento(uuid)           la lista de la pestaña Constancias y
--                                          la hoja imprimible
--   · fn_sin_constancia_del_reglamento()  la alerta de Disciplina (60.5)
--   · fn_acuses_politica_salarial(int)    la hoja de Política salarial
--
-- Las tres primeras se corrigen solas al cambiar `fn_poblacion_obligada()`:
-- por eso esta migración NO reescribe ninguna de las tres (cero cuerpos
-- copiados, cero riesgo de copiar uno viejo). Una población solo para Normas
-- habría dejado a Normas diciendo «falta el practicante» y a Disciplina sin
-- avisarlo, que es exactamente lo que la 0270 se escribió para evitar.
--
-- ── EL CONTRAPESO: LA POLÍTICA SALARIAL NO CAMBIA ───────────────────────────
-- La cuarta función habría arrastrado a los practicantes a la hoja de Política
-- salarial, y ahí SÍ hay una decisión escrita: la Política salarial los excluye
-- a propósito (Ley 30709 no les alcanza, decidido el 2026-08-31), y la
-- pantalla ya los muestra aparte, en «También dejaron constancia», fuera del
-- total (novedad del 2026-10-24). Por eso `fn_acuses_politica_salarial` se
-- reescribe aquí con UNA condición más —`p.tipo_vinculo = 'planilla'`—, que
-- devuelve exactamente la misma lista de antes. Es la única función que se
-- reescribe además de la de población, y su cuerpo es la 0458 con esa línea.
--
-- ── QUÉ NO CAMBIA ───────────────────────────────────────────────────────────
--   · 'prueba' (días de selección, decisión del 2026-08-18, 0270), 'rxh' y
--     'no_trabajador' siguen fuera.
--   · Las cuentas de servicio siguen fuera (0491): no son personas.
--   · Los inactivos siguen fuera: un practicante cuyo convenio terminó y ya no
--     está activo no aparece, igual que quien cesó en planilla.
--   · `fn_reglamento_no_acusado(persona, fecha)` —el freno del 60.5 antes de
--     sancionar a UNA persona— no mira la población y ya frenaba también a un
--     practicante; no se toca.
--   · Ninguna constancia ya registrada se toca: esto solo cambia a quién se
--     cuenta.
--
-- ── EFECTOS QUE HAY QUE CONOCER ANTES DE PEGAR ──────────────────────────────
--   1. Los números suben: el «N/M» de cada documento suma a los practicantes
--      activos, y «constancias pendientes» (la insignia roja de Constancias, el
--      aviso de la Bandeja) sube en practicantes × documentos que piden
--      constancia, hasta que cada uno la deje o DO registre su cargo en papel.
--   2. Disciplina: un practicante activo sin constancia del Reglamento vigente
--      pasa a salir en la alerta previa (numeral 60.5). Antes no salía, aunque
--      el freno por persona ya lo cubría.
--   3. La hoja imprimible de constancias (`/admin/normas/<id>/constancias`)
--      incluye a los practicantes, porque sale de la misma función que la
--      pantalla: un «19 de 21» en el papel y un «19 de 18» en la pantalla es
--      el defecto que la 0265 vino a cerrar. La frase «personal activo y en
--      planilla» de esa hoja se corrige en el mismo PR.
--   4. Un practicante INVITADO que todavía no abrió el correo ya tiene la
--      cuenta enlazada (`invitar` enlaza `auth_user_id` al aceptar GoTrue el
--      envío), así que la lista lo muestra sin la etiqueta «sin cuenta»;
--      igual puede registrársele el cargo en papel mientras tanto.
--
-- ── MD5 DE PARTIDA (la guardia del bloque 0 los comprueba) ──────────────────
-- Medidos sobre el CUERPO que está en el repositorio —no se pidieron a
-- producción—, con la misma expresión que usa la guardia:
--
--   función                        tal cual        sin comentarios   largo
--   fn_poblacion_obligada          1b69c217…       6b3b7228…         195   (la 0491)
--   fn_acuses_politica_salarial    e7e56114…       e7e56114…         1309  (la 0458; sin comentarios en el cuerpo)
--
-- Por eso el bloque 0 existe: esta migración NO SE FÍA de que producción tenga
-- esos cuerpos. Si alguna es otra —cualquier md5 distinto al de partida y al de
-- llegada, con o sin comentarios, con o sin los retornos de carro que mete
-- pegar desde Windows (CLAUDE.md, la 0401)— ABORTA sin tocar nada. Es el
-- accidente de la 0276 y de la 0261: una migración copiada de una versión que
-- ya no era la vigente revierte en silencio lo que había entre medias.
--
-- Acepta TAMBIÉN el md5 de los cuerpos nuevos, para que pegarla dos veces sea
-- seguro (el md5 de partida ya no coincide la segunda vez) sin dejar de parar
-- si alguien cambió esas funciones después.
--
-- ⚠ SI EL HOOK RENUMERA ESTA MIGRACIÓN, los marcadores «CAMBIO 0551» de los
-- cuerpos cambian con el número y los md5 de llegada de abajo también (misma
-- longitud, distinto hash: CLAUDE.md, la 0286). Se miden DESPUÉS de renumerar.
--
-- ASUME: la 0491 (cuenta_de_servicio) y la 0458 (fn_acuses_politica_salarial
--   con `p_version`) ya están pegadas. La guardia lo comprueba por el md5.
--
-- CÓMO SE REVIERTE: volver a pegar `fn_poblacion_obligada` desde la 0491 y
--   `fn_acuses_politica_salarial` desde la 0458, con `create or replace`; no
--   hay datos que restaurar, ninguna de las dos guarda nada. (Sin tocar
--   funciones, la única forma de «sacar» a alguien es marcarlo inactivo.)
--
-- Idempotente: se puede pegar dos veces.
-- ============================================================================


-- ── 0 · LA GUARDIA ──────────────────────────────────────────────────────────
do $freno$
declare
  v_fn        text;
  v_tal       text;
  v_sin       text;
  v_tal_nuevo text;
  v_sin_nuevo text;
  v_falla     text := '';
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'personas'
                    and column_name = 'cuenta_de_servicio') then
    raise exception 'FALTA LA 0490. personas.cuenta_de_servicio no existe; pégala antes que esta.';
  end if;

  for v_fn, v_tal, v_sin, v_tal_nuevo, v_sin_nuevo in
    select * from (values
      ('fn_poblacion_obligada',
        '1b69c21750df6c569232589070cd6332', '6b3b7228cd1a71c95223638f616f7250',
        'edb77fd45be9e703375a7656a35515a1',                '73a9af0bf81418c9bffb17f7fe819857'),
      ('fn_acuses_politica_salarial',
        'e7e56114260ed0d5d416fb26dff26b46', 'e7e56114260ed0d5d416fb26dff26b46',
        '4a39d12b6f2289eff99dfe233d19e9a0',                 '5a1e3bcac17ad88dae04214baa4ce925')
    ) as t(fn, tal_cual, sin_comentarios, tal_cual_nuevo, sin_comentarios_nuevo)
  loop
    if not exists (
      select 1
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
             lateral (values (p.prosrc), (replace(p.prosrc, chr(13), ''))) as v(src)
       where n.nspname = 'public' and p.proname = v_fn
         and (md5(v.src) in (v_tal, v_tal_nuevo)
              or md5(array_to_string(array(
                   select regexp_replace(l, '[[:space:]]*--.*$', '')
                   from unnest(string_to_array(v.src, chr(10))) as l
                   where btrim(l) not like '--%'
                 ), chr(10))) in (v_sin, v_sin_nuevo)))
    then
      v_falla := v_falla || '  · ' || v_fn || chr(10);
    end if;
  end loop;

  if v_falla <> '' then
    raise exception E'PARA. Producción no tiene el cuerpo del que se copió esta migración:\n%\nPegarla revertiría en silencio lo que haya entre medias. Corre ./scripts/donde-vive.sh sobre cada una y reconstrúyela desde la versión de producción. (Nada se ha modificado: esto abortó antes de tocar nada.)', v_falla;
  end if;
end
$freno$;


-- ── 1 · LA ÚNICA FUENTE: quién tiene que recibir las Normas ─────────────────
-- El cuerpo es el de la 0491 con UNA línea cambiada (la del vínculo). Todo
-- lo que cuelga de esta función —lista, contadores, hoja y alerta de
-- Disciplina— cambia a la vez.
create or replace function public.fn_poblacion_obligada()
 returns setof uuid
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select id from personas
  where estado = 'activo' and tipo_vinculo in ('planilla', 'practicante')   -- CAMBIO 0551: el practicante tambien recibe las Normas
    and not cuenta_de_servicio;   -- CAMBIO 0491: una cuenta de servicio (estación de retail) no es una persona
$function$;

comment on function public.fn_poblacion_obligada() is
  'Las personas a las que el Reglamento y los demás documentos institucionales obligan, y a las que por tanto se les pide constancia: activas, con contrato de trabajo (planilla) o con convenio de prácticas (practicante, 0551). NO incluye a quien está en días de selección pagados (prueba, 0270), a locadoras (rxh), a quien no trabaja (no_trabajador) ni a una cuenta de servicio (0491). La hoja de Política salarial NO usa esta lista tal cual: deja fuera al practicante a propósito (fn_acuses_politica_salarial, 0551). Vive en una sola función porque la misma pregunta se respondía con la misma frase escrita a mano en varios sitios, y dos respuestas distintas a una sola pregunta es lo que este repositorio prohíbe.';


-- ── 2 · LA HOJA DE POLÍTICA SALARIAL SIGUE SIN LOS PRACTICANTES ─────────────
-- El cuerpo es el de la 0458 con UNA condición más: sin ella, el cambio de
-- arriba metería a los practicantes en una hoja de la que están excluidos por
-- decisión (Ley 30709 no les alcanza, 2026-08-31).
create or replace function fn_acuses_politica_salarial(p_version int default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $fn$
declare v_version int; v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede ver quien acuso la politica.';
  end if;

  if p_version is not null then
    select version into v_version from politica_salarial where version = p_version;
    if v_version is null then
      raise exception 'Esa version de la politica salarial no existe.';
    end if;
  else
    select version into v_version from politica_salarial order by version desc limit 1;
  end if;

  if v_version is null then
    return jsonb_build_object('version', null, 'personas', '[]'::jsonb);
  end if;

  select jsonb_build_object(
    'version', v_version,
    'personas', coalesce(jsonb_agg(jsonb_build_object(
      'persona_id', p.id,
      'nombre',     p.nombres || ' ' || p.apellidos,
      'rango',      s.rango,
      'acusado_at', a.acusado_at,
      'nombre_declarado', a.nombre_declarado
    ) order by (a.acusado_at is not null), p.apellidos, p.nombres), '[]'::jsonb)
  ) into v_out
  from personas p
  left join politica_salarial_acuses a
         on a.persona_id = p.id and a.version = v_version
  left join asignaciones_salario s
         on s.persona_id = p.id and s.vigente_hasta is null
  where p.id in (select fn_poblacion_obligada())
    and p.tipo_vinculo = 'planilla';   -- CAMBIO 0551: la Politica salarial no alcanza al practicante (Ley 30709, decidido el 2026-08-31)

  return v_out;
end;
$fn$;


insert into migraciones_aplicadas (numero, nombre)
values (551, 'los_practicantes_tambien_reciben_las_normas')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
-- Un solo select, porque el SQL Editor solo devuelve el último.
--
--   · registrada                 → tiene que salir 1 fila con su nombre.
--   · poblacion_incluye_practicantes → true.
--   · practicantes_activos / practicantes_contados → el MISMO número (menos las
--     cuentas de servicio, que no son personas).
--   · politica_sin_practicantes  → true: la hoja de Política salarial sigue sin
--     ninguno. Si dice false, la 0551 no se aplicó entera.
--   · equipo_obligado            → cuánta gente cuenta ahora en total.
select
  (select string_agg(numero || ' ' || nombre, ' · ')
     from migraciones_aplicadas where numero = 551)                       as registrada,
  (select position('practicante' in p.prosrc) > 0
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_poblacion_obligada')   as poblacion_incluye_practicantes,
  (select count(*) from personas
    where tipo_vinculo = 'practicante' and estado = 'activo'
      and not cuenta_de_servicio)                                         as practicantes_activos,
  (select count(*) from personas p
    where p.tipo_vinculo = 'practicante'
      and p.id in (select fn_poblacion_obligada()))                       as practicantes_contados,
  (select position('tipo_vinculo = ''planilla''' in p.prosrc) > 0
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_acuses_politica_salarial')
                                                                          as politica_sin_practicantes,
  (select count(*) from fn_poblacion_obligada())                          as equipo_obligado;
