-- ============================================================================
-- 159_el_panel_puede_ejecutar_lo_que_llama.test.sql
-- ============================================================================
-- El defecto que cierra, vivo en producción del 2026-08-08 al 2026-08-10:
--
--   `authenticated` no podía ejecutar `fn_tardanzas_resumen`. PostgREST
--   devolvía error, la pantalla de Disciplina no miraba ese error, y durante
--   dos días imprimió «Nadie con tardanzas relevantes este mes» — la misma
--   frase exacta que cuando de verdad no hay nadie. El Dashboard y la Hoja de
--   sede leen la misma función y estaban igual de ciegos.
--
--   La causa: un `drop function` se lleva por delante los GRANT. La 0189 hace
--   ese drop —obligada, porque la función devuelve TABLE— y no vuelve a
--   otorgar. El último `grant execute` era de la 0067, y este proyecto revoca
--   el EXECUTE que Postgres da a PUBLIC por defecto, así que no hubo red.
--
-- ── POR QUÉ NINGUNA PRUEBA LO CAZÓ, Y POR QUÉ ESTA SÍ ────────────────────────
--
-- Las pgTAP corren como `postgres`, que puede ejecutarlo todo. El defecto solo
-- existía para `authenticated`. Ochenta y cinco archivos de prueba pasaban en
-- verde mientras la pantalla estaba muerta.
--
-- Esta prueba no EJECUTA nada: pregunta por el privilegio de OTRO rol, que es
-- algo que `postgres` puede consultar sin suplantarlo. Es la única forma de
-- ver este defecto desde aquí.
--
-- ── POR QUÉ UNA LISTA POSITIVA Y NO UN BARRIDO ──────────────────────────────
--
-- Un barrido por `prosecdef` recoge triggers, funciones de CHECK y auxiliares
-- internas que NO deben ser ejecutables por `authenticated`: catorce falsos
-- positivos, contados. Un freno que chilla siempre se desactiva a la semana, y
-- este repositorio ya se escribió esa regla.
--
-- Así que van nombradas, y el criterio para entrar es estrecho a propósito:
-- **funciones que el panel llama por `rpc()` y cuyo fallo es MUDO** — las que
-- alimentan una lista con estado vacío, donde «falló» y «no hay nadie» se ven
-- exactamente igual. Ese es el daño que esta prueba existe para impedir.
--
-- Si agregas una función de esa clase, agrégala aquí. Si la que agregas grita
-- cuando falla, no hace falta.
-- ============================================================================
begin;
select plan(6);

-- ── Las tres del motor disciplinario ────────────────────────────────────────
-- Son las de fallo más caro: alimentan Disciplina, el Dashboard y la Hoja de
-- sede, y las tres pintan un estado vacío tranquilizador cuando no hay datos.
select ok(
  has_function_privilege('authenticated', 'public.fn_tardanzas_resumen(date)'::regprocedure, 'EXECUTE'),
  'authenticated puede ejecutar fn_tardanzas_resumen — si no, Disciplina dice «Nadie» y miente');

select ok(
  has_function_privilege('authenticated', 'public.fn_faltas_resumen(date)'::regprocedure, 'EXECUTE'),
  'authenticated puede ejecutar fn_faltas_resumen — si no, el semáforo de faltas miente igual');

select ok(
  has_function_privilege('authenticated', 'public.fn_expediente_firmantes(uuid)'::regprocedure, 'EXECUTE'),
  'authenticated puede ejecutar fn_expediente_firmantes — si no, el borrador se queda sin desplegable de firmante y se firma con quien no toca');

-- ── La escala, que la 0200 puso en un solo sitio ───────────────────────────
-- No la llama el panel directamente, pero sí `fn_tardanzas_resumen`, que es
-- SECURITY DEFINER y corre como su dueño: por eso NO necesita el grant, y por
-- eso se comprueba lo contrario de lo que se esperaría — que exista, no que sea
-- ejecutable. Está aquí para que quien lea la prueba no le añada un grant que
-- no hace falta.
select has_function(
  'public', 'fn_tardanza_escalon', array['uuid'],
  'fn_tardanza_escalon existe — la escala del RIT art. 7 vive en un solo sitio');

-- ── La ficha personal, la segunda caída del mismo día ──────────────────────
-- La 0198 le añadió `p_cuspp` con un `create or replace`. Un parámetro nuevo NO
-- reemplaza: crea otra función, sin los permisos de la anterior. El panel manda
-- `p_cuspp`, así que PostgREST elegía justo la que no podía ejecutar.
select ok(
  has_function_privilege(
    'authenticated',
    'public.fn_set_datos_personales(uuid,text,date,text,text,text,text,text,text,boolean,text,text,text,text,text,text,boolean,text,text)'::regprocedure,
    'EXECUTE'),
  'authenticated puede ejecutar fn_set_datos_personales con p_cuspp — la firma que el panel elige de verdad');

-- ── Y que anon siga sin poder tocar nada de esto ───────────────────────────
-- La contraparte: arreglar un permiso a base de abrirlo de más sería peor que
-- el defecto. `anon` es quien entra sin sesión.
select ok(
  not has_function_privilege('anon', 'public.fn_tardanzas_resumen(date)'::regprocedure, 'EXECUTE'),
  'anon NO puede ejecutar fn_tardanzas_resumen — el arreglo no abrió la puerta de más');

select * from finish();
rollback;
