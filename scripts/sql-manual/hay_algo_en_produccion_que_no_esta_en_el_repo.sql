-- ============================================================================
-- ¿HAY ALGO APLICADO EN PRODUCCIÓN QUE NUNCA LLEGÓ AL REPOSITORIO?
-- ============================================================================
-- Solo LEE. Un solo select. Se pega entero en el SQL Editor.
--
-- Es la pregunta que `que_falta_pegar.sql` NO puede responder, y por diseño:
-- esa consulta arma su lista leyendo `supabase/migrations`, así que solo ve
-- las migraciones que el repositorio conoce. Si alguien pegó algo en producción
-- y no lo commiteó, para ella ese algo no existe.
--
-- No es hipotético. Pasó tres veces:
--   · la 0177 —que cambia cómo se pagan las vacaciones— estuvo aplicada en
--     producción con su único ejemplar en un archivo sin commitear en una Mac;
--   · la 0243 —una liquidación por cese— igual, el 2026-08-14;
--   · la 0277 —el régimen de pensión— corrió dos días sin estar en el repo.
--
-- CÓMO SE LEE
--
--   huerfanas = 0   → todo lo aplicado está en el repositorio. Nada que hacer.
--
--   huerfanas > 0   → `cuales` dice los números. Para cada uno hay que
--                     recuperar el SQL de producción y commitearlo, porque hoy
--                     su única copia está en la base. Si se pierde, no se puede
--                     reconstruir el esquema.
--
-- La 0031 y la 0033 quedan fuera a propósito: viven fuera de git por llevar
-- datos personales, y su ausencia del repositorio es deliberada.
-- ============================================================================

select
  (select count(*) from migraciones_aplicadas
    where numero not in (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,32,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,109,110,111,112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,134,135,136,137,138,140,141,142,143,144,145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,160,161,162,163,164,165,166,167,168,169,170,171,172,173,174,175,176,177,178,179,180,181,182,183,184,185,186,187,188,189,190,191,192,193,194,195,196,197,198,199,200,201,202,203,204,205,206,207,208,209,210,211,212,213,214,215,228,229,230,231,232,233,234,235,236,237,238,239,240,241,242,243,244,245,246,247,248,249,250,251,252,253,254,255,256,257,260,261,262,263,264,265,266,267,269,270,271,272,273,274,275,276,277,278,279,280,281,282,283,284,285,286,287,288,289,290,291,292,293,294,295,296,297,298,299,300,301,302,303,304,305,306,307,308,309,310,311,312,313,314,315,316) and numero not in (31, 33))        as huerfanas,

  (select coalesce(string_agg(numero::text || ' · ' || nombre, E'\n' order by numero), '(ninguna)')
     from migraciones_aplicadas
    where numero not in (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,32,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,109,110,111,112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,134,135,136,137,138,140,141,142,143,144,145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,160,161,162,163,164,165,166,167,168,169,170,171,172,173,174,175,176,177,178,179,180,181,182,183,184,185,186,187,188,189,190,191,192,193,194,195,196,197,198,199,200,201,202,203,204,205,206,207,208,209,210,211,212,213,214,215,228,229,230,231,232,233,234,235,236,237,238,239,240,241,242,243,244,245,246,247,248,249,250,251,252,253,254,255,256,257,260,261,262,263,264,265,266,267,269,270,271,272,273,274,275,276,277,278,279,280,281,282,283,284,285,286,287,288,289,290,291,292,293,294,295,296,297,298,299,300,301,302,303,304,305,306,307,308,309,310,311,312,313,314,315,316) and numero not in (31, 33))        as cuales,

  (select count(*) from migraciones_aplicadas)                     as filas_en_produccion,
  296                as archivos_en_el_repo,

  (select coalesce(max(numero), 0) from migraciones_aplicadas)     as ultima_aplicada;
