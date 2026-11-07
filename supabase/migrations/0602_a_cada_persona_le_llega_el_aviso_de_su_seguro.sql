-- ============================================================================
-- 0602 — A cada persona le llega el aviso de que su seguro ya está en Mi seguro
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que quien tiene una póliza nueva, o un PDF nuevo en una póliza suya, lo vea en
--   la Bandeja de su Info sin tener que entrar a «Mi seguro» a mirar. Pedido de
--   Felipe, 2026-11-06: «que se les pueda notificar y ellos también lo puedan
--   visualizar». Antes solo aparecía si la persona abría esa sección.
--
--   Son tres piezas chicas:
--     1. `fn_mis_polizas_avisos()`: de cada póliza SUYA, cuándo se registró y cuál es
--        su último archivo visible. Es lo único que le faltaba a la Bandeja.
--     2. `bandeja_vistos` acepta el tipo nuevo `poliza_mia`.
--     3. `fn_bandeja_marcar_visto` lo reconoce.
--
-- QUÉ ASUME
--
--   · Están pegadas la 0530 (`fn_mis_polizas`) y la 0587 (la versión vigente de
--     `fn_bandeja_marcar_visto`). Lo comprueba la guardia de abajo.
--   · md5 de partida de `fn_bandeja_marcar_visto`, pedido a PRODUCCIÓN el 2026-11-06:
--     444daa53487f048a5244c18e613299d4 (1001 caracteres, sin retornos de Windows).
--
-- POR QUÉ SE ELIGIÓ ASÍ
--
--   DECIDÍ:    Un aviso DERIVADO: la Bandeja lo calcula de las pólizas vivas de esa
--              persona. Nada se envía ni se guarda al registrar.
--   DESCARTÉ:  Un disparador, o escribir un aviso dentro de `fn_seguro_registrar`.
--              Los dos dejarían una fila que sale antes de que exista el PDF, que
--              sobrevive a una anulación y que obliga a deduplicar registro y archivo.
--              Derivado, una póliza anulada deja de avisar sola, y registrar y subir
--              el PDF en la misma sesión es un solo aviso.
--   DESCARTÉ:  Ampliar `fn_mis_polizas`. Devuelve `TABLE`, así que exigía `drop` +
--              `create` de la función que sostiene «Mi seguro», para dos columnas que
--              esa pantalla no usa.
--   DESCARTÉ:  Enseñarle a DO quién lo vio. `bandeja_vistos` no es una auditoría (0436):
--              abrir la Bandeja no prueba que alguien leyó algo.
--   SE ROMPE SI: alguien agrega un tipo de archivo visible para la persona y no lo suma
--              aquí. La lista es la misma de `fn_mis_polizas` y `fn_seguro_archivo_es_mio`.
--
-- QUÉ NO HACE
--
--   · No manda correo: el aviso vive en la Bandeja.
--   · No dice «estás cubierta»: la persona no ve la prima, y la Bandeja habla de la póliza.
--   · No toca planilla, pago ni el tablero de DO.
--
-- SE REVIERTE
--
--   drop function fn_mis_polizas_avisos();
--   y restaurar `fn_bandeja_marcar_visto` y el check desde la 0587, borrando antes
--   `delete from bandeja_vistos where tipo_item = 'poliza_mia';`.
-- ============================================================================

do $guardia$
declare
  v_md5 text;
begin
  if to_regprocedure('fn_mis_polizas()') is null then
    raise exception 'Falta la 0530: no existe fn_mis_polizas.';
  end if;

  select md5(p.prosrc) into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_bandeja_marcar_visto';

  -- Repegar es seguro: la segunda vez la función ya lleva este cambio.
  if v_md5 is distinct from '444daa53487f048a5244c18e613299d4'
     and not exists (select 1 from pg_proc where proname = 'fn_bandeja_marcar_visto' and prosrc like '%CAMBIO 0602%') then
    raise exception 'fn_bandeja_marcar_visto no es la versión de partida (md5 %). Corre ./scripts/donde-vive.sh fn_bandeja_marcar_visto antes de seguir.', v_md5;
  end if;
end
$guardia$;

-- ── 1 · Lo que la Bandeja necesita de sus pólizas ────────────────────────────
-- Solo lo suyo (`fn_persona_actual_id`), sin nada interno: ni prima ni nombre de
-- archivo. `id desc` como ancla, para que dos archivos subidos a la vez no empaten.

create or replace function fn_mis_polizas_avisos()
returns table (
  poliza_id         uuid,
  producto_nombre   text,
  creada_at         timestamptz,
  archivo_id        uuid,
  archivo_subido_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_yo uuid := fn_persona_actual_id();
begin
  if v_yo is null then
    return;
  end if;
  -- La cuenta de servicio no es una persona (el mismo cuidado de `fn_mis_polizas`).
  if (select p.cuenta_de_servicio from personas p where p.id = v_yo) is not false then
    return;
  end if;

  return query
  select z.id, t.nombre, z.creada_at, a.id, a.subido_at
    from polizas_seguro z
    join seguros_tipos t on t.clave = z.producto
    left join lateral (
      select x.id, x.subido_at
        from polizas_seguro_archivos x
       where x.poliza_id = z.id
         and x.tipo in ('poliza', 'convenio_pago')
         and x.retirado_at is null
       order by x.subido_at desc, x.id desc
       limit 1
    ) a on true
   where z.persona_id = v_yo
     and z.anulada_at is null
   order by z.creada_at desc, z.id desc;
end;
$fn$;

revoke all on function fn_mis_polizas_avisos() from public, anon;
grant execute on function fn_mis_polizas_avisos() to authenticated;

-- ── 2 · La Bandeja aprende 'poliza_mia' ──────────────────────────────────────
-- Copiada de la 0587 (la vigente). Único cambio: el tipo nuevo.

alter table bandeja_vistos drop constraint if exists bandeja_vistos_tipo_item_check;
alter table bandeja_vistos add constraint bandeja_vistos_tipo_item_check check (tipo_item in (
  'revision', 'revision_movilidad', 'revision_contrato',
  'solicitud_vacacion', 'solicitud_perfil',
  'entrega_educacion', 'aviso_fin_educacion',
  'solicitud_educacion',
  'cambio_turno',
  'conducta_registrada', 'caso_traspasado',
  'pedido_turno',
  -- ⇩ CAMBIO 0602 ⇩
  'poliza_mia'
));

create or replace function fn_bandeja_marcar_visto(p_tipo_item text, p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_persona uuid := fn_persona_actual_id();
begin
  if v_persona is null then
    raise exception 'Tu cuenta no está enlazada con tu ficha.';
  end if;
  -- ⇩ CAMBIO 0473 ⇩ cambio_turno.
  if p_tipo_item not in ('revision', 'revision_movilidad', 'revision_contrato',
                          'solicitud_vacacion', 'solicitud_perfil',
                          'entrega_educacion', 'aviso_fin_educacion',
                          'solicitud_educacion', 'cambio_turno',
                          -- CAMBIO 0515 · avisos de conducta
                          'conducta_registrada', 'caso_traspasado',
                          -- CAMBIO 0587 · «Este día no me calza»
                          'pedido_turno',
                          -- CAMBIO 0602 · su póliza o su PDF
                          'poliza_mia') then
    raise exception 'Tipo de ítem de Bandeja no reconocido: %', p_tipo_item;
  end if;

  insert into bandeja_vistos (persona_id, tipo_item, item_id)
  values (v_persona, p_tipo_item, p_item_id)
  on conflict (persona_id, tipo_item, item_id) do update set visto_at = now();
end;
$function$;

-- ── 3 · Registro ─────────────────────────────────────────────────────────────

insert into migraciones_aplicadas (numero, nombre) values (602, 'a_cada_persona_le_llega_el_aviso_de_su_seguro')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

select
  to_regprocedure('fn_mis_polizas_avisos()') is not null                                  as la_lectura_existe,
  has_function_privilege('authenticated', 'fn_mis_polizas_avisos()', 'execute')            as la_persona_la_llama,
  not has_function_privilege('anon', 'fn_mis_polizas_avisos()', 'execute')                 as sin_sesion_no,
  (select pg_get_constraintdef(oid) like '%poliza_mia%' from pg_constraint
    where conname = 'bandeja_vistos_tipo_item_check')                                      as la_bandeja_lo_acepta,
  (select prosrc like '%CAMBIO 0602%' from pg_proc where proname = 'fn_bandeja_marcar_visto') as la_funcion_lo_acepta,
  (select nombre from migraciones_aplicadas where numero = 602)                            as registro;
