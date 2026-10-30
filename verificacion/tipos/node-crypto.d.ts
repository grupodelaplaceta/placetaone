declare module "node:crypto" {
  export function createHmac(alg: string, key: string): { update(data: string): { digest(enc: "hex" | "base64url"): string } };
  export function randomBytes(n: number): { toString(enc: "hex" | "base64url"): string };
  export function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean;
}
declare module "crypto" { export * from "node:crypto"; }
declare module "node:crypto" {
  export function randomUUID(): string;
  export function createHash(alg: string): { update(data: string): { digest(enc: "hex" | "base64url"): string } };
}
