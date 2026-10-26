"use client";

import { useEffect, useRef } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Modal } from "@/components/ui/modal";
import { Boton } from "@/components/ui/boton";
import { useConstanciaDescargable } from "@/components/boletas/constancia-descargable";
import { PieDeModal } from "@/components/boletas/pie-de-modal";
import type { TipoBoleta } from "@/lib/boletas";
import type { HojaFirmada } from "@/lib/boletas-archivos";
import { nombreDelPeriodo, type FilaMiBoleta } from "@/lib/mis-boletas";

/**
 * TU BOLETA FIRMADA, CON TU FIRMA (2026-10-17).
 *
 * Lo que la persona ve en «Lo mío» → Boletas cuando abre una boleta que ya
 * firmó: la misma hoja que ve DO —sus datos, la boleta y, debajo, su firma—, y
 * «Descargar PDF» para llevársela en un solo archivo. Antes veía la foto sola y
 * descargaba la foto sola: la firma existía en la base y en ningún papel suyo.
 *
 * `descargarAlAbrir`: cuando se abrió con el botón «Descargar PDF» de la lista,
 * la descarga arranca sola en cuanto la hoja está lista. Si el navegador no la
 * abre (algún teléfono pide que el toque sea directo), el botón del pie sigue
 * ahí y hace lo mismo.
 */
export function ModalMiBoletaFirmada({
  supabase, fila, hojas, tipo, miNombre, descargarAlAbrir, onCerrar,
}: {
  supabase: ClienteCayla;
  fila: FilaMiBoleta;
  hojas: readonly HojaFirmada[];
  tipo: TipoBoleta;
  /** El nombre con que firma (el del DNI, con reserva al de uso diario). */
  miNombre: string;
  descargarAlAbrir: boolean;
  onCerrar: () => void;
}) {
  const periodo = nombreDelPeriodo(fila.fecha_fin);
  const hoja = useConstanciaDescargable({
    supabase,
    versionId: fila.version_id,
    hojas,
    tipo,
    periodo: { nombre: periodo, desde: fila.fecha_ini, hasta: fila.fecha_fin },
    version: fila.version_n,
    respaldo: { nombre: miNombre, sede: null, cargo: null },
    nombreDelPdf: `${miNombre} — Boleta firmada ${periodo}`,
  });

  // Una sola vez: cerrar el diálogo de imprimir no debe volver a abrirlo.
  const yaDescargo = useRef(false);
  const { lista, descargar } = hoja;
  useEffect(() => {
    if (!descargarAlAbrir || !lista || yaDescargo.current) return;
    yaDescargo.current = true;
    void descargar();
  }, [descargarAlAbrir, lista, descargar]);

  return (
    <Modal abierto onCerrar={onCerrar} titulo={`Tu boleta de ${periodo}`} ancho="xl">
      {hoja.contenido}
      <PieDeModal>
        <Boton variante="secundario" className="min-h-11" onClick={onCerrar}>Cerrar</Boton>
        <Boton
          variante="primario"
          className="min-h-11"
          disabled={!lista}
          cargando={hoja.preparando}
          onClick={() => void descargar()}
        >
          Descargar PDF
        </Boton>
      </PieDeModal>
    </Modal>
  );
}
