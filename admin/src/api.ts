// Tiny fetch wrapper around the Моя Кожа backend admin API.

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

  productList(
    params: {
      q?: string;
      kind?: string;
      limit?: number;
      offset?: number;
    } = {}
  ) {
    const qs = new URLSearchParams();
    if (params.q) qs.set('q', params.q);
    if (params.kind) qs.set('kind', params.kind);
    if (params.limit != null) qs.set('limit', String(params.limit));
    if (params.offset != null) qs.set('offset', String(params.offset));
    const suffix = qs.toString() ? `?${qs.toString()}` : '';
    return this.request<{
      items: AdminProduct[];
      total: number;
      limit: number;
      offset: number;
    }>(`/admin/products${suffix}`);
  },

  publishAllDrafts() {
    return this.request<{ ok: boolean; published: number }>(
      '/admin/products/publish-drafts',
      { method: 'POST' }
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

  productUploadPhotoSlot(
    id: string,
    slot: number,
    photoB64: string,
    mime: string
  ) {
    return this.request<{ ok: boolean }>(
      `/admin/products/${id}/photo/${slot}`,
      {
        method: 'POST',
        body: JSON.stringify({ photo_b64: photoB64, mime }),
      }
    );
  },

  productDeletePhotoSlot(id: string, slot: number) {
    return this.request<{ ok: boolean }>(
      `/admin/products/${id}/photo/${slot}`,
      { method: 'DELETE' }
    );
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

  productPhotoUrl(id: string, slot?: number) {
    return slot == null
      ? `${this.baseUrl}/products/${id}/photo`
      : `${this.baseUrl}/products/${id}/photo/${slot}`;
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

  getAiSettings() {
    return this.request<AiSettings>('/admin/settings/ai');
  },

  setAiSettings(input: AiSettingsPatch) {
    return this.request<{ ok: boolean }>('/admin/settings/ai', {
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

  // ===== Partners =====
  listPartners() {
    return this.request<{ items: AdminPartner[] }>('/admin/partners');
  },
  createPartner(input: {
    login: string;
    password: string;
    company_name: string;
    contact_email?: string;
    contact_phone?: string;
    note?: string;
  }) {
    return this.request<AdminPartner>('/admin/partners', {
      method: 'POST',
      body: JSON.stringify(input),
    });
  },
  blockPartner(id: string) {
    return this.request(`/admin/partners/${id}/block`, { method: 'POST' });
  },
  unblockPartner(id: string) {
    return this.request(`/admin/partners/${id}/unblock`, { method: 'POST' });
  },
  resetPartnerPassword(id: string, password: string) {
    return this.request(`/admin/partners/${id}/reset-password`, {
      method: 'POST',
      body: JSON.stringify({ password }),
    });
  },

  // ===== Brands moderation =====
  listBrands(status?: 'pending' | 'approved' | 'rejected') {
    return this.request<{ items: AdminBrand[] }>(
      `/admin/brands${status ? `?status=${status}` : ''}`
    );
  },
  approveBrand(id: string) {
    return this.request(`/admin/brands/${id}/approve`, { method: 'POST' });
  },
  rejectBrand(id: string, reason: string) {
    return this.request(`/admin/brands/${id}/reject`, {
      method: 'POST',
      body: JSON.stringify({ reason }),
    });
  },
  assignBrand(id: string, partnerId: string | null) {
    return this.request(`/admin/brands/${id}/assign`, {
      method: 'POST',
      body: JSON.stringify({ partner_id: partnerId }),
    });
  },

  // ===== Product moderation =====
  listPendingProducts() {
    return this.request<{ items: AdminProduct[] }>(
      '/admin/products?moderation_status=pending&limit=200'
    );
  },
  approveProductModeration(id: string) {
    return this.request(`/admin/products/${id}/moderate/approve`, {
      method: 'POST',
    });
  },
  rejectProductModeration(id: string, reason: string) {
    return this.request(`/admin/products/${id}/moderate/reject`, {
      method: 'POST',
      body: JSON.stringify({ reason }),
    });
  },

  // ===== Feed import =====
  feedPreview(url: string) {
    return this.request<{
      total_offers: number;
      categories: Array<{ id: string; name: string; offer_count: number }>;
      sample: {
        external_id: string;
        name: string;
        brand: string;
        price_rub: number;
        category_id: string;
        picture: string | null;
      } | null;
    }>('/admin/feed/preview', {
      method: 'POST',
      body: JSON.stringify({ url }),
    });
  },
  feedImport(params: {
    url: string;
    categoryIds: string[];
    adMarkerText: string;
    source?: string;
  }) {
    return this.request<{
      ok: boolean;
      inserted: number;
      updated: number;
      skipped: number;
      deleted_junk: number;
      total: number;
      photos_fetched: number;
      photos_failed: number;
      errors?: Array<{ external_id: string; error: string }>;
    }>('/admin/feed/import', {
      method: 'POST',
      body: JSON.stringify({
        url: params.url,
        category_ids: params.categoryIds,
        ad_marker_text: params.adMarkerText,
        source: params.source ?? 'advcake',
      }),
    });
  },

  changePassword(currentPassword: string, newPassword: string) {
    return this.request<{ ok: boolean }>('/admin/change-password', {
      method: 'POST',
      body: JSON.stringify({
        current_password: currentPassword,
        new_password: newPassword,
      }),
    });
  },
};

export type AdminPartner = {
  id: string;
  login: string;
  company_name: string;
  contact_email: string | null;
  contact_phone: string | null;
  note: string | null;
  is_blocked: boolean;
  created_at: string;
  last_login_at: string | null;
};

export type AdminBrand = {
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

export type AiProviderModels = {
  chat_model: string | null;
  vision_model: string | null;
  available_models: string[];
};

export type AiSettings = {
  provider: 'gigachat' | 'qwen';
  available_providers: Array<'gigachat' | 'qwen'>;
  gigachat: AiProviderModels;
  qwen: AiProviderModels;
};

export type AiSettingsPatch = {
  provider?: 'gigachat' | 'qwen';
  gigachat?: { chat_model?: string; vision_model?: string };
  qwen?: { chat_model?: string; vision_model?: string };
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
  photo_slots?: number[];
  buy_url?: string | null;
  moderation_status?: 'approved' | 'pending' | 'rejected';
  moderation_reason?: string | null;
  submitted_by_partner_id?: string | null;
  composition?: string | null;
  precautions?: string | null;
  usage?: string | null;
  extra_info?: string | null;
  ad_marker_visible?: boolean;
  ad_marker_text?: string | null;
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
  buy_url?: string | null;
  composition?: string | null;
  precautions?: string | null;
  usage?: string | null;
  extra_info?: string | null;
  ad_marker_visible?: boolean;
  ad_marker_text?: string | null;
};

export const PRODUCT_KINDS: Array<{ id: string; label: string }> = [
  { id: 'cleanser', label: 'Очищение' },
  { id: 'scrub', label: 'Скраб' },
  { id: 'peeling', label: 'Пилинг' },
  { id: 'toner', label: 'Тоник' },
  { id: 'pad', label: 'Пэды' },
  { id: 'essence', label: 'Эссенция' },
  { id: 'mask', label: 'Маска' },
  { id: 'eye_patch', label: 'Патчи для глаз' },
  { id: 'serum', label: 'Сыворотка' },
  { id: 'eye_serum', label: 'Сыворотка для глаз' },
  { id: 'eye_cream', label: 'Крем для глаз' },
  { id: 'moisturizer', label: 'Крем' },
  { id: 'spf', label: 'SPF' },
];

export const PRODUCT_TAGS: Array<{ id: string; label: string }> = [
  { id: 'acne', label: 'Акне / прыщи' },
  { id: 'blackheads', label: 'Чёрные точки' },
  { id: 'pih', label: 'Постакне' },
  { id: 'pores', label: 'Расширенные поры' },
  { id: 'oiliness', label: 'Жирный блеск' },
  { id: 'dryness', label: 'Сухость' },
  { id: 'dehydration', label: 'Обезвоженность' },
  { id: 'redness', label: 'Покраснения' },
  { id: 'rosacea', label: 'Розацеа / купероз' },
  { id: 'sensitivity', label: 'Чувствительная кожа' },
  { id: 'irritation', label: 'Раздражение' },
  { id: 'aging', label: 'Признаки старения' },
  { id: 'wrinkles', label: 'Морщины' },
  { id: 'elasticity', label: 'Упругость и плотность' },
  { id: 'dullness', label: 'Тусклый тон' },
  { id: 'pigmentation', label: 'Пигментация' },
  { id: 'texture', label: 'Неровный рельеф' },
  { id: 'dark_circles', label: 'Круги под глазами' },
  { id: 'puffiness', label: 'Отёчность' },
  { id: 'barrier', label: 'Восстановление барьера' },
  { id: 'post_procedure', label: 'После процедур' },
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
