// Tiny fetch wrapper around the MySkin backend admin API.

const TOKEN_KEY = 'myskin-admin-token';

export const api = {
  baseUrl: (import.meta.env.VITE_BACKEND_URL as string) || 'http://localhost:8080',

  getToken(): string | null {
    return localStorage.getItem(TOKEN_KEY);
  },
  setToken(token: string | null) {
    if (token) localStorage.setItem(TOKEN_KEY, token);
    else localStorage.removeItem(TOKEN_KEY);
  },

  async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const token = this.getToken();
    const resp = await fetch(`${this.baseUrl}${path}`, {
      ...init,
      headers: {
        'content-type': 'application/json',
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...(init.headers ?? {}),
      },
    });
    if (resp.status === 401) {
      this.setToken(null);
      throw new ApiError('unauthorized', 401);
    }
    const text = await resp.text();
    let data: unknown;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = text;
    }
    if (!resp.ok) {
      const code =
        (typeof data === 'object' && data && 'error' in data
          ? (data as { error?: string }).error
          : undefined) ?? `http_${resp.status}`;
      throw new ApiError(code, resp.status);
    }
    return data as T;
  },

  // ===== Endpoints =====

  login(login: string, password: string) {
    return this.request<{ token: string }>('/admin/login', {
      method: 'POST',
      body: JSON.stringify({ login, password }),
    });
  },

  stats() {
    return this.request<Stats>('/admin/stats');
  },

  users(params: { q?: string; limit?: number; offset?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.q) qs.set('q', params.q);
    if (params.limit != null) qs.set('limit', String(params.limit));
    if (params.offset != null) qs.set('offset', String(params.offset));
    const suffix = qs.toString() ? `?${qs.toString()}` : '';
    return this.request<UsersPage>(`/admin/users${suffix}`);
  },

  block(userId: string) {
    return this.request<{ ok: boolean }>(
      `/admin/users/${userId}/block`,
      { method: 'POST' }
    );
  },

  unblock(userId: string) {
    return this.request<{ ok: boolean }>(
      `/admin/users/${userId}/unblock`,
      { method: 'POST' }
    );
  },

  userDetail(userId: string) {
    return this.request<UserDetail>(`/admin/users/${userId}`);
  },

  userScans(userId: string) {
    return this.request<{ items: AdminScan[] }>(
      `/admin/users/${userId}/scans`
    );
  },

  userShelf(userId: string) {
    return this.request<{ items: ShelfProduct[] }>(
      `/admin/users/${userId}/shelf`
    );
  },

  productList(params: { q?: string; kind?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.q) qs.set('q', params.q);
    if (params.kind) qs.set('kind', params.kind);
    const suffix = qs.toString() ? `?${qs.toString()}` : '';
    return this.request<{ items: AdminProduct[] }>(
      `/admin/products${suffix}`
    );
  },

  productCreate(input: ProductInput) {
    return this.request<AdminProduct>('/admin/products', {
      method: 'POST',
      body: JSON.stringify(input),
    });
  },

  productUpdate(id: string, patch: Partial<ProductInput>) {
    return this.request<AdminProduct>(`/admin/products/${id}`, {
      method: 'PATCH',
      body: JSON.stringify(patch),
    });
  },

  productDelete(id: string) {
    return this.request<{ ok: boolean }>(`/admin/products/${id}`, {
      method: 'DELETE',
    });
  },

  productUploadPhoto(id: string, photoB64: string, mime: string) {
    return this.request<{ ok: boolean }>(
      `/admin/products/${id}/photo`,
      {
        method: 'POST',
        body: JSON.stringify({ photo_b64: photoB64, mime }),
      }
    );
  },

  productPhotoUrl(id: string) {
    return `${this.baseUrl}/products/${id}/photo`;
  },

  pendingCodes() {
    return this.request<{ items: PendingCode[] }>('/admin/pending-codes');
  },

  getGigaSettings() {
    return this.request<GigaSettings>('/admin/settings/gigachat');
  },

  setGigaSettings(input: { chat_model?: string; vision_model?: string }) {
    return this.request<{ ok: boolean }>('/admin/settings/gigachat', {
      method: 'PUT',
      body: JSON.stringify(input),
    });
  },

  getLegal() {
    return this.request<LegalDocs>('/admin/settings/legal');
  },

  setLegal(input: { terms?: string; privacy?: string; consent?: string }) {
    return this.request<{ ok: boolean }>('/admin/settings/legal', {
      method: 'PUT',
      body: JSON.stringify(input),
    });
  },
};

export type LegalDocs = {
  terms: string;
  privacy: string;
  consent: string;
};

export type GigaSettings = {
  chat_model: string | null;
  vision_model: string | null;
  available_models: string[];
};

export type PendingCode = {
  phone: string;
  code: string;
  sms_sent: boolean;
  attempts: number;
  created_at: string;
  expires_at: string;
};

export class ApiError extends Error {
  constructor(public code: string, public status: number) {
    super(code);
  }
}

export type Stats = {
  users_total: number;
  users_blocked: number;
  users_today: number;
  active_sessions: number;
};

export type AdminUser = {
  id: string;
  phone: string;
  created_at: string;
  last_login_at: string | null;
  is_blocked: boolean;
};

export type UsersPage = {
  items: AdminUser[];
  total: number;
  limit: number;
  offset: number;
};

export type UserDetail = {
  user: AdminUser;
  profile: UserProfile | null;
  shelf_count: number;
  scans_count: number;
  last_scan: AdminScan | null;
};

export type UserProfile = {
  name: string | null;
  skin_type: string | null;
  pores: string | null;
  concerns: string[];
  acne_type: string | null;
  sensitivity: string | null;
  sensitivity_reaction: string | null;
  budget: string | null;
  extras: Record<string, unknown>;
  updated_at: string;
};

export type AdminScan = {
  id: string;
  score: number;
  hydration: number;
  sebum: number;
  tone: number;
  pores: number;
  zones: { forehead: number; tzone: number; cheeks: number; chin: number };
  insight: string;
  has_photo: boolean;
  created_at: string;
};

export type ShelfProduct = Omit<AdminProduct, 'status'> & {
  status: 'have' | 'wishlist' | 'finished';
  added_at: string;
  notes: string | null;
};

export type AdminProduct = {
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
  is_active: boolean;
  gentle: boolean;
  routine_phase: string;
  status: 'draft' | 'published';
  has_photo: boolean;
};

export type ProductInput = {
  slug: string;
  brand: string;
  name: string;
  kind: string;
  description?: string;
  price_rub?: number;
  accent_color?: string;
  ingredients?: string[];
  tags?: string[];
  skin_types?: string[];
  is_active?: boolean;
  gentle?: boolean;
  routine_phase?: string;
  status?: 'draft' | 'published';
};

export const PRODUCT_KINDS: Array<{ id: string; label: string }> = [
  { id: 'cleanser', label: 'Очищение' },
  { id: 'toner', label: 'Тоник' },
  { id: 'essence', label: 'Эссенция' },
  { id: 'serum', label: 'Сыворотка' },
  { id: 'moisturizer', label: 'Крем' },
  { id: 'spf', label: 'SPF' },
  { id: 'mask', label: 'Маска' },
  { id: 'eye_cream', label: 'Крем для глаз' },
];

export const PRODUCT_TAGS: Array<{ id: string; label: string }> = [
  { id: 'acne', label: 'Акне' },
  { id: 'pih', label: 'Постакне' },
  { id: 'aging', label: 'Anti-age' },
  { id: 'dullness', label: 'Тусклость' },
  { id: 'redness', label: 'Покраснения' },
  { id: 'dehydration', label: 'Обезвоженность' },
];

export const SKIN_TYPES: Array<{ id: string; label: string }> = [
  { id: 'all', label: 'Все типы' },
  { id: 'dry', label: 'Сухая' },
  { id: 'oily', label: 'Жирная' },
  { id: 'combo', label: 'Комбинированная' },
  { id: 'normal', label: 'Нормальная' },
  { id: 'sensitive', label: 'Чувствительная' },
];

export const ROUTINE_PHASES: Array<{ id: string; label: string }> = [
  { id: 'any', label: 'Утром или вечером' },
  { id: 'morning', label: 'Утром' },
  { id: 'evening', label: 'Вечером' },
];
