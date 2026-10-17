-- ============================================================================
-- 0531 — La política de movilidad se firma con la firma que el sistema ya tiene
-- ============================================================================
--
-- QUÉ PROMETE
--   Que la política de movilidad pueda quedar firmada desde Documentación con
--   la firma de quien firma por CAYLA (`configuracion.firmante_empresa`, hoy
--   Felipe), la misma que ya está guardada en `firmas_escaneadas` y que ya se
--   estampa en los contratos, la declaración de ruta y el cargo del bono — sin
--   imprimir, firmar a mano, escanear y subir. Pedido el 2026-10-17 desde el
--   formulario «Subir la política de movilidad firmada»: «que use la firma
--   existente de Felipe».
--
--   Y que lo firmado quede CONGELADO, igual que un papel escaneado: el texto
--   de la política tal como estaba al firmarla (`documento_html`), la imagen
--   de la firma (`firma_persona`) y quién firmó por CAYLA
--   (`firmante_empresa_id`). Si mañana cambian las tarifas, el texto de una
--   cláusula o la persona configurada como firmante, la política firmada hoy
--   sigue diciendo lo que se firmó hoy.
--
-- QUÉ NO HACE, A PROPÓSITO
--   · No retira el escaneo: «Subir el papel firmado» sigue igual, por
--     `fn_documento_registrar`. Las dos vías conviven y manda la más reciente,
--     como ya pasa entre dos escaneos (0211) y como decidió Felipe para la
--     declaración de ruta (0423).
--   · No toca `fn_documento_registrar`, `fn_documentos_estado_politica` ni
--     `fn_documentos_listar`. La fila nueva es una política como cualquier otra
--     —`storage_path` en null, que la 0157 siempre permitió— y las tres la
--     leen sin cambios: `cargada` y `llego_tarde` no miran el archivo, y
--     `fn_documentos_listar` ya devuelve `firma_persona` desde la 0423.
--   · No deja estampar la firma de una persona cualquiera: la función no
--     recibe ni imagen ni persona. Lee SOLO la de quien está configurado como
--     firmante de la empresa, con el mismo join que `fn_firma_empresa` (0398).
--     La regla de la pantalla —«la firma de una persona no se estampa bajo el
--     nombre de otra»— se cumple: es su firma, bajo su nombre.
--
-- QUÉ ASUME
--   · `documentos_firmados` de la 0157 con las columnas de evidencia de la
--     0423 (`firma_persona`, `firma_persona_confirmada_at` y su constraint).
--   · `configuracion.firmante_empresa` (0147) y `firmas_escaneadas`
--     (0065/0076/0395).
--   · Que nadie más crea `fn_politica_firmar_con_firma_empresa` ni las dos
--     columnas: comprobado el 2026-10-17 con `git grep` sobre todas las ramas.
--
-- POR QUÉ ASÍ
--   El bucket `documentos` solo acepta imágenes y PDF (0157), y el navegador no
--   tiene con qué generar un PDF; por eso lo congelado vive en una columna y no
--   en un archivo. Es la misma forma que ya usa `contratos_generados.documento_html`.
--
--   El HTML lo arma la pantalla —es el mismo documento que se imprime— y esta
--   función lo valida antes de guardarlo: que traiga EXACTAMENTE la firma
--   guardada del firmante (así no puede archivarse una política con otra
--   rúbrica estampada), que sea la política, y que no traiga nada ejecutable.
--   Lo último importa porque la pantalla lo vuelve a pintar con
--   `dangerouslySetInnerHTML`; React nunca produce `<script>` ni atributos
--   `on…=`, así que si aparecen, no vino de la pantalla.
--
--   `fecha_firma` se recibe igual que en el escaneo: la política se fecha el día
--   en que empezó a pagarse la movilidad (ver el aviso de Documentación). El
--   instante REAL en que se firmó queda aparte en `firma_persona_confirmada_at`,
--   que el constraint de la 0423 exige junto con la imagen. Las dos fechas no se
--   mezclan, igual que en la declaración de ruta digital.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_politica_firmar_con_firma_empresa(date, text, text);
--   alter table documentos_firmados
--     drop constraint if exists chk_documento_politica_del_sistema,
--     drop column if exists documento_html,
--     drop column if exists firmante_empresa_id;
--   Las políticas que se hayan firmado así quedan como filas sin archivo: siguen
--   contando como «cargada», pero se pierde su texto congelado. Antes de
--   revertir, anularlas o subir el papel equivalente.
-- ============================================================================


-- ── A · Lo que se congela al firmar ────────────────────────────────────────
alter table documentos_firmados
  add column if not exists firmante_empresa_id uuid references personas(id),
  add column if not exists documento_html text;

-- Las dos van juntas, solo en la política, y solo con la firma puesta: una
-- política «del sistema» sin texto congelado no se podría volver a mostrar, y
-- una sin firma no está firmada.
alter table documentos_firmados drop constraint if exists chk_documento_politica_del_sistema;
alter table documentos_firmados add constraint chk_documento_politica_del_sistema check (
  (firmante_empresa_id is null and documento_html is null)
  or (tipo = 'politica'
      and firmante_empresa_id is not null
      and documento_html is not null
      and firma_persona is not null)
);

comment on column documentos_firmados.firmante_empresa_id is
  'Quién firmó por CAYLA una política firmada desde el sistema (0531): la persona '
  'que estaba en configuracion.firmante_empresa en ese momento. Null en todo lo '
  'demás, incluida la política subida como escaneo.';

comment on column documentos_firmados.documento_html is
  'El texto de la política tal como estaba al firmarla desde el sistema (0531), con '
  'la firma estampada. Es el equivalente del papel escaneado: no se regenera, se '
  'muestra tal cual. Null en todo lo demás.';

comment on column documentos_firmados.firma_persona is
  'La firma de QUIEN DECLARA, congelada al momento de firmar (0423) — no una '
  'referencia viva a firmas_escaneadas, por la misma razón que contratos_generados '
  'no la usa: si cambia su firma general después, esta declaración sigue mostrando '
  'la que firmó. Solo se llena cuando el trámite fue digital; un escaneo subido a '
  'mano (admin, sigue existiendo) deja esta columna en null y usa storage_path. '
  'En la política (0531) es la firma de quien firmó por CAYLA: ver firmante_empresa_id.';


-- ── B · Firmar la política con la firma de la empresa ──────────────────────
create or replace function fn_politica_firmar_con_firma_empresa(
  p_fecha_firma     date,
  p_documento_html  text,
  p_nota            text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo        uuid := fn_persona_actual_id();
  v_firmante  uuid;
  v_imagen    text;
  v_id        uuid;
begin
  -- Mismo guard que `fn_documento_registrar`: quien hoy puede subir el escaneo
  -- de la política es quien puede firmarla desde aquí.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo Desarrollo Organizacional registra documentos firmados.';
  end if;

  if p_fecha_firma is null then
    raise exception 'Falta la fecha de la política.';
  end if;
  if p_fecha_firma > fn_hoy_lima() then
    raise exception 'La fecha de la política no puede ser futura.';
  end if;

  -- Quién firma por CAYLA, y su firma. El mismo join que `fn_firma_empresa`
  -- (0398): ni la persona ni la imagen llegan por parámetro.
  select (c.valor ->> 'persona_id')::uuid into v_firmante
    from configuracion c
   where c.clave = 'firmante_empresa';
  if v_firmante is null then
    raise exception 'No hay nadie configurado para firmar por CAYLA. Sube el papel firmado a mano.';
  end if;

  select f.imagen into v_imagen
    from firmas_escaneadas f
   where f.persona_id = v_firmante;
  if v_imagen is null then
    raise exception 'Quien firma por CAYLA todavía no tiene su firma guardada en el sistema. Puede guardarla desde su ficha, o sube el papel firmado a mano.';
  end if;

  -- El documento que se congela.
  if p_documento_html is null or length(p_documento_html) < 500 then
    raise exception 'Falta el texto de la política que se firma.';
  end if;
  if length(p_documento_html) > 2000000 then
    raise exception 'El documento de la política pesa demasiado para guardarse.';
  end if;
  if position('Política de movilidad' in p_documento_html) = 0 then
    raise exception 'El documento que llegó no es la política de movilidad.';
  end if;
  -- Exactamente la firma guardada, no otra: si la pantalla tenía una copia
  -- vieja —la firma se cambió en otra pestaña— se vuelve a cargar y listo.
  if position(v_imagen in p_documento_html) = 0 then
    raise exception 'La firma estampada no es la que el sistema tiene guardada. Recarga la página y vuelve a firmar.';
  end if;
  if p_documento_html ~* '<\s*(script|iframe|object|embed|link|meta|style|base|form)\M|\son[a-z]+\s*=|javascript:' then
    raise exception 'El documento de la política trae contenido que no corresponde.';
  end if;

  -- ── REEMPLAZAR ES REEMPLAZAR (0211) ──────────────────────────────────
  -- La misma anulación, con el mismo motivo, que hace `fn_documento_registrar`
  -- con un escaneo: una política nueva deja a la anterior como historial.
  update documentos_firmados
     set anulado_at = now(),
         anulado_por = v_yo,
         anulado_motivo = 'Reemplazada por la política firmada el ' ||
                          to_char(p_fecha_firma, 'DD/MM/YYYY')
   where tipo = 'politica' and anulado_at is null;

  insert into documentos_firmados (
    alcance, persona_id, tipo, storage_path, fecha_firma, nota, registrado_por,
    firma_persona, firma_persona_confirmada_at, firmante_empresa_id, documento_html
  ) values (
    'empresa', null, 'politica', null, p_fecha_firma,
    nullif(trim(coalesce(p_nota, '')), ''), v_yo,
    v_imagen, now(), v_firmante, p_documento_html
  )
  returning id into v_id;

  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values
    (v_yo, 'documento_firmado', null,
     'politica · firmado el ' || p_fecha_firma::text,
     v_yo,
     'Política firmada desde el sistema con la firma de la empresa');

  return v_id;
end;
$$;
grant execute on function fn_politica_firmar_con_firma_empresa(date, text, text) to authenticated;
revoke execute on function fn_politica_firmar_con_firma_empresa(date, text, text) from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (531, 'la_politica_de_movilidad_se_firma_con_la_firma_del_sistema')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
-- Las tres tienen que salir en true.
select
  (select count(*) from information_schema.columns
     where table_name = 'documentos_firmados'
       and column_name in ('firmante_empresa_id', 'documento_html')) = 2
    as columnas_puestas,
  exists (select 1 from pg_constraint where conname = 'chk_documento_politica_del_sistema')
    as constraint_puesto,
  exists (select 1 from pg_proc where proname = 'fn_politica_firmar_con_firma_empresa')
    as funcion_creada;
