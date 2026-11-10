-- ============================================================================
-- 0616 — La firma de CAYLA en cada documento queda la de su día
-- ============================================================================
--
-- QUÉ PROMETE
--   Que cada documento que firma CAYLA en Dynamic guarde SU copia de la firma
--   de quien firmaba por CAYLA en ese momento, con quién era y con qué cargo, y
--   que se muestre esa —no la de hoy— para siempre. Vale para el contrato de
--   trabajo (`contratos_generados`), la declaración de ruta y la constancia
--   del bono (`documentos_firmados`) y cada versión de la política salarial
--   (`politica_salarial`). Decisión de Felipe, 2026-11-10.
--
--   Y que la confirmación de un contrato de trabajo anote desde qué IP y con
--   qué navegador se firmó, como ya hace la declaración de ruta (0423/0425).
--   También decidido por Felipe ese día («Sí, súmalo»).
--
-- POR QUÉ
--   Hasta hoy la firma de CAYLA se estampaba AL MOSTRAR con `fn_firma_empresa()`
--   (0398), que devuelve la firma ACTUAL de quien figura HOY en
--   `configuracion.firmante_empresa`. El nombre del firmante, en cambio, queda
--   congelado en el texto (el contrato y la política lo llevan escrito). Si
--   mañana cambia el firmante, o redibuja su firma en «Mi firma», todo lo ya
--   firmado muestra otra rúbrica —bajo el nombre de antes, en el contrato—. La
--   firma de la PERSONA ya se congelaba desde la 0402; la de CAYLA solo en la
--   política de movilidad (0531). Esta migración lleva el molde de la 0531 a
--   todo lo demás.
--
--   Importa más de lo que parecía: medido en producción el 2026-11-10, 17 de
--   los 23 contratos vivos se firmaron SOLO en Dynamic (desde la 0430), sin
--   papel detrás. Para ellos lo que se ve en Dynamic es el original, y si
--   alguien niega haber firmado, la prueba es de CAYLA (reglamento de la Ley
--   27269, art. 2-A). Por eso también la IP y el navegador.
--
-- CÓMO SE CONGELA: AL NACER EL DOCUMENTO, CON UN TRIGGER
--   `fn_congelar_firma_empresa()`, BEFORE INSERT en las tres tablas: toma el
--   firmante de `configuracion.firmante_empresa`, su cargo y su firma de
--   `firmas_escaneadas` en ese instante, y lo escribe en la fila. Se eligió el
--   trigger y no reescribir las funciones que crean filas (son siete
--   `insert into contratos_generados` y veinte en `documentos_firmados` a lo
--   largo de las migraciones) porque así ningún camino —una función de mañana,
--   el SQL Editor— puede crear un documento sin su firma congelada, ni con la
--   firma de otra persona: el valor que traiga la fila se pisa, siempre.
--
--   Un contrato que se CORRIGE antes de firmarse (cambia su `documento_html`)
--   vuelve a congelar: el texto nuevo nombra al firmante de hoy. Firmado, ya no.
--   Y nadie la cambia después: el mismo trigger rechaza el UPDATE.
--
-- LO YA FIRMADO (el relleno), con la regla de Felipe
--   «Se copia la firma de hoy solo donde se pueda probar que es la misma.» La
--   firma del firmante se guardó por última vez en `firmas_escaneadas.
--   actualizado_at` (en producción, el 2026-09-08). Se copia si:
--     · contrato: firmado en Dynamic después de esa fecha, o todavía sin firmar
--       (al congelarlo, CAYLA lo firma ahora), y su texto lleva el DNI del
--       firmante de hoy. Uno firmado en papel, solo si se generó después.
--     · declaración de ruta o constancia: firmada en Dynamic después de esa fecha.
--     · política de movilidad del sistema (0531): su `firma_persona` YA es la
--       firma de CAYLA de ese día; se copia tal cual, sin regla.
--     · política salarial: publicada después de esa fecha.
--   Lo demás queda en null: el documento muestra el nombre impreso y la línea
--   en blanco, más honesto que una rúbrica que quizá no fue la de ese día.
--   Medido el 2026-11-10: 0 contratos y 0 rutas firmados antes del 08-09 y 0
--   con otro firmante, así que todo lo firmado en Dynamic recibe la suya; en
--   blanco queda, como mucho, el contrato con escaneo y alguna versión vieja de
--   la política salarial.
--
-- QUÉ ASUME
--   · `configuracion.firmante_empresa` (0147) y `firmas_escaneadas` (0076, su
--     `actualizado_at` y `chk_firma_es_imagen`).
--   · `documentos_firmados.firmante_empresa_id` y su regla
--     `chk_documento_politica_del_sistema` (0531): la regla se reescribe,
--     porque decía que solo la política del sistema tiene firmante.
--   · Que no exista `fn_congelar_firma_empresa`: comprobado con
--     `donde-vive.sh` y en producción (`congelar_ya_existe` = 0).
--
-- CÓMO SE PEGA
--   En UNA pegada, con el molde de la 0604: altera tres tablas en uso, así que
--   toma los tres candados SIN ESPERAR (`nowait`) y, si una está ocupada,
--   deshace el intento y reintenta a los 0.2 s. Nadie queda esperando un
--   candado con otro en la mano, que es lo que cierra un deadlock.
--
-- CÓMO SE REVIERTE
--   drop trigger congelar_firma_empresa on contratos_generados;
--   drop trigger congelar_firma_empresa on documentos_firmados;
--   drop trigger congelar_firma_empresa on politica_salarial;
--   drop function fn_congelar_firma_empresa();
--   Las columnas NO se sueltan: son la evidencia de lo firmado. Las pantallas,
--   sin columna llena, vuelven a la línea en blanco; para volver a la firma de
--   hoy hay que revertir también su código.
-- ============================================================================

set local lock_timeout = '3s';

-- ── 0 · Los candados, sin esperar con ninguno en la mano (molde 0604) ───────
do $$
declare
  v_intentos int := 0;
begin
  loop
    begin
      -- ACCESS EXCLUSIVE de entrada: los `alter table` de abajo lo piden, y
      -- subir después desde un candado menor sería volver a esperar.
      lock table contratos_generados, documentos_firmados, politica_salarial
        in access exclusive mode nowait;
      exit;
    exception when lock_not_available then
      v_intentos := v_intentos + 1;
      if v_intentos >= 50 then
        raise exception 'No se pudieron tomar los candados en 10 s: hay mucho movimiento en este momento. No se aplicó nada; vuelve a pegarla en un rato.';
      end if;
      perform pg_sleep(0.2);
    end;
  end loop;
end $$;


-- ── 1 · Las columnas ────────────────────────────────────────────────────────
alter table contratos_generados
  add column if not exists firma_empresa text,
  add column if not exists firmante_empresa_id uuid references personas(id),
  add column if not exists firmante_empresa_cargo text,
  add column if not exists firma_persona_ip text,
  add column if not exists firma_persona_user_agent text;

alter table documentos_firmados
  add column if not exists firma_empresa text,
  add column if not exists firmante_empresa_cargo text;

alter table politica_salarial
  add column if not exists firma_empresa text,
  add column if not exists firmante_empresa_id uuid references personas(id),
  add column if not exists firmante_empresa_cargo text;

alter table contratos_generados drop constraint if exists chk_contrato_firma_empresa_imagen;
alter table contratos_generados add constraint chk_contrato_firma_empresa_imagen
  check (firma_empresa is null or (firma_empresa ~ '^data:image/(png|jpeg);base64,' and firmante_empresa_id is not null));
alter table documentos_firmados drop constraint if exists chk_documento_firma_empresa_imagen;
alter table documentos_firmados add constraint chk_documento_firma_empresa_imagen
  check (firma_empresa is null or (firma_empresa ~ '^data:image/(png|jpeg);base64,' and firmante_empresa_id is not null));
alter table politica_salarial drop constraint if exists chk_politica_firma_empresa_imagen;
alter table politica_salarial add constraint chk_politica_firma_empresa_imagen
  check (firma_empresa is null or (firma_empresa ~ '^data:image/(png|jpeg);base64,' and firmante_empresa_id is not null));

-- La 0531 decía «solo la política del sistema tiene firmante». Desde hoy todo
-- documento lo tiene; lo que sigue siendo solo de la política del sistema es
-- guardar su texto (`documento_html`), con su firmante y su firma.
alter table documentos_firmados drop constraint if exists chk_documento_politica_del_sistema;
alter table documentos_firmados add constraint chk_documento_politica_del_sistema check (
  documento_html is null
  or (tipo = 'politica' and firmante_empresa_id is not null and firma_persona is not null)
);

comment on column contratos_generados.firma_empresa is
  'La firma de quien firmaba por CAYLA cuando nació el documento (0616): se muestra esta, no la de hoy. Null en lo firmado antes de la 0616 que no se pudo probar (ver la migración).';
comment on column documentos_firmados.firma_empresa is
  'La firma de quien firmaba por CAYLA cuando nació el documento (0616). En la política del sistema (0531) es la misma que firma_persona.';
comment on column politica_salarial.firma_empresa is
  'La firma de quien firmaba por CAYLA al publicar esta versión (0616). El nombre y el cargo ya van dentro de `documento`.';
comment on column contratos_generados.firma_persona_ip is
  'IP desde la que la persona confirmó su firma (cabecera x-forwarded-for, como la 0423). Null en lo confirmado antes de la 0616.';


-- ── 2 · El relleno de lo ya firmado (antes del trigger, para que este no lo frene) ──
drop trigger if exists congelar_firma_empresa on contratos_generados;
drop trigger if exists congelar_firma_empresa on documentos_firmados;
drop trigger if exists congelar_firma_empresa on politica_salarial;

create temp table firma_de_hoy on commit drop as
select p.id as persona_id, p.documento as dni, c.valor ->> 'cargo' as cargo,
       f.imagen, f.actualizado_at
  from configuracion c
  join personas p on p.id = (c.valor ->> 'persona_id')::uuid
  join firmas_escaneadas f on f.persona_id = p.id
 where c.clave = 'firmante_empresa';

update contratos_generados g
   set firma_empresa = h.imagen, firmante_empresa_id = h.persona_id, firmante_empresa_cargo = h.cargo
  from firma_de_hoy h
 where g.firma_empresa is null
   and h.dni is not null and position(btrim(h.dni) in g.documento_html) > 0
   and (g.firma_persona_confirmada_at >= h.actualizado_at
        or (g.firma_persona_confirmada_at is null and g.fecha_firma is null)
        or (g.firma_persona_confirmada_at is null and g.generado_at >= h.actualizado_at));

update documentos_firmados d
   set firma_empresa = h.imagen, firmante_empresa_id = h.persona_id, firmante_empresa_cargo = h.cargo
  from firma_de_hoy h
 where d.firma_empresa is null and d.documento_html is null
   and d.firma_persona_confirmada_at >= h.actualizado_at;

-- La política del sistema (0531) ya guardó la firma de CAYLA de su día en `firma_persona`.
update documentos_firmados d
   set firma_empresa = d.firma_persona
 where d.firma_empresa is null and d.documento_html is not null and d.firmante_empresa_id is not null;

update politica_salarial s
   set firma_empresa = h.imagen, firmante_empresa_id = h.persona_id, firmante_empresa_cargo = h.cargo
  from firma_de_hoy h
 where s.firma_empresa is null and s.publicada_at >= h.actualizado_at;


-- ── 3 · Congelar al nacer, y que nadie la cambie después ───────────────────
-- SECURITY DEFINER a propósito: la firma que se congela tiene que ser la
-- configurada, la escriba quien la escriba. Con los permisos de quien inserta,
-- un camino que corriera como `authenticated` leería `firmas_escaneadas` con su
-- RLS (solo la propia) y congelaría un null sin que nada avisara. No recibe
-- parámetros ni devuelve datos: no abre nada que antes estuviera cerrado.
create or replace function fn_congelar_firma_empresa()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if tg_op = 'UPDATE' then
    -- Un contrato que se corrige antes de firmarse lleva el firmante de HOY en
    -- su texto nuevo: vuelve a congelar. Firmado, ya no se toca.
    if tg_table_name = 'contratos_generados' then
      if new.documento_html is distinct from old.documento_html
         and new.fecha_firma is null and new.firma_persona_confirmada_at is null then
        select h.persona_id, h.cargo, h.imagen
          into new.firmante_empresa_id, new.firmante_empresa_cargo, new.firma_empresa
          from (select p.id as persona_id, c.valor ->> 'cargo' as cargo, f.imagen
                  from configuracion c
                  join personas p on p.id = (c.valor ->> 'persona_id')::uuid
                  left join firmas_escaneadas f on f.persona_id = p.id
                 where c.clave = 'firmante_empresa') h;
        return new;
      end if;
    end if;
    if (new.firma_empresa, new.firmante_empresa_id, new.firmante_empresa_cargo)
       is distinct from (old.firma_empresa, old.firmante_empresa_id, old.firmante_empresa_cargo) then
      raise exception 'La firma de CAYLA de un documento no se cambia: es la de su día.';
    end if;
    return new;
  end if;

  -- INSERT: la de este instante, siempre. Lo que traiga la fila se pisa: nadie
  -- puede crear un documento con la firma de otra persona.
  new.firma_empresa := null;
  new.firmante_empresa_id := null;
  new.firmante_empresa_cargo := null;
  select p.id, c.valor ->> 'cargo', f.imagen
    into new.firmante_empresa_id, new.firmante_empresa_cargo, new.firma_empresa
    from configuracion c
    join personas p on p.id = (c.valor ->> 'persona_id')::uuid
    left join firmas_escaneadas f on f.persona_id = p.id
   where c.clave = 'firmante_empresa';
  return new;
end;
$fn$;

create trigger congelar_firma_empresa
  before insert or update on contratos_generados
  for each row execute function fn_congelar_firma_empresa();
create trigger congelar_firma_empresa
  before insert or update on documentos_firmados
  for each row execute function fn_congelar_firma_empresa();
create trigger congelar_firma_empresa
  before insert or update on politica_salarial
  for each row execute function fn_congelar_firma_empresa();


-- ── 4 · Las tres funciones que leen y firman ────────────────────────────────
-- (PENDIENTE: se escriben con el md5 de producción a la vista.)


insert into migraciones_aplicadas (numero, nombre) values (616, 'la_firma_de_cayla_queda_la_de_su_dia')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
