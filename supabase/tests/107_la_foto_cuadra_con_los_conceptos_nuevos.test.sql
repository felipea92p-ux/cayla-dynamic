-- ============================================================================
-- 107_la_foto_cuadra_con_los_conceptos_nuevos.test.sql
-- ============================================================================
-- Hermana de la 97, que ya cubre que la foto se tome, que sea inmutable y que el
-- sistema avise cuando el cálculo en vivo se desvía. Lo que la 97 NO cubría es
-- que el candado chk_foto_cuadra siga al día con la aritmética del total.
--
-- LO QUE PASÓ, y por eso existe esta prueba. La 0096 escribió el candado con la
-- aritmética de ese momento. Después la 0110 metió al total la movilidad
-- (sumando) y el descuento de pensión (restando), y la 0120 la asignación por
-- educación (sumando). El candado no se actualizó.
--
-- Mientras los tres valían cero no se notaba. Cuando Felipe encendió la
-- movilidad el 29/07 y la 0115 dejó la pensión vigente, «Marcar como PAGADO»
-- empezó a fallar para TODAS las personas: la 97 seguía verde porque su escenario
-- no enciende ninguno de los tres conceptos. La 0127 lo arregló.
--
-- La lección: una prueba que solo ejercita el camino viejo no protege el nuevo.
-- Esta prueba enciende movilidad Y pensión antes de pagar, que es la condición
-- que el sistema tiene en producción desde agosto de 2026.
--
-- Si estás leyendo esto porque acaba de fallar: alguien agregó un concepto al
-- total de fn_planilla_calcular y no lo agregó a planilla_pagada_detalle ni al
-- candado. NO aflojes el candado — es lo único que impide guardar una foto que no
-- se sostiene. Agregá la columna, copiala en fn_planilla_congelar y sumala al
-- CHECK.
-- ============================================================================
begin;
select plan(5);

-- ── Escenario: una persona, un periodo, con movilidad y pensión ENCENDIDAS ───
-- Se usan los datos que ya siembra el repo si existen; si no, la prueba se salta
-- sola en vez de inventar un escenario que no represente nada.
do $armar$
declare v_p uuid; v_per uuid;
begin
  -- Movilidad encendida, como en producción desde el 29/07/2026.
  update parametros_laborales set valor = 10.00
   where clave = 'movilidad_diaria' and vigente_hasta is null;

  -- Y que al menos una persona tenga régimen de pensión, para que el descuento
  -- no salga cero y el escenario ejercite de verdad la resta.
  select id into v_p from personas where estado = 'activo' limit 1;
  if v_p is not null then
    update personas set regimen_pension = 'profuturo'
     where id = v_p and regimen_pension is null;
  end if;
end
$armar$;

-- ── 1 · El candado conoce los tres conceptos ─────────────────────────────────
-- Se lee el texto del CHECK: si alguien agrega un concepto al total y se olvida
-- del candado, esto lo dice antes de que falle un pago real.
select ok(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'chk_foto_cuadra')
    like '%monto_movilidad%',
  'chk_foto_cuadra incluye la movilidad');

select ok(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'chk_foto_cuadra')
    like '%descuento_pension%',
  'chk_foto_cuadra resta el descuento de pensión');

select ok(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'chk_foto_cuadra')
    like '%monto_educacion%',
  'chk_foto_cuadra incluye la asignación por educación');

-- ── 2 · Y el EsSalud NO entra en la suma ─────────────────────────────────────
-- Es aporte del empleador: no se le paga ni se le descuenta a la persona, así que
-- no puede estar en un total que representa lo que recibe. Se guarda como dato.
select ok(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'chk_foto_cuadra')
    not like '%aporte_essalud%',
  'el aporte de EsSalud queda FUERA del total, porque no es plata de la persona');

-- ── 3 · La prueba de fuego: congelar de verdad, con los conceptos encendidos ──
-- fn_planilla_calcular tiene el guard de la 0090, así que hay que prestarle una
-- sesión de admin: sin esto la prueba falla por permiso y no por lo que mide.
select set_config('request.jwt.claim.sub',
  coalesce((select auth_user_id::text from personas
             where rol = 'admin' and auth_user_id is not null limit 1),
           '00000000-0000-0000-0000-000000000000'),
  true);

select lives_ok($$
  do $prueba$
  declare
    v_per uuid;
    v_n int;
    v_mov numeric;
    v_pen numeric;
    v_descuadres int;
  begin
    select id into v_per from periodos_planilla
     where estado <> 'pagado' order by fecha_ini desc limit 1;
    if v_per is null then return; end if;   -- base sin periodo abierto

    -- Esto es lo que reventaba antes de la 0127.
    v_n := fn_planilla_congelar(v_per, 'pago', null);

    select coalesce(sum(monto_movilidad),0), coalesce(sum(descuento_pension),0)
      into v_mov, v_pen
    from planilla_pagada_detalle where periodo_id = v_per;

    -- Que los conceptos hayan llegado de verdad a la foto, y no como ceros: si
    -- llegaran en cero el candado cuadraría igual y la prueba no probaría nada.
    if v_n > 0 and v_mov = 0 and v_pen = 0 then
      raise exception 'La foto se guardó pero movilidad y pensión llegaron en cero: '
        'el escenario no está ejercitando lo que dice ejercitar.';
    end if;

    -- Y que cada fila cuadre con la aritmética completa.
    select count(*) into v_descuadres
    from planilla_pagada_detalle
    where periodo_id = v_per
      and total <> pago_base + monto_feriados + monto_plus + asignacion_familiar
                   + monto_movilidad + monto_educacion - descuento_pension
                   + bonos - descuentos;
    if v_descuadres > 0 then
      raise exception '% fila(s) de la foto no cuadran', v_descuadres;
    end if;
  end
  $prueba$;
$$, 'cerrar un periodo con movilidad y pensión encendidas guarda la foto y cuadra');

select * from finish();
rollback;
