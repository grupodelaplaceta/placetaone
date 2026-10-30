// Forma del cliente de sesión que usan las pantallas. En el proyecto real lo da @supabase/supabase-js.
export function initSb(): Promise<void>;
export function sb(): {
  auth: {
    getSession(): Promise<{ data: { session: any } }>;
    onAuthStateChange(cb: (e: any, s: any) => void): { data: { subscription: { unsubscribe(): void } } };
    signInWithPassword(x: { email: string; password: string }): Promise<{ data: { session: any; user: any }; error: any }>;
    signOut(): Promise<any>;
  };
  from(t: string): any;
  rpc(f: string, a?: any): any;
  [k: string]: any;
};
