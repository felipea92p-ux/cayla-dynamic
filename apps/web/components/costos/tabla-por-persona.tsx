"use client";

// «Por persona» de Costos: cada persona que cobró en el año, con buscador, sede, orden y páginas de 15.
//
// QUÉ PROMETE
//   Encontrar a alguien en un año con rotación sin bajar por una tabla de cincuenta filas: por nombre (sin tildes), por sede, y
//   ordenada por costo, horas o periodos para los dos lados. Cambiar el filtro vuelve a la página 1.
//
// QUÉ ASUME
//   Que `personas` llega entera (fn_costos_planilla → por_persona): filtrar, ordenar y cortar pasa aquí, sin volver a la base. Qué
//   entra y en qué orden lo decide lib/admin/costos-por-persona.ts; esto solo lo dibuja.
//
// El buscador y los selectores van FUERA de <ListaPaginada>: la lista se vuelve a montar con cada cambio de filtro (es su `key`, para
// volver a la página 1), y un campo de texto adentro perdería el foco con cada letra.

import { useState } from "react";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { ListaPaginada } from "@/components/ui/paginas";
import { Fila, TablaEncabezado, Th } from "@/components/ui/tabla";
import { TablaCostos, TituloSeccion } from "@/components/costos/seccion-tabla";
import {
  FILTRO_PERSONAS_INICIAL,
  ORDENES_PERSONAS,
  PERSONAS_POR_PAGINA,
  hayFiltro,
  personasVisibles,
  type FiltroPersonas,
  type OrdenPersonas,
} from "@/lib/admin/costos-por-persona";
import { formatSoles } from "@/lib/rangos";

export interface PersonaCosto {
  persona_id: string;
  nombre: string;
  sede: string;
  periodos: number;
  horas: number;
  neto: number;
  provisiones: number;
  costo: number;
  salio_del_banco?: number;
}

const NUM = "px-4 py-2 text-right tabular-nums";

export function TablaPorPersona({
  personas,
  sedes,
}: {
  personas: readonly PersonaCosto[];
  /** Las sedes con gente pagada en el año, código y nombre: salen de `por_sede`, no de una lista escrita a mano. */
  sedes: readonly { sede: string; nombre: string }[];
}) {
  const [filtro, setFiltro] = useState<FiltroPersonas>(FILTRO_PERSONAS_INICIAL);
  const visibles = personasVisibles(personas, filtro);
  const nombreDeSede = new Map(sedes.map((s) => [s.sede, s.nombre]));
  const cambiar = (c: Partial<FiltroPersonas>) => setFiltro((f) => ({ ...f, ...c }));

  return (
    <section className="mb-6">
      <TituloSeccion>Por persona</TituloSeccion>

      <div role="search" className="mb-3 flex flex-wrap items-center gap-3">
        <div className="w-full sm:w-64">
          <Campo
            id="costos-persona-buscar"
            type="search"
            aria-label="Buscar persona por nombre"
            placeholder="Buscar persona…"
            value={filtro.texto}
            onChange={(e) => cambiar({ texto: e.target.value })}
          />
        </div>
        <CampoSelect
          id="costos-persona-sede"
          aria-label="Sede"
          value={filtro.sede}
          onChange={(e) => cambiar({ sede: e.target.value })}
        >
          <option value="">Todas las sedes</option>
          {sedes.map((s) => (
            <option key={s.sede} value={s.sede}>{s.nombre}</option>
          ))}
        </CampoSelect>
        <CampoSelect
          id="costos-persona-orden"
          aria-label="Ordenar por"
          value={filtro.orden}
          onChange={(e) => cambiar({ orden: e.target.value as OrdenPersonas })}
        >
          {ORDENES_PERSONAS.map((o) => (
            <option key={o.valor} value={o.valor}>{o.etiqueta}</option>
          ))}
        </CampoSelect>
        {/* Sin resultados, el «Limpiar filtros» va en el recuadro vacío: dos botones iguales a la vez son ruido. */}
        {hayFiltro(filtro) && visibles.length > 0 && (
          <Boton variante="enlace" className="text-sm" onClick={() => setFiltro(FILTRO_PERSONAS_INICIAL)}>
            Limpiar filtros
          </Boton>
        )}
        <span aria-live="polite" className="text-xs text-taupe tabular-nums sm:ml-auto">
          {visibles.length} de {personas.length} personas
        </span>
      </div>

      {visibles.length === 0 ? (
        <EstadoVacio
          accion={<Boton variante="secundario" onClick={() => setFiltro(FILTRO_PERSONAS_INICIAL)}>Limpiar filtros</Boton>}
        >
          Nadie pagado este año coincide con lo que buscas.
        </EstadoVacio>
      ) : (
        <ListaPaginada
          key={`${filtro.texto}|${filtro.sede}|${filtro.orden}`}
          items={visibles}
          porPagina={PERSONAS_POR_PAGINA}
          etiqueta="Páginas de «Por persona»"
        >
          {(pagina) => (
            <TablaCostos>
              <TablaEncabezado>
                <Th>Nombre</Th>
                <Th>Sede</Th>
                <Th className="text-right">Periodos</Th>
                <Th className="text-right">Horas</Th>
                <Th className="text-right">Se transfirió</Th>
                <Th className="text-right">Provisiones</Th>
                <Th className="text-right">Costo real</Th>
                <Th className="text-right">Salió del banco</Th>
              </TablaEncabezado>
              <tbody>
                {pagina.map((p) => (
                  <Fila key={p.persona_id}>
                    <td className="px-4 py-2">{p.nombre}</td>
                    <td className="px-4 py-2 text-taupe">{nombreDeSede.get(p.sede) ?? p.sede}</td>
                    <td className={NUM}>{p.periodos}</td>
                    <td className={NUM}>{p.horas.toLocaleString("es-PE", { maximumFractionDigits: 1 })}</td>
                    <td className={NUM}>{formatSoles(p.neto)}</td>
                    <td className={NUM}>{formatSoles(p.provisiones)}</td>
                    <td className={`${NUM} font-medium`}>{formatSoles(p.costo)}</td>
                    <td className={NUM}>{p.salio_del_banco === undefined ? "—" : formatSoles(p.salio_del_banco)}</td>
                  </Fila>
                ))}
              </tbody>
            </TablaCostos>
          )}
        </ListaPaginada>
      )}
    </section>
  );
}
