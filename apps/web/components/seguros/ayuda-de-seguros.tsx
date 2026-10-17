"use client";

// ============================================================================
// «Cómo funciona Seguros»: un ícono junto al título que abre el detalle
// ============================================================================
// La cabecera de la pantalla dice en una línea para qué sirve; todo lo demás —de dónde
// sale el seguro de cada quien, qué quiere decir cada filtro, qué pasa cuando alguien
// cambia de seguro— vive aquí, a un clic, y no ocupa la pantalla para quien ya lo sabe.
// Los filtros de arriba ya no llevan una frase larga cada uno: esta ventana es su leyenda.
//
// Los plazos que se nombran (los días de aviso de renovación y los de mora de la prima)
// salen de las MISMAS constantes que usa la lógica de la pantalla: si Felipe cambia un
// número, esta ayuda no queda diciendo otro.
// ============================================================================

import { useState } from "react";
import { Info } from "lucide-react";
import { Boton } from "@/components/ui/boton";
import { Modal } from "@/components/ui/modal";
import { DIAS_AVISO_RENOVACION, DIAS_DE_GRACIA_PRIMA } from "@/lib/admin/seguros";

/** Lo que significa cada filtro de situación, en el mismo orden en que se ven en la pantalla. */
const FILTROS: readonly { nombre: string; texto: string }[] = [
  { nombre: "Sin póliza vigente", texto: "Su seguro lleva póliza y hoy no tiene ninguna que cubra. El último día de una póliza ya cuenta como sin cubrir." },
  { nombre: "Cobertura suspendida", texto: `La póliza figura vigente, pero la prima lleva más de ${DIAS_DE_GRACIA_PRIMA} días sin pagarse y la cobertura se suspendió sola: hoy no cubre.` },
  { nombre: "Por vencer", texto: `Cubierta hoy, pero se queda sin póliza en ${DIAS_AVISO_RENOVACION} días o menos y no hay una renovación registrada que empalme.` },
  { nombre: "Cambios por cerrar", texto: "Alguien cambió de seguro y falta pedir la baja del anterior o dar de alta el nuevo." },
  { nombre: "Papeleo pendiente", texto: "Una póliza con la prima sin pagar, sin firmar o sin factura." },
  { nombre: "Piden la baja", texto: "Ya no está activa y su póliza sigue vigente: hay que pedirle la baja a la aseguradora." },
  { nombre: "Cubiertos", texto: "Tienen una póliza al día." },
  { nombre: "Sin póliza que registrar", texto: "Su seguro no lleva póliza (EsSalud se paga con la planilla): no hay nada que registrar." },
];

export function AyudaDeSeguros() {
  const [abierta, setAbierta] = useState(false);
  return (
    <>
      <button
        type="button"
        onClick={() => setAbierta(true)}
        aria-label="Cómo funciona Seguros"
        title="Cómo funciona Seguros"
        className="ml-1.5 inline-flex size-6 items-center justify-center rounded-full border border-sand align-middle text-taupe transition-colors duration-150 hover:border-taupe hover:text-tinta"
      >
        <Info className="size-3.5" strokeWidth={1.8} aria-hidden />
      </button>

      <Modal abierto={abierta} onCerrar={() => setAbierta(false)} titulo="Cómo funciona Seguros" ancho="lg">
        <div className="space-y-5 text-sm">
          <section>
            <h3 className="mb-1 font-serif text-base text-tinta">En qué seguro está cada quien</h3>
            <p className="text-taupe">
              Cada colaborador está en el seguro que le toca por su vínculo —por ejemplo, los practicantes en FOLA y
              planilla y prueba en EsSalud—, y Desarrollo Organizacional puede cambiárselo a una persona con «Cambiar su
              seguro». Si un colaborador tiene uno que el sistema no conoce, se agrega en «Tipos de seguro».
            </p>
          </section>

          <section>
            <h3 className="mb-1 font-serif text-base text-tinta">Qué quiere decir cada filtro</h3>
            <dl className="space-y-2">
              {FILTROS.map((f) => (
                <div key={f.nombre}>
                  <dt className="font-medium text-tinta">{f.nombre}</dt>
                  <dd className="text-taupe">{f.texto}</dd>
                </div>
              ))}
            </dl>
          </section>

          <section>
            <h3 className="mb-1 font-serif text-base text-tinta">Cuando alguien cambia de seguro</h3>
            <p className="text-taupe">
              Sea porque cambió de vínculo (por ejemplo, pasa de practicante a planilla) o porque DO se lo cambió, quedan dos
              pendientes: pedir la baja del seguro anterior y dar de alta el nuevo. Los marcas aquí con la fecha en que los
              hiciste; los de un seguro con póliza se cierran solos cuando la póliza termina o se registra la nueva.
            </p>
          </section>

          <section>
            <h3 className="mb-1 font-serif text-base text-tinta">Para no teclear lo mismo dos veces</h3>
            <dl className="space-y-2">
              <div>
                <dt className="font-medium text-tinta">Leer PDF de póliza</dt>
                <dd className="text-taupe">
                  Elige el PDF de la póliza —o varios, uno por persona— y el sistema lee el número, la vigencia, la prima y a quién
                  asegura. Tú lo revisas y lo registras, y el PDF se guarda en la póliza. Hoy entiende las pólizas de Pacífico; si un
                  PDF no se entiende (una foto escaneada, otra aseguradora), lo dice y se registra a mano.
                </dd>
              </div>
              <div>
                <dt className="font-medium text-tinta">Una póliza para varias personas</dt>
                <dd className="text-taupe">
                  En «Registrar una póliza», «A varias, la misma póliza»: se marcan las personas (con el atajo «Las de planilla») y
                  se registra a todas de una vez, con un solo PDF. La prima es la de cada persona. Si a una no se le puede
                  registrar, no se registra a nadie.
                </dd>
              </div>
              <div>
                <dt className="font-medium text-tinta">Lista de asegurados</dt>
                <dd className="text-taupe">
                  Quiénes están en un seguro hoy, con documento, nacimiento e ingreso, y a quién le falta algún dato: sin eso la
                  aseguradora no emite su certificado. Se puede bajar en CSV para el contador o la aseguradora.
                </dd>
              </div>
            </dl>
          </section>

          <section>
            <h3 className="mb-1 font-serif text-base text-tinta">Qué no hace</h3>
            <p className="text-taupe">
              Solo avisa. No cambia lo que cobra nadie ni toca la planilla: la prima se paga a la aseguradora y EsSalud
              sigue por planilla.
            </p>
          </section>
        </div>
        <div className="mt-5 flex justify-end">
          <Boton onClick={() => setAbierta(false)}>Cerrar</Boton>
        </div>
      </Modal>
    </>
  );
}
