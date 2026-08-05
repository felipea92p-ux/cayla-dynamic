-- ============================================================================
-- 0147 — Quién firma por CAYLA deja de estar escrito en una pantalla
-- ============================================================================
--
-- QUÉ PROMETE
--   El sistema sabe, en un solo lugar, qué PERSONA firma los documentos que
--   emite CAYLA. Las pantallas leen de ahí el nombre que imprimen y deciden con
--   eso si estampan la firma escaneada.
--
-- QUÉ ASUME
--   · Quien firma es siempre alguien con ficha en `personas`, activa, y con rol
--     admin o lider_do. Un trigger lo obliga; no es una convención.
--   · Las personas no se borran, se marcan inactivas. Por eso el trigger mira
--     `estado` y no la existencia de la fila.
--
-- POR QUÉ ASÍ, Y NO DE OTRA FORMA
--   Hasta hoy el nombre impreso —«Alvarez Pereyra Felipe Miguel»— era un texto
--   fijo dentro de cuatro pantallas distintas, y la rúbrica que se estampaba era
--   la de quien tuviera la sesión abierta. Dos cosas independientes: nada obligaba
--   a que fueran la misma persona. Con cuatro cuentas admin, bastaba que otra
--   imprimiera para que saliera SU firma bajo el nombre de Felipe — un documento
--   que afirma haber sido firmado por quien no lo firmó, en papeles cuya única
--   razón de ser es sostener conceptos no remunerativos ante una inspección.
--
--   Al guardar la PERSONA y no su nombre, las dos cosas salen de la misma fila:
--   la pantalla imprime el nombre de esa ficha y compara identificadores, no
--   textos. El estado malo deja de ser representable — no hay validación que
--   alguien pueda olvidar. Antes se comparaba por nombre y una tilde de
--   diferencia apagaba el estampado sin avisar.
--
--   VA EN `configuracion` Y NO EN UNA TABLA NUEVA. Es una sola fila que cambia
--   cada varios años. Y el histórico —qué persona firmó QUÉ documento— ya está
--   resuelto donde tiene que estar: `expediente_disciplinario.firmante_id` lo
--   guarda por expediente desde la 0071. Una tabla versionada acá sería un
--   histórico duplicado que nadie consultaría.
--
-- CÓMO SE CAMBIA EL FIRMANTE
--   Una sola sentencia en el SQL Editor. El trigger rechaza a quien no puede
--   firmar, así que no hay forma de dejarlo apuntando a alguien inválido:
--
--     update configuracion
--        set valor = jsonb_build_object(
--              'persona_id', (select id from personas
--                              where nombres ilike '%NOMBRE%' and estado = 'activo'),
--              'cargo', 'Gerencia General')
--      where clave = 'firmante_empresa';
--
-- CÓMO SE REVIERTE
--   delete from configuracion where clave = 'firmante_empresa';
--   drop trigger if exists trg_valida_firmante_empresa on configuracion;
--   drop function if exists fn_valida_firmante_empresa();
--   Las pantallas vuelven solas al texto fijo: si la fila no existe, imprimen
--   como imprimían antes y dejan la raya en blanco.
-- ============================================================================

-- ── 1 · El estado imposible, cerrado en la base ─────────────────────────────
-- Sin esto, `configuracion` acepta cualquier jsonb: un persona_id inventado, el
-- de alguien que ya cesó, o el de una cuenta sin permiso para firmar. Las tres
-- producen el mismo daño —un documento con el nombre de quien no corresponde—
-- y las tres se ven idénticas mirando la fila.
create or replace function fn_valida_firmante_empresa()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_persona_id uuid;
  v_estado text;
  v_rol text;
begin
  if new.clave <> 'firmante_empresa' then
    return new;
  end if;

  begin
    v_persona_id := (new.valor ->> 'persona_id')::uuid;
  exception when others then
    raise exception 'firmante_empresa: `persona_id` tiene que ser un identificador de persona válido.';
  end;

  if v_persona_id is null then
    raise exception 'firmante_empresa: falta `persona_id`. Quien firma se guarda por su ficha, no por su nombre.';
  end if;

  select p.estado::text, p.rol::text into v_estado, v_rol
    from personas p where p.id = v_persona_id;

  if v_estado is null then
    raise exception 'firmante_empresa: no existe ninguna persona con ese identificador.';
  end if;
  if v_estado <> 'activo' then
    raise exception 'firmante_empresa: esa persona está inactiva. Un documento no puede salir firmado por quien ya no está en CAYLA.';
  end if;
  if v_rol not in ('admin', 'lider_do') then
    raise exception 'firmante_empresa: esa cuenta no tiene permiso para firmar documentos de la empresa (rol %).', v_rol;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_valida_firmante_empresa on configuracion;
create trigger trg_valida_firmante_empresa
  before insert or update on configuracion
  for each row execute function fn_valida_firmante_empresa();

-- ── 2 · Dejar la fila apuntando a quien firma hoy ───────────────────────────
-- Se resuelve por nombre UNA SOLA VEZ, para arrancar. Es exactamente lo que
-- esta migración viene a eliminar como regla de todos los días, y por eso acá
-- es aceptable: si acierta, el sistema nunca vuelve a comparar nombres; si no
-- acierta, no inserta nada y las pantallas siguen imprimiendo como hasta hoy,
-- con la raya en blanco. Nunca deja el sistema peor que como lo encontró.
--
-- La comparación ignora tildes porque las pantallas escriben «Alvarez» y la
-- ficha puede decir «Álvarez».
insert into configuracion (clave, valor, descripcion)
select
  'firmante_empresa',
  jsonb_build_object('persona_id', p.id, 'cargo', 'Gerencia General'),
  'Quién firma los documentos que emite CAYLA. Las pantallas leen de acá el nombre que imprimen y solo estampan la firma escaneada si quien imprime es esta persona. Ver migración 0147.'
from personas p
where p.estado = 'activo'
  and p.rol in ('admin', 'lider_do')
  and translate(lower(p.apellidos || ' ' || p.nombres), 'áéíóúüñ', 'aeiouun')
      = translate(lower('Alvarez Pereyra Felipe Miguel'), 'áéíóúüñ', 'aeiouun')
limit 1
on conflict (clave) do nothing;

-- Si la fila no quedó puesta, decirlo en voz alta en vez de dejarlo pasar: el
-- síntoma sería una raya en blanco, que se ve igual que «todavía no cargué mi
-- firma» y que «esta no es mi cuenta».
do $$
begin
  if not exists (select 1 from configuracion where clave = 'firmante_empresa') then
    raise warning 'La 0147 NO pudo resolver quién firma por CAYLA: ningún admin activo coincide con «Alvarez Pereyra Felipe Miguel». Los documentos siguen saliendo con la raya en blanco hasta que se corra el update de la cabecera.';
  end if;
end $$;

insert into migraciones_aplicadas (numero, nombre)
values (147, 'quien_firma_por_cayla')
on conflict (numero) do nothing;
