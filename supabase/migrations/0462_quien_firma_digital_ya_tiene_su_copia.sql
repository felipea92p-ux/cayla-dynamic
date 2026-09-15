-- ============================================================================
-- 0462 · Quien firma digital ya tiene su copia
-- ============================================================================
-- QUÉ PROMETE
--
--   Que confirmar la firma en /mio/contrato («Confirmar mi firma aquí») deje
--   registrada al mismo tiempo la entrega de la copia del contrato
--   (`copia_entregada_at`), igual que ya deja fechada la firma
--   (`fecha_firma`, 0430). El acceso permanente al documento firmado que la
--   persona ve en /mio/contrato ES su copia — no hay una copia distinta que
--   alguien deba imprimirle o escanearle aparte.
--
--   Reportado por Felipe el 2026-09-15, revisando el Dashboard rediseñado:
--   Pamela Burgos, Daniel Ruiz, Fernanda Espinoza, Benjamin Cueva y otras
--   personas que ya habían firmado su contrato desde el sistema seguían
--   apareciendo en la Bandeja con «Falta entregar la copia del contrato» y
--   plazo vencido — un trámite que, para quien firmó digital, nunca puede
--   completarse solo, porque nada lo marca. Decidido con Felipe por
--   AskUserQuestion: el criterio que ya usó la 0430 para aceptar la firma
--   100% digital (el medio —papel o pantalla— no cambia la validez del acto)
--   se extiende acá a la entrega de copia (art. 83, D.S. 001-96-TR, citado en
--   `docs/reglamento-interno-de-trabajo.md` 8.3).
--
-- QUÉ NO HACE, Y ES DELIBERADO
--
--   NO toca el camino del escaneo. Cuando Desarrollo Organizacional sube un
--   escaneo (`fn_contrato_registrar` con `p_id` + `p_storage_path`), la
--   entrega de la copia física SIGUE siendo un trámite manual aparte
--   (`fn_contrato_marcar_tramite('copia', …)`), exactamente como hoy — ahí sí
--   existe un papel físico que de verdad hay que entregar, y nada en este
--   repositorio sabe si eso ya ocurrió salvo que alguien lo anote. La 0430 ya
--   distinguía las dos vías para `fecha_firma`; esta migración distingue las
--   mismas dos vías para `copia_entregada_at`, por el mismo motivo.
--
--   NO toca `comunicado_mtpe_at`. La comunicación del contrato a la Autoridad
--   Administrativa de Trabajo (art. 73 LPCL) es un trámite ante el Estado,
--   ajeno a si la persona firmó en papel o en pantalla — sigue pendiente y
--   sigue exigiendo una acción real de Desarrollo Organizacional para
--   cualquier contrato a plazo fijo, firmado como sea.
--
--   NO cambia ninguna pantalla de TypeScript. `fn_contratos_tablero` (0386) y
--   `textoContrato`/`urgenciaContrato` de la Bandeja (2026-09-15) ya leen
--   `copia_entregada_at` sin condicionar por el origen de la firma — arreglar
--   el dato en el origen basta para que el síntoma (Bandeja, Contratos,
--   Dashboard) desaparezca solo, sin tocar ninguna de esas tres pantallas.
--
-- QUÉ ASUME
--
--   `fn_confirmar_mi_firma_contrato` vigente es la 0430 (un parámetro,
--   `p_contrato_id`) — confirmado con `./scripts/donde-vive.sh` el
--   2026-09-15. El cuerpo de abajo es el de la 0430 íntegro, con una sola
--   línea nueva marcada CAMBIO 0462 dentro del mismo `update` que ya fecha el
--   contrato — nunca se sobrescribe una `copia_entregada_at` que ya exista,
--   con el mismo `coalesce` que la 0430 ya usa para `fecha_firma` y
--   `registrado_por`.
--
--   MD5 DE PARTIDA — SE PIDE A PRODUCCIÓN ANTES DE PEGAR, no antes de
--   escribir (regla de la casa: el árbol se mueve entre que se pregunta y se
--   pega). Correr contra el SQL Editor:
--
--     select md5(prosrc) from pg_proc
--      where proname = 'fn_confirmar_mi_firma_contrato' and pronargs = 1;
--
--   Tiene que coincidir con el md5 de esta Mac contra el Postgres local en el
--   momento de pegar (`./scripts/donde-vive.sh fn_confirmar_mi_firma_contrato`
--   lo imprime). Si no coincide, PARA: alguien fusionó otra versión de esta
--   función entre que se escribió esta migración y que se pega.
--
-- POR QUÉ EL BACKFILL VA CON UN AUTOR SEMBRADO, IGUAL QUE LA 0430
--
--   El backfill de abajo llama a `fn_contrato_marcar_tramite`, que exige
--   `fn_es_admin_o_lider()` — y en el SQL Editor no hay sesión
--   (`fn_persona_actual_id()` es null). Mismo problema y misma solución que
--   la parte F de la 0430: se siembra la sesión con el admin activo más
--   antiguo (criterio de la 0176), transaction-local
--   (`set_config(…, true)`), y si no hay ningún admin activo con usuario la
--   migración se detiene sin tocar nada en vez de escribir sin poder decir
--   quién lo hizo.
--
-- CÓMO SE REVIERTE
--
--   -- recrear fn_confirmar_mi_firma_contrato con el cuerpo de la 0430;
--   El backfill no se puede deshacer con exactitud (no queda registro de qué
--   filas cambió esta migración en particular), pero revertir el código deja
--   de PONER esa fecha para las firmas nuevas — no hace falta borrar las que
--   ya se escribieron para que el revert sea seguro, igual que en la 0430.
-- ============================================================================


-- ── A · fn_confirmar_mi_firma_contrato: confirmar también entrega la copia ──
-- Cuerpo vigente: 0430, copiado literal salvo lo marcado CAMBIO 0462. Misma
-- firma (un parámetro): `create or replace` basta.
create or replace function fn_confirmar_mi_firma_contrato(p_contrato_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_yo            uuid;
  v_imagen        text;
  v_dueno         uuid;
  v_anulado       timestamptz;
  v_fecha_previa  date;
  v_tipo          text;
  v_nota          text := '';
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  select persona_id, anulado_at, fecha_firma, tipo
    into v_dueno, v_anulado, v_fecha_previa, v_tipo
    from contratos_generados where id = p_contrato_id;
  if v_dueno is null then raise exception 'No se encontró ese contrato.'; end if;
  if v_dueno <> v_yo then raise exception 'Ese contrato no es tuyo.'; end if;
  if v_anulado is not null then raise exception 'Ese contrato está anulado.'; end if;

  select imagen into v_imagen from firmas_escaneadas where persona_id = v_yo;
  if v_imagen is null then
    raise exception 'Todavía no configuraste tu firma. Ve a Mi perfil → Firma antes de confirmar.';
  end if;

  -- La constancia primero (0406): reconfirmar con otra firma no debe borrar
  -- de qué imagen era ni de qué día la anterior.
  insert into confirmaciones_firma_contrato (contrato_id, persona_id, imagen)
  values (p_contrato_id, v_yo, v_imagen);

  -- La primera confirmación digital fecha el contrato (0430) Y entrega su
  -- copia (0462): quien firma en pantalla ve ahí mismo, para siempre, el
  -- documento que firmó — no hay una copia distinta que darle aparte. Los dos
  -- `coalesce` protegen un valor que ya exista (de una confirmación anterior,
  -- o —para fecha_firma/registrado_por— de un escaneo que subió DO):
  -- reconfirmar sigue sirviendo solo para corregir la IMAGEN de la firma,
  -- nunca para mover estas fechas.
  update contratos_generados
     set firma_persona = v_imagen,
         firma_persona_confirmada_at = now(),
         fecha_firma = coalesce(fecha_firma, fn_hoy_lima()),
         registrado_por = coalesce(registrado_por, v_yo),
         copia_entregada_at = coalesce(copia_entregada_at, fn_hoy_lima())  -- ⇦ CAMBIO 0462
   where id = p_contrato_id;

  -- Solo la PRIMERA vez (v_fecha_previa era null): recalcular hasta cuándo
  -- vale el vencimiento de esta persona (0287/0312/0333/0347) y dejar
  -- constancia en su historial. Sin cambios desde la 0430.
  if v_fecha_previa is null then
    if v_tipo in ('nuevo', 'renovacion', 'adendum', 'convenio_practicas', 'indefinido') then
      v_nota := fn_contrato_refrescar_vencimiento(v_yo, 'Contrato firmado — autoservicio digital');
    end if;

    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (v_yo, 'contrato_firmado', null,
       v_tipo || ' · firmado digitalmente el ' || fn_hoy_lima()::text, v_yo,
       'Firma digital confirmada en /mio/contrato, sin escaneo' || v_nota);

    -- ⇩⇩⇩ CAMBIO 0462 ⇩⇩⇩ Constancia aparte para la entrega de copia, con el
    -- mismo `campo_modificado` que ya usa el trámite manual
    -- (`fn_contrato_marcar_tramite`, 0287) — así el historial de la persona
    -- lee «se entregó la copia» igual sin importar por cuál de las dos vías.
    insert into correcciones_auditoria
      (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values
      (v_yo, 'contrato_copia_entregada', null, fn_hoy_lima()::text, v_yo,
       'Entrega de copia del contrato — acceso digital permanente en /mio/contrato, sin trámite físico aparte');
  end if;
end;
$$;
-- Sin GRANT nuevo: la firma no cambió, y ya estaba concedida a `authenticated`
-- desde la 0402/0406/0430.


-- ── B · Backfill: quien ya firmó digital antes de esta migración también ───
--        cuenta con su copia entregada ─────────────────────────────────────
-- Sin esto, Pamela Burgos, Daniel Ruiz, Fernanda Espinoza y cualquiera que ya
-- hubiera confirmado su firma ANTES de esta migración seguiría en
-- «tramite_pendiente» hasta volver a confirmar (cosa que la pantalla no les
-- vuelve a pedir, porque para ellas ya está firmado). Por persona, no en un
-- solo `update` masivo: cada una necesita su propia fila en
-- `correcciones_auditoria` con el mismo motivo que dejaría el camino normal.
do $$
declare
  v_fila    record;
  v_admin   uuid;
  v_auth    uuid;
  v_cuantas int;
begin
  select count(*) into v_cuantas from contratos_generados
   where storage_path is null and fecha_firma is not null and copia_entregada_at is null
     and anulado_at is null;

  if v_cuantas = 0 then
    raise notice '0462 · no hay nada que rellenar: nadie firmado digital sin copia registrada.';
    return;
  end if;

  -- Mismo problema que la parte F de la 0430, y la misma solución: el
  -- backfill necesita un autor para `correcciones_auditoria.corregido_por`
  -- (NOT NULL, FK a personas), y en el SQL Editor no hay sesión. Se siembra
  -- con el admin activo más antiguo (criterio de la 0176); si no hay ninguno
  -- con usuario, se detiene sin tocar nada.
  select p.id, p.auth_user_id into v_admin, v_auth
    from personas p
   where p.rol = 'admin' and p.estado = 'activo' and p.auth_user_id is not null
   order by p.fecha_ingreso
   limit 1;

  if v_admin is null then
    raise exception '0462 · hay % contrato(s) por rellenar pero ningun admin activo con usuario que firme el rastro. No se toca nada.', v_cuantas;
  end if;

  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  raise notice '0462 · rellenando % contrato(s); el rastro queda a nombre del admin activo mas antiguo.', v_cuantas;

  for v_fila in
    select c.id, c.persona_id, c.fecha_firma
      from contratos_generados c
     where c.storage_path is null and c.fecha_firma is not null and c.copia_entregada_at is null
       and c.anulado_at is null
  loop
    update contratos_generados
       set copia_entregada_at = v_fila.fecha_firma
     where id = v_fila.id
       and storage_path is null and fecha_firma is not null and copia_entregada_at is null;

    if found then
      insert into correcciones_auditoria
        (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
      values
        (v_fila.persona_id, 'contrato_copia_entregada', null, v_fila.fecha_firma::text, v_admin,
         'Backfill de la migracion 0462: la firma digital confirmada antes de esta migracion tambien cuenta como entrega de copia. Lo ejecuta la migracion, no el admin que figura como autor — el rastro exige un autor y se toma el admin activo mas antiguo.');
    end if;
  end loop;
end $$;


insert into migraciones_aplicadas (numero, nombre)
values (462, 'quien_firma_digital_ya_tiene_su_copia')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select prosrc like '%CAMBIO 0462%' from pg_proc
    where proname = 'fn_confirmar_mi_firma_contrato' and pronargs = 1)
    as confirmar_al_dia,
  (select count(*) from contratos_generados
    where storage_path is null and fecha_firma is not null and copia_entregada_at is null
      and anulado_at is null) = 0
    as backfill_completo;
