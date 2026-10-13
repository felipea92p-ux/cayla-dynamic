-- SOLO LEE. Qué quedó en producción del bono de cumpleaños después de la 0518 y la 0519 (2026-10-13).
-- Dos migraciones de dos ramas reescribieron las mismas funciones; la que se pegó última manda.
select numero, nombre, aplicada_at from migraciones_aplicadas where numero in (518, 519) order by numero;

select p.proname,
       position('CAMBIO 0518' in p.prosrc) > 0 as tiene_0518,
       position('CAMBIO 0519' in p.prosrc) > 0 as tiene_0519,
       length(p.prosrc) as caracteres
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('fn_mi_bono_cumpleanos', 'fn_documento_registrar', 'fn_documentos_tablero', 'fn_confirmar_mi_bono_cumpleanos')
 order by 1;

-- Las dos funciones «a quién le toca»: la de la 0518 y la de la 0519. Cuál usa cada puerta se ve arriba.
select proname from pg_proc where proname like 'fn_persona_le_corresponde_bono%' order by 1;
