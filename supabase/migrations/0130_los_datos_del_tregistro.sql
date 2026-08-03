-- ============================================================================
-- 0130 — Los datos personales que trae el T-Registro
--
-- QUÉ CARGA. Fecha de nacimiento, correo, celular, estado civil y grado de
-- instrucción de las 10 personas que tienen constancia de alta en el T-Registro
-- (formulario 1604-1, registradas el 21/07/2026). Los valores se transcribieron
-- de esas constancias, leídas del Drive de CAYLA el 2026-08-02.
--
-- LA REGLA QUE ORDENA TODO: se llena lo que falta y se corrige solo lo que está
-- demostrablemente mal. NO se pisa un dato existente que pueda ser más nuevo que
-- el papel.
--
-- ── LO QUE SE CORRIGE, Y POR QUÉ ────────────────────────────────────────────
--
-- RAQUEL TICONA · fecha de nacimiento 2026-01-02 → 1991-01-02.
--   El sistema la tiene naciendo ESTE año. El día y el mes coinciden con la
--   constancia; el año se quedó en el actual, que es la firma de un campo
--   tipeado a mano. Importa porque la fecha de nacimiento va a alimentar el bono
--   de cumpleaños, y porque una edad imposible ensucia cualquier reporte.
--
-- DANIXA VALVERDE · fecha de nacimiento 2005-12-02 → 2005-12-01.
--   Un día de diferencia. Felipe eligió el 2026-08-02 quedarse con la
--   constancia: es el documento oficial y se llenó desde su DNI. No cambia el
--   bono de cumpleaños —los dos caen en diciembre—, así que el único efecto es
--   que la ficha coincida con el papel.
--
-- ── LO QUE NO SE TOCA, Y ES DELIBERADO ──────────────────────────────────────
--
-- EL GRADO DE INSTRUCCIÓN DE QUIEN YA TIENE UNO. El T-Registro dice
-- «EDUCACIÓN SECUNDARIA COMPLETA» en las 10 constancias, porque es lo que se
-- declaró AL CONTRATAR. El sistema tiene datos más nuevos para tres personas:
--
--     Mateo Zárate      Universitario en curso
--     Danitza Gutiérrez superior técnica incompleta
--     Raquel Ticona     superior técnica completa
--
-- La gente estudia después de entrar. Sobreescribir eso con «secundaria
-- completa» sería retroceder el dato, así que el T-Registro solo llena los seis
-- que están en blanco. (De paso: que Mateo y Danitza estén estudiando HOY los
-- hace candidatos de la asignación por educación de la 0120.)
--
-- EL ESTADO CIVIL DE ANGIE CHÁVEZ. El sistema dice «conviviente» y la constancia
-- dice «SOLTERO». Tiene un hijo inscrito como derechohabiente, así que el dato
-- del sistema es el más nuevo y el más probable. Se queda.
--
-- ── LO QUE SE NORMALIZA ─────────────────────────────────────────────────────
-- Tres fichas tienen «Soltero» como texto libre y una tiene «Universitario en
-- curso». Los catálogos de packages/shared usan otros códigos, y la pantalla de
-- Datos Personales marca esos valores con un aviso de «valor antiguo». Se pasan
-- al código del catálogo, que significa exactamente lo mismo escrito distinto:
--
--     'Soltero'                → 'soltera'
--     'Universitario en curso' → 'superior_universitaria_incompleta'
--
-- ── POR QUÉ POR DNI Y NO POR NOMBRE ────────────────────────────────────────
-- El cruce va por `personas.documento`, que desde la 0124 tiene índice único. Un
-- cruce por nombre ya casi produjo un accidente en esta sesión: `apellidos ilike
-- '%Pereyra%'` alcanzaba a tres personas distintas, Felipe incluido.
--
-- NO MUEVE NINGÚN PAGO. Ninguno de estos campos entra en el cálculo de planilla.
-- La fecha de nacimiento habilitará el bono de cumpleaños cuando se conecte, y
-- ahí sí moverá plata — pero ese bono todavía no está automatizado.
--
-- CÓMO SE REVIERTE. No tiene reversa automática: son datos, no estructura. La
-- migración imprime el antes y el después de cada cambio, así que el aviso de la
-- corrida ES el respaldo.
-- ============================================================================

do $mig$
declare
  -- Lo que dicen las 10 constancias del T-Registro.
  v_tr jsonb := '[
    {"dni":"75322651","nac":"2001-11-14","correo":"mateozaratebutron@gmail.com","cel":"986010052"},
    {"dni":"77692125","nac":"2003-05-10","correo":"sashamashafer@gmail.com","cel":"907030067"},
    {"dni":"61324934","nac":"2008-05-30","correo":"luurodh28@gmail.com","cel":"997528091"},
    {"dni":"63347992","nac":"2000-04-22","correo":"joselyngavilan9@gmail.com","cel":"978513927"},
    {"dni":"46763460","nac":"1991-01-02","correo":"rbticonalopez1@gmail.com","cel":"986852563"},
    {"dni":"77035131","nac":"1999-10-07","correo":"achavezhonorio@gmail.com","cel":"939521928"},
    {"dni":"77669479","nac":"2005-12-01","correo":"valverde.danixa20@gmail.com","cel":"932677960"},
    {"dni":"62468006","nac":"2004-01-30","correo":"palaciosdianax@gmail.com","cel":"989196291"},
    {"dni":"74492818","nac":"1998-12-17","correo":"keyramosagui@gmail.com","cel":"950187414"},
    {"dni":"61273109","nac":"2008-01-07","correo":"gutierrezdanitza07@gmail.com","cel":"901559687"}
  ]'::jsonb;

  r          jsonb;
  v_id       uuid;
  v_nombre   text;
  v_antes    text;
  v_no_halla text := '';
  n_cel int := 0; n_correo int := 0; n_nac int := 0; n_civil int := 0; n_instr int := 0;
begin
  for r in select * from jsonb_array_elements(v_tr)
  loop
    select p.id, p.nombres || ' ' || p.apellidos into v_id, v_nombre
    from personas p where p.documento = r->>'dni';

    if v_id is null then
      v_no_halla := v_no_halla || (r->>'dni') || ' ';
      continue;
    end if;

    -- Asegurar que exista la fila de ficha, sin tocar nada de lo que ya tenga.
    insert into datos_personales (persona_id) values (v_id)
    on conflict (persona_id) do nothing;

    -- ── Celular: solo si falta ──────────────────────────────────────────────
    update datos_personales
       set celular = r->>'cel', actualizado_at = now()
     where persona_id = v_id and nullif(btrim(coalesce(celular,'')),'') is null;
    if found then
      n_cel := n_cel + 1;
      raise notice '  % · celular ← %', v_nombre, r->>'cel';
    end if;

    -- ── Correo: solo si falta. Vive en personas, no en la ficha. ────────────
    update personas
       set email = r->>'correo'
     where id = v_id and nullif(btrim(coalesce(email,'')),'') is null;
    if found then
      n_correo := n_correo + 1;
      raise notice '  % · correo ← %', v_nombre, r->>'correo';
    end if;

    -- ── Fecha de nacimiento: se llena si falta, y se CORRIGE si difiere ─────
    -- Acá sí se pisa, porque la constancia es el documento oficial y las dos
    -- diferencias encontradas eran errores demostrables (ver la cabecera).
    select fecha_nacimiento::text into v_antes
    from datos_personales where persona_id = v_id;

    if v_antes is distinct from (r->>'nac') then
      update datos_personales
         set fecha_nacimiento = (r->>'nac')::date, actualizado_at = now()
       where persona_id = v_id;
      n_nac := n_nac + 1;
      raise notice '  % · nacimiento % → %', v_nombre, coalesce(v_antes,'(vacío)'), r->>'nac';
    end if;

    -- ── Estado civil: llenar los vacíos y normalizar el texto libre ─────────
    -- El T-Registro declara SOLTERO en las 10. No se toca a quien ya tenga un
    -- valor del catálogo distinto (el 'conviviente' de Angie).
    update datos_personales
       set estado_civil = 'soltera', actualizado_at = now()
     where persona_id = v_id
       and (nullif(btrim(coalesce(estado_civil,'')),'') is null
            or lower(btrim(estado_civil)) in ('soltero','soltera/o','soltero/a'));
    if found then
      n_civil := n_civil + 1;
      raise notice '  % · estado civil ← soltera', v_nombre;
    end if;

    -- ── Grado de instrucción: SOLO si falta ─────────────────────────────────
    -- No se pisa a quien ya tenga uno: el suyo es más nuevo que el papel.
    update datos_personales
       set grado_instruccion = 'secundaria_completa', actualizado_at = now()
     where persona_id = v_id
       and nullif(btrim(coalesce(grado_instruccion,'')),'') is null;
    if found then
      n_instr := n_instr + 1;
      raise notice '  % · instrucción ← secundaria_completa (lo declarado al contratar)', v_nombre;
    end if;
  end loop;

  -- ── Normalizar el único grado que está como texto libre ──────────────────
  update datos_personales
     set grado_instruccion = 'superior_universitaria_incompleta', actualizado_at = now()
   where lower(btrim(coalesce(grado_instruccion,''))) in
         ('universitario en curso', 'universitaria en curso', 'universitario');
  if found then
    raise notice '  · «Universitario en curso» → superior_universitaria_incompleta';
  end if;

  raise notice '';
  raise notice '0130 · celulares cargados: %  ·  correos: %  ·  nacimientos corregidos: %',
    n_cel, n_correo, n_nac;
  raise notice '0130 · estado civil: %  ·  grado de instruccion: %', n_civil, n_instr;

  if v_no_halla <> '' then
    raise notice '0130 · ⚠ NO se encontro a nadie con estos DNI: %', v_no_halla;
    raise notice '0130 ·   Revisar si el documento esta mal escrito en personas.';
  else
    raise notice '0130 · las 10 personas del T-Registro se encontraron por DNI.';
  end if;
end
$mig$;


insert into migraciones_aplicadas (numero, nombre)
values (130, 'los_datos_del_tregistro')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
