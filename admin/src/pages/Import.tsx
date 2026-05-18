import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { api } from '../api';
import ProductForm, {
  ProductFormResult,
  ProductPrefill,
} from '../components/ProductForm';

/// Bookmarklet sends payloads from goldapple.ru — we strict-check origin
/// before accepting anything as input.
const GA_ORIGIN = 'https://goldapple.ru';

type IncomingPayload = {
  type: 'myskin-import-payload';
  payload: {
    source_url: string;
    brand?: string;
    name?: string;
    description?: string;
    price_rub?: number;
    composition?: string;
    usage?: string;
    precautions?: string;
    extra_info?: string;
    ingredients?: string[];
    photo_data_urls?: string[];
    debug?: string;
  };
};

export default function Import() {
  const [params] = useSearchParams();
  const source = params.get('source');
  if (source === 'ga') return <ImportReceiver />;
  return <BookmarkletInfo />;
}

function BookmarkletInfo() {
  const adminOrigin = window.location.origin;
  const bookmarkletJs = useMemo(
    () => buildBookmarkletJs(adminOrigin),
    [adminOrigin]
  );
  const href = `javascript:${encodeURIComponent(bookmarkletJs)}`;
  return (
    <div className="max-w-2xl">
      <div className="eyebrow text-rose mb-1">Импорт</div>
      <h1 className="font-serif text-4xl mb-4">
        Из <span className="italic text-rose">Golden Apple</span>
      </h1>
      <p className="text-ink2 text-sm mb-6">
        Перетащи кнопку ниже в панель закладок браузера. Открой любую
        карточку товара на <code>goldapple.ru</code> и нажми эту закладку —
        админка откроется новой вкладкой с заполненной карточкой. Картинки
        и текст подтянутся автоматически, тип/теги/типы кожи проставишь
        руками перед публикацией.
      </p>
      <div className="card p-6 flex flex-col gap-4">
        <div className="eyebrow">Шаг 1 — перетащи в закладки</div>
        <div className="flex items-center gap-3">
          <a
            href={href}
            className="btn-primary cursor-grab active:cursor-grabbing"
            onClick={(e) => {
              e.preventDefault();
              alert(
                'Не кликай — перетащи эту кнопку в панель закладок браузера.'
              );
            }}
          >
            ⇪ Импорт в МойСкин
          </a>
          <span className="text-ink2 text-xs">
            Левой кнопкой → удерживай → перетащи на панель закладок.
          </span>
        </div>
        <div className="eyebrow mt-2">Шаг 2 — на goldapple.ru</div>
        <ol className="text-sm text-ink2 list-decimal pl-5 space-y-1">
          <li>Открой страницу товара.</li>
          <li>Нажми закладку «Импорт в МойСкин».</li>
          <li>
            Откроется новая вкладка с этой админкой и предзаполненной
            карточкой. Проверь, поправь, опубликуй (или сохрани черновик).
          </li>
        </ol>
        <details className="text-xs text-ink2 mt-2">
          <summary className="cursor-pointer">Код букмарклета (для отладки)</summary>
          <pre className="mt-2 p-3 bg-ink/5 rounded-xl overflow-x-auto whitespace-pre-wrap break-all">
            {bookmarkletJs}
          </pre>
        </details>
      </div>
    </div>
  );
}

function ImportReceiver() {
  const [payload, setPayload] = useState<IncomingPayload['payload'] | null>(
    null
  );
  const [waiting, setWaiting] = useState(true);
  const navigate = useNavigate();

  useEffect(() => {
    function onMessage(e: MessageEvent) {
      if (e.origin !== GA_ORIGIN) return;
      const data = e.data as IncomingPayload | undefined;
      if (data?.type !== 'myskin-import-payload') return;
      setPayload(data.payload);
      setWaiting(false);
    }
    window.addEventListener('message', onMessage);
    // Ping the opener (bookmarklet on goldapple.ru) — it's listening for
    // this 'ready' before posting the payload, to avoid sending into an
    // unloaded window.
    if (window.opener) {
      try {
        window.opener.postMessage(
          { type: 'myskin-import-ready' },
          GA_ORIGIN
        );
      } catch {
        // opener might be cross-origin and rejecting; that's fine, the
        // bookmarklet will retry on a timer.
      }
    }
    // Bail out of waiting state after 30s so user sees the BookmarkletInfo
    // instead of a hanging spinner if they opened the URL by accident.
    const t = window.setTimeout(() => setWaiting(false), 30_000);
    return () => {
      window.removeEventListener('message', onMessage);
      window.clearTimeout(t);
    };
  }, []);

  if (waiting) {
    return (
      <div className="max-w-xl">
        <div className="eyebrow text-rose mb-1">Импорт</div>
        <h1 className="font-serif text-3xl mb-3">Ждём данные…</h1>
        <p className="text-ink2 text-sm">
          Ничего не делай — закладка с goldapple.ru сейчас передаст карточку
          и форма откроется сама.
        </p>
      </div>
    );
  }

  if (!payload) {
    return (
      <div className="max-w-xl">
        <h1 className="font-serif text-3xl mb-3">Не удалось получить данные</h1>
        <p className="text-ink2 text-sm">
          Похоже, эта вкладка была открыта не из букмарклета на goldapple.ru.
          Вернись на страницу{' '}
          <a className="text-rose underline" href="/import">
            Импорт
          </a>{' '}
          и попробуй ещё раз.
        </p>
      </div>
    );
  }

  const prefill: ProductPrefill = {
    brand: payload.brand,
    name: payload.name,
    description: payload.description,
    priceRub: payload.price_rub,
    composition: payload.composition,
    usage: payload.usage,
    precautions: payload.precautions,
    extraInfo: payload.extra_info,
    ingredients: payload.ingredients,
    buyUrl: payload.source_url,
    photoDataUrl: payload.photo_data_urls?.[0],
    photoMime: guessMimeFromDataUrl(payload.photo_data_urls?.[0]),
    extraPhotoDataUrls: (payload.photo_data_urls ?? [])
      .slice(1, 4)
      .map((u) => ({ dataUrl: u, mime: guessMimeFromDataUrl(u) })),
    slug: makeSlug(payload.brand, payload.name),
  };

  return (
    <ProductForm
      prefill={prefill}
      onCancel={() => navigate('/products')}
      onSave={async (r: ProductFormResult) => {
        const created = await api.productCreate(r.input);
        if (r.photo) {
          const b64 = r.photo.dataUrl.split(',')[1] ?? '';
          if (b64) await api.productUploadPhoto(created.id, b64, r.photo.mime);
        }
        for (const e of r.extraPhotos) {
          if (e.dataUrl) {
            const b64 = e.dataUrl.split(',')[1] ?? '';
            if (b64) {
              await api.productUploadPhotoSlot(created.id, e.slot, b64, e.mime);
            }
          }
        }
        navigate('/products');
      }}
    />
  );
}

function guessMimeFromDataUrl(u: string | undefined): string {
  if (!u) return 'image/jpeg';
  const m = /^data:([^;]+);/i.exec(u);
  return m?.[1] ?? 'image/jpeg';
}

function makeSlug(brand?: string, name?: string): string {
  const s = `${brand ?? ''}-${name ?? ''}`
    .toLowerCase()
    .replace(/[^a-z0-9а-яё]+/gi, '-')
    .replace(/^-|-$/g, '');
  return s;
}

/// Bookmarklet source. Reads product data from goldapple.ru product pages
/// using the first available signal (JSON-LD → OpenGraph → known window
/// globals → DOM). Fetches images as data URLs in the user's browser
/// session (bypassing Cloudflare), then opens the admin import URL and
/// posts the payload via window.postMessage once the receiver pings ready.
function buildBookmarkletJs(adminOrigin: string): string {
  const adminUrl = `${adminOrigin}/import?source=ga`;
  // Keep this function self-contained — bookmarklets can't import.
  function run(adminUrlInjected: string) {
    const ADMIN_URL = adminUrlInjected;
    const ADMIN_ORIGIN = new URL(ADMIN_URL).origin;

    function pickFromJsonLd(): any | null {
      const scripts = Array.from(
        document.querySelectorAll('script[type="application/ld+json"]')
      ) as HTMLScriptElement[];
      for (const s of scripts) {
        try {
          const data = JSON.parse(s.textContent || 'null');
          const arr = Array.isArray(data) ? data : [data];
          for (const node of arr) {
            const type = node?.['@type'];
            if (
              type === 'Product' ||
              (Array.isArray(type) && type.includes('Product'))
            ) {
              return node;
            }
            // Some sites nest under @graph
            const graph = node?.['@graph'];
            if (Array.isArray(graph)) {
              for (const g of graph) {
                if (
                  g?.['@type'] === 'Product' ||
                  (Array.isArray(g?.['@type']) &&
                    g['@type'].includes('Product'))
                ) {
                  return g;
                }
              }
            }
          }
        } catch (_) {
          // ignore malformed JSON-LD
        }
      }
      return null;
    }

    function meta(name: string): string | undefined {
      const sels = [
        `meta[property="${name}"]`,
        `meta[name="${name}"]`,
      ];
      for (const sel of sels) {
        const el = document.querySelector(sel) as HTMLMetaElement | null;
        if (el?.content) return el.content;
      }
      return undefined;
    }

    function metaAll(name: string): string[] {
      const sels = [
        `meta[property="${name}"]`,
        `meta[name="${name}"]`,
      ];
      const out: string[] = [];
      for (const sel of sels) {
        document.querySelectorAll(sel).forEach((el) => {
          const c = (el as HTMLMetaElement).content;
          if (c) out.push(c);
        });
      }
      return out;
    }

    function toNumberPrice(v: any): number | undefined {
      if (v == null) return undefined;
      if (typeof v === 'number') return Math.round(v);
      const m = String(v).replace(/[^\d.,]/g, '').replace(',', '.');
      const n = parseFloat(m);
      return isFinite(n) ? Math.round(n) : undefined;
    }

    function blobToDataUrl(blob: Blob): Promise<string> {
      return new Promise((resolve, reject) => {
        const r = new FileReader();
        r.onload = () => resolve(r.result as string);
        r.onerror = () => reject(r.error);
        r.readAsDataURL(blob);
      });
    }

    async function fetchAsDataUrl(url: string): Promise<string | null> {
      try {
        const resp = await fetch(url, { credentials: 'include' });
        if (!resp.ok) return null;
        const blob = await resp.blob();
        // Skip oversized images — backend caps at 6 MB.
        if (blob.size > 5.5 * 1024 * 1024) return null;
        return await blobToDataUrl(blob);
      } catch (_) {
        return null;
      }
    }

    function uniqueUrls(urls: (string | undefined)[]): string[] {
      const seen = new Set<string>();
      const out: string[] = [];
      for (const u of urls) {
        if (!u) continue;
        const abs = (() => {
          try {
            return new URL(u, location.href).toString();
          } catch {
            return null;
          }
        })();
        if (!abs || seen.has(abs)) continue;
        seen.add(abs);
        out.push(abs);
      }
      return out;
    }

    /// Walks any object tree and returns the "richest" node that looks like
    /// a product card — i.e. has the highest count of product-shaped keys
    /// (name/brand/price/images/...). Used to dig product data out of
    /// __NUXT__ / __INITIAL_STATE__ / custom globals without knowing the
    /// exact path.
    function findProductLikeNode(root: any): any | null {
      const productKeys = [
        'name',
        'title',
        'brand',
        'brandName',
        'price',
        'priceCurrent',
        'priceActual',
        'images',
        'imageUrls',
        'mediaList',
        'description',
        'shortDescription',
        'composition',
        'ingredients',
        'usage',
        'howToUse',
        'warning',
        'precautions',
        'itemId',
        'sku',
        'productCode',
      ];
      let best: any = null;
      let bestScore = 0;
      const seen = new WeakSet();
      function walk(o: any, depth: number) {
        if (depth > 14 || o == null || typeof o !== 'object') return;
        if (seen.has(o)) return;
        seen.add(o);
        if (Array.isArray(o)) {
          for (const v of o) walk(v, depth + 1);
          return;
        }
        const keys = Object.keys(o);
        const score = keys.filter((k) => productKeys.includes(k)).length;
        if (score >= 3 && score > bestScore) {
          bestScore = score;
          best = o;
        }
        for (const k of keys) walk(o[k], depth + 1);
      }
      walk(root, 0);
      return best;
    }

    function pickStr(...vals: any[]): string | undefined {
      for (const v of vals) {
        if (typeof v === 'string' && v.trim()) return v.trim();
      }
      return undefined;
    }

    function htmlToText(html: string): string {
      const div = document.createElement('div');
      div.innerHTML = html;
      return div.textContent?.trim() ?? '';
    }

    function collectImageUrls(node: any, out: string[]) {
      if (node == null) return;
      if (typeof node === 'string') {
        if (/\.(jpe?g|png|webp|avif)(\?|$)/i.test(node)) out.push(node);
        return;
      }
      if (Array.isArray(node)) {
        for (const v of node) collectImageUrls(v, out);
        return;
      }
      if (typeof node === 'object') {
        // Common shapes: {url}, {src}, {full}, {large}, {original}
        for (const k of ['url', 'src', 'full', 'large', 'original', 'href']) {
          if (typeof node[k] === 'string') out.push(node[k]);
        }
      }
    }

    async function extract(): Promise<any> {
      const ld = pickFromJsonLd();
      const debug: string[] = [];

      let brand: string | undefined;
      let name: string | undefined;
      let description: string | undefined;
      let price: number | undefined;
      let composition: string | undefined;
      let usage: string | undefined;
      let precautions: string | undefined;
      const imageUrls: string[] = [];

      if (ld) {
        debug.push('jsonld');
        if (typeof ld.brand === 'string') brand = ld.brand;
        else if (ld.brand?.name) brand = ld.brand.name;
        if (typeof ld.name === 'string') name = ld.name;
        if (typeof ld.description === 'string')
          description = ld.description;
        const offer = Array.isArray(ld.offers) ? ld.offers[0] : ld.offers;
        if (offer) price = toNumberPrice(offer.price);
        const img = ld.image;
        if (typeof img === 'string') imageUrls.push(img);
        else if (Array.isArray(img))
          img.forEach((x) => typeof x === 'string' && imageUrls.push(x));
      }

      // Nuxt / Vue / generic global state fallback.
      const w = window as any;
      const globalSources = [
        w.__NUXT__,
        w.__INITIAL_STATE__,
        w.__NEXT_DATA__,
        w.__APOLLO_STATE__,
      ].filter(Boolean);
      for (const src of globalSources) {
        if (name && brand && imageUrls.length) break;
        const node = findProductLikeNode(src);
        if (!node) continue;
        debug.push('global');
        if (!brand) {
          brand = pickStr(
            typeof node.brand === 'string' ? node.brand : null,
            node.brand?.title,
            node.brand?.name,
            node.brandName
          );
        }
        if (!name) name = pickStr(node.name, node.title);
        if (!description) {
          const d = pickStr(
            node.description,
            node.shortDescription,
            node.descriptionHtml,
            node.descriptionFull
          );
          if (d) description = /<[a-z]/i.test(d) ? htmlToText(d) : d;
        }
        if (!price) {
          price = toNumberPrice(
            node.priceCurrent ??
              node.priceActual ??
              node.price?.actual?.amount ??
              node.price?.amount ??
              node.price
          );
        }
        if (!composition) {
          const c = pickStr(
            node.composition,
            node.ingredients,
            node.attributes?.composition,
            node.attributes?.ingredients
          );
          if (c) composition = /<[a-z]/i.test(c) ? htmlToText(c) : c;
        }
        if (!usage) {
          const u = pickStr(
            node.usage,
            node.howToUse,
            node.attributes?.usage,
            node.application
          );
          if (u) usage = /<[a-z]/i.test(u) ? htmlToText(u) : u;
        }
        if (!precautions) {
          const p = pickStr(
            node.precautions,
            node.warning,
            node.warnings,
            node.contraindications,
            node.attributes?.warnings
          );
          if (p) precautions = /<[a-z]/i.test(p) ? htmlToText(p) : p;
        }
        collectImageUrls(node.images, imageUrls);
        collectImageUrls(node.imageUrls, imageUrls);
        collectImageUrls(node.mediaList, imageUrls);
        collectImageUrls(node.gallery, imageUrls);
      }

      // OpenGraph fallback (GA's og:* is generic for the storefront, not
      // per product — keep it as last resort).
      if (!name) name = meta('og:title');
      if (!description) description = meta('og:description');
      if (!price) price = toNumberPrice(meta('product:price:amount'));
      if (!brand) brand = meta('og:brand') || meta('product:brand');
      metaAll('og:image').forEach((u) => imageUrls.push(u));
      metaAll('og:image:secure_url').forEach((u) => imageUrls.push(u));

      // DOM fallback for images: any product gallery img.
      if (imageUrls.length === 0) {
        document
          .querySelectorAll<HTMLImageElement>(
            'img[src*="goldapple"], img[data-src*="goldapple"]'
          )
          .forEach((el) => {
            const src = el.getAttribute('src') || el.getAttribute('data-src');
            if (src) imageUrls.push(src);
          });
      }

      // Title fallback
      if (!name) name = document.title.split('|')[0].trim();

      // Fetch top 4 unique images.
      const unique = uniqueUrls(imageUrls).slice(0, 4);
      const photos: string[] = [];
      for (const u of unique) {
        const d = await fetchAsDataUrl(u);
        if (d) photos.push(d);
      }
      debug.push(`images:${photos.length}/${unique.length}`);

      return {
        source_url: location.href,
        brand,
        name,
        description,
        price_rub: price,
        composition,
        usage,
        precautions,
        photo_data_urls: photos,
        debug: debug.join('|'),
      };
    }

    function openReceiverAndSend(payload: any) {
      const w = window.open(ADMIN_URL, '_blank');
      if (!w) {
        alert(
          'Не удалось открыть админку — разреши всплывающие окна для goldapple.ru.'
        );
        return;
      }
      let sent = false;
      function send() {
        if (sent) return;
        try {
          w!.postMessage(
            { type: 'myskin-import-payload', payload },
            ADMIN_ORIGIN
          );
          sent = true;
        } catch (_) {
          /* retry */
        }
      }
      // Receiver pings 'ready' once it mounts. If we missed the ping
      // (race), retry every 500ms for 20s.
      window.addEventListener('message', (e) => {
        if (e.origin !== ADMIN_ORIGIN) return;
        if ((e.data as any)?.type === 'myskin-import-ready') send();
      });
      let n = 0;
      const t = window.setInterval(() => {
        if (sent || ++n > 40) {
          window.clearInterval(t);
          return;
        }
        send();
      }, 500);
    }

    extract()
      .then((p) => openReceiverAndSend(p))
      .catch((err) => {
        alert(`Импорт упал: ${err?.message ?? err}`);
      });
  }
  // Stringify the function and inject the admin URL literal so the
  // bookmarklet is self-contained (no template tags inside javascript:).
  const body = run.toString();
  return `javascript:(${body})(${JSON.stringify(adminUrl)});void 0;`;
}
