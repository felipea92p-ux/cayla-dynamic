-- ============================================================================
-- PARA PEGAR EN EL SQL EDITOR — el tablero de Documentación deja de pedirle
-- la declaración a quien no la va a firmar
-- ============================================================================
-- QUÉ MUEVE AL PEGARLO: **NI UN CENTAVO**. Solo cambia a quién LISTA la
-- pantalla de Documentación. `fn_planilla_calcular` no se toca, y el candado
-- de la 0159 sigue apagado, así que quien salga del tablero sigue cobrando su
-- movilidad exactamente igual que hoy.
--
-- DESPUÉS DE PEGARLO, EL TABLERO BAJA DE 22 A 20 PERSONAS:
--   · sale quien firma por CAYLA (la persona de `configuracion.firmante_empresa`),
--     porque no puede ser las dos partes del mismo pacto individual;
--   · sale quien termina contrato este mes — PERO SOLO SI ANTES SE LE ANOTA SU
--     FECHA DE FIN DE CONTRATO. Eso es el otro script:
--     `poner_fin_de_contrato.sql`. Sin esa fecha, este archivo no saca a nadie
--     por ese motivo, y el tablero baja a 21 y no a 20.
--
-- ⚠️ EL DÍA QUE SE ENCIENDA EL CANDADO DE LA 0159, ESTO SÍ MUEVE PLATA: quien
-- no está en el tablero no consigue su papel, y sin papel deja de devengar
-- movilidad. Leer la nota de la 0159 antes de encenderlo.
--
-- Requiere la 0161 aplicada antes.
--
-- ============================================================================
-- 0162 — El tablero no le pide la declaración a quien no la va a firmar
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `fn_documentos_tablero()` deje de listar como pendientes a dos personas
--   que nunca van a firmar esa declaración, y por el mismo criterio que ya usa
--   la lista de reparto de la pantalla de Documentación:
--
--     · QUIEN FIRMA POR CAYLA. La declaración de ruta es un pacto individual
--       entre la empresa y la persona. Quien firma en representación de CAYLA no
--       puede ser además la contraparte: sería el mismo puño en los dos lados del
--       acuerdo, que es justo lo que un inspector mira primero. Sale de
--       `configuracion.firmante_empresa` (0147), no de un nombre escrito acá:
--       el día que firme otra persona, la regla la sigue sola.
--
--     · QUIEN TERMINA CONTRATO ESTE MES O ANTES. Sale de `personas.
--       fecha_fin_contrato` (0144).
--
-- QUÉ ASUME
--   · La 0161, que es la definición VIGENTE de esta función. El cuerpo de abajo
--     es el suyo, byte por byte, salvo las dos condiciones marcadas «CAMBIO 0162».
--   · La 0147 (`configuracion.firmante_empresa`) y la 0144 (`fecha_fin_contrato`).
--     Si cualquiera de las dos falta, su condición no excluye a nadie y el tablero
--     se comporta exactamente como hoy — ninguna de las dos puede vaciar la lista.
--
-- POR QUÉ «ESTE MES» Y NO «TIENE FECHA DE FIN»
--   Porque el contrato a plazo fijo es la norma en tienda: si bastara con TENER
--   fecha, alguien contratado hasta el 31 de diciembre desaparecería del tablero
--   en agosto y cobraría cinco meses de movilidad sin el pacto que la sostiene.
--   El tablero existe para que eso no pase. Solo se calla cuando ya no queda un
--   periodo futuro que documentar.
--
--   La pantalla de Documentación es más laxa —desmarca a cualquiera con fecha de
--   fin— y puede permitírselo: ahí es un desmarcado que se vuelve a marcar de un
--   clic. Acá la persona desaparece, y lo que desaparece no se revisa.
--
-- LO QUE ESTO NO ARREGLA, Y HAY QUE SABERLO
--   Quien se va a fin de mes SÍ cobra la movilidad de este mes. Sacarlo del
--   tablero no cambia eso: cambia que ya nadie le va a perseguir la firma. Esa
--   movilidad queda sin pacto individual, y el momento en que se revisa es su
--   liquidación — el más auditado de toda la relación laboral. Es una decisión de
--   Felipe (2026-08-05), tomada sabiendo esto, no un efecto secundario.
--
-- QUÉ NO TOCA
--   Ni un centavo. `fn_planilla_calcular` no se roza: esta función solo LEE y solo
--   alimenta una pantalla. Quien sale del tablero sigue cobrando su movilidad
--   exactamente igual, porque el candado de la 0159 sigue apagado
--   (`movilidad_exige_declaracion` = 0).
--
--   ⚠️ EL DÍA QUE ESE CANDADO SE ENCIENDA, ESTO SÍ MUEVE PLATA: quien no está en
--   el tablero no consigue su papel, y sin papel deja de devengar movilidad. Ver
--   la nota de la 0159 antes de encenderlo.
--
-- DE QUÉ VERSIÓN PARTE, Y UNA ADVERTENCIA SOBRE `donde-vive.sh`
--   De la 0161. `./scripts/donde-vive.sh fn_documentos_tablero` respondió «0157»
--   y se equivocó: la 0161 la redefine con `drop function` + `create function`
--   —tuvo que hacerlo, porque cambió el tipo de retorno para agregar las columnas
--   del bono— y el script solo reconoce `create or replace`. Copiar de la 0157,
--   que es lo que el script indicaba, habría borrado en silencio `bono_estado`,
--   `bono_firmada_el` y `bono_mes`, y la pantalla habría dejado de ver los cargos
--   del bono de cumpleaños sin que fallara nada.
--
--   Es el mismo accidente del 2026-08-05 con `fn_planilla_calcular`, en el guard
--   que existe para evitarlo. Arreglar el script es aparte de esta migración.
--
-- CÓMO SE REVIERTE
--   Volver a aplicar el bloque A de la 0161 tal cual. No hay cambio de esquema ni
--   de datos: solo cambia a quién lista una consulta.
-- ============================================================================

-- Se conserva `create or replace` —y no drop+create— a propósito: el tipo de
-- retorno NO cambia respecto de la 0161, así que reemplazar basta y los permisos
-- concedidos sobre la función sobreviven.
create or replace function fn_documentos_tablero()
returns table (
  persona_id        uuid,
  persona           text,
  sede              text,
  fecha_ingreso     date,
  ruta_id           uuid,
  ruta_firmada_el   date,
  ruta_monto        numeric,
  ruta_negativa     boolean,
  ruta_desfasada    boolean,
  bono_id           uuid,
  bono_anio         integer,
  bono_firmada_el   date,
  bono_mes          integer,
  bono_estado       text,
  estado            text
)
language sql
stable
security definer
set search_path = public
as $$
  with hoy as (
    select fn_hoy_lima()                             as dia,
           extract(year  from fn_hoy_lima())::int    as anio,
           extract(month from fn_hoy_lima())::int    as mes,
           -- CAMBIO 0162 · el último día calendario de este mes. Se calcula acá y
           -- no en el `where` para que el corte sea UNO solo en toda la consulta.
           (date_trunc('month', fn_hoy_lima()) + interval '1 month - 1 day')::date
                                                     as fin_de_mes
  ),
  ruta as (
    select distinct on (d.persona_id)
           d.persona_id, d.id, d.fecha_firma, d.monto_declarado, d.es_negativa
    from documentos_firmados d
    where d.tipo = 'ruta' and d.anulado_at is null
    order by d.persona_id, d.fecha_firma desc, d.created_at desc
  ),
  bono as (
    select distinct on (d.persona_id)
           d.persona_id, d.id, d.anio, d.fecha_firma
    from documentos_firmados d, hoy
    where d.tipo = 'bono' and d.anulado_at is null and not d.es_negativa
      and d.anio = hoy.anio
    order by d.persona_id, d.fecha_firma desc
  )
  select
    p.id,
    p.nombres || ' ' || p.apellidos,
    coalesce(s.codigo, '?'),
    p.fecha_ingreso,
    r.id, r.fecha_firma, r.monto_declarado, coalesce(r.es_negativa, false),
    -- Firmada con una tarifa que ya no es la vigente: el papel declara un monto
    -- y se está pagando otro. No bloquea; avisa, que es lo acordado.
    --
    -- La tarifa es POR SEDE desde la 0142 (AQP y TRU a S/10, LIM a S/12), así que
    -- se compara contra la de SU sede. Compararla contra el máximo marcaría como
    -- desfasadas todas las de TRU y AQP el día que LIM tenga otra cifra — un aviso
    -- que grita sin motivo se desactiva a la semana.
    (r.monto_declarado is not null
      and tar.valor is not null
      and r.monto_declarado <> tar.valor),
    b.id, b.anio, b.fecha_firma,
    dp.mes_nacimiento,
    case
      -- El orden importa: primero lo que ya está resuelto, después lo que no se
      -- puede saber, y al final lo que hay que perseguir. Así ninguna persona
      -- cae en dos estados a la vez.
      when b.id is not null            then 'ok'
      when dp.mes_nacimiento is null   then 'sin_fecha'
      -- Su mes de onomástico de este año cayó antes del mes en que entró: ese año
      -- no había nada que entregarle.
      when make_date(hoy.anio, dp.mes_nacimiento, 1)
             < date_trunc('month', p.fecha_ingreso)::date then 'no_aplica'
      when dp.mes_nacimiento = hoy.mes then 'este_mes'
      when dp.mes_nacimiento <  hoy.mes then 'vencido'
      else                                  'proximo'
    end,
    case
      when r.id is null                    then 'sin_ruta'
      when coalesce(r.es_negativa, false)  then 'se_nego'
      else 'ok'
    end
  from personas p
  cross join hoy
  left join sedes s on s.id = p.sede_base_id
  left join ruta r on r.persona_id = p.id
  left join bono b on b.persona_id = p.id
  -- Solo el MES sale de la ficha personal. La fecha de nacimiento completa es
  -- dato sensible y esta consulta la ve una pantalla: se devuelve lo mínimo que
  -- responde la pregunta, que es en qué mes hay que entregar.
  left join lateral (
    select extract(month from d.fecha_nacimiento)::int as mes_nacimiento
    from datos_personales d
    where d.persona_id = p.id and d.fecha_nacimiento is not null
  ) dp on true
  left join lateral (
    -- La fila de su sede si existe; si no, la general (sede_codigo nulo).
    select pl.valor
    from parametros_laborales pl
    where pl.clave = 'movilidad_diaria'
      and pl.vigente_desde <= hoy.dia
      and (pl.vigente_hasta is null or pl.vigente_hasta >= hoy.dia)
      and (pl.sede_codigo = s.codigo or pl.sede_codigo is null)
    order by (pl.sede_codigo is null), pl.vigente_desde desc
    limit 1
  ) tar on true
  where p.estado = 'activo'
    and p.en_planilla
    and fn_es_admin_o_lider() is true
    -- ⇩⇩⇩ CAMBIO 0162 ⇩⇩⇩ QUIEN FIRMA POR CAYLA NO SE PIDE EL PAPEL A SÍ MISMO.
    --
    -- `is distinct from` y no `<>` a propósito: si la fila de configuración no
    -- existe, la subconsulta devuelve null y `<>` daría null —o sea, FALSE en un
    -- WHERE— y el tablero saldría VACÍO. Es la misma trampa de los guards
    -- `is not true`: un null nunca puede decidir por su cuenta.
    and p.id is distinct from (
      select (c.valor->>'persona_id')::uuid
      from configuracion c
      where c.clave = 'firmante_empresa'
    )
    -- ⇩⇩⇩ CAMBIO 0162 ⇩⇩⇩ Y QUIEN TERMINA CONTRATO ESTE MES O ANTES.
    -- Sin fecha de fin, se queda: el caso normal es el contrato indefinido.
    and (p.fecha_fin_contrato is null or p.fecha_fin_contrato > hoy.fin_de_mes)
  order by (r.id is not null), p.apellidos;
$$;

grant execute on function fn_documentos_tablero() to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (162, 'el_tablero_no_le_pide_el_papel_a_quien_no_lo_firma')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $mig$
declare v_ret text;
begin
  -- Que la 0161 haya sobrevivido. Si estas columnas se perdieron, este archivo se
  -- copió de la 0157 —que es lo que `donde-vive.sh` indicaba— y la pantalla del
  -- bono se acaba de quedar ciega sin que nada falle.
  select pg_get_function_result(p.oid) into v_ret
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where p.proname = 'fn_documentos_tablero' and n.nspname = 'public';

  if v_ret is null
     or v_ret not like '%bono_estado%'
     or v_ret not like '%bono_firmada_el%'
     or v_ret not like '%bono_mes%' then
    raise exception '0162 · se perdieron las columnas del bono de la 0161. Revisa de qué migración se copió el cuerpo.';
  end if;

  raise notice '0162 · el tablero ya no lista a quien firma por CAYLA';
  raise notice '0162 · ni a quien termina contrato este mes o antes';
  raise notice '0162 · ningun pago cambia: el candado de la 0159 sigue apagado';
end $mig$;
