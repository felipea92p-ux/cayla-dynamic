-- ============================================================================
-- 0569 — La entrega arranca el plazo del art. 31 y avisa del notario
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que entregar una imputación de cargos haga las dos cosas que la ley hace
-- depender de ese momento:
--
--   1. ARRANCAR EL RELOJ. El plazo de descargo del art. 31 de la LPCL corre
--      desde la RECEPCIÓN, no desde que se redacta la carta. La 0568 guardó los
--      días concedidos (`plazo_descargo_dias`) justo para que el vencimiento se
--      calcule acá, donde se sabe cuándo la recibió.
--   2. AVISAR DEL ART. 57.8. Si la entrega se registra con el acta interna de
--      negativa a firmar, el documento queda diciéndolo en su propio
--      expediente: ese acta NO sustituye la notificación por notario, juez de
--      paz o Policía Nacional.
--
-- Y de paso, una tercera que es gratis estando dentro: el guard se vuelve
-- null-safe.
--
-- Una función reescrita UNA vez por tres razones, y no tres veces. Es la
-- función más barata de reescribir del expediente —1693 caracteres, dos
-- versiones— y aun así cada reescritura es una oportunidad de revertir algo
-- en silencio.
--
-- ── EL AGUJERO QUE CIERRA ───────────────────────────────────────────────────
--
-- Antes de la 0568, una imputación no tenía forma de recibir su
-- `descargo_vence_at`: las dos funciones que comunican cargos la rechazan
-- —«La imputación y el despido siguen el procedimiento del artículo 57»— y ese
-- procedimiento no estaba escrito en ninguna función. La 0568 puso la puerta
-- de entrada; esta pone el reloj.
--
-- Sin las dos, `fn_expediente_resolver` resolvía sobre un plazo que nunca
-- empezó, y la carta de despido se podía escribir sin que hubiera corrido un
-- solo día de defensa.
--
-- ── DE QUIÉN ES LA DECISIÓN DEL AVISO ───────────────────────────────────────
--
-- De Felipe, el 2026-10-29: «avisar, no bloquear». Se le presentó la otra
-- opción y la descartó él.
--
-- Mi recomendación había sido bloquear, y el costo de no hacerlo queda dicho
-- una vez: un aviso se aprende a ignorar, y lo que se cae por un defecto de
-- notificación es un despido por una falta real. El art. 57.8 no deja margen
-- —«Tratándose de la carta de imputación o de la carta de despido, el acta
-- interna de negativa a firmar no sustituye esta vía»— y un despido mal
-- notificado se paga como despido arbitrario aunque la falta esté probada.
--
-- Pero bloquear tenía su propio costo, y es real: la negativa a firmar ocurre
-- en una tienda, a una hora en que no hay notario abierto. Frenar ahí deja el
-- documento firmado y sin entregar, y el plazo del art. 31 sin arrancar, que
-- es peor que una entrega anotada. Se ejecuta lo decidido.
--
-- Medido antes de escribir esto: en producción hay **0** documentos de nivel
-- imputación o despido entregados con acta interna (consultado el 2026-10-30).
-- O sea que este aviso es preventivo, no correctivo: no hay ningún expediente
-- vivo al que haya que ir a anotarle nada.
--
-- ── POR QUÉ EL AVISO SE ESCRIBE EN `observacion` ────────────────────────────
--
-- Copia la forma que la 0267 ya usa para un memo firmado sin descargo previo:
-- una frase en `observacion`, con su artículo citado, SOLO cuando el defecto
-- de verdad ocurrió —un documento que no lo tiene no necesita explicar nada—.
--
-- Dos puertas distintas con el mismo defecto contando la misma historia de dos
-- maneras sería lo que la integridad conceptual prohíbe; con esto, quien abra
-- un legajo en dos años lee las dos anotaciones con la misma forma.
--
-- Y queda en el documento y no en un aviso de pantalla porque un aviso se
-- cierra y desaparece. Lo que hace falta el día que el despido se discuta es
-- que el expediente diga, con fecha, que se eligió esta vía: eso convierte un
-- descuido invisible en un hecho que alguien puede ver y corregir a tiempo.
--
-- ── QUÉ NO HACE, Y POR QUÉ ──────────────────────────────────────────────────
--
-- · NO bloquea. Decisión de Felipe, arriba.
--
-- · NO arranca el reloj de las imputaciones que NO traen plazo, y son casi
--   todas las que existen hoy. `fn_expediente_generar_tardanza` y
--   `fn_expediente_generar_falta` crean sus imputaciones por
--   `fn_expediente_crear_borrador`, que no recibe `plazo_descargo_dias`: esas
--   se entregan igual que siempre, sin reloj. Hacerlas pasar por acá
--   INVENTARÍA un plazo —¿seis días?, ¿los que decía el papel?— y el plazo
--   concedido no se adivina: se concede por escrito (art. 57.2).
--
--   Así que el art. 31 sigue sin reloj en la rama de asistencia, que es la que
--   más se usa. Es la pieza siguiente y es más cara de lo que parece, porque
--   toca los dos motores. Queda nombrada acá y en el ADR 0005 en vez de
--   resolverse a medias.
--
-- · NO toca la vía: no agrega `juez_de_paz` ni `policia` a `medio_entrega`. El
--   art. 57.8 las nombra como subsidiarias del notario, y hoy `notarial` las
--   cubre a las tres sin distinguirlas. Separarlas es una decisión de forma
--   —¿importa en el legajo cuál de las tres fue?— y no hace falta para que el
--   aviso funcione.
--
-- · NO reabre un plazo ya abierto. Si `cargos_comunicados_at` ya tiene valor,
--   se deja como está: es la misma regla que `fn_expediente_comunicar_cargos`
--   dice con sus palabras —«El plazo no se reabre»— y vale por lo mismo acá.
--
-- ── MD5 DE PARTIDA (pedido a PRODUCCIÓN el 2026-10-30) ──────────────────────
--
--   fn_expediente_entregar   1693 caracteres
--                            tal cual        75367baa1e895ff801d24aa06e3800fb
--                            sin comentarios ac7adb0d657aa807b72b94b3c7209b6d
--                            retornos \r     0
--
-- Coincide byte por byte con la 0303 de este repositorio, que es la última que
-- la define (`donde-vive.sh`: 2 versiones, 0058 y 0303). El cuerpo de abajo
-- parte de ese texto; lo que cambia va marcado «CAMBIO 0569».
--
-- La firma NO cambia, así que va con `create or replace` y no hay riesgo de
-- sobrecarga —el que la 0303 tuvo que cerrar a mano con un `drop` de la firma
-- de tres argumentos, y el que la 0568 tuvo que cerrar con el suyo.
--
-- ── ORDEN DE PEGADO, Y POR QUÉ LLEVA UN FRENO PROPIO ───────────────────────
--
-- DESPUÉS de la 0568: esta función lee `plazo_descargo_dias`, que esa columna
-- agrega.
--
-- La primera versión de este encabezado decía que pegarla antes «falla en el
-- acto, ruidoso, que es como tiene que fallar». Se midió y es FALSO: Postgres
-- no analiza el cuerpo de una función plpgsql al crearla. La migración se pega
-- sin una queja, y `r.plazo_descargo_dias` revienta la primera vez que alguien
-- ENTREGA un documento firmado — con la persona delante, con el papel en la
-- mano. Es la firma del accidente que este repositorio ya conoce: «no falló al
-- pegar la migración: falló al abrir la pantalla».
--
-- Así que el orden no se deja a la memoria de quien pega. El bloque de abajo
-- comprueba la columna y aborta la transacción entera antes de tocar nada.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
-- Volver a pegar la 0303 desde «create or replace function
-- fn_expediente_entregar» hasta su `revoke`. La firma es la misma, así que no
-- hay que borrar nada antes.
--
-- Lo que no se revierte son las anotaciones ya escritas en `observacion` de
-- los documentos entregados entre medias, ni los plazos ya calculados. Las
-- primeras son historia del legajo y no se tocan; los segundos son plazos que
-- ya corrieron para una persona de verdad.
-- ============================================================================

begin;


-- ════════════════════════════════════════════════════════════════════════════
-- 0 · El orden de pegado, comprobado y no recordado
-- ════════════════════════════════════════════════════════════════════════════
-- Sin esto, pegar la 0569 antes de la 0568 «funciona» y deja una bomba en la
-- entrega. Ver el encabezado: el cuerpo de una función plpgsql no se analiza
-- al crearla.
do $mig$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name   = 'expediente_disciplinario'
       and column_name  = 'plazo_descargo_dias'
  ) then
    raise exception
      'Falta la columna expediente_disciplinario.plazo_descargo_dias, que agrega la migración 0568. '
      'Pega la 0568 primero: esta función la lee al entregar, y si no está, la entrega de un '
      'documento firmado reventaría con la persona delante.';
  end if;
end $mig$;


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · La entrega, con el reloj y el aviso
-- ════════════════════════════════════════════════════════════════════════════
create or replace function fn_expediente_entregar(
  p_id uuid,
  p_medio text,
  p_fecha timestamptz default now(),
  p_testigo_nombre text default null,
  p_testigo_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  r expediente_disciplinario%rowtype;
  -- CAMBIO 0569 · Lo que se calcula una vez acá y se usa en el update.
  v_vence timestamptz;
  v_aviso text;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'firmado' then
    raise exception 'Solo se entrega un documento firmado (estado actual: %).', r.estado;
  end if;
  -- CAMBIO 0569 · `is not true` y no `not (…)`. Hoy esta función devuelve
  -- false y nunca null, así que el cambio no altera ningún caso; la forma es
  -- obligatoria de todas formas (CLAUDE.md) porque cualquier condición que
  -- compare un UUID contra `fn_persona_actual_id()` vuelve a producir null por
  -- su cuenta, y un null no debe pasar como autorizado.
  if fn_expediente_puede_actuar(r.persona_id, r.nivel) is not true then
    raise exception 'Sin permiso.';
  end if;
  if p_medio not in ('fisico','correo','notarial','acta_negativa') then
    raise exception 'Medio de entrega inválido.';
  end if;
  if r.nivel in ('imputacion','despido') and p_medio = 'correo' then
    raise exception 'Nivel 4 (imputación/despido) no admite entrega por correo: usa físico o notarial.';
  end if;

  -- NUMERAL 55.4: «acta de negativa suscrita por quien entrega y por un
  -- testigo». Sin el testigo no hay acta, y sin acta no hay entrega — así que
  -- se para acá en vez de dejar el documento a medias.
  if p_medio = 'acta_negativa' and coalesce(btrim(p_testigo_nombre), '') = '' then
    raise exception
      'El acta de negativa la suscriben quien entrega y un testigo (numeral 55.4 del RIT). '
      'Escribe el nombre de quien atestigua la negativa.';
  end if;

  -- CAMBIO 0569 · EL RELOJ DEL ART. 31.
  --
  -- Solo para una imputación que trae su plazo concedido por escrito. Días
  -- NATURALES: `fn_sumar_dias_habiles` sirve al art. 55.2 y no a este.
  --
  -- `cargos_comunicados_at` se fija a la fecha de ENTREGA y no a now(): una
  -- entrega se puede registrar días después de ocurrida, y el plazo corrió
  -- desde que ella recibió la carta, no desde que alguien lo anotó.
  if r.nivel = 'imputacion'
     and r.plazo_descargo_dias is not null
     and r.cargos_comunicados_at is null then
    v_vence := p_fecha + (r.plazo_descargo_dias || ' days')::interval;
  end if;

  -- CAMBIO 0569 · EL AVISO DEL ART. 57.8, escrito en el propio expediente.
  if r.nivel in ('imputacion','despido') and p_medio = 'acta_negativa' then
    v_aviso :=
      'Entregada el ' || to_char(p_fecha at time zone 'America/Lima', 'DD/MM/YYYY HH24:MI') ||
      ' con ACTA INTERNA de negativa a firmar. El art. 57.8 del RIT advierte que, '
      'tratándose de la carta de imputación o de la carta de despido, el acta interna '
      'no sustituye la notificación por intermedio de notario, de juez de paz o, a falta '
      'de ambos, de la Policía Nacional del Perú. Mientras no conste esa notificación, '
      'la entrega queda con un defecto que puede discutirse.';
  end if;

  update expediente_disciplinario
    set estado                 = 'entregado',
        medio_entrega          = p_medio,
        entregado_at           = p_fecha,
        entregado_por          = fn_persona_actual_id(),
        entrega_testigo_nombre = case when p_medio = 'acta_negativa'
                                      then btrim(p_testigo_nombre) end,
        entrega_testigo_id     = case when p_medio = 'acta_negativa' then p_testigo_id end,
        -- CAMBIO 0569 · Las dos fechas van juntas o ninguna: lo exige
        -- `chk_descargo_coherente`, y tiene razón. `v_vence` es null cuando no
        -- hay reloj que arrancar, y entonces las dos columnas se quedan como
        -- estaban.
        cargos_comunicados_at  = case when v_vence is not null then p_fecha
                                      else cargos_comunicados_at end,
        descargo_vence_at      = coalesce(v_vence, descargo_vence_at),
        observacion            = case when v_aviso is not null
                                      then coalesce(observacion || E'\n', '') || v_aviso
                                      else observacion end
    where id = p_id;
end;
$$;

comment on function fn_expediente_entregar(uuid, text, timestamptz, text, uuid) is
  'Entrega un documento disciplinario firmado. En una imputación que trae plazo concedido, la entrega arranca el plazo de descargo del art. 31 de la LPCL en días naturales. Si la entrega es con acta interna de negativa a firmar y el documento es de nivel imputación o despido, queda anotado en su expediente que el art. 57.8 exige además notario, juez de paz o PNP.';

grant  execute on function fn_expediente_entregar(uuid, text, timestamptz, text, uuid) to authenticated;
revoke execute on function fn_expediente_entregar(uuid, text, timestamptz, text, uuid) from public, anon;


insert into migraciones_aplicadas (numero, nombre) values (569, 'la_entrega_arranca_el_plazo_y_avisa_del_notario')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

commit;


-- ════════════════════════════════════════════════════════════════════════════
-- COMPROBAR DESPUÉS DE PEGAR (en el SQL Editor)
-- ════════════════════════════════════════════════════════════════════════════
-- select
--   (select length(prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public' and p.proname = 'fn_expediente_entregar')        as largo_de_entregar,
--   (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public' and p.proname = 'fn_expediente_entregar')        as versiones,
--   (select position('CAMBIO 0569' in prosrc) > 0 from pg_proc p
--      join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public' and p.proname = 'fn_expediente_entregar')        as trae_los_cambios,
--   (select count(*) from expediente_disciplinario
--     where nivel in ('imputacion','despido') and medio_entrega = 'acta_negativa'
--       and observacion ilike '%57.8%')                                          as avisados,
--   (select numero || ':' || nombre from migraciones_aplicadas where numero = 569) as registro;
--
-- Se espera: 1 versión, `trae_los_cambios` = true, y
-- «569:la_entrega_arranca_el_plazo_y_avisa_del_notario».
--
-- `versiones` = 1 es la que importa: la firma no cambió, así que un 2 solo
-- puede significar que alguien dejó viva otra sobrecarga.
--
-- Y la línea PLANILLA de `que_falta_pegar.sql`, como siempre después de pegar
-- algo que reescribe una función.
