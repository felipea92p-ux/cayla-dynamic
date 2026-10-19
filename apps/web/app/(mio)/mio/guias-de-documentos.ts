// ============================================================================
// guias-de-documentos.ts — las guías de «Contrato», «Firma», «Mi DNI», «Mi
// seguro» y «Mis datos» (2026-10-19)
// ============================================================================
// Escritas contra lo que cada pantalla HACE. Lo que se comprobó, porque la
// maqueta suponía otra cosa:
//   · «Contrato» solo MUESTRA las fechas y si está firmado, y lleva a la hoja
//     donde se lee, se imprime y se confirma la firma. No se firma aquí mismo.
//   · «Mis datos» es de SOLO LECTURA: no tiene botón de editar. Cambiar algo se
//     hace desde «Editar datos», en la cabecera, y solo siete campos son de la
//     persona; el resto (DNI, nombre, pensión, correo…) lo corrige Desarrollo
//     Organizacional.
//   · «Mi DNI» pide la autorización al enviar las fotos, con el texto que se
//     guarda tal cual: es el consentimiento de la Ley N.° 29733 que ya existe
//     (migración 0404), no uno nuevo.
//   · «Mi seguro» es de todo el equipo, pero solo un seguro con póliza trae
//     número y PDF; uno que gestiona la empresa con la planilla (EsSalud) dice
//     solo eso.
//
// Las anclas `data-tour` están puestas a mano: la de «Contrato», «Firma», «Mi
// DNI» y «Mis datos» en `page.tsx`, y la de «Mi seguro» en `seguro/mi-seguro.tsx`.
// El PRIMER paso de cada guía es lo único que existe siempre; los demás dependen
// de que haya datos y se saltan solos.
// ============================================================================

import type { PasoRecorrido } from "@/lib/use-recorrido-guiado";

export const PASOS_GUIA_CONTRATO: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-contrato-seccion"]', titulo: "Tu contrato",
    texto: "Dice desde cuándo y hasta cuándo, y si ya está firmado. Si no tienes uno registrado, avisa a Desarrollo Organizacional." },
  { selector: '[data-tour="mio-contrato-ver"]', titulo: "Leerlo y confirmar tu firma",
    texto: "Ahí está el documento completo: lo lees, lo imprimes y confirmas tu firma. Leerlo no es firmarlo." },
];

export const PASOS_GUIA_FIRMA: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-firma-seccion"]', titulo: "Tu firma, una sola vez",
    texto: "Aparece en tu contrato de trabajo. Si además firmas documentos por la empresa, o firmas tus boletas, es esta misma firma la que se usa." },
  { selector: '[data-tour="mio-firma-editor"]', titulo: "Subirla, dibujarla o escribirla",
    texto: "Puedes subir una imagen, dibujarla o escribirla con tu nombre oficial, que no se puede cambiar. La guardas aquí y queda lista para cuando haga falta." },
];

export const PASOS_GUIA_DNI: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-dni-seccion"]', titulo: "Las fotos de tu DNI",
    texto: "Subes una foto de cada cara. Se revisan antes de que queden guardadas: hasta entonces tu ficha sigue con lo que ya tenía. Las ven Administración y tu líder de equipo; nadie más." },
  { selector: '[data-tour="mio-dni-caras"]', titulo: "Lo guardado y lo que propones",
    texto: "Arriba de cada recuadro está lo que ya está guardado; lo que eliges abajo es solo una propuesta hasta que se aprueba." },
  { selector: '[data-tour="mio-dni-autorizacion"]', titulo: "La autorización, antes de enviar",
    texto: "Marcas que autorizas el tratamiento de tus datos, y queda guardado el texto exacto que ves aquí. Hacen falta las dos caras y la autorización para poder enviar." },
];

export const PASOS_GUIA_SEGURO: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-seguro-principal"]', titulo: "En qué seguro estás",
    texto: "Si tu seguro lleva póliza ves su número, hasta cuándo te cubre y la aseguradora. Si lo gestiona la empresa con la planilla, como EsSalud, dice solo eso: ahí no hay póliza ni PDF." },
  { selector: '[data-tour="mio-seguro-archivos"]', titulo: "Los PDF de tu póliza",
    texto: "Tu póliza y tu convenio de pago, para abrirlos o descargarlos y tenerlos a la mano en el celular." },
  { selector: '[data-tour="mio-seguro-como-usarlo"]', titulo: "Cómo usarla",
    texto: "Los pasos para usar tu póliza, los teléfonos de la aseguradora y algunas cosas que no cubre. Esa lista de lo que no cubre no está completa." },
];

export const PASOS_GUIA_DATOS: readonly PasoRecorrido[] = [
  { selector: '[data-tour="mio-datos-seccion"]', titulo: "Lo que Desarrollo Organizacional tiene de ti",
    texto: "Esta pantalla solo se lee: no tiene botón de editar. Revisa que esté todo bien." },
  { selector: '[data-tour="mio-datos-bloques"]', titulo: "Qué hay registrado",
    texto: "Tu identidad, lo laboral, tu contacto, tu cuenta bancaria, tu contacto de emergencia y los familiares registrados para el Seguro de Vida Ley y EsSalud." },
  { selector: '[data-tour="mio-editar-datos"]', titulo: "Cambiar algo",
    texto: "Desde «Editar datos» puedes cambiar tu celular, dirección, contacto de emergencia, estado civil, grado de instrucción, hijos a cargo y cuenta bancaria. El resto lo corrige Desarrollo Organizacional." },
];
