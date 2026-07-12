/**
 * CAYLA Dynamic → Espejo a Google Sheets
 * Pega esto en la hoja destino: Extensiones → Apps Script → reemplaza todo por esto.
 * Luego en "Configuración del proyecto" → Propiedades del script, agrega:
 *    SUPABASE_URL  =  https://vovjyyiafkxteijimpuy.supabase.co
 *    SUPABASE_KEY  =  (tu llave sb_secret_… de Supabase)
 * Corre actualizarEspejo() una vez (autoriza), y crea un disparador por tiempo (cada hora).
 * Mantén esta hoja PRIVADA (la llave vive en las Propiedades del script).
 */

function actualizarEspejo() {
  var props = PropertiesService.getScriptProperties();
  var URL = props.getProperty('SUPABASE_URL');
  var KEY = props.getProperty('SUPABASE_KEY');
  if (!URL || !KEY) throw new Error('Falta SUPABASE_URL o SUPABASE_KEY en Propiedades del script.');
  var H = { apikey: KEY, Authorization: 'Bearer ' + KEY };

  var hoy = new Date();
  var y = hoy.getFullYear(), m = hoy.getMonth(); // m: 0-11
  var pad = function (n) { return ('0' + n).slice(-2); };
  var diasMes = new Date(y, m + 1, 0).getDate();
  var ini = y + '-' + pad(m + 1) + '-01';
  var fin = y + '-' + pad(m + 1) + '-' + pad(diasMes);

  // Personas (id -> nombre, sede)
  var personas = fetchAll(URL + '/rest/v1/personas?select=id,nombres,apellidos,estado,sede_base_id,sedes:sede_base_id(codigo)', H);
  var sedes = fetchAll(URL + '/rest/v1/sedes?select=id,codigo', H);
  var sedeCod = {}; sedes.forEach(function (s) { sedeCod[s.id] = s.codigo; });
  var info = {};
  personas.forEach(function (p) {
    info[p.id] = { nombre: p.nombres + ' ' + p.apellidos, sede: (p.sedes && p.sedes.codigo) || '?', activo: p.estado === 'activo' };
  });

  // Jornadas del mes
  var jornadas = fetchAll(URL + '/rest/v1/jornadas?select=persona_id,fecha,horas_trabajadas,minutos_tarde&fecha=gte.' + ini + '&fecha=lte.' + fin, H);
  // Marcajes del mes
  var marcajes = fetchAll(URL + '/rest/v1/marcajes?select=persona_id,tipo,timestamp_marca,sede_id&order=timestamp_marca&timestamp_marca=gte.' + ini + 'T00:00:00-05:00&timestamp_marca=lte.' + fin + 'T23:59:59-05:00', H);

  escribirResumen(info, jornadas, y, m, diasMes);
  escribirMarcajes(info, sedeCod, marcajes);
}

function fetchAll(url, headers) {
  var out = [], from = 0, LIM = 1000;
  while (true) {
    var u = url + (url.indexOf('?') >= 0 ? '&' : '?') + 'limit=' + LIM + '&offset=' + from;
    var res = UrlFetchApp.fetch(u, { headers: headers, muteHttpExceptions: true });
    var txt = res.getContentText() || '[]';
    var data = JSON.parse(txt);
    if (!Array.isArray(data)) throw new Error('Respuesta inesperada de Supabase: ' + txt.slice(0, 200));
    if (!data.length) break;
    out = out.concat(data);
    if (data.length < LIM) break;
    from += LIM;
  }
  return out;
}

function escribirResumen(info, jornadas, y, m, diasMes) {
  var sh = hoja('Resumen');
  var horas = {}; // persona -> {dia -> horas, total, tarde}
  jornadas.forEach(function (j) {
    var d = parseInt(j.fecha.slice(8, 10), 10);
    var r = horas[j.persona_id] || (horas[j.persona_id] = { dias: {}, total: 0, tarde: 0 });
    r.dias[d] = j.horas_trabajadas || 0;
    r.total += j.horas_trabajadas || 0;
    if (j.minutos_tarde) r.tarde++;
  });
  var head = ['Persona', 'Sede'];
  for (var d = 1; d <= diasMes; d++) head.push(d);
  head.push('Total', 'Tardanzas');
  var filas = [head];
  Object.keys(info).filter(function (id) { return info[id].activo; })
    .sort(function (a, b) { return info[a].nombre.localeCompare(info[b].nombre); })
    .forEach(function (id) {
      var r = horas[id] || { dias: {}, total: 0, tarde: 0 };
      var fila = [info[id].nombre, info[id].sede];
      for (var d = 1; d <= diasMes; d++) fila.push(r.dias[d] ? round2(r.dias[d]) : '');
      fila.push(round2(r.total), r.tarde || '');
      filas.push(fila);
    });
  volcar(sh, filas, y, m);
}

function escribirMarcajes(info, sedeCod, marcajes) {
  var sh = hoja('Marcajes');
  var tz = 'America/Lima';
  var filas = [['Fecha', 'Hora', 'Persona', 'Sede', 'Tipo']];
  marcajes.forEach(function (mk) {
    var f = new Date(mk.timestamp_marca);
    filas.push([
      Utilities.formatDate(f, tz, 'yyyy-MM-dd'),
      Utilities.formatDate(f, tz, 'HH:mm'),
      (info[mk.persona_id] && info[mk.persona_id].nombre) || mk.persona_id,
      sedeCod[mk.sede_id] || '?',
      String(mk.tipo).replace(/_/g, ' '),
    ]);
  });
  volcar(sh, filas);
}

function hoja(nombre) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  return ss.getSheetByName(nombre) || ss.insertSheet(nombre);
}
function volcar(sh, filas, y, m) {
  sh.clearContents();
  if (filas.length) sh.getRange(1, 1, filas.length, filas[0].length).setValues(filas);
  sh.getRange(1, 1, 1, filas[0].length).setFontWeight('bold');
  var meta = 'Actualizado ' + Utilities.formatDate(new Date(), 'America/Lima', 'yyyy-MM-dd HH:mm');
  sh.getRange(filas.length + 2, 1).setValue(meta);
}
function round2(n) { return Math.round(n * 100) / 100; }
