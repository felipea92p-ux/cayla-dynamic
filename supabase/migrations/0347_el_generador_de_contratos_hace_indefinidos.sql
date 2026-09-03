-- ============================================================================
-- 0347 · El generador de contratos hace indefinidos
-- ============================================================================
-- QUÉ PROMETE
--
--   Que `/admin/contratos` pueda emitir un CONTRATO DE TRABAJO A PLAZO
--   INDETERMINADO, además de los cuatro documentos que ya sabía hacer (nuevo,
--   renovación, adendum, convenio de prácticas — 0272/0333). Hasta hoy todo lo
--   que no era convenio o adendum salía como plazo fijo por inicio o
--   incremento de actividad (art. 57, D.Leg. 728), sin importar si el ingreso
--   era permanente.
--
--   Cinco cambios:
--     1. `contratos_generados.tipo` acepta un quinto valor: 'indefinido'.
--     2. `contratos_generados.fecha_fin` deja de ser NOT NULL — un indefinido
--        no tiene fecha de término — y una constraint nueva ata los dos: un
--        indefinido SIEMPRE tiene `fecha_fin` en blanco, y ningún otro tipo
--        puede dejarla en blanco.
--     3. `fn_contrato_registrar` valida el quinto tipo y dispensa la fecha de
--        fin cuando corresponde.
--     4. `fn_contrato_refrescar_vencimiento` deja de romperse cuando el
--        contrato firmado más reciente es un indefinido (ver más abajo — esto
--        NO se anticipó al diseñar, lo cazó la prueba pgTAP de esta misma
--        migración).
--     5. `fn_contratos_tablero` resuelve un indefinido ANTES de llegar al
--        chequeo genérico de vencimiento: si le falta entregar la copia,
--        "trámite pendiente"; si no, "ok" — sin exigirle nunca
--        `comunicado_mtpe_at`. El registro ante la Autoridad Administrativa
--        de Trabajo (art. 72-73 del TUO del D.Leg. 728) es una obligación
--        propia de los contratos SUJETOS A MODALIDAD, no del indefinido.
--
--        Esto no es un detalle menor: como un indefinido nunca tiene
--        `fecha_fin_contrato` (ver el porqué más abajo), su fecha efectiva
--        SIEMPRE es NULL, y el chequeo genérico ya existente
--        (`when g.fecha_efectiva is null then 'sin_vencimiento'`) lo habría
--        capturado primero — dejándolo en "sin_vencimiento" PARA SIEMPRE,
--        incluso después de entregar la copia, porque esa fecha nunca deja
--        de ser NULL. Como "sin_vencimiento" no es 'ok' (`pendientes = tablero
--        .filter(f => f.estado !== "ok")` en la pantalla), cada indefinido
--        habría quedado clavado en "Necesitan atención" de por vida, sin que
--        quedara ningún trámite real por hacer — el mismo tipo de falso
--        positivo permanente que este sistema evita en todos lados (ver
--        CLAUDE.md, "Los falsos positivos son el peor error").
--
--   El texto legal del contrato (título, cláusula PRIMERA/SEGUNDA de
--   naturaleza y vigencia, cláusula VIGÉSIMA de terminación, y la DÉCIMA
--   OCTAVA sobre entrega de copia) vive en
--   `apps/web/lib/admin/contrato-texto.ts` — no en esta migración. El resto
--   del cuerpo (jornada, remuneración, beneficios, período de prueba,
--   disciplina, anexos) se reutiliza tal cual del contrato a plazo fijo: son
--   las mismas cláusulas para cualquier régimen laboral común.
--
-- QUÉ ASUME
--
--   Que la 0333 es la versión vigente de `fn_contrato_registrar`, que la
--   0312 es la vigente de `fn_contrato_refrescar_vencimiento`, y que la 0336
--   es la vigente de `fn_contratos_tablero` (comprobado con
--   `./scripts/donde-vive.sh` antes de escribir esta migración — las tres son
--   funciones con varias versiones repartidas).
--
--   PERO EL md5 DE PRODUCCIÓN, pedido al entregar este SQL (2026-09-03), dijo
--   otra cosa para `fn_contratos_tablero`: `8c26b81d021bf1b8bf6a62699499a874`,
--   2620 caracteres — que no es la 0336 (vigente en el repositorio), sino la
--   0333 tal cual, reconstruida y comprobada aparte. **La 0336 — "el tablero
--   avisa el tope de 12 meses del convenio" — nunca se pegó en producción**,
--   aunque lleva semanas en GitHub y la pantalla de `/admin/contratos` ya
--   asume su comportamiento (el texto "se acerca al tope de 12 meses del
--   convenio" para una practicante). Pegar esta migración pone a producción
--   al día con la 0336 Y la 0347 en un solo paso — decisión tomada con
--   Felipe por `AskUserQuestion` el 2026-09-03: la 0336 es aditiva y segura
--   (no quita nada de la 0333, solo agrega la fecha efectiva con tope), así
--   que no hace falta separarla en su propia pegada.
--
-- POR QUÉ fecha_fin NULLABLE Y NO UNA FECHA LEJANA DE RELLENO
--
--   Poner "2099-12-31" o similar sería mentir en la base: un indefinido NO
--   vence, y una fecha de relleno tarde o temprano dispara un aviso de
--   vencimiento falso en `fn_contratos_tablero` o en el aviso de "por vencer".
--   NULL ya es, en todo este sistema, cómo se dice "sin fecha de término" —
--   es exactamente el valor que `fn_set_fin_contrato` ya sabe recibir cuando
--   un contrato se renueva sin plazo fijo (0144): si el contrato firmado más
--   reciente es un indefinido, su `fecha_fin` es NULL, y
--   `fn_set_fin_contrato(persona_id, null, motivo)` ya hace lo correcto —
--   "sin fecha de vencimiento" — sin una sola línea nueva en ESA función.
--
-- POR QUÉ fn_contrato_refrescar_vencimiento SÍ SE TOCA (y fn_set_fin_contrato no)
--
--   `fn_set_fin_contrato` ya hace lo correcto sin cambios (ver arriba). Pero
--   `fn_contrato_refrescar_vencimiento` NO — y esto no se anticipó al leer su
--   código, lo hizo saltar la prueba pgTAP de esta misma migración al
--   firmar un indefinido de verdad:
--
--     return ' · su vencimiento queda en ' || to_char(v_r.fecha_fin, 'DD/MM/YYYY')
--            || ', el del contrato firmado más reciente';
--
--   Con `v_r.fecha_fin` NULL (un indefinido), `to_char(null, …)` es NULL, y
--   `||` con NULL colapsa TODA la concatenación a NULL — no solo esa cláusula,
--   el `return` completo. Ese NULL sube como `v_nota` en `fn_contrato_registrar`,
--   que a su vez hace `'Escaneo del contrato firmado registrado' || v_nota` —
--   otra vez NULL por la misma razón — y ese NULL termina como `motivo` del
--   `insert into correcciones_auditoria`, que tiene `motivo` NOT NULL. El
--   resultado no es un mensaje raro: es que FIRMAR UN INDEFINIDO REVENTABA,
--   sin que nada en el diseño lo hiciera sospechar. Se corrige separando el
--   caso `v_r.fecha_fin is null` con su propio texto, en vez de interpolarlo
--   a ciegas — la instancia exacta de la regla de este repo que ya pesa: medir
--   contra la base antes de dar algo por bueno.
--
--   `fn_contratos_desnaturalizados` (0231) sí sigue sin tocarse: ya excluye
--   con `p.fecha_fin_contrato is not null` a cualquiera sin fecha de término —
--   un indefinido nunca puede aparecer ahí, que es exactamente lo que debe
--   pasar: no hay "vencimiento" del que desnaturalizarse.
--
-- CÓMO SE REVIERTE
--   alter table contratos_generados drop constraint contrato_fecha_fin_segun_tipo;
--   alter table contratos_generados alter column fecha_fin set not null;
--   alter table contratos_generados drop constraint contratos_generados_tipo_check;
--   alter table contratos_generados add constraint contratos_generados_tipo_check
--     check (tipo in ('nuevo', 'renovacion', 'adendum', 'convenio_practicas'));
--   Y correr de nuevo el cuerpo de `fn_contrato_registrar`,
--   `fn_contrato_refrescar_vencimiento` y `fn_contratos_tablero` tal como
--   quedaron en la 0333, la 0312 y la 0336. (Antes de revertir, comprobar que
--   ningún `contratos_generados.tipo = 'indefinido'` siga en uso — revertir
--   la constraint con filas así fallaría, como debe.)
-- ============================================================================

-- ── 1 · fecha_fin deja de ser NOT NULL, y la nueva constraint ata los dos ──
alter table contratos_generados alter column fecha_fin drop not null;

alter table contratos_generados drop constraint if exists contrato_fecha_fin_segun_tipo;
alter table contratos_generados add constraint contrato_fecha_fin_segun_tipo
  check ((tipo = 'indefinido') = (fecha_fin is null));

-- ── 2 · El CHECK de tipo ─────────────────────────────────────────────────────
-- Idempotente: se reconstruye completo, así pegarla dos veces no rompe nada.
-- Solo AGREGA un valor — ninguna fila existente deja de ser válida.
alter table contratos_generados drop constraint if exists contratos_generados_tipo_check;

alter table contratos_generados add constraint contratos_generados_tipo_check
  check (tipo in (
    'nuevo',
    'renovacion',
    'adendum',
    'convenio_practicas',
    'indefinido'  -- ⇦ 0347: contrato de trabajo a plazo indeterminado
  ));

comment on column contratos_generados.tipo is
  'Tipo de documento generado. nuevo/renovacion/adendum/indefinido son '
  'contratos de trabajo (D.Leg. 728) — indefinido (0347) a plazo '
  'indeterminado, los otros tres sujetos a modalidad temporal. '
  'convenio_practicas (0333) NO es un contrato de trabajo: es un convenio de '
  'modalidad formativa (Ley 28518) para tipo_vinculo=''practicante''. No se '
  'funden: un convenio no tiene causa objetiva, periodo de prueba ni régimen '
  'disciplinario laboral, y un indefinido no tiene causa objetiva ni fecha '
  'de término.';

comment on column contratos_generados.fecha_fin is
  'Fecha de término del documento. NULL únicamente cuando tipo=''indefinido'' '
  '(0347) — un contrato a plazo indeterminado no vence. Cualquier otro tipo '
  'la exige, y tiene que ser posterior a fecha_inicio (ver constraint '
  'contrato_fecha_fin_segun_tipo).';

-- ── 3 · fn_contrato_refrescar_vencimiento ya no revienta con un indefinido ──
-- Cuerpo vigente: 0312_un_contrato_anulado_no_deja_su_fecha_puesta.sql. Un
-- solo cambio, marcado CAMBIO 0347; el resto es idéntico — ver "QUÉ ASUME" y
-- "POR QUÉ fn_contrato_refrescar_vencimiento SÍ SE TOCA" en la cabecera.
create or replace function fn_contrato_refrescar_vencimiento(
  p_persona_id   uuid,
  p_motivo       text,
  p_puede_borrar boolean default false
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r      contratos_generados%rowtype;
  v_activa boolean;
begin
  select (estado = 'activo') into v_activa from personas where id = p_persona_id;
  if v_activa is not true then
    -- `fn_set_fin_contrato` corta con «ya está inactiva». Para quien cesó la
    -- fecha de vencimiento no significa nada, pero el papel sí: registrar o
    -- anular no pueden fallar por esto. Es el defecto 1 que documentó la 0287.
    return ' · su fecha de vencimiento no se tocó: la persona ya no está activa';
  end if;

  v_r := fn_contrato_firmado_vigente_de(p_persona_id);

  if v_r.id is not null then
    perform fn_set_fin_contrato(p_persona_id, v_r.fecha_fin, p_motivo);
    -- ⇩⇩⇩ CAMBIO 0347 ⇩⇩⇩ `to_char(null, …)` es NULL, y `||` con NULL colapsa
    -- TODO el `return` a NULL — no solo esa cláusula. Antes de esta migración
    -- nunca pasaba (todo `fecha_fin` era NOT NULL); un indefinido lo dispara
    -- siempre, y el NULL resultante terminaba violando el NOT NULL de
    -- `correcciones_auditoria.motivo` en el llamador. Se separa el caso en
    -- vez de interpolar a ciegas.
    if v_r.fecha_fin is not null then
      return ' · su vencimiento queda en ' || to_char(v_r.fecha_fin, 'DD/MM/YYYY')
             || ', el del contrato firmado más reciente';
    else
      return ' · queda sin fecha de vencimiento: su contrato firmado más reciente es indefinido';
    end if;
  elsif p_puede_borrar is true then
    perform fn_set_fin_contrato(p_persona_id, null, p_motivo);
    return ' · no queda ningún contrato firmado: su vencimiento queda sin fijar';
  else
    return '';
  end if;
end;
$$;

revoke execute on function fn_contrato_refrescar_vencimiento(uuid, text, boolean) from public;

-- ── 4 · fn_contrato_registrar admite el quinto tipo ─────────────────────────
-- Cuerpo vigente: 0333_el_generador_de_contratos_hace_convenios_de_practicas.sql.
-- Tres cambios, marcados CAMBIO 0347; el resto es idéntico.
create or replace function fn_contrato_registrar(
  p_persona_id            uuid    default null,
  p_tipo                  text    default null,
  p_cargo                 text    default null,
  p_sede_id               uuid    default null,
  p_remuneracion_mensual  numeric default null,
  p_fecha_inicio          date    default null,
  p_fecha_fin             date    default null,
  p_horas_semanales       numeric default null,
  p_documento_html        text    default null,
  p_id                    uuid    default null,   -- no nulo = adjuntar firma a un borrador existente
  p_storage_path          text    default null,
  p_fecha_firma           date    default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id      uuid;
  v_yo      uuid := fn_persona_actual_id();
  v_nota    text := '';
  r         contratos_generados%rowtype;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional genera contratos.';
  end if;

  -- ── Adjuntar la firma a un borrador ya generado ──
  if p_id is not null then
    select * into r from contratos_generados where id = p_id;
    if not found then raise exception 'Ese contrato no existe.'; end if;
    if r.anulado_at is not null then raise exception 'Ese contrato está anulado.'; end if;
    if r.storage_path is not null then raise exception 'Ese contrato ya tiene un escaneo registrado.'; end if;
    if p_storage_path is null then raise exception 'Falta el escaneo firmado.'; end if;
    if p_fecha_firma is null then raise exception 'Falta la fecha en que se firmó.'; end if;
    if p_fecha_firma > fn_hoy_lima() then raise exception 'La fecha de firma no puede ser futura.'; end if;

    -- El archivo tiene que ser EL DE ESTE CONTRATO. `p_storage_path` es texto
    -- libre, y `fn_contrato_puede_ver` resuelve el permiso por el uuid que va
    -- en el nombre del archivo: apuntar la fila de una persona al escaneo de
    -- otra dejaría a la primera sin poder abrir su propio contrato y a la
    -- segunda viéndolo. Se cierra acá, que es donde se elige el path.
    if p_storage_path !~ ('^contratos/' || p_id::text || '\.') then
      raise exception 'La ruta del escaneo no corresponde a este contrato.';
    end if;

    update contratos_generados
       set storage_path = p_storage_path, fecha_firma = p_fecha_firma, registrado_por = v_yo
     where id = p_id;

    -- La fecha de vencimiento se mueve recién con la firma puesta: un borrador
    -- descartado nunca debe haber tocado este dato.
    --
    -- PERO NO SE DEJA CAER EL REGISTRO SI LA PERSONA YA NO ESTÁ ACTIVA. Ese era
    -- el defecto: `fn_set_fin_contrato` corta con «ya está inactiva», y quien
    -- cesó entre imprimir y firmar se quedaba SIN PODER ARCHIVAR su contrato
    -- firmado — justo el papel que hay que conservar. Para alguien cesado la
    -- fecha de vencimiento no significa nada; el documento sí.
    -- La fecha se recalcula, no se escribe a ciegas (0312). Antes se le ponía
    -- la fecha DE ESTE contrato sin más. Firmar un borrador viejo después de
    -- haber firmado el nuevo movía el vencimiento HACIA ATRÁS, y ese es el
    -- dato que `fn_contratos_desnaturalizados` usa para avisar del riesgo del
    -- artículo 77: retrocederlo fabrica una desnaturalización que no ocurrió,
    -- o esconde una que sí.
    --
    -- Se recalcula DESPUÉS del update de arriba, así que el contrato que se
    -- acaba de firmar ya cuenta como firmado y compite en igualdad. Si es el
    -- más reciente firmado, la fecha es la suya; si no, gana el otro y la suya
    -- no toca nada. Nunca borra: acaba de aparecer un contrato firmado.
    -- Un convenio firmado también mueve fecha_fin_contrato (0333) — es el
    -- mismo dato, reusado como fecha de fin de convenio.
    -- ⇩⇩⇩ CAMBIO 0347 ⇩⇩⇩ un indefinido firmado también dispara el recálculo:
    -- su `fecha_fin` es NULL, y `fn_set_fin_contrato(..., null, ...)` ya sabe
    -- leer eso como "sin fecha de vencimiento" — no hace falta un caso aparte.
    if r.tipo in ('nuevo', 'renovacion', 'adendum', 'convenio_practicas', 'indefinido') then
      v_nota := fn_contrato_refrescar_vencimiento(
                  r.persona_id, 'Contrato firmado — generador de contratos');
    end if;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (r.persona_id, 'contrato_firmado', null,
       r.tipo || ' · firmado el ' || p_fecha_firma::text, v_yo,
       'Escaneo del contrato firmado registrado' || v_nota);

    return p_id;
  end if;

  -- ── Generar el borrador ──
  -- ⇩⇩⇩ CAMBIO 0347 ⇩⇩⇩ admite 'indefinido'.
  if p_tipo not in ('nuevo', 'renovacion', 'adendum', 'convenio_practicas', 'indefinido') then
    raise exception 'Tipo de contrato inválido: «%».', p_tipo;
  end if;
  if p_persona_id is null or not exists (
    select 1 from personas where id = p_persona_id and estado = 'activo'
  ) then
    raise exception 'Esa persona no existe o no está activa.';
  end if;
  if p_cargo is null or btrim(p_cargo) = '' then
    raise exception 'Falta el cargo.';
  end if;
  if p_sede_id is null then
    raise exception 'Falta la sede.';
  end if;
  if p_remuneracion_mensual is null or p_remuneracion_mensual < 0 then
    raise exception 'Falta la remuneración, o es inválida.';
  end if;
  -- ⇩⇩⇩ CAMBIO 0347 ⇩⇩⇩ un indefinido NUNCA lleva fecha de fin; cualquier otro
  -- tipo SIEMPRE la exige, posterior a la de inicio — la misma validación de
  -- siempre, solo que ahora depende de `p_tipo`.
  if p_fecha_inicio is null then
    raise exception 'Las fechas del contrato son inválidas.';
  end if;
  if p_tipo = 'indefinido' then
    if p_fecha_fin is not null then
      raise exception 'Un contrato indefinido no lleva fecha de fin.';
    end if;
  else
    if p_fecha_fin is null or p_fecha_fin <= p_fecha_inicio then
      raise exception 'Las fechas del contrato son inválidas.';
    end if;
  end if;
  if p_documento_html is null or btrim(p_documento_html) = '' then
    raise exception 'Falta el texto del contrato.';
  end if;

  insert into contratos_generados (
    persona_id, tipo, cargo, sede_id, remuneracion_mensual,
    fecha_inicio, fecha_fin, horas_semanales, documento_html, generado_por
  ) values (
    p_persona_id, p_tipo, trim(p_cargo), p_sede_id, p_remuneracion_mensual,
    p_fecha_inicio, p_fecha_fin, p_horas_semanales, p_documento_html, v_yo
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (p_persona_id, 'contrato_generado', null,
     p_tipo || ' · generado el ' || fn_hoy_lima()::text, v_yo,
     'Alta de borrador de contrato');

  return v_id;
end;
$$;

grant execute on function fn_contrato_registrar(
  uuid, text, text, uuid, numeric, date, date, numeric, text, uuid, text, date
) to authenticated;
revoke execute on function fn_contrato_registrar(
  uuid, text, text, uuid, numeric, date, date, numeric, text, uuid, text, date
) from public, anon;

-- ── 5 · fn_contratos_tablero deja de exigir comunicado_mtpe_at a un indefinido
-- Cuerpo vigente: 0336_el_tablero_avisa_el_tope_de_12_meses_del_convenio.sql.
-- Devuelve TABLE con el mismo shape de columnas, así que basta `create or
-- replace` — mismo patrón que ya usa esta función desde que existe.
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
  'Qué contrato o convenio necesita atención, y por qué (0287/0333/0336/0347). '
  'Para una practicante, `fecha_fin_contrato` es la fecha EFECTIVA que gobierna: '
  'la más temprana entre su convenio y el tope legal de 12 meses desde que '
  'ingresó (Ley 28518 art. 30) — no necesariamente la que tiene escrita en su '
  'ficha. Un indefinido (0347) se resuelve antes del chequeo de vencimiento: '
  '"trámite pendiente" si falta la copia, si no "ok" — nunca exige '
  '`comunicado_mtpe_at` (esa obligación no le corresponde) y nunca queda '
  'atrapado en "sin_vencimiento", que sería un falso positivo permanente.';

insert into migraciones_aplicadas (numero, nombre)
values (347, 'el_generador_de_contratos_hace_indefinidos')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $$
begin
  raise notice '0347 · contratos_generados.tipo acepta indefinido, fecha_fin es nullable para ese tipo. fn_contrato_registrar y fn_contratos_tablero actualizados.';
end $$;
