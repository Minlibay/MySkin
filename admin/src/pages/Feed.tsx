import { useState } from 'react';
import { api } from '../api';

const DEFAULT_FEED_URL =
  'https://feeds.advcake.ru/feed/download/ee4fe7c65692ee30af71b937fb396a64';
const DEFAULT_AD_MARKER =
  'Реклама. ООО ЕКАТЕРИНБУРГ ЯБЛОКО, ИНН 6670381056, erid: LdtCKFJmG';

type Category = { id: string; name: string; offer_count: number };

type PreviewState = {
  total_offers: number;
  categories: Category[];
  sample: {
    external_id: string;
    name: string;
    brand: string;
    price_rub: number;
    category_id: string;
    picture: string | null;
  } | null;
};

type ImportResult = {
  ok: boolean;
  inserted: number;
  updated: number;
  skipped: number;
  deleted_junk: number;
  total: number;
  photos_fetched: number;
  photos_failed: number;
  errors?: Array<{ external_id: string; error: string }>;
};

export default function Feed() {
  const [url, setUrl] = useState(DEFAULT_FEED_URL);
  const [adMarker, setAdMarker] = useState(DEFAULT_AD_MARKER);
  const [preview, setPreview] = useState<PreviewState | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState('');
  const [loadingPreview, setLoadingPreview] = useState(false);
  const [importing, setImporting] = useState(false);
  const [result, setResult] = useState<ImportResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function runPreview() {
    setError(null);
    setResult(null);
    setLoadingPreview(true);
    try {
      const p = await api.feedPreview(url.trim());
      setPreview(p);
      setSelected(new Set());
    } catch (e) {
      const code = String(e).replace(/^.*ApiError:?\s*/, '');
      setError(
        code === 'feed_download_failed'
          ? 'Не получилось скачать фид. Возможно, ещё генерируется на стороне поставщика — попробуй через минуту.'
          : `Не удалось получить превью: ${code}`
      );
    } finally {
      setLoadingPreview(false);
    }
  }

  async function runImport() {
    if (selected.size === 0) return;
    setError(null);
    setImporting(true);
    setResult(null);
    try {
      const r = await api.feedImport({
        url: url.trim(),
        categoryIds: Array.from(selected),
        adMarkerText: adMarker.trim(),
      });
      setResult(r);
    } catch (e) {
      setError(`Импорт упал: ${String(e)}`);
    } finally {
      setImporting(false);
    }
  }

  function toggle(id: string) {
    const next = new Set(selected);
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
    }
    setSelected(next);
  }

  function selectAllVisible(filtered: Category[]) {
    setSelected(new Set(filtered.map((c) => c.id)));
  }

  const filtered = preview?.categories.filter((c) =>
    c.name.toLowerCase().includes(search.toLowerCase())
  ) ?? [];
  const totalSelectedOffers = filtered
    .filter((c) => selected.has(c.id))
    .reduce((sum, c) => sum + c.offer_count, 0);

  return (
    <div className="max-w-4xl">
      <div className="eyebrow text-rose mb-1">Импорт</div>
      <h1 className="font-serif text-4xl mb-2">
        Из <span className="italic text-rose">фида</span>
      </h1>
      <p className="text-ink2 text-sm mb-6 max-w-2xl">
        Загружает товары из XML-фида (Yandex Market формат — advcake, Golden
        Apple и т.д.) Превью покажет категории и количество офферов в
        каждой; ты отметишь нужные и нажмёшь «Импортировать». Товары
        сохраняются как <b>черновики</b> — потом ревьюишь и публикуешь.
        Всем импортированным автоматически проставляется маркировка
        рекламы (текст ниже редактируется).
      </p>

      <div className="card p-6 mb-6 space-y-4">
        <label className="block">
          <div className="eyebrow mb-1.5">URL фида</div>
          <input
            className="input font-mono text-xs"
            value={url}
            onChange={(e) => setUrl(e.target.value)}
            placeholder="https://feeds.advcake.ru/feed/download/..."
          />
        </label>
        <label className="block">
          <div className="eyebrow mb-1.5">
            Текст маркировки рекламы (для всех импортированных)
          </div>
          <textarea
            className="input min-h-[60px] py-2 text-xs"
            value={adMarker}
            onChange={(e) => setAdMarker(e.target.value)}
          />
          <div className="text-[11px] text-ink2 mt-1.5">
            Оставь пустым, если не хочешь автоматически проставлять
            маркировку.
          </div>
        </label>
        <button
          className="btn-primary"
          onClick={runPreview}
          disabled={loadingPreview || !url.trim()}
        >
          {loadingPreview ? 'Загружаем…' : 'Получить категории'}
        </button>
      </div>

      {error && (
        <div className="text-warning bg-warning/10 border border-warning/30 rounded-xl px-4 py-3 mb-6">
          {error}
        </div>
      )}

      {preview && (
        <div className="card p-6 mb-6">
          <div className="flex items-baseline justify-between mb-3">
            <div>
              <div className="eyebrow">Категории</div>
              <div className="text-sm text-ink2 mt-1">
                Всего в фиде {preview.total_offers} офферов. Выбрано
                категорий: {selected.size}, офферов: {totalSelectedOffers}.
              </div>
            </div>
            <div className="flex gap-2">
              <button
                className="btn-ghost text-xs"
                onClick={() => selectAllVisible(filtered)}
              >
                Выделить видимые
              </button>
              <button
                className="btn-ghost text-xs"
                onClick={() => setSelected(new Set())}
              >
                Снять всё
              </button>
            </div>
          </div>
          <input
            className="input mb-3"
            placeholder="Поиск по названию категории…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <div className="max-h-[420px] overflow-y-auto border border-black/5 rounded-xl">
            {filtered.length === 0 ? (
              <div className="p-4 text-ink2 text-sm">Ничего не нашлось.</div>
            ) : (
              filtered.map((c) => (
                <label
                  key={c.id}
                  className="flex items-center gap-3 px-4 py-2 border-b border-black/5 last:border-b-0 cursor-pointer hover:bg-black/[0.02]"
                >
                  <input
                    type="checkbox"
                    checked={selected.has(c.id)}
                    onChange={() => toggle(c.id)}
                    className="w-4 h-4 accent-rose"
                  />
                  <span className="flex-1 text-sm">{c.name}</span>
                  <span className="text-xs text-ink2 font-mono">
                    {c.offer_count}
                  </span>
                </label>
              ))
            )}
          </div>
          <div className="mt-4 flex items-center gap-3">
            <button
              className="btn-primary"
              disabled={importing || selected.size === 0}
              onClick={runImport}
            >
              {importing
                ? 'Импортируем…'
                : `Импортировать ${totalSelectedOffers} офферов`}
            </button>
            {importing && (
              <span className="text-xs text-ink2">
                Может занять минуту — не закрывай вкладку.
              </span>
            )}
          </div>
        </div>
      )}

      {result && (
        <div className="card p-6">
          <div className="eyebrow text-success mb-2">Готово</div>
          <div className="font-serif text-2xl mb-3">
            {result.inserted + result.updated} товаров в каталоге
          </div>
          <ul className="text-sm space-y-1 text-ink2">
            <li>Создано: {result.inserted}</li>
            <li>Обновлено (по external_id): {result.updated}</li>
            <li>
              Пропущено как не-skincare: {result.skipped}
              {result.deleted_junk > 0 && (
                <span className="text-warning">
                  {' '}
                  · удалено из предыдущих импортов: {result.deleted_junk}
                </span>
              )}
            </li>
            <li>Всего в выбранных категориях: {result.total}</li>
            <li>
              Скачано фото: {result.photos_fetched}
              {result.photos_failed > 0 && (
                <span className="text-warning">
                  {' '}
                  · не удалось: {result.photos_failed}
                </span>
              )}
            </li>
          </ul>
          {result.errors && result.errors.length > 0 && (
            <details className="mt-4">
              <summary className="cursor-pointer text-xs text-warning">
                Ошибки ({result.errors.length})
              </summary>
              <pre className="mt-2 p-3 bg-warning/10 rounded-xl text-[11px] overflow-x-auto">
                {result.errors
                  .map((e) => `${e.external_id}: ${e.error}`)
                  .join('\n')}
              </pre>
            </details>
          )}
          <p className="text-xs text-ink2 mt-4">
            Все импортированные товары — черновики. Перейди в «Каталог» и
            пройди по новым: проставь теги, тип кожи, при желании подтяни
            фото из URL и опубликуй.
          </p>
        </div>
      )}
    </div>
  );
}
