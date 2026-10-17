"use client";

import { useState } from "react";
import { ChevronDown, Download, SlidersHorizontal } from "lucide-react";
import {
  ESTADO_CONSTANCIA, TIPOS_CONSTANCIA, TIPO_CONSTANCIA_LABELS,
  type EstadoConstancia, type TipoConstancia,
} from "@cayla-dynamic/shared";
import { GRUPOS_EDUCACION, type GrupoEducacion } from "@/lib/admin/educacion-grupos";
import { FILTROS_VACIOS, hayFiltros, mesLargo, type Filtros, type QuienEstudia, type VigenciaFiltro } from "@/lib/admin/educacion-meses";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoCasilla, CampoSelect } from "@/components/ui/campo";
import { Filtro } from "@/components/ui/filtro";
import { Menu, MenuItem } from "@/components/ui/menu";

/**
 * LA BARRA DE FILTROS DE EDUCACIÓN: tres filas, cada una con un solo trabajo.
 *
 * PROMETE: dejar escoger sede, grupo, mes y estado sin abrir nada, y guardar lo
 *   menos usado en «Más filtros», que dice cuántos tiene puestos.
 * ASUME: los conteos ya vienen calculados con los DEMÁS filtros puestos (cada chip
 *   cuenta lo que mostraría al tocarlo; ver `pasaFiltros` con `ignorar`).
 * NO HACE: no filtra nada; solo dibuja y avisa. Y no recuerda la sede entre visitas
 *   (Felipe delegó el diseño, 2026-10-16, y pesó más la regla de que la sede sale
 *   en el enlace, no en el navegador de una Mac que se comparte).
 *
 * ── POR QUÉ ASÍ ─────────────────────────────────────────────────────────────
 * Antes eran ocho controles del mismo peso en dos filas, con nombres que no se
 * entendían solos —«Pago» era un mes, «Beneficio» era vigentes o terminados—.
 * La SEDE es la primera decisión de quien entra («¿de quién estoy hablando?»), así
 * que va primero y con su número; el resto del tamaño que tiene cada cosa: lo que
 * se toca todo el día a la vista, lo que se toca una vez por semana plegado.
 */

const COMO_QUIEN: { valor: QuienEstudia; etiqueta: string }[] = [
  { valor: "", etiqueta: "Cualquiera" },
  { valor: "trabajador", etiqueta: "La persona misma" },
  { valor: "hijo", etiqueta: "Su hijo o hija" },
];

const COMO_VIGENCIA: { valor: VigenciaFiltro; etiqueta: string }[] = [
  { valor: "activas", etiqueta: "Vigentes y por empezar" },
  { valor: "terminada", etiqueta: "Terminados" },
  { valor: "todas", etiqueta: "Todos" },
];

export interface OpcionesDeBarra {
  sedes: { sede: string; n: number }[];
  totalSedes: number;
  grupos: Record<GrupoEducacion, number>;
  totalGrupos: number;
  meses: string[];
  instituciones: string[];
  revisores: string[];
  /** Las constancias todavía están llegando: los filtros que las miran avisan en vez de callar. */
  cargandoConstancias: boolean;
}

export function BarraFiltros({
  filtros, cambiar, limpiar, opciones, descargas,
}: {
  filtros: Filtros;
  cambiar: (parcial: Partial<Filtros>) => void;
  limpiar: () => void;
  opciones: OpcionesDeBarra;
  descargas: { csv: () => void; zip: () => void; zipDisponible: boolean; ocupado: boolean };
}) {
  const [masAbierto, setMasAbierto] = useState(false);
  const enMas = [
    filtros.mes, filtros.estado, filtros.institucion, filtros.quien, filtros.tipo, filtros.revisor, filtros.desde || filtros.hasta,
    filtros.vigencia !== FILTROS_VACIOS.vigencia, filtros.liquidadas,
  ].filter(Boolean).length;

  return (
    <div className="mb-4 flex flex-col gap-3">
      {/* ── UNA FILA: sede, buscar, más filtros, descargar (2026-10-17: menos rótulos, menos texto) ── */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="w-full sm:w-52">
          <CampoSelect aria-label="Sede" value={filtros.sede} onChange={(e) => cambiar({ sede: e.target.value })}>
            <option value="">Todas las sedes · {opciones.totalSedes}</option>
            {opciones.sedes.map((x) => <option key={x.sede} value={x.sede}>{x.sede} · {x.n}</option>)}
          </CampoSelect>
        </div>
        <div className="min-w-48 flex-1 basis-56">
          <Campo aria-label="Buscar persona" value={filtros.buscar} onChange={(e) => cambiar({ buscar: e.target.value })}
            placeholder="Buscar persona" />
        </div>
        <Boton variante="secundario" aria-expanded={masAbierto} aria-controls="mas-filtros" onClick={() => setMasAbierto((a) => !a)}
          className="inline-flex items-center gap-1.5">
          <SlidersHorizontal className="size-4" aria-hidden />
          Filtros{enMas > 0 && <span className="rounded-full bg-tinta px-1.5 text-[11px] leading-4 text-crema">{enMas}</span>}
          <ChevronDown className={`size-4 transition-transform duration-150 motion-reduce:transition-none ${masAbierto ? "rotate-180" : ""}`} aria-hidden />
        </Boton>
        <Menu trigger={({ abierto, alternar }) => (
          <Boton variante="secundario" cargando={descargas.ocupado} aria-haspopup="menu" aria-expanded={abierto} onClick={alternar}
            aria-label="Descargar" className="inline-flex items-center gap-1.5">
            <Download className="size-4" aria-hidden />
          </Boton>
        )}>
          <MenuItem onClick={descargas.csv}>Cuadro de lo que ves (CSV)</MenuItem>
          <MenuItem onClick={descargas.zip} disabled={!descargas.zipDisponible}>
            Constancias del mes (ZIP)
            {!descargas.zipDisponible && <span className="block text-xs text-taupe">Elige un mes en Filtros para armarlo</span>}
          </MenuItem>
        </Menu>
        {hayFiltros(filtros) && <Boton variante="enlace" onClick={limpiar}>Limpiar</Boton>}
      </div>

      {/* ── EN QUÉ PUNTO ESTÁ CADA UNO: la ayuda de cada pastilla va en su globo, no en una línea aparte ── */}
      <div role="group" aria-label="Mostrar" className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-0.5 sm:mx-0 sm:flex-wrap sm:overflow-visible sm:px-0 [scrollbar-width:none]">
        <Filtro activo={filtros.grupo === null} onClick={() => cambiar({ grupo: null })} title="Todos los estudios, con lo que pide acción primero.">
          Todos <Cuenta n={opciones.totalGrupos} />
        </Filtro>
        {GRUPOS_EDUCACION.filter((g) => g.clave !== "sin_solicitar").map((g) => (
          <Filtro key={g.clave} activo={filtros.grupo === g.clave} onClick={() => cambiar({ grupo: g.clave })} title={g.ayuda}>
            {g.etiqueta} <Cuenta n={opciones.grupos[g.clave]} />
          </Filtro>
        ))}
        {GRUPOS_EDUCACION.filter((g) => g.clave === "sin_solicitar").map((g) => (
          <Filtro key={g.clave} activo={filtros.grupo === g.clave} onClick={() => cambiar({ grupo: g.clave })} title={g.ayuda}
            className="border-dashed">
            {g.etiqueta} <Cuenta n={opciones.grupos[g.clave]} />
          </Filtro>
        ))}
      </div>

      {masAbierto && (
        <div id="mas-filtros" className="grid gap-3 rounded-superficie border border-sand bg-papel p-4 sm:grid-cols-2 lg:grid-cols-4">
          <CampoSelect etiqueta="Mes del pago" value={filtros.mes} disabled={opciones.cargandoConstancias && opciones.meses.length === 0}
            onChange={(e) => cambiar({ mes: e.target.value, desde: "", hasta: "" })}>
            <option value="">Todos</option>
            {opciones.meses.map((m) => <option key={m} value={m}>{mesLargo(m)}</option>)}
          </CampoSelect>
          <CampoSelect etiqueta="Estado de la constancia" value={filtros.estado}
            onChange={(e) => cambiar({ estado: e.target.value as EstadoConstancia | "" })}>
            <option value="">Todos</option>
            {(Object.keys(ESTADO_CONSTANCIA) as EstadoConstancia[]).map((k) => <option key={k} value={k}>{ESTADO_CONSTANCIA[k].etiqueta}</option>)}
          </CampoSelect>
          <CampoSelect etiqueta="Institución" value={filtros.institucion} onChange={(e) => cambiar({ institucion: e.target.value })}>
            <option value="">Todas</option>
            {opciones.instituciones.map((i) => <option key={i} value={i}>{i}</option>)}
          </CampoSelect>
          <CampoSelect etiqueta="Quién estudia" value={filtros.quien} onChange={(e) => cambiar({ quien: e.target.value as QuienEstudia })}>
            {COMO_QUIEN.map((o) => <option key={o.valor} value={o.valor}>{o.etiqueta}</option>)}
          </CampoSelect>
          <CampoSelect etiqueta="Tipo de constancia" value={filtros.tipo} onChange={(e) => cambiar({ tipo: e.target.value as TipoConstancia | "" })}>
            <option value="">Todos</option>
            {TIPOS_CONSTANCIA.map((t) => <option key={t} value={t}>{TIPO_CONSTANCIA_LABELS[t]}</option>)}
          </CampoSelect>
          <CampoSelect etiqueta="Quién la revisó" value={filtros.revisor} onChange={(e) => cambiar({ revisor: e.target.value })}>
            <option value="">Cualquiera</option>
            {opciones.revisores.map((r) => <option key={r} value={r}>{r}</option>)}
          </CampoSelect>
          <Campo etiqueta="Pago desde" type="date" value={filtros.desde} max={filtros.hasta || undefined}
            onChange={(e) => cambiar({ desde: e.target.value, mes: "" })} />
          <Campo etiqueta="Pago hasta" type="date" value={filtros.hasta} min={filtros.desde || undefined}
            onChange={(e) => cambiar({ hasta: e.target.value, mes: "" })} />
          <CampoSelect etiqueta="Estado del apoyo" value={filtros.vigencia} onChange={(e) => cambiar({ vigencia: e.target.value as VigenciaFiltro })}>
            {COMO_VIGENCIA.map((o) => <option key={o.valor} value={o.valor}>{o.etiqueta}</option>)}
          </CampoSelect>
          <div className="flex items-end pb-2">
            <CampoCasilla etiqueta="Incluir personas ya liquidadas" checked={filtros.liquidadas}
              onChange={(e) => cambiar({ liquidadas: e.target.checked })} />
          </div>
          {opciones.cargandoConstancias && (
            <p className="text-xs text-taupe sm:col-span-2 lg:col-span-4">
              Se están trayendo las constancias: el mes, el tipo, quién revisó y el rango de fechas se aplican cuando terminen.
            </p>
          )}
        </div>
      )}
    </div>
  );
}

function Cuenta({ n }: { n: number }) {
  return <span className="tabular-nums opacity-70">{n}</span>;
}
