import bcrypt from "bcryptjs";

export async function verificarPin(pin: string, pinHash: string): Promise<boolean> {
  return bcrypt.compare(pin, pinHash);
}
