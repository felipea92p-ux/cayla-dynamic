-- ============================================================================
-- 0285_el_kiosco_ve_solo_lo_que_necesita_para_marcar.sql
-- ============================================================================
-- QUE PROMETE
--
--   Una vista con las SEIS cosas que el terminal necesita para pintar su lista
--   de nombres, y ninguna mas. Nada de DNI, nada de remuneracion, nada de
--   correo.
--
-- QUE NO HACE, Y ES A PROPOSITO
--
--   NO quita todavia la policy `personas_select_terminal_roster`. Esta
--   migracion es ADITIVA y no puede romper nada: crea una vista que nadie usa
--   aun. La policy se quita en una migracion posterior, DESPUES de desplegar el
--   frontend que lee de aqui.
--
--   El orden importa y no es una preferencia: si se quitara la policy antes de
--   que el terminal sepa leer la vista, `cargarRoster` devolveria cero filas y
--   —por el guard de la 0202 que la propia funcion documenta— caeria a la cache
--   offline. En un terminal recien instalado no hay cache. Eso es una sede
--   entera sin poder marcar.
--
-- POR QUE EXISTE
--
--   La auditoria de agosto lo dio como P0 y se COMPROBO el 2026-08-19
--   ejecutandolo, no leyendo la policy: puesto en el papel del terminal
--   —`set role authenticated` mas su `auth_user_id`— un select devuelve
--   `documento` y `sueldo_base_legal` de todas las personas de su sede.
--
--   No es un fallo de la policy: es que **RLS filtra FILAS, no COLUMNAS**. La
--   policy hace bien su trabajo —acota a la sede y a quien esta activa— y no
--   puede hacer el otro. `roster.ts` pide cuatro campos con toda la educacion,
--   pero el token que viaja en esa Mac mini alcanza la fila entera.
--
--   Y esa Mac mini esta a la vista de todo el equipo, a pantalla completa, sin
--   PIN — que es una decision tomada y correcta (CLAUDE.md, jul-2026). Lo que
--   no puede ser es que ademas lleve dentro el padron con sueldos.
--
--   Medido tambien lo que NO alcanza, para no exagerar el hallazgo: la tabla
--   `datos_personales` —celular, direccion, cuenta bancaria— devuelve CERO
--   filas al terminal. Esa parte ya estaba bien.
--
-- POR QUE UNA VISTA Y NO UNA POLICY MEJOR
--
--   Porque no existe una policy mejor: ninguna puede acotar columnas. La unica
--   forma de que el token no alcance el sueldo es que la superficie que ese
--   token puede leer no lo contenga. Eso es una vista.
--
--   Va con `security_invoker = false` A PROPOSITO —al reves que la vista
--   `vacaciones`, que si hereda la RLS de `ausencias`—. Aqui tiene que seguir
--   funcionando cuando la policy de `personas` ya no exista, asi que la vista
--   lleva ella misma la condicion, copiada literal de la policy que sustituye.
--
--   Lo que la hace segura no es el `grant`, es `fn_sede_actual_terminal()`:
--   devuelve la sede si `auth.uid()` es un terminal ACTIVO, y null para
--   cualquier otra sesion. Una integrante con cuenta que consulte esta vista
--   obtiene cero filas.
--
-- QUE ASUME
--   · La 0008, de donde sale la condicion (sede del terminal o
--     `visible_todas_sedes`), copiada sin cambiarle una coma.
--   · La 0202, que obliga a desactivar un terminal antes de borrar su cuenta.
--     Un terminal desactivado sigue viendo cero filas, igual que hoy.
--
-- COMO SE REVIERTE
--   `drop view if exists terminal_roster;`. Nada mas: mientras el frontend no
--   la use, soltarla no tiene efecto alguno.
--
-- COMO SE COMPRUEBA QUE QUEDO BIEN
--   La consulta del final devuelve una fila con cuatro `true`.
-- ============================================================================

create or replace view terminal_roster
with (security_invoker = false)
as
select
  p.id,
  p.nombres,
  p.apellidos,
  p.pin_hash,
  s.codigo as sede_codigo,
  s.nombre  as sede_nombre
from personas p
join sedes s on s.id = p.sede_base_id
-- Copiada LITERAL de personas_select_terminal_roster (0008). Si algun dia se
-- cambia alla, hay que cambiarla aqui — y por eso la migracion que quita la
-- policy deja esta vista como el unico sitio donde vive.
where p.estado = 'activo'
  and fn_sede_actual_terminal() is not null
  and (p.sede_base_id = fn_sede_actual_terminal() or p.visible_todas_sedes = true);

comment on view terminal_roster is
  'Lo unico que el kiosco de marcaje necesita ver de una persona: como se llama, de que sede es y su pin_hash. Existe porque RLS filtra filas y no columnas, asi que mientras el terminal leyera `personas` su token alcanzaba el DNI y la remuneracion (0285).';

revoke all on terminal_roster from public, anon;
grant select on terminal_roster to authenticated;

notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (285, 'el_kiosco_ve_solo_lo_que_necesita_para_marcar')
on conflict (numero) do nothing;


-- ── Comprobacion de que la pegada llego entera ──────────────────────────────
-- Cuatro `true`. El tercero es el que importa: que la vista NO lleve columnas
-- sensibles, que es la razon entera de que exista.
select
  (select count(*) from pg_views where viewname = 'terminal_roster') = 1
    as existe_la_vista,
  (select has_table_privilege('authenticated', 'terminal_roster', 'select'))
    as el_terminal_la_puede_leer,
  (select count(*) from information_schema.columns
    where table_name = 'terminal_roster'
      and column_name in ('documento', 'sueldo_base_legal', 'email',
                          'regimen_pension', 'fecha_ingreso')) = 0
    as no_expone_nada_sensible,
  (select count(*) from pg_policy
    where polrelid = 'personas'::regclass
      and polname = 'personas_select_terminal_roster') = 1
    as la_policy_vieja_sigue_puesta_todavia;
