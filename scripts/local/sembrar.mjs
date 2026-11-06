// Datos INVENTADOS para el entorno local. Nadie de aquí existe: ni nombres, ni DNI, ni sueldos, ni firmas.
// Nunca copiar datos de producción a este archivo.
//
// Promete: una cuenta por rol, las cuatro sedes y los casos que rompen pantallas: nombre larguísimo, nombre de
// dos letras, persona sin ningún dato, de baja, en vacaciones, en descanso médico, por recibos, practicante y
// en preselección; un periodo de febrero, uno de 20 días, y documentos firmados para mirar la firma en oscuro.
// Asume: la base recién migrada (crear-base.sh) y `psql` en el PATH. Es determinista: lo mismo cada vez.
//
// `--solo-marcas` agrega las marcas de los días que falten hasta hoy, para que el Dashboard no se quede en el
// día en que se creó la base. Lo llama arrancar.sh.

import { spawnSync } from "node:child_process";
import sharp from "sharp";

const CLAVE = "Colibri-Local-2026"; // cumple la regla de clave fuerte: sin ella, las cuentas con poder no pasan de la pantalla «Nueva clave»
const ZONA = "-05"; // Perú no cambia de hora: alcanza con el desplazamiento fijo.

const ahoraLima = new Date(Date.now() - 5 * 3600 * 1000);
const fecha = (d) => d.toISOString().slice(0, 10);
const HOY = fecha(ahoraLima);
const sumarDias = (iso, n) => fecha(new Date(Date.parse(iso) + n * 86400000));
const esc = (s) => (s === null || s === undefined ? "null" : `'${String(s).replaceAll("'", "''")}'`);

function psql(sql) {
  const r = spawnSync("psql", ["-q", "-v", "ON_ERROR_STOP=1", "-At"], { input: sql, encoding: "utf8", maxBuffer: 1 << 28 });
  if (r.status !== 0) {
    console.error(r.stderr);
    process.exit(1);
  }
  return r.stdout.trim();
}

// Un azar con semilla: las mismas tardanzas y faltas en cada reconstrucción.
function azar(semilla) {
  let h = 2166136261;
  for (const c of semilla) h = Math.imul(h ^ c.charCodeAt(0), 16777619);
  return () => {
    h = Math.imul(h ^ (h >>> 15), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    h ^= h >>> 16;
    return (h >>> 0) / 4294967296;
  };
}

const DIAS_TIENDA = [0, 2, 3, 4, 5, 6]; // Trujillo trabaja domingo y descansa lunes: 6 días, 7.5 h.
const DIAS_OFICINA = [1, 2, 3, 4, 5]; // Lima, Arequipa y Central: 5 días, 9 h.

const PERSONAS = [
  { n: "Alma", a: "Reyes Soto", s: "CCO", rol: "admin", correo: "admin@dynamic.local", cargo: "Dirección general", rango: "archicaylo", sueldo: 4800, direccion: true },
  { n: "Dana", a: "Vargas Pino", s: "CCO", rol: "lider_do", correo: "do@dynamic.local", cargo: "Líder de Desarrollo Organizacional", rango: "oraculo", sueldo: 3600, area: "desarrollo_organizacional" },
  { n: "Vera", a: "Ampuero Lazo", s: "CCO", cargo: "Asistente administrativa", rango: "support", sueldo: 1900, area: "estrategia_comercial" },

  { n: "Luz", a: "Quispe Rojas", s: "TRU", rol: "supervisor_sede", correo: "lider@dynamic.local", cargo: "Líder de equipo", rango: "aurora", sueldo: 2700, piso: true },
  { n: "Ana", a: "Torres Ruiz", s: "TRU", correo: "integrante@dynamic.local", cargo: "Asesora de experiencia", rango: "cayla", sueldo: 1850 },
  { n: "Rosa", a: "Medina Paz", s: "TRU", cargo: "Asesora de experiencia", rango: "cayla", sueldo: 1730 },
  { n: "Elena", a: "Ríos Vega", s: "TRU", cargo: "Asesora de experiencia", rango: "colibri", sueldo: 1500 },
  { n: "Marta", a: "Silva León", s: "TRU", cargo: "Visual", rango: "colibri", sueldo: 1500 },
  // El nombre que rompe tablas, fichas, papeles y casillas del terminal.
  { n: "María de los Ángeles Concepción", a: "Villanueva-Santisteban de la Puente Arredondo y Zegarra", s: "TRU", cargo: "Asesora senior de experiencia y comunidad de marca", rango: "cayla", sueldo: 2100, correo: "nombre.largo@dynamic.local" },

  { n: "Carmen", a: "Vega Núñez", s: "AQP", rol: "supervisor_sede", correo: "lider.aqp@dynamic.local", cargo: "Líder de equipo", rango: "aurora", sueldo: 2600, piso: true },
  { n: "Julia", a: "Paredes Cruz", s: "AQP", cargo: "Asesora de experiencia", rango: "cayla", sueldo: 1700 },
  { n: "Sofía", a: "Núñez Ortiz", s: "AQP", cargo: "Asesora de experiencia", rango: "colibri", sueldo: 1500 },
  { n: "Li", a: "Wu", s: "AQP", cargo: "Caja", rango: "colibri", sueldo: 1500 }, // el nombre más corto
  { n: "Ñusta", a: "Huamán Ccori", s: "AQP", cargo: "Asesora de experiencia", rango: "cayla", sueldo: 1650 },

  { n: "Teresa", a: "Flores Mamani", s: "LIM", rol: "supervisor_sede", correo: "lider.lim@dynamic.local", cargo: "Líder de equipo", rango: "aurora", sueldo: 2800, area: "taller_produccion" },
  { n: "Pedro", a: "Campos Salas", s: "LIM", cargo: "Cortador", rango: "cayla", sueldo: 2000, area: "taller_produccion" },
  { n: "Iván", a: "Ramos Díaz", s: "LIM", cargo: "Costurero", rango: "cayla", sueldo: 1800, area: "taller_produccion" },
  { n: "Nora", a: "Chávez Tello", s: "LIM", cargo: "Acabados", rango: "colibri", sueldo: 1500, area: "taller_produccion" },

  // Vínculos que se pagan distinto y que algunas pantallas tratan aparte.
  { n: "Bruno", a: "Rojas Prado", s: "CCO", cargo: "Consultor por recibos", vinculo: "rxh", sinHorario: true, sueldo: 2500, rango: "support" },
  { n: "Camila", a: "Pérez Luna", s: "TRU", cargo: "Practicante", vinculo: "practicante", modalidad: "preprofesional", sueldo: 1100, rango: "colibri" },
  { n: "Gina", a: "Soto Vera", s: "AQP", cargo: "Asesora en preselección", vinculo: "prueba", sueldo: 1500, rango: "colibri", ingreso: -12 },

  // Quien acaba de entrar: sin horario, sin marcas, sin sueldo, sin nada. Toda pantalla tiene que soportarla.
  { n: "Nadia", a: "Sin Datos", s: "TRU", correo: "sin.datos@dynamic.local", vacia: true, ingreso: 0 },
];

const terminales = ["TRU", "LIM", "AQP", "CCO"];

function firmaSvg(trazos) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="420" height="140"><g fill="none" stroke="#1a1a18" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round">${trazos.map((d) => `<path d="${d}"/>`).join("")}</g></svg>`;
}
// Firmas dibujadas para esta prueba: tinta #1a1a18 sobre fondo TRANSPARENTE, igual que las que guarda FirmaEditor.
async function firmaPng(trazos) {
  const png = await sharp(Buffer.from(firmaSvg(trazos))).png().toBuffer();
  return `data:image/png;base64,${png.toString("base64")}`;
}

// La fila de una persona, con su cuenta si trae correo.
function sqlPersona(p, { ingreso, dni, pension }) {
  return `
      with cuenta as (
        insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
        select '00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated', ${esc(p.correo)},
               crypt(${esc(CLAVE)}, gen_salt('bf', 4)), now(), '{"provider":"email","providers":["email"]}', '{}'
        where ${esc(p.correo)} is not null
        returning id
      )
      insert into personas (nombres, apellidos, documento, tipo_documento, sede_base_id, rol, pin_hash, fecha_ingreso, auth_user_id, email,
                            funcion, es_encargada_piso, tipo_vinculo, practicante_modalidad, cargo, personal_direccion, sueldo_fijo,
                            regimen_pension, jornada_semanal_horas)
      values (${esc(p.n)}, ${esc(p.a)}, ${p.vacia ? "null" : esc(dni)}, ${p.vacia ? "null" : "'dni'"},
              (select id from sedes where codigo = ${esc(p.s)}), ${esc(p.rol ?? "integrante")}::rol_usuario,
              crypt('1234', gen_salt('bf', 4)), ${esc(ingreso)},
              (select id from cuenta), ${esc(p.correo)}, ${esc(p.area ?? "calidad_servicio")}, ${p.piso ? "true" : "false"},
              ${esc(p.vinculo ?? "planilla")}, ${esc(p.modalidad ?? null)}, ${esc(p.cargo ?? null)}, ${p.direccion ? "true" : "false"}, ${p.direccion ? "true" : "false"},
              ${esc(pension)},
              ${p.vinculo === "rxh" || p.vacia ? "null" : "45"});
    `;
}

// Salario, horario y datos personales: lo que hace falta para calcularle un pago a alguien.
function sqlFicha(p, id, ALMA, i) {
  const desde = `(select fecha_ingreso from personas where id = ${esc(id)})`;
  let sql = `
      insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, asignado_por)
      values (${esc(id)}, ${esc(p.rango)}, ${p.sueldo}, ${desde}, ${esc(ALMA)});
      insert into tarifas_hora (persona_id, vigente_desde, tarifa_hora_soles, creado_por)
      values (${esc(id)}, ${desde}, ${(p.sueldo / 195).toFixed(2)}, ${esc(ALMA)});
    `;
  if (!p.sinHorario) {
    const tienda = p.s === "TRU";
    sql += `
        insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables, horas_semana_objetivo)
        values (${esc(id)}, ${desde}, '10:00', ${tienda ? "'18:30'" : "'20:00'"}, '{${(tienda ? DIAS_TIENDA : DIAS_OFICINA).join(",")}}', 45);
      `;
  }
  sql += `
      insert into datos_personales (persona_id, nombre_dni, fecha_nacimiento, estado_civil, direccion, celular, grado_instruccion, emergencia_nombre, emergencia_vinculo, emergencia_telefono, genero)
      values (${esc(id)}, ${esc(`${p.n} ${p.a}`.toUpperCase())}, ${esc(`199${i % 10}-${String((i % 12) + 1).padStart(2, "0")}-15`)},
              'soltera', 'Calle Inventada 123', '900000000', 'Superior', 'Contacto Inventado', 'Hermana', '900000001', 'femenino');
    `;
  return sql;
}

async function sembrarTodo() {
  // ── Sedes: las migraciones crean tres con sus nombres viejos. Central se sumó después.
  psql(`
    update sedes set nombre = 'Tienda TRU', tipo = 'tienda', ciudad = 'Trujillo' where codigo = 'TRU';
    update sedes set nombre = 'Taller LIM', tipo = 'taller', ciudad = 'Lima' where codigo = 'LIM';
    update sedes set nombre = 'Tienda AQP', tipo = 'tienda', ciudad = 'Arequipa' where codigo = 'AQP';
    insert into sedes (codigo, nombre, tipo, ciudad) values ('CCO', 'Central', 'central', 'Lima');
  `);

  // ── Cuentas y personas.
  let sql = "begin;\n";
  PERSONAS.forEach((p, i) => {
    sql += sqlPersona(p, {
      ingreso: p.ingreso !== undefined ? sumarDias(HOY, p.ingreso) : sumarDias(HOY, -420 - i * 13),
      dni: String(70000000 + i * 137).padStart(8, "0"),
      pension: p.vacia || p.vinculo === "rxh" || p.vinculo === "practicante" ? null : ["onp", "prima", "integra"][i % 3],
    });
  });
  sql += "commit;\n";
  psql(sql);

  const ids = Object.fromEntries(
    psql("select nombres || '|' || id from personas").split("\n").map((l) => l.split("|")),
  );
  const yo = (nombre) => ids[nombre];
  const ALMA = yo("Alma");

  // ── Terminales: una cuenta por sede, para entrar al marcaje con login real.
  psql(terminales.map((c) => `
    with cuenta as (
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
      values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated', ${esc(`terminal-${c.toLowerCase()}@dynamic.local`)},
              crypt(${esc(CLAVE)}, gen_salt('bf', 4)), now(), '{"provider":"email","providers":["email"]}', '{}')
      returning id)
    insert into terminales (sede_id, nombre_dispositivo, auth_user_id)
    select (select id from sedes where codigo = ${esc(c)}), ${esc(`Mac mini ${c}`)}, id from cuenta;
  `).join("\n"));

  // ── Salario, horario y lo que hace falta para calcular una planilla.
  let base = "begin;\n";
  PERSONAS.forEach((p, i) => {
    if (!p.vacia) base += sqlFicha(p, yo(p.n), ALMA, i);
  });
  base += "commit;\n";
  psql(base);

  // ── Periodos: dos anteriores, el abierto, y dos meses raros (febrero y uno de 20 días, el mínimo que la base admite).
  const [anio, mes, dia] = HOY.split("-").map(Number);
  const inicioActual = dia >= 29 ? new Date(Date.UTC(anio, mes - 1, 29)) : new Date(Date.UTC(anio, mes - 2, 29));
  const finDe = (d) => fecha(new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 28)));
  const atras = (d, n) => new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() - n, 29));
  psql(`
    insert into periodos_planilla (fecha_ini, fecha_fin, creado_por) values
      ('2026-01-29', '2026-02-28', ${esc(ALMA)}),
      ('2026-03-01', '2026-03-20', ${esc(ALMA)}),
      (${esc(fecha(atras(inicioActual, 2)))}, ${esc(finDe(atras(inicioActual, 2)))}, ${esc(ALMA)}),
      (${esc(fecha(atras(inicioActual, 1)))}, ${esc(finDe(atras(inicioActual, 1)))}, ${esc(ALMA)}),
      (${esc(fecha(inicioActual))}, ${esc(finDe(inicioActual))}, ${esc(ALMA)});
  `);

  const marcas = sembrarMarcas(sumarDias(HOY, -100));
  console.log(`Marcas: ${marcas}`);

  // ── Ausencias y pedidos: quien está de vacaciones, quien tiene descanso médico y una solicitud por responder.
  psql(`
    insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, aprobada_por, aprobada_at, registrada_por)
    values (${esc(yo("Ñusta"))}, 'vacaciones', ${esc(sumarDias(HOY, -3))}, ${esc(sumarDias(HOY, 9))}, 'Vacaciones programadas', ${esc(ALMA)}, now(), ${esc(ALMA)}),
           (${esc(yo("Nora"))}, 'descanso_medico', ${esc(sumarDias(HOY, -2))}, ${esc(sumarDias(HOY, 3))}, 'Descanso médico', ${esc(ALMA)}, now(), ${esc(ALMA)});
    insert into solicitudes_vacaciones (persona_id, fecha_inicio, fecha_fin, comentario)
    values (${esc(yo("Ana"))}, ${esc(sumarDias(HOY, 20))}, ${esc(sumarDias(HOY, 26))}, 'Viaje familiar, si se puede'),
           (${esc(yo("María de los Ángeles Concepción"))}, ${esc(sumarDias(HOY, 30))}, ${esc(sumarDias(HOY, 44))}, 'Un comentario largo a propósito para ver cómo se comporta el renglón cuando alguien escribe más de lo que la pantalla esperaba que escribiera.');
    insert into anuncios (titulo, cuerpo, publicado_por)
    values ('Reunión de equipo el viernes', 'Nos vemos a las 9:00 en la sede.', ${esc(ALMA)}),
           ('Un anuncio con un título bastante más largo de lo normal para ver cómo se parte en dos o tres renglones en el teléfono', 'Texto inventado para probar la lectura de un anuncio largo. Segundo párrafo, también inventado.', ${esc(ALMA)});
  `);

  await sembrarFirmados(yo, ALMA);
  console.log(`Periodos pagados: ${pagarPeriodosAnteriores()}`);

  console.log(`Datos inventados listos: ${PERSONAS.length} personas, ${terminales.length} terminales.`);
  console.log(`Clave de todas las cuentas: ${CLAVE}`);
  for (const p of PERSONAS.filter((x) => x.correo)) console.log(`  ${p.correo.padEnd(28)} ${p.rol ?? "integrante"}`);
}

function sembrarMarcas(desde) {
  const personas = psql(`
    select p.id || '|' || s.codigo || '|' || p.fecha_ingreso || '|' || s.id || '|' || p.nombres
      from personas p join sedes s on s.id = p.sede_base_id
      join horarios_asignados h on h.persona_id = p.id
     where p.estado = 'activo'`).split("\n").filter(Boolean);
  const finHoy = ahoraLima.getUTCHours() * 60 + ahoraLima.getUTCMinutes();
  const filas = [];
  for (const linea of personas) {
    const [id, sede, ingreso, sedeId, nombre] = linea.split("|");
    const dias = sede === "TRU" ? DIAS_TIENDA : DIAS_OFICINA;
    const finJornada = sede === "TRU" ? 18 * 60 + 30 : 20 * 60;
    for (let d = desde; d <= HOY; d = sumarDias(d, 1)) {
      if (d < ingreso) continue;
      const dow = new Date(`${d}T12:00:00Z`).getUTCDay();
      if (!dias.includes(dow)) continue;
      const r = azar(`${id}${d}`);
      if (r() < 0.03) continue; // una falta de vez en cuando
      const tarde = r() < 0.12 ? Math.floor(r() * 40) + 3 : -Math.floor(r() * 8);
      const entrada = 600 + tarde;
      const almuerzo = 13 * 60 + Math.floor(r() * 45);
      const hora = (m) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}:00`;
      const marca = (tipo, min) => {
        if (d === HOY && min > finHoy) return; // lo que todavía no pasó hoy, no se marca
        filas.push(`(gen_random_uuid(), ${esc(id)}, ${esc(sedeId)}, ${esc(tipo)}::tipo_marca, '${d} ${hora(min)}${ZONA}', 'terminal')`);
      };
      marca("entrada", entrada);
      marca("salida_almuerzo", almuerzo);
      marca("retorno_almuerzo", almuerzo + 45 + Math.floor(r() * 25));
      // Alguien olvida marcar la salida: esa jornada queda para Correcciones.
      if (!(nombre === "Rosa" && d === sumarDias(HOY, -2))) marca("salida_final", finJornada + Math.floor(r() * 12));
    }
  }
  if (filas.length === 0) return 0;
  // Por tandas: la base recalcula la jornada con cada marca.
  for (let i = 0; i < filas.length; i += 500) {
    psql(`begin; insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen) values ${filas.slice(i, i + 500).join(",\n")}; commit;`);
  }
  return filas.length;
}

async function sembrarFirmados(yo, ALMA) {
  const firmaAlma = await firmaPng(["M20 90 C60 10 90 10 80 70 C75 110 40 120 60 80 C90 40 140 50 130 90 C125 110 170 60 200 70 C230 80 220 110 260 90 C300 70 340 60 400 80"]);
  const firmaAna = await firmaPng(["M30 60 C50 110 70 110 90 50 C100 30 110 100 140 90 C170 80 160 40 190 60 C210 75 230 100 270 70", "M60 120 C150 100 260 110 380 90"]);
  const firmaRosa = await firmaPng(["M40 100 C40 30 90 30 90 60 C90 90 50 80 60 70 C100 110 130 110 150 70 C170 40 190 80 220 70 C260 60 300 90 350 60"]);
  const ANA = yo("Ana");
  const ROSA = yo("Rosa");
  const LUZ = yo("Luz");
  const TRU = "(select id from sedes where codigo = 'TRU')";

  const contrato = (nombre, dni) => `<div class="contrato">
  <h1>CONTRATO DE TRABAJO A PLAZO FIJO</h1>
  <p>Documento inventado para el entorno local. Conste por el presente, entre CAYLA y ${nombre}, identificada con DNI N.° ${dni}.</p>
  <p><strong>PRIMERA.</strong> La colaboradora se desempeñará como asesora de experiencia en Tienda TRU.</p>
  <p><strong>SEGUNDA.</strong> La remuneración mensual es de S/ 1,850.00.</p>
  <div class="firmas">
    <div><p class="linea"><!--FIRMA_EMPRESA--></p><p><strong>GERENCIA GENERAL</strong><br/>Alma Reyes Soto<br/>DNI N.° 70000000<br/>CAYLA</p></div>
    <div><p class="linea"><!--FIRMA_PERSONA--></p><p><strong>LA COLABORADORA</strong><br/>${nombre}<br/>DNI N.° ${dni}</p></div>
  </div>
</div>`;

  psql(`
    insert into firmas_escaneadas (persona_id, imagen, tipo) values
      (${esc(ALMA)}, ${esc(firmaAlma)}, 'dibujo'),
      (${esc(ANA)}, ${esc(firmaAna)}, 'dibujo'),
      (${esc(ROSA)}, ${esc(firmaRosa)}, 'dibujo');
    insert into configuracion (clave, valor) values ('firmante_empresa', jsonb_build_object('persona_id', ${esc(ALMA)}::uuid, 'cargo', 'Gerencia General', 'dni', '70000000'))
      on conflict (clave) do update set valor = excluded.valor;

    -- Un memo ya entregado y firmado por quien lo recibió, y otro esperando su firma.
    insert into expediente_disciplinario (correlativo, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, firmante_id, firmado_at,
       medio_entrega, entregado_at, entregado_por, enviado_a_info_at, enviado_a_info_por, firma_sancionado, firma_sancionado_confirmada_at, creado_por)
    values ('MEM-2026-0001', ${esc(ANA)}, 'tardanza', 'verbal', 'entregado', ${esc(sumarDias(HOY, -60))}, ${esc(sumarDias(HOY, -32))},
            '{"tardanzas": [{"fecha": "${sumarDias(HOY, -40)}", "minutos": 18}, {"fecha": "${sumarDias(HOY, -36)}", "minutos": 25}]}',
            ${esc(ALMA)}, now() - interval '20 days', 'digital', now() - interval '18 days', ${esc(ALMA)}, now() - interval '19 days', ${esc(ALMA)},
            ${esc(firmaAna)}, now() - interval '18 days', ${esc(ALMA)});
    insert into expediente_disciplinario (correlativo, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, firmante_id, firmado_at,
       enviado_a_info_at, enviado_a_info_por, creado_por)
    values ('MEM-2026-0002', ${esc(ROSA)}, 'tardanza', 'verbal', 'firmado', ${esc(sumarDias(HOY, -30))}, ${esc(sumarDias(HOY, -2))},
            '{"tardanzas": [{"fecha": "${sumarDias(HOY, -9)}", "minutos": 14}]}',
            ${esc(ALMA)}, now() - interval '2 days', now() - interval '1 day', ${esc(ALMA)}, ${esc(ALMA)});

    -- Un contrato con las dos firmas y dos sin firmar.
    insert into contratos_generados (persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, fecha_fin, horas_semanales, documento_html, generado_por, fecha_firma, registrado_por, firma_persona, firma_persona_confirmada_at)
    values (${esc(ANA)}, 'nuevo', 'Asesora de experiencia', ${TRU}, 1850, ${esc(sumarDias(HOY, -60))}, ${esc(sumarDias(HOY, 120))}, 45, ${esc(contrato("ANA TORRES RUIZ", "70000548"))}, ${esc(ALMA)}, ${esc(sumarDias(HOY, -60))}, ${esc(ALMA)}, ${esc(firmaAna)}, now() - interval '60 days');
    insert into contratos_generados (persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, fecha_fin, horas_semanales, documento_html, generado_por)
    values (${esc(ROSA)}, 'renovacion', 'Asesora de experiencia', ${TRU}, 1730, ${esc(sumarDias(HOY, 5))}, ${esc(sumarDias(HOY, 185))}, 45, ${esc(contrato("ROSA MEDINA PAZ", "70000685"))}, ${esc(ALMA)}),
           (${esc(LUZ)}, 'nuevo', 'Líder de equipo', ${TRU}, 2700, ${esc(sumarDias(HOY, -200))}, ${esc(sumarDias(HOY, 10))}, 45, ${esc(contrato("LUZ QUISPE ROJAS", "70000411"))}, ${esc(ALMA)});

    -- El bono de cumpleaños ya pedido y firmado por Ana.
    insert into documentos_firmados (alcance, persona_id, tipo, fecha_firma, monto_declarado, anio, registrado_por, firma_persona, firma_persona_confirmada_at)
    values ('individual', ${esc(ANA)}, 'bono', ${esc(sumarDias(HOY, -15))}, 200, ${esc(Number(HOY.slice(0, 4)))}, ${esc(ALMA)}, ${esc(firmaAna)}, now() - interval '15 days');
  `);

  // De baja: sigue en los reportes de periodos pasados y ya no puede entrar. Por la función real, no por un UPDATE.
  sembrarBaja(ALMA);
}

// Los dos periodos anteriores quedan pagados por la función real, para ver desgloses congelados y un mes cerrado.
function pagarPeriodosAnteriores() {
  const admin = psql("select auth_user_id from personas where rol = 'admin' limit 1");
  const periodos = psql(`select id from periodos_planilla where fecha_ini >= '2026-04-01' order by fecha_ini desc offset 1 limit 2`).split("\n").filter(Boolean);
  const claims = JSON.stringify({ sub: admin, role: "authenticated" });
  for (const id of periodos) {
    psql(`begin; select set_config('request.jwt.claims', ${esc(claims)}, true);
      select fn_periodo_pagado(${esc(id)}, true, g) from unnest(array['planilla','prueba','rxh','practicante']) as g;
      commit;`);
  }
  return periodos.length;
}

function sembrarBaja(ALMA) {
  const sede = "(select id from sedes where codigo = 'LIM')";
  psql(`
    with cuenta as (
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
      values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated', 'de.baja@dynamic.local',
              crypt(${esc(CLAVE)}, gen_salt('bf', 4)), now(), '{"provider":"email","providers":["email"]}', '{}')
      returning id)
    insert into personas (nombres, apellidos, documento, tipo_documento, sede_base_id, rol, pin_hash, fecha_ingreso, auth_user_id, email, funcion, cargo, estado, fecha_cese, motivo_cese)
    select 'Lucía', 'Mendoza Alva', '70009999', 'dni', ${sede}, 'integrante', crypt('1234', gen_salt('bf', 4)), ${esc(sumarDias(HOY, -500))}, id, 'de.baja@dynamic.local', 'taller_produccion', 'Costurera',
           'inactivo', ${esc(sumarDias(HOY, -40))}, 'renuncia'
      from cuenta;
    update auth.users set banned_until = now() + interval '100 years' where email = 'de.baja@dynamic.local';
  `);
}

if (process.argv.includes("--solo-marcas")) {
  const ultima = psql("select coalesce(max(fecha), (now() - interval '100 days')::date) from jornadas");
  // Solo se agrega lo que falta: si ya hay marcas de hoy, no se toca nada.
  if (ultima < HOY) console.log(`Marcas agregadas desde ${sumarDias(ultima, 1)}: ${sembrarMarcas(sumarDias(ultima, 1))}`);
} else {
  await sembrarTodo();
}
