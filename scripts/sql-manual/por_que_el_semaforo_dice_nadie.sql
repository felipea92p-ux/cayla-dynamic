-- ============================================================================
-- por_que_el_semaforo_dice_nadie.sql
-- ============================================================================
-- QUÉ RESPONDE
--   Por qué la pantalla de Disciplina dice «Nadie con tardanzas relevantes este
--   mes» cuando las tablas sí tienen a alguien.
--
--   Se corre DESPUÉS de recargar la página. Si al recargar ya aparece la
--   persona, no hace falta: era la pestaña vieja, que carga los datos una sola
--   vez al montarse.
--
-- QUÉ NO HACE
--   No escribe nada. Solo lee. Se pega tal cual en el SQL Editor de Supabase.
--
-- ── POR QUÉ HAY QUE MEDIR Y NO RAZONAR ──────────────────────────────────────
--
-- Ya se descartaron dos explicaciones a mano, y las dos parecían buenas:
--
--   «es una versión vieja de la función»   FALSO. Las seis versiones desde la
--                                          0057 listan a partir de 2 tardanzas.
--   «la sesión no tiene permiso»           FALSO. La lista de Entregados muestra
--                                          documentos de AQP y de LIM a la vez,
--                                          y la política RLS solo permite eso si
--                                          fn_es_admin_o_lider() es true — que es
--                                          la misma puerta que usa el semáforo.
--
-- Lo que queda es medir el estado REAL de la función en producción. Esta
-- consulta mira las tres cosas que pueden dejar la lista vacía sin decir nada.
--
-- ── CÓMO SE LEE ─────────────────────────────────────────────────────────────
--
--   sobrecargas   Tiene que ser 1. Si son 2, la llamada de la pantalla
--                 —rpc("fn_tardanzas_resumen", {})— es ambigua y PostgREST
--                 responde PGRST203 sin devolver filas. La 0057 la creó sin
--                 argumentos y la 0067 la cambió a (date); desde entonces cada
--                 versión suelta solo la de (date).
--   md5           Contra qué versión estás. El de la 0189 aparece abajo.
--   umbral_vivo   El trozo real del cuerpo que decide a quién lista. Se lee
--                 directo: si dice `c.n >= 2`, Mateo con 2 tiene que salir.
--   es_medible    Si falta, la 0189 no está aplicada y el cuerpo es otro.
-- ============================================================================

select
  p.proname                                 as funcion,
  pg_get_function_identity_arguments(p.oid) as argumentos,
  count(*) over (partition by p.proname)    as sobrecargas,
  md5(p.prosrc)                             as md5_en_produccion,
  case p.proname
    when 'fn_tardanzas_resumen'   then '928f45222dbff5e3a8546a76240ebaba (0189)'
    when 'fn_tardanza_es_medible' then '7c09aa63c68987b249469ab3f3f828d3 (0189)'
    else '—'
  end                                       as md5_esperado,
  -- Solo la LÍNEA que decide quién entra a la lista, cortada en el salto de
  -- línea. Un `substring` sobre el prosrc real es lo que zanjó la falsa alarma
  -- del 2026-08-08 después de tres hipótesis equivocadas; uno codicioso vuelca
  -- medio cuerpo y no se lee.
  nullif(trim(substring(p.prosrc from 'where\s+c\.n[^\n]*')), '') as umbral_vivo,
  length(p.prosrc)                          as largo
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('fn_tardanzas_resumen', 'fn_faltas_resumen', 'fn_tardanza_es_medible')
order by 1, 2;
