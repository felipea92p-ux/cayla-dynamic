-- ============================================================================
-- 0404 — Queda constancia de que aceptó el tratamiento de sus datos
-- ============================================================================
--
-- QUÉ PROMETE
--   Cuando alguien manda las fotos de su DNI desde «Mi DNI» (0401), la
--   pantalla le pide antes marcar una casilla de consentimiento —Ley N.° 29733,
--   art. 5: el consentimiento se pide EN EL MOMENTO de recolectar el dato, no
--   se da por incluido en un contrato que se firma después—. Esta migración
--   guarda ESA aceptación: quién, cuándo, para qué, y con qué texto exacto.
--
--   Es un registro APPEND-ONLY: una fila por acto de consentimiento, nunca una
--   por persona. Si vuelve a mandar sus fotos, se guarda una fila nueva; si el
--   texto de la casilla cambia con los años, cada fila sigue diciendo lo que
--   esa persona aceptó ese día. Sin `texto` guardado, la constancia diría
--   «aceptó» sin poder decir qué — que es justo lo que la ley pide probar.
--
-- QUÉ ASUME
--   Que el control REAL de que el DNI se recolectó de verdad no es esta tabla,
--   sino la aprobación humana que ya trae la 0401: Desarrollo Organizacional
--   —o la encargada de sede, desde la 0403— mira las dos fotos y las aprueba.
--   Esta tabla no verifica nada; solo deja constancia de la aceptación.
--
-- QUÉ NO HACE, Y ES DELIBERADO
--   No bloquea `fn_crear_solicitud_perfil` en la base: la casilla se exige en
--   la pantalla. Se evaluó exigirla también del lado del servidor y se decidió
--   que no, por dos razones concretas:
--     · esa función ya la reescriben DOS migraciones sin pegar de esta misma
--       rama (0401 y 0403). Una tercera reescritura encadenada es exactamente
--       el accidente que CLAUDE.md documenta con la 0276 y la 0261.
--     · condicionarla ahí obligaría a distinguir `p_campo = 'foto_dni'` dentro
--       de una función que sirve a los once campos del catálogo, metiendo una
--       regla de UN campo en el camino de todos.
--   Cuando la 0401/0403 estén pegadas y la función quede quieta, el guard
--   servidor es una migración de tres líneas sobre esta misma tabla.
--
--   Tampoco valida que el texto aceptado sea el texto vigente: solo exige que
--   no venga vacío. Comparar contra una copia en la base obligaría a versionar
--   el texto en dos sitios y a que cada retoque de redacción fuera una
--   migración; guardar lo que la persona vio en pantalla es lo que se necesita
--   para probar qué aceptó.
--
-- POR QUÉ ASÍ
--   Tabla propia y no una columna en `datos_personales`: ahí solo entra lo que
--   YA está aprobado (la 0401 escribe las rutas del DNI al aprobar), y el
--   consentimiento ocurre antes, al mandarlas. Tampoco va en
--   `solicitudes_cambio_perfil`: esa fila se reemplaza cuando alguien vuelve a
--   proponer el mismo campo (estado `reemplazada`, 0399), y una constancia
--   legal no se reemplaza.
--
--   Quién puede LEERLA copia el criterio de la 0403 para la solicitud que
--   acompaña —admin/líder, o la encargada de esa sede— en vez de inventar uno:
--   ver `fn_solicitudes_perfil_pendientes` en esa migración.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_registrar_mi_consentimiento(text, text);
--   drop table if exists consentimientos_datos_personales;
-- ============================================================================


-- ── A · La constancia, una fila por acto ────────────────────────────────────
create table if not exists consentimientos_datos_personales (
  id          uuid primary key default gen_random_uuid(),
  persona_id  uuid not null references personas(id),
  finalidad   text not null,
  texto       text not null,
  aceptado_at timestamptz not null default now()
);

comment on table consentimientos_datos_personales is
  'Constancia de consentimiento informado para el tratamiento de datos '
  'personales (Ley N.° 29733). Append-only: una fila por acto de aceptación, '
  'con el texto exacto que la persona tenía delante. Nunca se actualiza ni se '
  'borra — es prueba, no estado. Escritura solo vía fn_registrar_mi_consentimiento.';

comment on column consentimientos_datos_personales.finalidad is
  'Qué se estaba recolectando cuando aceptó — hoy solo ''foto_dni'' (0401). '
  'Sin lista cerrada a propósito: una finalidad nueva no debería necesitar una '
  'migración, y la constancia vale igual.';

create index if not exists idx_consentimientos_datos_persona
  on consentimientos_datos_personales (persona_id, aceptado_at desc);

alter table consentimientos_datos_personales enable row level security;

-- Ve la suya cada quien.
drop policy if exists consentimientos_datos_select_propia on consentimientos_datos_personales;
create policy consentimientos_datos_select_propia on consentimientos_datos_personales
  for select to authenticated using (persona_id = fn_persona_actual_id());

-- Y la de otra persona, quien ya puede ver su solicitud de perfil: mismo
-- criterio que fn_solicitudes_perfil_pendientes (0403), copiado, no inventado.
drop policy if exists consentimientos_datos_select_quien_aprueba on consentimientos_datos_personales;
create policy consentimientos_datos_select_quien_aprueba on consentimientos_datos_personales
  for select to authenticated using (
    fn_es_admin_o_lider() is true
    or (fn_rol_actual() = 'supervisor_sede'
        and exists (
          select 1 from personas pe
           where pe.id = consentimientos_datos_personales.persona_id
             and pe.sede_base_id = fn_sede_actual_persona()
        ))
  );

grant select on consentimientos_datos_personales to authenticated;
revoke all on consentimientos_datos_personales from anon, public;
-- Sin insert/update/delete: se escribe solo por la función de abajo, y no se
-- actualiza ni se borra nunca — ver el comment de la tabla.


-- ── B · Dejar constancia de MI consentimiento ───────────────────────────────
create or replace function fn_registrar_mi_consentimiento(p_finalidad text, p_texto text)
returns void language plpgsql security definer set search_path = public as $$
declare v_yo uuid;
begin
  v_yo := fn_persona_actual_id();
  if v_yo is null then raise exception 'No se encontró tu persona.'; end if;

  if coalesce(trim(p_finalidad), '') = '' then
    raise exception 'Falta decir para qué se dio el consentimiento.';
  end if;

  -- El mínimo no es un número mágico: es «esto no puede ser una constancia
  -- vacía». El texto real de la casilla pasa de 600 caracteres.
  if length(coalesce(trim(p_texto), '')) < 50 then
    raise exception 'El texto del consentimiento llegó vacío o incompleto; no se puede dejar constancia de él.';
  end if;

  insert into consentimientos_datos_personales (persona_id, finalidad, texto)
  values (v_yo, trim(p_finalidad), p_texto);
end;
$$;
grant execute on function fn_registrar_mi_consentimiento(text, text) to authenticated;
revoke execute on function fn_registrar_mi_consentimiento(text, text) from public, anon;


insert into migraciones_aplicadas (numero, nombre) values (404, 'queda_constancia_de_que_acepto_el_tratamiento')
on conflict (numero) do nothing;
