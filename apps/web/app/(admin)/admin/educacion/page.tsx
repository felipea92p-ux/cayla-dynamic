"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { AdminNav } from "../nav";
import { Cargando } from "@/components/cargando";
import { useRolActual } from "@/lib/admin/use-rol";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { hoyLima, puedeVerPlanilla } from "@cayla-dynamic/shared";

// La asignación por educación (art. 19 f) D.S. 001-97-TR) no es remuneración
// SIEMPRE QUE esté sostenida por un comprobante. Por eso esta pantalla no deja
// registrar un monto suelto: el comprobante y el costo declarado son parte del
// mismo acto, no un adjunto que se sube después "cuando se pueda".

interface Fila {
  id: string;
  persona_id: string;
  persona: string;
  sede: string;
  rango: string;
  monto: number;
  institucion: string;
  costo_declarado: number;
  cobertura_pct: number;
  beneficiario: "trabajador" | "hijo";
  comprobante_url: string | null;
  vigente_desde: string;
  vigente_hasta: string | null;
  nota: string | null;
  registrada_por: string | null;
}

interface Candidato {
  persona_id: string;
  persona: string;
  sede: string;
  rango: string;
  tope: number | null;
  ya_tiene: boolean;
}

interface Form {
  personaId: string;
  monto: string;
  institucion: string;
  costoDeclarado: string;
  coberturaPct: string;
  beneficiario: "trabajador" | "hijo";
  vigenteDesde: string;
  nota: string;
}

const FORM_VACIO: Form = {
  personaId: "", monto: "", institucion: "", costoDeclarado: "",
  coberturaPct: "75", beneficiario: "trabajador", vigenteDesde: "", nota: "",
};

const TIPOS_ACEPTADOS = "image/jpeg,image/png,image/heic,image/webp,application/pdf";
const MAX_BYTES = 10 * 1024 * 1024;

const soles = (n: number) =>
  `S/ ${n.toLocaleString("es-PE", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

// "2026-08-04" → "04/08/2026". Aritmética de string: la fecha ya viene como día
// de Lima desde la base, así que construir un Date solo podría estropearla.
const fmtFecha = (iso: string) => { const [y, m, d] = iso.split("-"); return `${d}/${m}/${y}`; };

export default function EducacionPage() {
  const router = useRouter();
  const rol = useRolActual();
  const puedeGestionar = puedeVerPlanilla(rol);

  const [filas, setFilas] = useState<Fila[]>([]);
  const [candidatos, setCandidatos] = useState<Candidato[]>([]);
  const [cargando, setCargando] = useState(true);
  const [cargaError, setCargaError] = useState<string | null>(null);
  const [mensaje, setMensaje] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);

  const [mostrandoAlta, setMostrandoAlta] = useState(false);
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [form, setForm] = useState<Form>(FORM_VACIO);
  const [archivo, setArchivo] = useState<File | null>(null);
  const [guardando, setGuardando] = useState(false);
  const [verSoloVigentes, setVerSoloVigentes] = useState(true);

  const cargar = useCallback(async () => {
    const supabase = createAdminSupabaseClient();
    const { data: sesion } = await supabase.auth.getSession();
    if (!sesion.session) { router.replace("/admin/login"); return; }

    const [lista, cands] = await Promise.all([
      supabase.rpc("fn_educacion_listar"),
      supabase.rpc("fn_educacion_candidatos"),
    ]);
    setFilas((lista.data as Fila[]) ?? []);
    setCandidatos((cands.data as Candidato[]) ?? []);
    setCargaError(lista.error?.message ?? cands.error?.message ?? null);
    setCargando(false);
  }, [router]);

  useEffect(() => { void cargar(); }, [cargar]);

  const avisar = (tipo: "ok" | "error", texto: string) => setMensaje({ tipo, texto });

  const candidato = useMemo(
    () => candidatos.find((c) => c.persona_id === form.personaId) ?? null,
    [candidatos, form.personaId],
  );

  // Los dos techos, calculados MIENTRAS se escribe. El de abajo es el que manda.
  const costo = Number(form.costoDeclarado) || 0;
  const cobertura = Number(form.coberturaPct) || 0;
  const monto = Number(form.monto) || 0;
  const topeComprobante = costo > 0 && cobertura > 0 ? Math.round(costo * cobertura) / 100 : null;
  const topeRango = candidato?.tope ?? null;
  const topeReal = topeComprobante === null ? topeRango
    : topeRango === null ? topeComprobante
    : Math.min(topeComprobante, topeRango);
  const excede = topeReal !== null && monto > topeReal;

  function empezarAlta() {
    setMostrandoAlta(true); setEditandoId(null); setArchivo(null); setMensaje(null);
    setForm({ ...FORM_VACIO, vigenteDesde: hoyLima().slice(0, 8) + "01" });
  }
  function empezarEdicion(f: Fila) {
    setEditandoId(f.id); setMostrandoAlta(false); setArchivo(null); setMensaje(null);
    setForm({
      personaId: f.persona_id, monto: String(f.monto), institucion: f.institucion,
      costoDeclarado: String(f.costo_declarado), coberturaPct: String(f.cobertura_pct),
      beneficiario: f.beneficiario, vigenteDesde: f.vigente_desde, nota: f.nota ?? "",
    });
  }
  function cancelar() { setMostrandoAlta(false); setEditandoId(null); setForm(FORM_VACIO); setArchivo(null); }

  function elegirArchivo(f: File | null) {
    if (f && f.size > MAX_BYTES) {
      avisar("error", `“${f.name}” pesa ${(f.size / 1048576).toFixed(1)} MB y el máximo es 10 MB. Si es una foto, vuelve a tomarla en menor calidad.`);
      return;
    }
    setArchivo(f); setMensaje(null);
  }

  async function guardar() {
    const institucion = form.institucion.trim();
    if (!form.personaId) { avisar("error", "Elige de quién es la asignación."); return; }
    if (institucion.length < 3) { avisar("error", "Escribe qué institución emite el comprobante."); return; }
    if (costo <= 0) { avisar("error", "El costo que dice el comprobante tiene que ser mayor que cero."); return; }
    if (monto <= 0) { avisar("error", "El monto mensual tiene que ser mayor que cero."); return; }
    if (!form.vigenteDesde) { avisar("error", "Indica desde cuándo se paga."); return; }
    if (excede) {
      avisar("error", `El monto no puede pasar de ${soles(topeReal!)}. Ajusta el monto, o el costo declarado si el comprobante dice otra cifra.`);
      return;
    }
    // El comprobante es la razón por la que esto no es remuneración. En un alta
    // se exige; en una edición se conserva el que ya estaba si no se sube otro.
    const yaTeniaComprobante = editandoId !== null && filas.find((f) => f.id === editandoId)?.comprobante_url;
    if (!archivo && !yaTeniaComprobante) {
      avisar("error", "Falta el comprobante. Sin el papel que sostiene el monto, esto sería remuneración y pagaría impuestos.");
      return;
    }

    setGuardando(true);
    const supabase = createAdminSupabaseClient();

    // 1) La fila primero: da el id con el que se nombra el archivo, y si algo
    //    falla aquí no queda un archivo huérfano en el bucket.
    const { data: id, error } = await supabase.rpc("fn_educacion_registrar", {
      p_persona_id: form.personaId,
      p_monto: monto,
      p_institucion: institucion,
      p_costo_declarado: costo,
      p_cobertura_pct: cobertura,
      p_beneficiario: form.beneficiario,
      p_vigente_desde: form.vigenteDesde,
      p_nota: form.nota.trim() || null,
      p_id: editandoId,
    });
    if (error) { setGuardando(false); avisar("error", mensajeDeError(error, "guardar")); return; }

    // 2) El comprobante, si se eligió uno.
    if (archivo) {
      const ext = archivo.name.split(".").pop()?.toLowerCase() ?? "bin";
      const ruta = `educacion/${form.personaId}/${id}.${ext}`;
      const subida = await supabase.storage.from("comprobantes").upload(ruta, archivo, { upsert: true });
      if (subida.error) {
        setGuardando(false);
        avisar("error", `La asignación se guardó, pero el comprobante no subió (${subida.error.message}). Ábrela con “Editar” y vuelve a intentarlo — sin el papel, el monto no está sustentado.`);
        await cargar();
        return;
      }
      // 3) Enlazar el archivo a la fila.
      const { error: e3 } = await supabase.rpc("fn_educacion_registrar", {
        p_persona_id: form.personaId, p_monto: monto, p_institucion: institucion,
        p_costo_declarado: costo, p_cobertura_pct: cobertura, p_beneficiario: form.beneficiario,
        p_vigente_desde: form.vigenteDesde, p_nota: form.nota.trim() || null,
        p_comprobante_url: ruta, p_id: id,
      });
      if (e3) {
        setGuardando(false);
        avisar("error", `El comprobante subió pero no quedó enlazado (${mensajeDeError(e3)}). Ábrela con “Editar” y vuelve a subirlo.`);
        await cargar();
        return;
      }
    }

    setGuardando(false);
    cancelar();
    await cargar();
    avisar("ok", editandoId ? "Cambios guardados." : "Asignación registrada. Entra en el próximo cálculo de planilla.");
  }

  async function verComprobante(f: Fila) {
    if (!f.comprobante_url) return;
    const supabase = createAdminSupabaseClient();
    // URL firmada de vida corta: el bucket es privado y estos papeles llevan el
    // nombre de una persona (y a veces el de un menor).
    const { data, error } = await supabase.storage.from("comprobantes").createSignedUrl(f.comprobante_url, 60);
    if (error || !data) { avisar("error", `No se pudo abrir el comprobante: ${error?.message ?? "sin URL"}`); return; }
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  }

  async function cerrar(f: Fila) {
    const sugerida = hoyLima();
    const hasta = window.prompt(
      `¿Hasta qué día se le paga la asignación a ${f.persona}?\n\n` +
      `La fila NO se borra: sigue sosteniendo lo que ya se pagó. Solo deja de sumarse ` +
      `en los periodos posteriores a la fecha que pongas.\n\nFormato AAAA-MM-DD:`,
      sugerida,
    );
    if (!hasta) return;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(hasta)) { avisar("error", "La fecha va como AAAA-MM-DD (por ejemplo 2026-12-31)."); return; }
    const supabase = createAdminSupabaseClient();
    const { error } = await supabase.rpc("fn_educacion_cerrar", { p_id: f.id, p_hasta: hasta });
    if (error) { avisar("error", mensajeDeError(error)); return; }
    await cargar();
    avisar("ok", `Cerrada al ${fmtFecha(hasta)}. Deja de pagarse en los periodos posteriores.`);
  }

  const visibles = verSoloVigentes ? filas.filter((f) => f.vigente_hasta === null) : filas;
  const totalMensual = filas.filter((f) => f.vigente_hasta === null).reduce((s, f) => s + Number(f.monto), 0);

  const formulario = (
    <div className="mb-6 grid max-w-3xl gap-3 rounded-2xl border border-sand bg-papel p-5 sm:grid-cols-2">
      <label className="flex flex-col gap-1 text-sm sm:col-span-2">
        ¿De quién es?
        <select
          value={form.personaId}
          onChange={(e) => setForm({ ...form, personaId: e.target.value })}
          disabled={editandoId !== null}
          className="rounded-lg border bg-crema px-3 py-2 disabled:text-taupe"
        >
          <option value="">— elige a la persona —</option>
          {candidatos.map((c) => (
            <option key={c.persona_id} value={c.persona_id}>
              {c.persona} · {c.sede} · rango {c.rango}
              {c.ya_tiene ? " (ya tiene una vigente)" : ""}
            </option>
          ))}
        </select>
        {candidato?.ya_tiene && !editandoId && (
          <span className="text-xs text-ambar">
            Ya tiene una asignación vigente. Si es un estudio nuevo, cierra primero la anterior — si no, se le pagarían las dos.
          </span>
        )}
        {candidato && candidato.tope === null && (
          <span className="text-xs text-ambar">
            El rango “{candidato.rango}” no tiene tope cargado, así que aquí solo manda el comprobante.
          </span>
        )}
      </label>

      <label className="flex flex-col gap-1 text-sm">
        Institución
        <input
          value={form.institucion}
          onChange={(e) => setForm({ ...form, institucion: e.target.value })}
          placeholder="ej. Instituto San Ignacio"
          className="rounded-lg border px-3 py-2"
        />
        <span className="text-xs text-taupe">Tal como aparece en el comprobante.</span>
      </label>

      <label className="flex flex-col gap-1 text-sm">
        ¿De quién es el estudio?
        <select
          value={form.beneficiario}
          onChange={(e) => setForm({ ...form, beneficiario: e.target.value as "trabajador" | "hijo" })}
          className="rounded-lg border bg-crema px-3 py-2"
        >
          <option value="trabajador">De ella misma</option>
          <option value="hijo">De su hijo o hija</option>
        </select>
        <span className="text-xs text-taupe">
          {form.beneficiario === "hijo"
            ? "Archiva también el documento que acredita el vínculo."
            : "Basta la constancia de matrícula a su nombre."}
        </span>
      </label>

      <label className="flex flex-col gap-1 text-sm">
        Costo que dice el comprobante
        <input
          type="number" min="0" step="0.01" inputMode="decimal"
          value={form.costoDeclarado}
          onChange={(e) => setForm({ ...form, costoDeclarado: e.target.value })}
          placeholder="ej. 200.00"
          className="rounded-lg border px-3 py-2"
        />
        <span className="text-xs text-taupe">El importe real del papel, no una estimación.</span>
      </label>

      <label className="flex flex-col gap-1 text-sm">
        ¿Qué parte cubre CAYLA?
        <div className="flex items-center gap-2">
          <input
            type="number" min="1" max="100" step="1" inputMode="numeric"
            value={form.coberturaPct}
            onChange={(e) => setForm({ ...form, coberturaPct: e.target.value })}
            className="w-24 rounded-lg border px-3 py-2"
          />
          <span className="text-sm text-taupe">%</span>
        </div>
      </label>

      <label className="flex flex-col gap-1 text-sm">
        Monto mensual a pagar
        <input
          type="number" min="0" step="0.01" inputMode="decimal"
          value={form.monto}
          onChange={(e) => setForm({ ...form, monto: e.target.value })}
          placeholder="ej. 150.00"
          className={`rounded-lg border px-3 py-2 ${excede ? "border-rojo text-rojo" : ""}`}
        />
        {/* El techo se dice ANTES de guardar, no como error después. */}
        {topeReal !== null && (
          <span className={`text-xs ${excede ? "text-rojo" : "text-taupe"}`}>
            {excede ? "Se pasa. " : ""}Máximo {soles(topeReal)}
            {topeComprobante !== null && topeRango !== null && (
              <> — {topeComprobante <= topeRango
                ? `es lo que sostiene el comprobante (${cobertura}% de ${soles(costo)})`
                : `es el tope del rango ${candidato?.rango}`}</>
            )}
          </span>
        )}
      </label>

      <label className="flex flex-col gap-1 text-sm">
        Se paga desde
        <input
          type="date"
          value={form.vigenteDesde}
          onChange={(e) => setForm({ ...form, vigenteDesde: e.target.value })}
          className="rounded-lg border px-3 py-2"
        />
        <span className="text-xs text-taupe">Entra en los periodos que terminen en esta fecha o después.</span>
      </label>

      <label className="flex flex-col gap-1 text-sm sm:col-span-2">
        Comprobante {editandoId && "(subir uno nuevo reemplaza el anterior)"}
        <input
          type="file"
          accept={TIPOS_ACEPTADOS}
          onChange={(e) => elegirArchivo(e.target.files?.[0] ?? null)}
          className="rounded-lg border bg-crema px-3 py-2 text-sm file:mr-3 file:rounded file:border-0 file:bg-sand file:px-3 file:py-1 file:text-sm"
        />
        <span className="text-xs text-taupe">
          Foto o PDF de la constancia o boleta, hasta 10 MB. Es lo que hace que este monto no sea remuneración:
          sin él, el día de una fiscalización el pago se recategoriza y genera aportes.
        </span>
        {archivo && <span className="text-xs text-tinta">Elegido: {archivo.name} ({(archivo.size / 1048576).toFixed(1)} MB)</span>}
      </label>

      <label className="flex flex-col gap-1 text-sm sm:col-span-2">
        Nota (opcional)
        <input
          value={form.nota}
          onChange={(e) => setForm({ ...form, nota: e.target.value })}
          placeholder="ej. ciclo agosto–diciembre 2026"
          className="rounded-lg border px-3 py-2"
        />
      </label>

      <div className="flex items-end gap-3 sm:col-span-2">
        <button onClick={guardar} disabled={guardando || excede} className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema disabled:opacity-50">
          {guardando ? "Guardando…" : editandoId ? "Guardar cambios" : "Registrar asignación"}
        </button>
        <button onClick={cancelar} className="rounded-lg border px-4 py-2 text-sm">Cancelar</button>
      </div>
    </div>
  );

  return (
    <div className="flex min-h-screen flex-col">
      <AdminNav />
      <main className="flex-1 p-6">
        <div className="mb-4 flex items-center justify-between">
          <h1 className="font-serif text-2xl">Asignación por educación</h1>
          {puedeGestionar && !cargaError && !mostrandoAlta && !editandoId && (
            <button onClick={empezarAlta} className="rounded-lg bg-tinta px-4 py-2 text-sm font-medium text-crema">+ Registrar asignación</button>
          )}
        </div>

        {rol === null ? (
          <Cargando />
        ) : !puedeGestionar ? (
          <div className="max-w-2xl rounded-lg bg-ambar/15 px-4 py-3 text-sm text-ambar">
            Solo Desarrollo Organizacional gestiona las asignaciones por educación.
          </div>
        ) : (
          <>
            <p className="mb-4 max-w-3xl text-sm text-taupe">
              Lo que CAYLA aporta a los estudios de una integrante o de sus hijos. No es remuneración —
              no paga aportes ni entra en la base de gratificación o CTS— <strong>siempre que el
              comprobante lo sostenga</strong>. Por eso el papel se guarda aquí y no en una carpeta aparte.
            </p>

            {mensaje && (
              <div className={`mb-4 max-w-3xl rounded-lg px-4 py-3 text-sm ${mensaje.tipo === "ok" ? "bg-sand/40 text-tinta" : "bg-rojo/10 text-rojo"}`}>
                {mensaje.texto}
              </div>
            )}
            {cargaError && (
              <div className="mb-4 max-w-3xl rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
                No se pudieron cargar las asignaciones: {cargaError}.{" "}
                <button onClick={() => void cargar()} className="font-medium underline">Reintentar</button>
              </div>
            )}

            {(mostrandoAlta || editandoId) && formulario}

            {cargando ? (
              <Cargando />
            ) : filas.length === 0 ? (
              <div className="max-w-3xl rounded-2xl border border-sand bg-papel px-5 py-6 text-sm text-taupe">
                Todavía no hay ninguna asignación cargada. Cada una necesita su comprobante: es lo que
                permite que el pago no cuente como remuneración.
              </div>
            ) : (
              <>
                <div className="mb-3 flex flex-wrap items-center gap-4 text-sm">
                  <label className="flex items-center gap-2">
                    <input type="checkbox" checked={verSoloVigentes} onChange={(e) => setVerSoloVigentes(e.target.checked)} />
                    Solo las vigentes
                  </label>
                  <span className="text-taupe">
                    Vigentes: <strong className="text-tinta">{filas.filter((f) => f.vigente_hasta === null).length}</strong>
                    {" · "}suman <strong className="text-tinta">{soles(totalMensual)}</strong> al mes
                  </span>
                </div>

                <div className="overflow-x-auto rounded-2xl border border-sand bg-papel">
                  <table className="w-full text-sm">
                    <thead className="bg-sand/70 text-left text-taupe">
                      <tr>
                        <th className="px-4 py-2 font-normal">Persona</th>
                        <th className="px-4 py-2 font-normal">Institución</th>
                        <th className="px-4 py-2 font-normal">Estudia</th>
                        <th className="px-4 py-2 font-normal">Mensual</th>
                        <th className="px-4 py-2 font-normal">Sustento</th>
                        <th className="px-4 py-2 font-normal">Vigencia</th>
                        <th className="px-4 py-2 font-normal">Papel</th>
                        <th className="px-4 py-2 font-normal">Acciones</th>
                      </tr>
                    </thead>
                    <tbody>
                      {visibles.map((f) => (
                        <tr key={f.id} className={`border-t ${f.vigente_hasta ? "text-taupe" : ""}`}>
                          <td className="px-4 py-2">
                            {f.persona}
                            <span className="ml-1 text-xs text-taupe">{f.sede} · {f.rango}</span>
                          </td>
                          <td className="px-4 py-2">{f.institucion}</td>
                          <td className="px-4 py-2 text-xs">{f.beneficiario === "hijo" ? "su hijo/a" : "ella misma"}</td>
                          <td className="px-4 py-2 tabular-nums">{soles(Number(f.monto))}</td>
                          <td className="px-4 py-2 text-xs text-taupe">
                            {f.cobertura_pct}% de {soles(Number(f.costo_declarado))}
                          </td>
                          <td className="px-4 py-2 text-xs">
                            desde {fmtFecha(f.vigente_desde)}
                            {f.vigente_hasta
                              ? <span className="block text-taupe">cerrada al {fmtFecha(f.vigente_hasta)}</span>
                              : <span className="block text-tinta">vigente</span>}
                          </td>
                          <td className="px-4 py-2">
                            {f.comprobante_url ? (
                              <button onClick={() => void verComprobante(f)} className="text-xs font-medium underline">Ver</button>
                            ) : (
                              <span className="rounded-full bg-rojo/10 px-2 py-0.5 text-xs text-rojo" title="Sin el comprobante, este pago se recategoriza como remuneración en una fiscalización">
                                falta
                              </span>
                            )}
                          </td>
                          <td className="px-4 py-2">
                            <div className="flex flex-wrap gap-2 text-xs">
                              <button onClick={() => empezarEdicion(f)} className="rounded border px-2 py-1 hover:bg-sand/50">Editar</button>
                              {!f.vigente_hasta && (
                                <button onClick={() => void cerrar(f)} className="rounded border border-rojo/30 px-2 py-1 text-rojo hover:bg-rojo/10">Cerrar</button>
                              )}
                            </div>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </>
            )}
          </>
        )}
      </main>
    </div>
  );
}
