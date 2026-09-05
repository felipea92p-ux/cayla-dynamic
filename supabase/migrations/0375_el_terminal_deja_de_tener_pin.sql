-- ============================================================================
-- 0375_el_terminal_deja_de_tener_pin.sql
-- ============================================================================
--
-- QUÉ PROMETE
--   Que el terminal no pueda pedir un PIN nunca más, y que el hash del PIN deje
--   de viajar al navegador de las Mac mini.
--
-- POR QUÉ, Y POR QUÉ AHORA
--   Marcar sin PIN ya era la decisión, escrita en CLAUDE.md desde julio de 2026:
--   «Se prioriza que marcar sea instantáneo; el control real es que la Mac mini
--   está a la vista de todo el equipo, no una clave». Felipe la reafirmó el
--   2026-09-04: «el pin no me interesa, quiero agilidad».
--
--   Lo que hasta hoy había era la decisión APAGADA, no RETIRADA: el mecanismo
--   seguía entero y, peor, apuntando en la dirección contraria a la decisión.
--
-- LA TRAMPA QUE ESTO DESACTIVA, Y QUE ERA DE AGILIDAD, NO DE SEGURIDAD
--   `terminales.requiere_pin` nació `not null default TRUE` (0012). Los
--   terminales se dan de alta a mano —`insert into terminales (sede_id,
--   nombre_dispositivo)`, tal como lo documenta la 0202— sin mencionar esa
--   columna, así que caen en `true`. Y el respaldo del navegador hacía lo mismo:
--   `data.requiere_pin ?? true`.
--
--   Dos sitios independientes que, ante la duda, PEDÍAN PIN. Consecuencia: la
--   próxima Mac mini vinculada —o una reinstalada— le habría pedido un PIN de
--   cuatro dígitos a cada persona, cada vez. No habría fallado al pegar ninguna
--   migración ni al desplegar: habría fallado el día que abra una sede.
--
-- QUÉ HACE, EXACTAMENTE
--   1. `requiere_pin` pasa a `default false`, y todas las filas a `false`.
--      La columna NO se borra: se deja muerta y en falso, para no tocar el
--      esquema de una tabla que ninguna pantalla edita.
--   2. `terminal_roster` se recrea SIN `pin_hash`. El kiosco deja de descargar
--      hashes que ya no compara nadie.
--
-- POR QUÉ UN DROP + CREATE Y NO UN `create or replace`
--   Postgres se niega a quitarle una columna a una vista existente («cannot
--   drop columns from view»). Medido, no supuesto. Y el `drop` se lleva por
--   delante tres cosas que hay que reponer en esta misma migración:
--     · los grants — es donde esta casa ya se quemó: la 0363 tuvo que devolverle
--       a `fn_provisiones` un `grant execute` que la 0338 perdió;
--     · el `comment on view`;
--     · y la más silenciosa, `with (security_invoker = false)`. Sin ella la
--       vista pasaría a leer `personas` con los permisos de QUIEN CONSULTA, y
--       desde que la 0291 borró `personas_select_terminal_roster` una sesión de
--       terminal no tiene ningún SELECT sobre `personas`: el kiosco dejaría de
--       ver a nadie. No falla al pegar; falla a la mañana siguiente.
--   El `drop` es seguro sin `cascade`: se comprobó contra `pg_depend` que
--   ninguna vista, función ni regla depende de `terminal_roster`.
--
-- ⚠️ EL ORDEN IMPORTA, Y ES LO ÚNICO QUE PUEDE DEJAR UNA SEDE SIN FICHAR
--   EL PANEL VA PRIMERO. `roster.ts` pedía `pin_hash` POR NOMBRE. Si esta
--   migración se pega antes de que el panel nuevo esté publicado en Vercel,
--   PostgREST responde 42703 («column terminal_roster.pin_hash does not
--   exist»), `cargarRoster` lo trata como caída de red y cae a la caché local.
--   Un terminal ya instalado seguiría marcando con una lista vieja y nadie se
--   enteraría; una Mac recién instalada mostraría «Esta Mac no pudo leer la
--   lista» y esa sede no ficha en toda la mañana.
--
--   Secuencia correcta:
--     1. desplegar apps/web a producción;
--     2. comprobar en las cuatro Mac mini que la lista de nombres carga;
--     3. recién entonces pegar esta migración.
--
-- QUÉ ASUME
--   · Que ninguna función, policy ni constraint lee `terminales.requiere_pin`.
--     Medido contra el esquema: cero funciones, cero policies, cero vistas. El
--     único lector del sistema entero era `apps/web/lib/terminal/terminal-info.ts`,
--     que deja de pedirla en este mismo lote.
--   · Que nada en la base compara el hash del PIN. Medido: de las tres funciones
--     que tocan `personas.pin_hash`, una lo inserta (`fn_crear_persona`), otra lo
--     escribe (`fn_regenerar_pin`) y la tercera bloquea su escritura por REST
--     (`fn_trg_pin_solo_por_rpc`). Ninguna lo LEE para compararlo: esa comparación
--     vivía enteramente en el navegador.
--
-- LO QUE NO HACE, A PROPÓSITO — Y QUE LA PRÓXIMA SESIÓN NO DEBE «LIMPIAR»
--   · NO borra `personas.pin_hash`. Es `not null` y `fn_crear_persona` la exige:
--     tocarla significaría rehacer el alta de personas, que no es este cambio.
--   · NO toca `fn_regenerar_pin` ni `trg_personas_pin_solo_por_rpc`, de la 0364,
--     fusionada el 2026-09-04. Puede parecer código muerto y no lo es: el botón
--     «Nuevo PIN» de /admin/equipo sigue llamando a la función, y el trigger
--     conserva su valor con PIN o sin él —es lo que impide que una columna
--     `not null` de `personas` se escriba desde el navegador por REST—.
--   · Y queda una deuda de honestidad de pantalla, anotada aquí para que no se
--     pierda: /admin/equipo sigue diciendo «Agregar (genera PIN)» y sigue
--     ofreciendo «Nuevo PIN» por persona. Ese número ya no lo pide ningún
--     terminal. La pantalla le va a pedir a una encargada que anote y entregue
--     algo que nadie va a usar. Arreglarlo es texto y un panel, no toca la
--     creación de personas — pero es otro cambio.
--
-- CÓMO SE REVIERTE
--   Volviendo a pegar el bloque `create or replace view terminal_roster` de la
--   0285 (que sí incluye `p.pin_hash`) con sus dos líneas de grant, y
--   `alter table terminales alter column requiere_pin set default true`. Los
--   valores de las filas no se restauran solos: quien quiera volver a exigir PIN
--   tendría que ponerlos en `true` a mano, que es justamente la puerta que esta
--   migración cierra.
-- ============================================================================

-- ── 1 · El default deja de ser una trampa ───────────────────────────────────
alter table terminales alter column requiere_pin set default false;

update terminales set requiere_pin = false where requiere_pin;

-- ── 2 · El hash deja de viajar al navegador ─────────────────────────────────
drop view if exists terminal_roster;

create view terminal_roster
with (security_invoker = false)
as
select
  p.id,
  p.nombres,
  p.apellidos,
  s.codigo as sede_codigo,
  s.nombre  as sede_nombre
from personas p
join sedes s on s.id = p.sede_base_id
-- Copiada LITERAL de personas_select_terminal_roster (0008), igual que en la
-- 0285. Lo unico que cambia respecto de alli es que ya no viaja `p.pin_hash`.
where p.estado = 'activo'
  and fn_sede_actual_terminal() is not null
  and (p.sede_base_id = fn_sede_actual_terminal() or p.visible_todas_sedes = true);

comment on view terminal_roster is
  'Lo unico que el kiosco de marcaje necesita ver de una persona: como se llama y de que sede es. '
  'Existe porque RLS filtra filas y no columnas, asi que mientras el terminal leyera `personas` su '
  'token alcanzaba el DNI y la remuneracion (0285). Desde la 0375 tampoco lleva `pin_hash`: el '
  'terminal ya no pide PIN, asi que descargar el hash era regalar un dato que nadie compara.';

-- Los mismos dos de la 0285, repuestos porque el `drop` se los llevo.
revoke all on terminal_roster from public, anon;
grant select on terminal_roster to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (375, 'el_terminal_deja_de_tener_pin')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
-- Lo que hay que ver al terminar de pegar. Las cinco tienen que salir en true:
--   cinco_columnas   · la vista quedo sin `pin_hash`
--   sin_pin_hash     · y no se coló por ningun lado
--   es_del_dueno     · `security_invoker = false` sobrevivio al drop+create
--   la_puede_leer    · `authenticated` (el terminal) recupero su grant
--   anon_no_puede    · y `anon` sigue sin poder
--   ningun_terminal_pide_pin · el default y las filas quedaron en false
select
  (select count(*) from information_schema.columns
    where table_name = 'terminal_roster') = 5                                   as cinco_columnas,
  (select count(*) from information_schema.columns
    where table_name = 'terminal_roster' and column_name = 'pin_hash') = 0      as sin_pin_hash,
  (select reloptions::text like '%security_invoker=false%'
     from pg_class where relname = 'terminal_roster')                           as es_del_dueno,
  has_table_privilege('authenticated', 'terminal_roster', 'select')             as la_puede_leer,
  not has_table_privilege('anon', 'terminal_roster', 'select')                  as anon_no_puede,
  (select count(*) from terminales where requiere_pin) = 0                      as ningun_terminal_pide_pin,
  (select column_default from information_schema.columns
    where table_name = 'terminales' and column_name = 'requiere_pin')           as el_default_ahora;
