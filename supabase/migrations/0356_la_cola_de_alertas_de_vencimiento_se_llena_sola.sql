-- ============================================================================
-- 0356_la_cola_de_alertas_de_vencimiento_se_llena_sola.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que los contratos por vencer —hoy de consulta, solo se miran si alguien
--   abre el Dashboard— generen una fila en `alertas` la primera vez que un
--   vencimiento entra en su ventana, para cada admin/líder de DO activo con
--   correo.
--
--   Las vacaciones por vencer se quedan FUERA de esta migración, a
--   propósito — ver la sección de abajo.
--
-- QUÉ NO PROMETE, Y ES A PROPÓSITO
--   No manda ningún correo. Esta migración solo LLENA la cola; `alertas`
--   existe desde la 0001 con `canal` y `estado`, pero nunca hubo código que
--   la vaciara — 0 líneas de envío de push o email en todo el repositorio.
--   Escribir el despachador real necesita una decisión que no es mía: elegir
--   proveedor de correo, crear la cuenta, y poner la API key en Vercel. Esta
--   migración deja listo el lado que sí se puede construir y probar hoy sin
--   depender de nadie — y que el despachador, cuando exista, va a necesitar
--   de todos modos.
--
--   Tampoco toca el canal 'push': `push_tokens.expo_push_token` se diseñó
--   para una app móvil (Expo) que no existe en este repositorio. Generar
--   alertas con canal='push' hoy sería llenar una cola para un cartero que
--   no existe. Todo lo de acá usa canal='email'.
--
-- ── POR QUÉ LAS VACACIONES SE QUEDAN AFUERA, Y NO ES UN OLVIDO ──────────────
--
-- `fn_contratos_por_vencer` y `fn_vacaciones_por_vencer` filtran ambas por
-- `fn_es_admin_o_lider() is true` — correcto para una pantalla, pero
-- pg_cron llama sin ninguna sesión: `auth.uid()` es null, y esa condición
-- es siempre falsa. Sin sesión, las dos devolverían cero filas siempre, en
-- silencio — el mismo tipo de fallo silencioso que esta casa ya sufrió antes.
--
-- Para contratos el arreglo es seguro: el filtro de sesión es una línea del
-- `WHERE`, sin cálculo detrás, así que esta migración reescribe la misma
-- consulta sin esa línea — no hay lógica de negocio que duplicar.
--
-- Para vacaciones NO es seguro hacer lo mismo. `fn_vacaciones_por_vencer`
-- delega en `fn_vacaciones_saldo`, que sí tiene cálculo real de devengo
-- detrás de su propia guardia (`raise exception 'No puedes ver el saldo de
-- vacaciones de otra persona.'`). Copiarlo aquí sería la regla 2 de
-- `packages/shared` con otro nombre: dos lugares respondiendo la misma
-- pregunta, uno de los cuales quedará desactualizado el día que el cálculo
-- cambie. El arreglo correcto es separar, dentro de `fn_vacaciones_saldo`,
-- el cálculo (reusable) de la guardia de permiso (para quien pregunta desde
-- una pantalla) — y eso es tocar una función existente de la que ya
-- dependen varias pantallas, no agregar algo nuevo al lado. Queda pendiente
-- de una decisión explícita, no de esta migración.
--
-- ── POR QUÉ "UNA VEZ POR HECHO", Y NO UNA POR DÍA ───────────────────────────
--
-- `fn_vacaciones_por_vencer(60, null)` va a seguir devolviendo el mismo
-- récord cada día durante dos meses mientras se acerca su vencimiento. Sin
-- freno, esto llenaría `alertas` con la misma fila 60 veces. La deduplicación
-- usa `persona_id || fecha límite` como identidad del HECHO (no cambia día a
-- día, solo cambian los "días que faltan"): una vez que existe una fila para
-- ese hecho, no se genera otra. Es la lectura simple para una primera
-- versión — si hace falta un segundo recordatorio más cerca del límite
-- (el patrón de dos tonos que ya usa Incidencias para las 48 h), es un
-- cambio contenido a esta única función, no un rediseño.
--
-- ── POR QUÉ SOLO ADMIN/LÍDER DO, Y NO TAMBIÉN LA ENCARGADA DE SEDE ──────────
--
-- La encargada YA ve esto en vivo al entrar a Ausencias — mandarle además un
-- correo sería el mismo aviso en dos sitios, que esta casa ya decidió que
-- deja de ser aviso (mismo criterio que el contador de `nav.tsx`). DO es
-- quien no tiene una pantalla que abra todos los días.
--
-- ── POR QUÉ UN CRON DIARIO, NO CADA 15 MINUTOS COMO EL AUTO-CIERRE ──────────
--
-- Un vencimiento se mide en días, no en minutos: correr esto cada 15 minutos
-- no encontraría nada nuevo 95 de cada 96 veces. 08:00 hora de Lima
-- (13:00 UTC) es una hora en la que DO ya está mirando el correo.
--
-- ── CÓMO SE REVIERTE ─────────────────────────────────────────────────────────
--   select cron.unschedule('generar-alertas-vencimiento');
--   drop function if exists fn_generar_alertas_vencimiento();
--   alter table alertas drop constraint alertas_tipo_check;
--   alter table alertas add constraint alertas_tipo_check
--     check (tipo = any (array['olvido_salida','tardanza','salida_no_retornada','auto_cierre','digest_diario']));
--   Revertir significa volver a que nadie sepa de un vencimiento salvo quien
--   entre a mirar la pantalla correcta ese día.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Va la última porque el SQL Editor solo muestra el
--   resultado de la última.
-- ============================================================================

-- ── 1 · `alertas` aprende dos tipos nuevos ──────────────────────────────────
alter table alertas drop constraint alertas_tipo_check;
alter table alertas add constraint alertas_tipo_check check (
  tipo = any (array[
    'olvido_salida', 'tardanza', 'salida_no_retornada', 'auto_cierre', 'digest_diario',
    'vacaciones_por_vencer', 'contrato_por_vencer'
  ])
);

-- ── 2 · Generar — sin guard de permiso, a propósito ─────────────────────────
-- Mismo criterio que `fn_auto_cierre` (0007): la ejecuta pg_cron como dueño
-- de la base, nunca una sesión de `authenticated` — por eso no hay
-- `fn_es_admin_o_lider()` ni `grant execute` más abajo.
create or replace function fn_generar_alertas_vencimiento()
returns int
language plpgsql security definer set search_path = public
as $fn$
declare
  v_generadas int := 0;
begin
  -- Misma consulta que `fn_contratos_por_vencer` (0144), sin el
  -- `fn_es_admin_o_lider() is true` de su WHERE: acá no hay sesión que
  -- filtrar, y esta función ya es SECURITY DEFINER — el propio cron es la
  -- autorización, igual que `fn_auto_cierre` (0007) nunca pide permiso.
  insert into alertas (persona_id, tipo, canal, payload)
  select do_.id, 'contrato_por_vencer', 'email',
    jsonb_build_object(
      'evento', p.id::text || '|' || p.fecha_fin_contrato::text,
      'persona_id', p.id,
      'persona', p.nombres || ' ' || p.apellidos,
      'sede', coalesce(s.codigo, '—'),
      'fecha_fin_contrato', p.fecha_fin_contrato,
      'dias_restantes', (p.fecha_fin_contrato - fn_hoy_lima())::int
    )
  from personas p
  left join sedes s on s.id = p.sede_base_id
  cross join (
    select id from personas where rol in ('admin', 'lider_do') and estado = 'activo' and email is not null
  ) do_
  where p.estado = 'activo'
    and p.fecha_fin_contrato is not null
    -- Ya vencido no es "por vencer": ese caso ya se ve directo en el
    -- Dashboard, y alertarlo por este camino confundiría "avisar antes" con
    -- "avisar tarde".
    and p.fecha_fin_contrato >= fn_hoy_lima()
    and p.fecha_fin_contrato <= fn_hoy_lima() + 30
    and not exists (
      select 1 from alertas a
      where a.tipo = 'contrato_por_vencer'
        and a.payload ->> 'evento' = p.id::text || '|' || p.fecha_fin_contrato::text
    );
  get diagnostics v_generadas = row_count;

  return v_generadas;
end;
$fn$;

-- ── 3 · El cron ──────────────────────────────────────────────────────────
select cron.schedule('generar-alertas-vencimiento', '0 13 * * *', $$select fn_generar_alertas_vencimiento()$$);

insert into migraciones_aplicadas (numero, nombre)
values (356, 'la_cola_de_alertas_de_vencimiento_se_llena_sola')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_generar_alertas_vencimiento') as fn_creada,
  (select count(*) from cron.job where jobname = 'generar-alertas-vencimiento') as cron_programado,
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'alertas_tipo_check') as constraint_nuevo;
