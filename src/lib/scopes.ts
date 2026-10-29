// Catálogo único de permisos de las claves de API (el servidor rechaza cualquier scope que no esté aquí)
export const SCOPES = [
  { k: "accounts:read", l: "Consultar cuentas y saldos" }, { k: "accounts:write", l: "Abrir cuentas desde un producto" },
  { k: "transactions:read", l: "Ver movimientos de una cuenta" }, { k: "transfers:write", l: "Crear transferencias" }, { k: "transfers:read", l: "Consultar una transferencia" },
  { k: "receipts:read", l: "Ver recibos fiscales" }, { k: "cards:read", l: "Ver tarjetas de una cuenta" }, { k: "memberships:read", l: "Consultar la membresía de una cuenta Junior" }, { k: "memberships:write", l: "Renovar la membresía de una cuenta Junior" }, { k: "products:read", l: "Ver el catálogo de productos activo" },
] as const;
export const SCOPE_KEYS: string[] = SCOPES.map(s => s.k);
export const ENDPOINTS: [string, string, string][] = [
  ["GET", "/api/v1/products", "products:read"], ["GET", "/api/v1/accounts/{iban}/membership", "memberships:read"], ["POST", "/api/v1/accounts/{iban}/membership/renew", "memberships:write"], ["POST", "/api/v1/accounts", "accounts:write"], ["GET", "/api/v1/accounts/{iban}", "accounts:read"],
  ["GET", "/api/v1/accounts/{iban}/transactions", "transactions:read"], ["GET", "/api/v1/accounts/{iban}/receipts", "receipts:read"], ["GET", "/api/v1/accounts/{iban}/cards", "cards:read"],
  ["POST", "/api/v1/transfers", "transfers:write"], ["GET", "/api/v1/transfers/{ref}", "transfers:read"],
];
