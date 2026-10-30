declare module "react" {
  export type ReactNode = any;
  export type FormEvent<T = any> = { preventDefault(): void; currentTarget: T };
  export function useState<T>(v: T | (() => T)): [T, (v: T | ((p: T) => T)) => void];
  export function useEffect(f: () => void | (() => void), d?: readonly unknown[]): void;
  export function useCallback<T extends (...a: any[]) => any>(f: T, d: readonly unknown[]): T;
  export function useMemo<T>(f: () => T, d: readonly unknown[]): T;
  export function useRef<T>(v: T): { current: T };
  const React: any; export default React;
}
declare namespace JSX { interface IntrinsicAttributes { key?: any } interface IntrinsicElements { div: { [k: string]: any; onClick?: (e: any) => void }; [e: string]: any; input: { [k: string]: any; onChange?: (e: any) => void; onKeyDown?: (e: any) => void }; select: { [k: string]: any; onChange?: (e: any) => void }; textarea: { [k: string]: any; onChange?: (e: any) => void }; button: { [k: string]: any; onClick?: (e: any) => void }; form: { [k: string]: any; onSubmit?: (e: any) => void }; a: { [k: string]: any; onClick?: (e: any) => void } } interface Element {} interface ElementChildrenAttribute { children: {} } }
declare namespace React { type ReactNode = any; type FormEvent<T = any> = { preventDefault(): void; currentTarget: T }; }
declare module "react/jsx-runtime" { export const jsx: any; export const jsxs: any; export const Fragment: any; }
declare module "react/jsx-dev-runtime" { export const jsxDEV: any; export const Fragment: any; }
