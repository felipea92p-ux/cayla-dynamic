-- ############################################################################
-- ####  ESTE ES EL ARCHIVO QUE SE PEGA EN EL SQL EDITOR DE SUPABASE.      ####
-- ############################################################################
--
-- arreglar_firmante_y_ver_provisiones.sql
--
-- Dos cosas, en este orden:
--
--   A · ARREGLA que tu firma no se esté estampando. La migración 0147 corrió
--       (su trigger existe) pero su arranque no encontró a nadie: busca a quien
--       se llame «Alvarez Pereyra Felipe Miguel» comparando apellidos + nombres,
--       y en la ficha real eso está escrito de otra forma. Resultado: los
--       documentos salen con la raya en blanco.
--
--       No adivina. Si encuentra EXACTAMENTE una persona admin activa llamada
--       Felipe, la deja como firmante. Si encuentra cero o varias, NO toca nada
--       y te muestra la lista para que elijas.
--
--   B · LEE, sin cambiar nada, si las provisiones ya descuentan los cinco
--       desembolsos de CTS de mayo que están registrados.
--
-- ############################################################################

begin;

-- ── A · El firmante ─────────────────────────────────────────────────────────
do $$
declare
  v_id     uuid;
  v_cuenta int;
begin
  if exists (select 1 from configuracion where clave = 'firmante_empresa') then
    raise notice 'A · Ya había un firmante guardado. No se toca.';
    return;
  end if;

  -- En dos pasos, no en uno: `min()` no existe para uuid en Postgres, y contar
  -- primero es además lo que hace que esto no adivine — solo elige cuando hay
  -- exactamente una candidata.
  select count(*) into v_cuenta
  from personas p
  where p.estado = 'activo'
    and p.rol in ('admin', 'lider_do')
    and translate(lower(p.nombres), 'áéíóúüñ', 'aeiouun') like '%felipe%';

  if v_cuenta = 1 then
    select p.id into v_id
    from personas p
    where p.estado = 'activo'
      and p.rol in ('admin', 'lider_do')
      and translate(lower(p.nombres), 'áéíóúüñ', 'aeiouun') like '%felipe%';

    -- El trigger de la 0147 valida que exista, esté activa y pueda firmar.
    -- Si algo de eso fallara, esto revienta y la transacción entera se deshace.
    insert into configuracion (clave, valor, descripcion)
    values ('firmante_empresa',
            jsonb_build_object('persona_id', v_id, 'cargo', 'Gerencia General'),
            'Quién firma los documentos que emite CAYLA. Las pantallas leen de acá el '
            'nombre que imprimen y solo estampan la firma escaneada si quien imprime es '
            'esta persona. Ver migración 0147.');
    raise notice 'A · Firmante fijado. Tu firma vuelve a estamparse en los documentos.';
  elsif v_cuenta = 0 then
    raise notice 'A · NO se encontró ninguna cuenta admin activa con «Felipe» en el nombre. Mira la lista de abajo.';
  else
    raise notice 'A · Hay % cuentas admin con «Felipe» en el nombre. No se elige sola: mira la lista de abajo.', v_cuenta;
  end if;
end $$;

commit;

-- ############################################################################
-- Lo de abajo SOLO LEE. Va después del commit para que un error suyo no pueda
-- deshacer el arreglo de arriba.
-- ############################################################################

-- ── El resultado de A, y la lista por si hubo que elegir ────────────────────
select 'A · RESULTADO' as bloque,
       coalesce(
         (select p.apellidos || ', ' || p.nombres
            from configuracion c
            join personas p on p.id = (c.valor ->> 'persona_id')::uuid
           where c.clave = 'firmante_empresa'),
         'SIN FIRMANTE — elige de la lista de abajo') as quien_firma;

select 'A · CANDIDATOS (por si hubo que elegir)' as bloque,
       p.id as persona_id, p.apellidos, p.nombres, p.rol
from personas p
where p.estado = 'activo' and p.rol in ('admin','lider_do')
order by p.apellidos;

-- ── B · ¿Las provisiones ya descuentan lo desembolsado? ─────────────────────
-- fn_provisiones exige sesión de admin y el SQL Editor no la tiene, así que se
-- le presta una. Solo para esta consulta.
select set_config('request.jwt.claim.sub',
  (select auth_user_id::text from personas
    where rol = 'admin' and auth_user_id is not null limit 1), true) as _sesion_prestada;

-- Devuelve la fila de provisiones TAL CUAL de las cinco personas que tienen un
-- desembolso registrado, sin suponer cómo se llaman sus campos. Al lado, lo que
-- el libro dice que ya se les entregó.
--
-- LA PREGUNTA QUE RESPONDE: si en esa fila la CTS de esas personas sigue
-- acumulando como si no se hubiera pagado, entonces el número que va al contador
-- está inflado — el depósito de mayo salió por PLAME, no como movimiento de
-- planilla, y la 0123 solo sabe mirar los movimientos de planilla.
select d.ventana || ' ' || d.anio || ' · S/ ' || to_char(d.monto, 'FM999999.00')
         || ' por ' || d.origen                     as lo_que_dice_el_libro,
       d.fecha_pago,
       prov.fila                                    as lo_que_dicen_las_provisiones
from desembolsos_beneficios d
left join lateral (
  select e as fila
  from jsonb_array_elements(fn_provisiones(current_date) -> 'personas') e
  where (e ->> 'persona_id')::uuid = d.persona_id
  limit 1
) prov on true
order by d.fecha_pago, d.ventana;
