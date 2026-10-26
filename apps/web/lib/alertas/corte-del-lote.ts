// CUÁNDO SE CORTA EL LOTE — la decisión, separada del bucle que la aplica.
//
// PROMETE: dado el resultado de cada envío, en orden, dice si hay que dejar de
// reservar filas y si a la fila que falló se le devuelve el intento. Es una
// función pura con un contador (`Racha`) que el llamador conserva entre filas.
// ASUME: solo recibe los envíos que PASARON por Resend. Los avisos «sin
// destinatario» no llegan aquí: no son un éxito ni un fallo del canal, y por eso
// ni suman ni reinician ninguna racha.
//
// POR QUÉ EXISTE. El 2026-10-25, 61 avisos gastaron sus tres intentos contra UNA
// avería (dominio sin verificar). La reserva gasta un intento ANTES de enviar y
// el cron es diario, así que tres intentos son tres DÍAS. Distinguir si el
// problema es del canal (todas las filas fallarán igual) o de la fila (solo esa
// dirección) es lo que evita matar sesenta filas por una sola causa. Pero esa
// distinción se apoya en reconocer los mensajes de Resend, y Resend puede
// cambiarlos o traer uno que no conocemos: por eso hay además un disyuntor que
// no depende de reconocer nada.
//
// LAS REGLAS, cada una con el caso real que la justifica:
//  · Causa DETERMINISTA del canal (remitente sin verificar, clave inválida,
//    variable sin configurar): corta a la primera y DEVUELVE el intento de esa
//    fila. Con esas causas la fila no pudo tener culpa; sin devolverlo, la fila
//    más vieja (el contrato que vence primero) moría definitiva al tercer día de
//    avería sin haber hecho nada.
//  · Límite de envíos: corta a la primera (la ruta ya reintentó UNA vez si era
//    «por segundo»). NO devuelve el intento: no es seguro que la culpa sea ajena.
//  · Resend caído (5xx, tiempo agotado, red): corta a la SEGUNDA fila seguida.
//    Una fila envenenada que produce un 500 en Resend no debe dejar sin correo a
//    todas las demás; dos seguidas ya sí es una caída. Tampoco devuelve el
//    intento, justo por eso: devolverlo dejaría a la fila envenenada reintentar
//    para siempre y bloquear cada lote.
//  · Disyuntor: 3 fallos SEGUIDOS de la misma causa de FILA ('otra',
//    'rechazo_de_resend') sin un éxito en medio se tratan como avería del canal.
//    Es la red de seguridad para lo que Dynamic no sabe reconocer: una clave
//    suspendida cayó en 'otra' y, sin esto, mataba las 61 filas igual que antes.

import type { CausaDeFallo, CausaInfo } from "./causa-del-fallo";

/** Causas que no pueden ser culpa de una fila: arreglarlas es tocar el canal. */
const DETERMINISTAS_DEL_CANAL: readonly CausaDeFallo[] = ["remitente_sin_verificar", "clave_invalida", "configuracion_faltante"];

/** Cuántos fallos seguidos de la misma causa de fila hacen saltar el disyuntor. */
export const FALLOS_SEGUIDOS_PARA_CORTAR = 3;

/** Cuántas caídas seguidas de Resend (5xx, red, tiempo) hacen falta para cortar. */
export const CAIDAS_SEGUIDAS_PARA_CORTAR = 2;

/** Lo que se recuerda de las filas anteriores. Se crea una vez por lote. */
export interface Racha {
  caidasSeguidas: number;
  causaDeFilaSeguida: CausaDeFallo | null;
  fallosDeFilaSeguidos: number;
}

export function rachaNueva(): Racha {
  return { caidasSeguidas: 0, causaDeFilaSeguida: null, fallosDeFilaSeguidos: 0 };
}

export type ResultadoParaCorte = { ok: true } | { ok: false; causa: CausaInfo };

export type DecisionDeCorte =
  | { corta: false }
  | {
      corta: true;
      /** 'canal' = se sabe qué se averió; 'disyuntor' = no se sabe, pero fue lo mismo tres veces. */
      razon: "canal" | "disyuntor";
      /** true = a esa fila hay que devolverle el intento que la reserva le gastó. */
      devolverIntento: boolean;
    };

/** Registra el resultado de un envío en la racha y dice si se corta. Modifica `racha`. */
export function decidirCorte(racha: Racha, resultado: ResultadoParaCorte): DecisionDeCorte {
  if (resultado.ok) {
    racha.caidasSeguidas = 0;
    racha.causaDeFilaSeguida = null;
    racha.fallosDeFilaSeguidos = 0;
    return { corta: false };
  }

  const { causa, del_canal: delCanal } = resultado.causa;

  // Sin destinatario no pasa por Resend: no cuenta para nada (defensivo, la
  // ruta ni siquiera lo envía aquí).
  if (causa === "sin_destinatario") return { corta: false };

  if (DETERMINISTAS_DEL_CANAL.includes(causa)) {
    return { corta: true, razon: "canal", devolverIntento: true };
  }

  if (causa === "resend_caido") {
    racha.causaDeFilaSeguida = null;
    racha.fallosDeFilaSeguidos = 0;
    racha.caidasSeguidas++;
    return racha.caidasSeguidas >= CAIDAS_SEGUIDAS_PARA_CORTAR
      ? { corta: true, razon: "canal", devolverIntento: false }
      : { corta: false };
  }

  // Cualquier otra avería del canal (hoy, el límite de envíos): corta a la primera.
  if (delCanal) return { corta: true, razon: "canal", devolverIntento: false };

  // Causa de FILA o desconocida: se sigue con la siguiente, hasta que se repite
  // tantas veces que ya no parece de la fila.
  racha.caidasSeguidas = 0;
  if (racha.causaDeFilaSeguida === causa) {
    racha.fallosDeFilaSeguidos++;
  } else {
    racha.causaDeFilaSeguida = causa;
    racha.fallosDeFilaSeguidos = 1;
  }
  return racha.fallosDeFilaSeguidos >= FALLOS_SEGUIDOS_PARA_CORTAR
    ? { corta: true, razon: "disyuntor", devolverIntento: false }
    : { corta: false };
}
