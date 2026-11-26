"use client";

// ============================================================================
// editor-persona.tsx — ubicar a alguien en el organigrama (solo DO)
// ============================================================================
// Cambia únicamente el dibujo: el cargo, el rol y el sueldo de la ficha no se
// tocan desde aquí. La base (0623) es quien valida; esta hoja solo pregunta.
// ============================================================================

import { useMemo, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { useToast } from "@/components/toast";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoCasilla, CampoSelect } from "@/components/ui/campo";
import { Modal } from "@/components/ui/modal";
import { Rotulo } from "@/components/ui/rotulo";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import {
  COLORES, ETIQUETAS, TIPOS_DE_LINEA,
  type Color, type Etiqueta, type Organigrama, type TipoLinea,
} from "@/lib/organigrama";

/** A quién se edita: alguien que ya está en el dibujo o alguien sin ubicar. */
export interface Editando {
  persona_id: string;
  nombre: string;
  /** El cargo de la ficha, como punto de partida de la función. */
  cargo?: string | null;
}

export function EditorDePersona({ datos, quien, onCerrar, onGuardado }: {
  datos: Organigrama;
  quien: Editando;
  onCerrar: () => void;
  onGuardado: () => Promise<void> | void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const { avisar } = useToast();
  const actual = datos.personas.find((p) => p.persona_id === quien.persona_id) ?? null;

  const [bloque, setBloque] = useState(actual?.bloque ?? datos.bloques[0]?.clave ?? "");
  const [funcion, setFuncion] = useState(actual?.funcion ?? quien.cargo ?? "");
  const [nivel, setNivel] = useState(actual?.nivel ?? 1);
  const [columna, setColumna] = useState<number | null>(actual?.columna ?? null);
  const [orden, setOrden] = useState(actual?.orden ?? 1);
  const [etiqueta, setEtiqueta] = useState<Etiqueta | "">(actual?.etiqueta ?? "");
  const [color, setColor] = useState<Color | "">(actual?.color ?? "");
  const [discreto, setDiscreto] = useState(actual?.discreto ?? false);
  const [distintivo, setDistintivo] = useState(actual?.distintivo ?? "");
  const [con, setCon] = useState("");
  const [tipo, setTipo] = useState<TipoLinea>("equipo");
  const [enviando, setEnviando] = useState(false);

  const columnas = datos.bloques.find((b) => b.clave === bloque)?.columnas ?? null;
  const nombreDe = (id: string) => {
    const p = datos.personas.find((x) => x.persona_id === id);
    return p ? `${p.nombres} ${p.apellidos}` : "alguien";
  };
  const susLineas = datos.lineas.filter((l) => l.desde === quien.persona_id || l.hasta === quien.persona_id);
  const unibles = datos.personas.filter((p) => p.persona_id !== quien.persona_id
    && !susLineas.some((l) => l.desde === p.persona_id || l.hasta === p.persona_id));

  async function correr(accion: string, pedido: () => PromiseLike<{ error: { message: string; code?: string } | null }>, cerrar: boolean) {
    setEnviando(true);
    const { error } = await pedido();
    if (error) {
      avisar("error", mensajeDeError(error, accion));
    } else {
      await onGuardado();
      if (cerrar) onCerrar();
    }
    setEnviando(false);
  }

  const guardar = () => correr("guardar en el organigrama", () => supabase.rpc("fn_organigrama_guardar", {
    p_persona_id: quien.persona_id, p_bloque: bloque, p_nivel: nivel, p_funcion: funcion,
    p_etiqueta: etiqueta || null, p_color: color || null, p_discreto: discreto,
    p_columna: columnas ? columna : null, p_orden: orden, p_distintivo: distintivo,
  }), true);

  const unir = () => correr("unir en el organigrama", () => supabase.rpc("fn_organigrama_linea", {
    p_desde: quien.persona_id, p_hasta: con, p_tipo: tipo,
  }), false).then(() => setCon(""));

  const numeros = (hasta: number) => Array.from({ length: hasta }, (_, i) => i + 1);

  return (
    <Modal abierto titulo={quien.nombre} ancho="lg" bloqueado={enviando} onCerrar={onCerrar}>
      <div className="flex flex-col gap-3">
        <CampoSelect etiqueta="Equipo" value={bloque} onChange={(e) => { setBloque(e.target.value); setColumna(null); }}>
          {datos.bloques.map((b) => <option key={b.clave} value={b.clave}>{b.nombre}</option>)}
        </CampoSelect>
        <Campo etiqueta="Función que se muestra (no cambia el cargo de su ficha)" value={funcion} maxLength={120}
          onChange={(e) => setFuncion(e.target.value)} />
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <CampoSelect etiqueta="Nivel (1 es arriba)" value={nivel} onChange={(e) => setNivel(Number(e.target.value))}>
            {numeros(9).map((n) => <option key={n} value={n}>{n}</option>)}
          </CampoSelect>
          {columnas ? (
            <CampoSelect etiqueta="Columna" value={columna ?? ""} onChange={(e) => setColumna(e.target.value ? Number(e.target.value) : null)}>
              <option value="">Todo el ancho</option>
              {numeros(columnas).map((n) => <option key={n} value={n}>{n}</option>)}
            </CampoSelect>
          ) : (
            <CampoSelect etiqueta="Posición en su nivel" value={orden} onChange={(e) => setOrden(Number(e.target.value))}>
              {numeros(30).map((n) => <option key={n} value={n}>{n}</option>)}
            </CampoSelect>
          )}
          <CampoSelect etiqueta="Etiqueta" value={etiqueta} onChange={(e) => setEtiqueta(e.target.value as Etiqueta | "")}>
            <option value="">Ninguna</option>
            {Object.entries(ETIQUETAS).map(([v, t]) => <option key={v} value={v}>{t}</option>)}
          </CampoSelect>
          <CampoSelect etiqueta="Color de la tarjeta" value={color} onChange={(e) => setColor(e.target.value as Color | "")}>
            <option value="">Sin color</option>
            {Object.entries(COLORES).map(([v, t]) => <option key={v} value={v}>{t}</option>)}
          </CampoSelect>
        </div>
        <Campo etiqueta="Distintivo (opcional): una especialidad en común" value={distintivo} maxLength={40}
          onChange={(e) => setDistintivo(e.target.value)} />
        <CampoCasilla etiqueta="Tarjeta pequeña y sin negrita" checked={discreto} onChange={(e) => setDiscreto(e.target.checked)} />

        <div className="flex flex-wrap items-center justify-between gap-2">
          {actual ? (
            <Boton variante="enlace" disabled={enviando}
              onClick={() => { void correr("quitar del organigrama", () => supabase.rpc("fn_organigrama_quitar", { p_persona_id: quien.persona_id }), true); }}>
              Quitar del organigrama
            </Boton>
          ) : <span />}
          <Boton variante="primario" tamano="lg" cargando={enviando} disabled={funcion.trim().length < 2} onClick={() => { void guardar(); }}>
            Guardar
          </Boton>
        </div>

        {actual && (
          <div className="flex flex-col gap-2 border-t border-sand pt-3">
            <Rotulo como="h3">Líneas</Rotulo>
            {susLineas.length === 0 && <p className="text-sm text-taupe">No tiene líneas.</p>}
            {susLineas.map((l) => {
              const otra = l.desde === quien.persona_id ? l.hasta : l.desde;
              return (
                <div key={otra} className="flex items-center justify-between gap-2 text-sm text-tinta">
                  <span>{nombreDe(otra)} · {TIPOS_DE_LINEA[l.tipo]}</span>
                  <Boton variante="enlace" disabled={enviando}
                    onClick={() => { void correr("quitar la línea", () => supabase.rpc("fn_organigrama_linea", { p_desde: quien.persona_id, p_hasta: otra, p_tipo: null }), false); }}>
                    Quitar
                  </Boton>
                </div>
              );
            })}
            <div className="grid grid-cols-1 items-end gap-2 sm:grid-cols-[1fr_1fr_auto]">
              <CampoSelect etiqueta="Unir con" value={con} onChange={(e) => setCon(e.target.value)}>
                <option value="">Elige a alguien</option>
                {unibles.map((p) => <option key={p.persona_id} value={p.persona_id}>{p.nombres} {p.apellidos}</option>)}
              </CampoSelect>
              <CampoSelect etiqueta="Tipo de línea" value={tipo} onChange={(e) => setTipo(e.target.value as TipoLinea)}>
                {Object.entries(TIPOS_DE_LINEA).map(([v, t]) => <option key={v} value={v}>{t}</option>)}
              </CampoSelect>
              <Boton disabled={!con || enviando} onClick={() => { void unir(); }}>Unir</Boton>
            </div>
          </div>
        )}
      </div>
    </Modal>
  );
}
