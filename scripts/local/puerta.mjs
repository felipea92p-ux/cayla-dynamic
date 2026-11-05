// «La puerta» del entorno local: lo que en Supabase real hacen Kong + GoTrue, en un solo archivo y sin dependencias.
//
//   /rest/v1/*    → PostgREST, el mismo de producción, con RLS de verdad.
//   /auth/v1/*    → entrar con correo y clave, mantener la sesión, salir, cambiar la clave y administrar cuentas.
//                   La clave se comprueba contra auth.users con pgcrypto, igual que GoTrue. Respeta `banned_until`.
//   /storage/v1/* → no existe aquí: las pantallas que suben fotos o PDF responden un error claro.
//
// Promete: login real contra la base local con las mismas respuestas que la app espera de GoTrue.
// No hace: correos, enlaces mágicos ni OAuth. Un defecto que dependa de GoTrue no se reproduce aquí.
// Solo para esta computadora: escucha en 127.0.0.1 y usa el secreto de desarrollo público de Supabase.
//
// Uso: node puerta.mjs            sirve
//      node puerta.mjs llaves     imprime las llaves para apps/web/.env.local

import http from "node:http";
import crypto from "node:crypto";
import { spawn } from "node:child_process";

const PUERTO = Number(process.env.PUERTA_PUERTO ?? 55892);
const REST = { host: "127.0.0.1", port: Number(process.env.REST_PUERTO ?? 55891) };
const SECRETO = process.env.JWT_SECRET ?? "super-secret-jwt-token-with-at-least-32-characters-long";
const URL_PUBLICA = `http://127.0.0.1:${PUERTO}`;
const VIDA_ACCESO = 3600;
const VIDA_REFRESCO = 60 * 60 * 24 * 30;

const b64 = (x) => Buffer.from(x).toString("base64url");
const firmar = (payload) => {
  const cuerpo = `${b64(JSON.stringify({ alg: "HS256", typ: "JWT" }))}.${b64(JSON.stringify(payload))}`;
  return `${cuerpo}.${crypto.createHmac("sha256", SECRETO).update(cuerpo).digest("base64url")}`;
};
function verificar(token) {
  const partes = (token ?? "").split(".");
  if (partes.length !== 3) return null;
  const esperado = crypto.createHmac("sha256", SECRETO).update(`${partes[0]}.${partes[1]}`).digest();
  const dado = Buffer.from(partes[2], "base64url");
  if (dado.length !== esperado.length || !crypto.timingSafeEqual(dado, esperado)) return null;
  try {
    const p = JSON.parse(Buffer.from(partes[1], "base64url").toString());
    return p.exp && p.exp < Date.now() / 1000 ? null : p;
  } catch {
    return null;
  }
}
const llave = (role) => firmar({ iss: "supabase-local", role, iat: 1700000000, exp: 4102444800 });
if (process.argv[2] === "llaves") {
  console.log(JSON.stringify({ url: URL_PUBLICA, publica: llave("anon"), servicio: llave("service_role") }));
  process.exit(0);
}

// Una consulta por psql: variables con :'nombre' para que nada se arme concatenando texto.
function consulta(sql, variables = {}) {
  return new Promise((ok, mal) => {
    const args = ["-q", "-At", "-v", "ON_ERROR_STOP=1"];
    for (const [k, v] of Object.entries(variables)) args.push("-v", `${k}=${v ?? ""}`);
    const p = spawn("psql", args);
    let salida = "";
    let errores = "";
    p.stdout.on("data", (d) => (salida += d));
    p.stderr.on("data", (d) => (errores += d));
    p.on("close", (codigo) => (codigo === 0 ? ok(salida.trim()) : mal(new Error(errores))));
    p.stdin.end(sql);
  });
}
const FILA = (where) => `select row_to_json(u) from auth.users u where ${where} and deleted_at is null`;
const fila = async (sql, variables) => {
  const s = await consulta(sql, variables);
  return s ? JSON.parse(s.split("\n")[0]) : null;
};

const usuarioJson = (u) => ({
  id: u.id, aud: "authenticated", role: "authenticated", email: u.email, email_confirmed_at: u.email_confirmed_at,
  phone: u.phone ?? "", confirmed_at: u.email_confirmed_at, last_sign_in_at: u.last_sign_in_at,
  app_metadata: u.raw_app_meta_data ?? {}, user_metadata: u.raw_user_meta_data ?? {}, identities: [],
  created_at: u.created_at, updated_at: u.updated_at, is_anonymous: false,
});

function sesionDe(u, sid = crypto.randomUUID()) {
  const ahora = Math.floor(Date.now() / 1000);
  const acceso = firmar({
    iss: `${URL_PUBLICA}/auth/v1`, aud: "authenticated", sub: u.id, iat: ahora, exp: ahora + VIDA_ACCESO, email: u.email,
    phone: u.phone ?? "", app_metadata: u.raw_app_meta_data ?? {}, user_metadata: u.raw_user_meta_data ?? {},
    role: "authenticated", aal: "aal1", amr: [{ method: "password", timestamp: ahora }], session_id: sid, is_anonymous: false,
  });
  const cuerpo = b64(JSON.stringify({ sub: u.id, sid, exp: ahora + VIDA_REFRESCO, r: crypto.randomUUID().slice(0, 8) }));
  const refresco = `${cuerpo}.${crypto.createHmac("sha256", SECRETO).update(cuerpo).digest("base64url")}`;
  return { access_token: acceso, token_type: "bearer", expires_in: VIDA_ACCESO, expires_at: ahora + VIDA_ACCESO, refresh_token: refresco, user: usuarioJson(u) };
}
function leerRefresco(token) {
  const [cuerpo, firma] = (token ?? "").split(".");
  if (!cuerpo || !firma) return null;
  if (firma !== crypto.createHmac("sha256", SECRETO).update(cuerpo).digest("base64url")) return null;
  try {
    const p = JSON.parse(Buffer.from(cuerpo, "base64url").toString());
    return p.exp > Date.now() / 1000 ? p : null;
  } catch {
    return null;
  }
}

function cors(req, res) {
  res.setHeader("Access-Control-Allow-Origin", req.headers.origin ?? "*");
  res.setHeader("Access-Control-Allow-Credentials", "true");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", req.headers["access-control-request-headers"] ?? "*");
  res.setHeader("Access-Control-Max-Age", "600");
  res.setHeader("Access-Control-Expose-Headers", "*");
  res.setHeader("Vary", "Origin");
}
const responder = (res, estado, cuerpo) => {
  res.writeHead(estado, { "Content-Type": "application/json" });
  res.end(cuerpo === undefined ? undefined : JSON.stringify(cuerpo));
};
const error = (res, estado, codigo, msg) => responder(res, estado, { code: estado, error_code: codigo, msg, message: msg, error: codigo, error_description: msg });
const leerCuerpo = (req) => new Promise((ok) => {
  const trozos = [];
  req.on("data", (t) => trozos.push(t));
  req.on("end", () => {
    try { ok(JSON.parse(Buffer.concat(trozos).toString() || "{}")); } catch { ok({}); }
  });
});
const bearer = (req) => (req.headers.authorization ?? "").replace(/^Bearer\s+/i, "");
const usuarioPorId = (id) => fila(`${FILA("id = :'id'::uuid")};`, { id });

async function auth(req, res, ruta, url) {
  const metodo = req.method;

  if (ruta === "/token" && metodo === "POST") {
    const tipo = url.searchParams.get("grant_type");
    const c = await leerCuerpo(req);
    if (tipo === "password") {
      const candidato = await fila(`${FILA("lower(email) = lower(:'correo')")};`, { correo: String(c.email ?? "") });
      if (candidato?.banned_until && new Date(candidato.banned_until) > new Date()) {
        return error(res, 400, "user_banned", "User is banned");
      }
      const u = await fila(`
        with h as (update auth.users set last_sign_in_at = now()
                    where lower(email) = lower(:'correo') and deleted_at is null
                      and encrypted_password = crypt(:'clave', encrypted_password) returning *)
        select row_to_json(h) from h;`, { correo: String(c.email ?? ""), clave: String(c.password ?? "") });
      if (!u) return error(res, 400, "invalid_credentials", "Invalid login credentials");
      return responder(res, 200, sesionDe(u));
    }
    if (tipo === "refresh_token") {
      const r = leerRefresco(c.refresh_token);
      const u = r && (await usuarioPorId(r.sub));
      if (!u) return error(res, 400, "refresh_token_not_found", "Invalid Refresh Token: Refresh Token Not Found");
      if (u.banned_until && new Date(u.banned_until) > new Date()) return error(res, 400, "user_banned", "User is banned");
      return responder(res, 200, sesionDe(u, r.sid));
    }
    return error(res, 400, "unsupported_grant_type", "En local solo hay password y refresh_token");
  }

  if (ruta === "/user" && (metodo === "GET" || metodo === "PUT")) {
    const t = verificar(bearer(req));
    if (!t || t.role !== "authenticated" || !t.sub) return error(res, 401, "bad_jwt", "invalid JWT: unable to parse or verify signature");
    let u = await usuarioPorId(t.sub);
    if (!u) return error(res, 403, "user_not_found", "User from sub claim in JWT does not exist");
    if (metodo === "PUT") {
      const c = await leerCuerpo(req);
      if (c.password) await consulta(`update auth.users set encrypted_password = crypt(:'clave', gen_salt('bf', 4)), updated_at = now() where id = :'id'::uuid;`, { clave: String(c.password), id: u.id });
      if (c.email) await consulta(`update auth.users set email = :'correo', updated_at = now() where id = :'id'::uuid;`, { correo: String(c.email), id: u.id });
      u = await usuarioPorId(u.id);
    }
    return responder(res, 200, usuarioJson(u));
  }

  if (ruta === "/logout" && metodo === "POST") return responder(res, 204);
  if (ruta === "/recover" && metodo === "POST") return responder(res, 200, {}); // el correo no sale: en local no hay correo
  if (ruta === "/.well-known/jwks.json") return responder(res, 200, { keys: [] });
  if (ruta === "/settings") return responder(res, 200, { external: { email: true }, disable_signup: true, mailer_autoconfirm: true });

  if (ruta.startsWith("/admin/users")) {
    const t = verificar(bearer(req));
    if (!t || t.role !== "service_role") return error(res, 403, "not_admin", "User not allowed");
    const id = ruta.split("/")[3];
    if (!id && metodo === "POST") {
      const c = await leerCuerpo(req);
      if (!c.email) return error(res, 422, "validation_failed", "Falta el correo");
      const ya = await consulta(`select 1 from auth.users where lower(email) = lower(:'correo');`, { correo: c.email });
      if (ya) return error(res, 422, "email_exists", "A user with this email address has already been registered");
      const u = await fila(`
        with h as (insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
          values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated', :'correo',
                  crypt(:'clave', gen_salt('bf', 4)), now(), '{"provider":"email","providers":["email"]}', '{}') returning *)
        select row_to_json(h) from h;`, { correo: c.email, clave: String(c.password ?? crypto.randomUUID()) });
      return responder(res, 200, usuarioJson(u));
    }
    if (id && metodo === "GET") {
      const u = await usuarioPorId(id);
      return u ? responder(res, 200, usuarioJson(u)) : error(res, 404, "user_not_found", "User not found");
    }
    if (id && metodo === "PUT") {
      if (!(await usuarioPorId(id))) return error(res, 404, "user_not_found", "User not found");
      const c = await leerCuerpo(req);
      if (c.password) await consulta(`update auth.users set encrypted_password = crypt(:'clave', gen_salt('bf', 4)), updated_at = now() where id = :'id'::uuid;`, { clave: String(c.password), id });
      if (c.email) await consulta(`update auth.users set email = :'correo', updated_at = now() where id = :'id'::uuid;`, { correo: String(c.email), id });
      if (c.ban_duration === "none") await consulta(`update auth.users set banned_until = null where id = :'id'::uuid;`, { id });
      else if (c.ban_duration) await consulta(`update auth.users set banned_until = now() + interval '100 years' where id = :'id'::uuid;`, { id });
      return responder(res, 200, usuarioJson(await usuarioPorId(id)));
    }
    if (id && metodo === "DELETE") {
      await consulta(`delete from auth.users where id = :'id'::uuid;`, { id });
      return responder(res, 200, {});
    }
  }
  return error(res, 501, "not_implemented", `El entorno local no implementa ${metodo} /auth/v1${ruta} (correo, enlaces mágicos y OAuth no existen aquí)`);
}

function aRest(req, res, ruta, url) {
  const cabeceras = { ...req.headers, host: `${REST.host}:${REST.port}` };
  delete cabeceras.origin;
  const salida = http.request({ ...REST, method: req.method, path: ruta + url.search, headers: cabeceras }, (r) => {
    res.writeHead(r.statusCode ?? 502, r.headers);
    r.pipe(res);
  });
  salida.on("error", () => error(res, 502, "rest_caido", "PostgREST no responde: corre scripts/local/arrancar.sh"));
  req.pipe(salida);
}

http.createServer(async (req, res) => {
  cors(req, res);
  if (req.method === "OPTIONS") return responder(res, 204);
  const url = new URL(req.url ?? "/", URL_PUBLICA);
  try {
    if (url.pathname.startsWith("/auth/v1")) return await auth(req, res, url.pathname.slice("/auth/v1".length) || "/", url);
    if (url.pathname.startsWith("/rest/v1")) return aRest(req, res, url.pathname.slice("/rest/v1".length) || "/", url);
    if (url.pathname.startsWith("/storage/v1")) return error(res, 501, "storage_apagado", "En el entorno local no hay almacenamiento de archivos");
    if (url.pathname === "/salud") return responder(res, 200, { ok: true, base: await consulta("select 1;") });
    return error(res, 404, "not_found", "Ruta desconocida");
  } catch (e) {
    console.error(new Date().toISOString(), req.method, req.url, e?.message ?? e);
    if (!res.headersSent) error(res, 500, "unexpected_failure", String(e?.message ?? e));
  }
}).listen(PUERTO, "127.0.0.1", () => console.log(`puerta lista en ${URL_PUBLICA}`));
