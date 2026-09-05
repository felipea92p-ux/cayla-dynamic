-- ############################################################################
-- ####  QUÉ PASA CON LA AFP — SOLO LEE, NO ESCRIBE NADA                    ####
-- ############################################################################
--
-- PARA QUÉ
--   Tres preguntas distintas que se suelen mezclar en una:
--
--     1. ¿A quién se le descuenta con la tasa de SU AFP y a quién con la
--        genérica? Porque quien no tiene régimen cargado NO se queda sin
--        descuento: se le aplica `configuracion.tasa_afp`, que es una
--        aproximación. Un dato faltante acá no se ve como un cero, se ve como
--        un número plausible.
--     2. ¿El CUSPP cambia algún cálculo? No. Va abajo por qué.
--     3. ¿Se le está descontando AFP a alguien a quien no le corresponde?
--        Esa es la que puede costar plata, y es el BLOQUE 2.
--
-- EL CUSPP NO CAMBIA NI UN SOL, Y CONVIENE TENERLO CLARO
--   El monto lo decide `tasas_pension` según el régimen (0114). El CUSPP es
--   IDENTIFICACIÓN: es lo que hace que el aporte ya calculado y declarado
--   aterrice en la cuenta individual de esa persona en su AFP en vez de quedar
--   sin atribuir. Cargarlo no movió ninguna boleta — y no tenerlo tampoco
--   frenaba el descuento, que es justo lo que lo hacía fácil de no notar.
--
-- NO LLEVA NINGÚN DATO SENSIBLE
--   Nombres, régimen y montos calculados. Ni DNI, ni número de cuenta, ni el
--   CUSPP en sí — para eso está la ficha de cada persona, que registra quién
--   la vio.
-- ############################################################################


-- ############################################################################
-- ####  BLOQUE 1 · CON QUÉ TASA SE LE DESCUENTA A CADA UNA                 ####
-- ############################################################################
--
-- `de_donde_sale_la_tasa` es la columna a mirar. «la genérica» significa que
-- esa persona no tiene régimen cargado y se le está aplicando un porcentaje
-- aproximado — no está mal calculado, está calculado con el dato equivocado.

select
  p.apellidos || ', ' || p.nombres            as persona,
  coalesce(s.codigo, '?')                     as sede,
  p.tipo_vinculo                              as vinculo,
  p.en_planilla,
  coalesce(p.regimen_pension, 'SIN RÉGIMEN')  as regimen,
  coalesce(tp.tasa::text, cfg.tasa::text)     as tasa_que_se_aplica,
  case when tp.tasa is not null
       then 'la de su régimen'
       else 'LA GENÉRICA (configuracion.tasa_afp)' end as de_donde_sale_la_tasa
from personas p
left join sedes s on s.id = p.sede_base_id
left join lateral (
  select tp.aporte + tp.comision + tp.prima as tasa
  from tasas_pension tp
  where tp.regimen = p.regimen_pension
    and tp.vigente_desde <= current_date
    and (tp.vigente_hasta is null or tp.vigente_hasta >= current_date)
  order by tp.vigente_desde desc
  limit 1
) tp on true
left join lateral (
  select (valor->>'tasa')::numeric as tasa
  from configuracion where clave = 'tasa_afp'
) cfg on true
where p.estado = 'activo'
order by de_donde_sale_la_tasa, p.apellidos;


-- ############################################################################
-- ####  BLOQUE 2 · ¿SE LE DESCUENTA A QUIEN NO DEBE? — EL QUE IMPORTA      ####
-- ############################################################################
--
-- A un locador NO se le retiene AFP. La locación de servicios no genera
-- retención previsional del pagador: si esa persona aporta, lo hace como
-- independiente y por su cuenta. Cualquier `descuento_afp` distinto de cero en
-- una fila `rxh` es plata retenida de menos en su recibo.
--
-- ── ESTA CONSULTA NO REHACE LA ARITMÉTICA, LE PREGUNTA A LA FUNCIÓN ─────────
--
-- Llama a `fn_planilla_calcular` con el periodo que diga `periodos_planilla` y
-- lee lo que devuelve. Es a propósito: una consulta que reprodujera el cálculo
-- podría estar de acuerdo consigo misma y equivocada las dos veces. Ya pasó en
-- este repo, y es el motivo de la advertencia de la 0116.
--
-- El periodo se LEE, nunca se asume: va del 29 al 28 y no es mes calendario.
--
-- ── LO QUE SE MIDIÓ EL 2026-08-13, Y POR QUÉ NO ERA LO QUE PARECÍA ──────────
--
-- El encabezado de la 0193 afirma que un locador no puede recibir descuento
-- porque «su básica es 0». **Eso es cierto solo si alguien le puso
-- `sueldo_base_legal` en NULL a mano** — y esa columna tiene DEFAULT 1130.00
-- (el RMV, migración 0103). Quien se creó sin tocarla tiene básica, y con
-- básica hay descuento.
--
-- Medido contra el Postgres local, con la función vigente (md5
-- 7d67ff3c1d769ebffc3de0af20ab83fe = 0239), cuatro locadoras idénticas salvo
-- dos columnas, sueldo 1200, 24 días de 8 h:
--
--     sueldo_base_legal   con_hijos   básica    asig.fam.   AFP descontada
--     ─────────────────   ─────────   ───────   ─────────   ──────────────
--     1130 (el DEFAULT)      sí       1192.09     113.00        168.62
--     1130 (el DEFAULT)      no       1192.09       0.00        154.02
--     NULL                   sí            —      113.00         14.60
--     NULL                   no            —        0.00          0.00
--
-- Dos defectos distintos, y conviene no mezclarlos:
--
--   1 · LA BÁSICA. El descuento de pensión es `bri.base × tasa` y es el único
--       concepto SIN guarda de vínculo — todos los demás la llevan escrita
--       (EsSalud y movilidad en la 0117, educación en la 0120, sobretasas en la
--       0193). Descansa en que la base sea 0, y un DEFAULT de columna decide si
--       lo es. Que hoy funcione o no es una coincidencia, no un diseño.
--
--   2 · LA ASIGNACIÓN FAMILIAR. Entra al pago y a la base SIN condición de
--       vínculo, y es la única vía que le inventa base incluso a quien tiene
--       `sueldo_base_legal` en NULL. Aparte del descuento, cobrarla ya está mal:
--       la Ley 25129 es para trabajadores del régimen laboral privado. Y es el
--       mismo argumento de la 0117 con la movilidad — **el concepto que protege
--       a una trabajadora de planilla es el que incrimina en un RxH**. Un
--       locador que cobra asignación familiar es un indicio de laboralidad.
--       Ver A.2.b en docs/estado.md.
--
-- ── QUÉ SIGNIFICA EL RESULTADO ──────────────────────────────────────────────
--
-- CERO FILAS es la respuesta buena. Cada fila es plata de este periodo, y la
-- columna `de_donde_sale` dice cuál de los dos defectos la produjo — que es lo
-- que decide el arreglo.

with per as (
  -- El periodo vigente. Se lee, no se asume: 29 al 28.
  select fecha_ini, fecha_fin
  from periodos_planilla
  order by fecha_fin desc
  limit 1
),
filas as (
  select (e->>'persona_id')::uuid                as persona_id,
         (e->>'basica_legal_prop')::numeric      as basica,
         (e->>'asignacion_familiar')::numeric    as asig,
         (e->>'descuento_afp')::numeric          as afp,
         (e->>'aporte_essalud')::numeric         as essalud
  from per, jsonb_array_elements(
         fn_planilla_calcular(per.fecha_ini, per.fecha_fin) -> 'filas') e
)
select
  p.apellidos || ', ' || p.nombres            as persona,
  p.tipo_vinculo                              as vinculo,
  coalesce(p.regimen_pension, 'SIN RÉGIMEN')  as regimen,
  (select fecha_ini || ' a ' || fecha_fin from per) as periodo,
  f.afp                                       as afp_retenida_sin_deberla,
  f.asig                                      as asignacion_familiar_que_cobra,
  p.sueldo_base_legal,
  case
    when p.sueldo_base_legal is not null and coalesce(f.asig, 0) > 0
      then 'LOS DOS: tiene sueldo_base_legal (default 1130) Y cobra asignación familiar'
    when p.sueldo_base_legal is not null
      then 'la básica: sueldo_base_legal quedó con el DEFAULT 1130 en vez de NULL'
    when coalesce(f.asig, 0) > 0
      then 'la asignación familiar: entra a la base sin guarda de vínculo'
    else 'ninguno de los dos — revisar, no debería salir en esta lista'
  end                                         as de_donde_sale,
  case when f.essalud > 0
       then 'Y ADEMÁS EsSalud, que la 0117 sí había apagado — revisar' end as ojo
from filas f
join personas p on p.id = f.persona_id
where p.en_planilla is not true
  and (coalesce(f.afp, 0) <> 0 or coalesce(f.asig, 0) <> 0)
order by f.afp desc;


-- ############################################################################
-- ####  LO QUE NO HACE FALTA COMPROBAR, Y POR QUÉ                          ####
-- ############################################################################
--
-- Acá iba un tercer bloque que comparaba `en_planilla` contra `tipo_vinculo`,
-- por la sospecha de que dos columnas para la misma pregunta terminan
-- contradiciéndose — como ya pasó en este repo con los permisos y con el huso
-- horario de Lima.
--
-- **Se borró porque la sospecha era falsa, y medirlo lo demostró:**
--
--     select generation_expression from information_schema.columns
--      where table_name = 'personas' and column_name = 'en_planilla';
--     → (tipo_vinculo = ANY (ARRAY['planilla'::text, 'prueba'::text]))
--
-- `en_planilla` es una columna GENERADA. No es un segundo dato que alguien
-- pueda escribir distinto: es la misma verdad con otro nombre, y Postgres se
-- encarga de que no puedan separarse. Un bloque que las comparara devolvería
-- cero filas siempre, y un freno que nunca puede sonar enseña que los frenos
-- son decoración.
--
-- Queda escrito en vez de borrado del todo porque la pregunta es razonable y
-- alguien la va a volver a tener. La respuesta es esa consulta de una línea.
