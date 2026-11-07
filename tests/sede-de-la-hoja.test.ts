// ============================================================================
// sede-de-la-hoja.test.ts — la Hoja de sede abre la sede de quien la mira
// ============================================================================
// El caso que la originó (2026-11-07): Luz, líder de equipo de TRU, abría la Hoja
// de sede desde el menú y le salía Arequipa —la primera por código—, vacía, con
// «Nada pendiente en disciplina. Buena señal.». Lo que se defiende acá: quien ve
// solo su sede abre la suya y no se le ofrece otra, DO sigue eligiendo entre todas,
// y la dirección (`?sede=`) nunca se contesta con una sede distinta de la pedida.
// ============================================================================

import { describe, expect, it } from "vitest";
import { sedeDeLaHoja } from "@/lib/admin/sede-de-la-hoja";

const AQP = { id: "aqp", codigo: "AQP" };
const CCO = { id: "cco", codigo: "CCO" };
const LIM = { id: "lim", codigo: "LIM" };
const TRU = { id: "tru", codigo: "TRU" };
const ACTIVAS = [AQP, CCO, LIM, TRU];

const LIDER_TRU = { veTodas: false, sedeBaseId: "tru" };
const DO = { veTodas: true, sedeBaseId: "cco" };

describe("la líder de equipo", () => {
  it("abre su sede desde el menú, no la primera de la lista", () => {
    const r = sedeDeLaHoja(ACTIVAS, LIDER_TRU, null);
    expect(r.abre).toEqual(TRU);
  });

  it("solo se le ofrece su sede: las otras le saldrían vacías", () => {
    expect(sedeDeLaHoja(ACTIVAS, LIDER_TRU, null).sedes).toEqual([TRU]);
  });

  it("con ?sede=TRU, abre TRU", () => {
    expect(sedeDeLaHoja(ACTIVAS, LIDER_TRU, "tru").abre).toEqual(TRU);
  });

  it("con ?sede=AQP no abre AQP ni la suya: dice que esa sede no es la suya", () => {
    const r = sedeDeLaHoja(ACTIVAS, LIDER_TRU, "AQP");
    expect(r.abre).toBeNull();
    expect(r.sinHoja).toEqual({ motivo: "no-es-tuya", codigo: "AQP" });
  });

  it("un código que no existe se distingue de una sede ajena", () => {
    expect(sedeDeLaHoja(ACTIVAS, LIDER_TRU, "XYZ").sinHoja).toEqual({ motivo: "no-existe", codigo: "XYZ" });
  });

  it("si su sede no está activa, no se le abre otra en su lugar", () => {
    const r = sedeDeLaHoja([AQP, CCO, LIM], LIDER_TRU, null);
    expect(r.abre).toBeNull();
    expect(r.sinHoja).toEqual({ motivo: "sin-sede-propia", codigo: null });
  });

  it("sin sede en su ficha, tampoco se le abre otra", () => {
    expect(sedeDeLaHoja(ACTIVAS, { veTodas: false, sedeBaseId: null }, null).abre).toBeNull();
  });
});

describe("DO y la dirección", () => {
  it("abren la primera de la lista, como hasta hoy", () => {
    expect(sedeDeLaHoja(ACTIVAS, DO, null).abre).toEqual(AQP);
  });

  it("se les ofrecen todas", () => {
    expect(sedeDeLaHoja(ACTIVAS, DO, null).sedes).toEqual(ACTIVAS);
  });

  it("con ?sede= abren la pedida (el enlace de Sedes)", () => {
    expect(sedeDeLaHoja(ACTIVAS, DO, "lim").abre).toEqual(LIM);
  });

  it("un código que no existe no cae a la primera", () => {
    const r = sedeDeLaHoja(ACTIVAS, DO, "XYZ");
    expect(r.abre).toBeNull();
    expect(r.sinHoja).toEqual({ motivo: "no-existe", codigo: "XYZ" });
  });

  it("sin ninguna sede activa, lo dice", () => {
    expect(sedeDeLaHoja([], DO, null).sinHoja).toEqual({ motivo: "ninguna-activa", codigo: null });
  });
});
