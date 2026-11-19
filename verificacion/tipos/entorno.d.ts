declare module "@supabase/supabase-js" { export function createClient(url: string, key: string, opts?: any): any; export type SupabaseClient = any; }
declare module "next/headers" { export function cookies(): Promise<any>; }
declare module "next/navigation" { export function usePathname(): string; export function redirect(url: string): never; export function notFound(): never; export function useRouter(): any; }
declare module "next/link" { const Link: any; export default Link; }
declare module "next/navigation" { export function useParams<T = Record<string, string>>(): T; export function usePathname(): string; export function useRouter(): any; }
declare module "*.css" { const x: any; export default x; }
