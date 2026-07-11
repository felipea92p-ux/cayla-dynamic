-- Correo de contacto por persona (para la futura app personal y notificaciones).
-- Distinto de auth.users.email: solo admins/supervisores tienen login; este campo
-- es el correo de contacto de CUALQUIER integrante.
alter table personas add column email text unique;
