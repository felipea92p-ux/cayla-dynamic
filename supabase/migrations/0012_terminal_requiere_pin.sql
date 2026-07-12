-- PIN opcional por terminal. En sedes de confianza (ej. Trujillo) se marca con
-- solo tocar el nombre, sin PIN, para no restar tiempo. La confirmación de 3
-- segundos sigue protegiendo contra toques accidentales.
alter table terminales add column requiere_pin boolean not null default true;
