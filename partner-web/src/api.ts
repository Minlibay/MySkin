// Тонкий API-клиент партнёрского кабинета. Все запросы идут на backend
// (api.моякожа.рф) — этот SPA сам по себе только статика.
//
// Токен хранится в localStorage и подкладывается в Authorization. Никакого
// SSR — если токена нет, App перебрасывает на /login.

const BASE_URL =
  (import.meta.env.VITE_BACKEND_URL || '').replace(/\/$/, '') ||
  'https://api.xn--80aafdpbnbtbcvu1f.xn--p1ai';

const TOKEN_KEY = 'myskin.partner.token';

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(t: string | null) {
  if (t) localStorage.setItem(TOKEN_KEY, t);
  else localStorage.removeItem(TOKEN_KEY);
}

async function req<T>(
  method: string,
  path: string,
  body?: unknown
): Promise<T> {
  const headers: Record<string, string> = {
    Accept: 'application/json',
  };
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';

  const res = await fetch(`${BASE_URL}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (res.status === 401) {
    setToken(null);
    // Hard reload — simpler than wiring an event bus, and the login page
    // is what the user needs anyway.
    if (location.pathname !== '/login') location.href = '/login';
    throw new Error('unauthorized');
  }
  if (!res.ok) {
    let detail = '';
    try {
      const j = (await res.json()) as Record<string, unknown>;
      detail = (j.error as string) || (j.message as string) || '';
    } catch {
      // Body wasn't JSON — fall through with empty detail.
    }
    throw new Error(detail || `HTTP ${res.status}`);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

export type Partner = {
  id: string;
  login: string;
  company_name: string;
  contact_email: string | null;
  contact_phone: string | null;
};

export type Brand = {
  id: string;
  name: string;
  slug: string;
  owner_partner_id: string | null;
  status: 'approved' | 'pending' | 'rejected';
  moderation_reason: string | null;
  submitted_at: string | null;
  reviewed_at: string | null;
  created_at: string;
};

export type Product = {
  id: string;
  slug: string;
  brand: string;
  name: string;
  kind: string;
  description: string;
  price_rub: number;
  accent_color: string;
  ingredients: string[];
  tags: string[];
  skin_types: string[];
  routine_phase: string;
  gentle: boolean;
  is_active: boolean;
  status: 'draft' | 'published';
  has_photo: boolean;
  buy_url: string | null;
  moderation_status: 'approved' | 'pending' | 'rejected';
  moderation_reason: string | null;
};

export type ProductInput = {
  slug: string;
  brand_id: string;
  name: string;
  kind: string;
  description?: string;
  price_rub?: number;
  accent_color?: string;
  routine_phase?: string;
  gentle?: boolean;
  tags?: string[];
  skin_types?: string[];
  ingredients?: string[];
  buy_url?: string | null;
};

export type StatTotals = {
  impressions: number;
  opens: number;
  buy_clicks: number;
  unique_openers: number;
};

export type DailyPoint = {
  day: string;
  impressions: number;
  opens: number;
  buy_clicks: number;
};

export type ProductStats = {
  product_id: string;
  product_name: string;
  range_from: string;
  totals: StatTotals;
  daily: DailyPoint[];
};

export type TopItem = {
  product_id: string;
  slug: string;
  name: string;
  brand: string;
  count: number;
};

export const api = {
  baseUrl: BASE_URL,

  async login(login: string, password: string) {
    const r = await req<{ token: string; partner: Partner }>(
      'POST',
      '/partner/login',
      { login, password }
    );
    setToken(r.token);
    return r.partner;
  },

  async logout() {
    try {
      await req('POST', '/partner/logout');
    } catch {
      // Ignore — token is being cleared anyway.
    }
    setToken(null);
  },

  me() {
    return req<{ partner: Partner }>('GET', '/partner/me').then(
      (r) => r.partner
    );
  },

  listBrands() {
    return req<{ items: Brand[] }>('GET', '/partner/brands').then(
      (r) => r.items
    );
  },

  createBrand(name: string) {
    return req<Brand>('POST', '/partner/brands', { name });
  },

  listProducts(status?: 'approved' | 'pending' | 'rejected') {
    const qs = status ? `?moderation_status=${status}` : '';
    return req<{ items: Product[] }>('GET', `/partner/products${qs}`).then(
      (r) => r.items
    );
  },

  createProduct(input: ProductInput) {
    return req<Product>('POST', '/partner/products', input);
  },

  updateProduct(id: string, patch: Partial<ProductInput>) {
    return req<Product>('PATCH', `/partner/products/${id}`, patch);
  },

  deleteProduct(id: string) {
    return req<void>('DELETE', `/partner/products/${id}`);
  },

  productStats(productId: string, range: '7d' | '30d' | '90d' | 'all') {
    return req<ProductStats>(
      'GET',
      `/partner/products/${productId}/stats?range=${range}`
    );
  },

  top(
    metric: 'impression' | 'open' | 'buy_click',
    range: '7d' | '30d' | '90d' | 'all',
    limit = 10
  ) {
    return req<{
      metric: string;
      range_from: string;
      items: TopItem[];
    }>(
      'GET',
      `/partner/stats/top?metric=${metric}&range=${range}&limit=${limit}`
    );
  },
};
