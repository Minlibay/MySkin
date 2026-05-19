import { useEffect, useState } from 'react';
import { AdminProduct, PRODUCT_KINDS, api } from '../api';
import ProductForm, { ProductFormResult } from '../components/ProductForm';

const PAGE_SIZE = 50;

export default function Products() {
  const [items, setItems] = useState<AdminProduct[]>([]);
  const [total, setTotal] = useState(0);
  const [offset, setOffset] = useState(0);
  const [loading, setLoading] = useState(false);
  const [q, setQ] = useState('');
  const [kind, setKind] = useState<string>('');
  const [editing, setEditing] = useState<AdminProduct | null>(null);
  const [creating, setCreating] = useState(false);

  async function load(opts: { resetPage?: boolean; gotoOffset?: number } = {}) {
    const targetOffset =
      opts.gotoOffset != null
        ? opts.gotoOffset
        : opts.resetPage
        ? 0
        : offset;
    setLoading(true);
    try {
      const r = await api.productList({
        q: q || undefined,
        kind: kind || undefined,
        limit: PAGE_SIZE,
        offset: targetOffset,
      });
      setItems(r.items);
      setTotal(r.total);
      setOffset(r.offset);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load({ resetPage: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const pageStart = total === 0 ? 0 : offset + 1;
  const pageEnd = Math.min(offset + items.length, total);
  const canPrev = offset > 0;
  const canNext = offset + PAGE_SIZE < total;

  async function uploadPhotoIfAny(
    id: string,
    photo: ProductFormResult['photo']
  ) {
    if (!photo) return;
    const b64 = photo.dataUrl.split(',')[1] ?? '';
    if (!b64) return;
    await api.productUploadPhoto(id, b64, photo.mime);
  }

  async function syncExtraPhotos(
    id: string,
    extras: ProductFormResult['extraPhotos']
  ) {
    for (const e of extras) {
      if (e.dataUrl == null) {
        await api.productDeletePhotoSlot(id, e.slot);
      } else {
        const b64 = e.dataUrl.split(',')[1] ?? '';
        if (b64) await api.productUploadPhotoSlot(id, e.slot, b64, e.mime);
      }
    }
  }

  async function onCreate(r: ProductFormResult) {
    const created = await api.productCreate(r.input);
    await uploadPhotoIfAny(created.id, r.photo);
    await syncExtraPhotos(created.id, r.extraPhotos);
    setCreating(false);
    // Reload so the new product lands wherever the brand-name sort puts
    // it and the total count stays accurate.
    await load({ resetPage: true });
  }

  async function onUpdate(r: ProductFormResult) {
    if (!editing) return;
    const updated = await api.productUpdate(editing.id, r.input);
    if (r.photo) await uploadPhotoIfAny(updated.id, r.photo);
    await syncExtraPhotos(updated.id, r.extraPhotos);
    setItems((arr) =>
      arr.map((p) =>
        p.id === updated.id
          ? {
              ...updated,
              has_photo: r.photo ? true : updated.has_photo,
            }
          : p
      )
    );
    setEditing(null);
  }

  async function onDelete(p: AdminProduct) {
    if (!confirm(`Удалить «${p.name}»?`)) return;
    await api.productDelete(p.id);
    // Reload current page so total / pagination stays consistent (and a
    // freed slot at the bottom backfills from the next page).
    await load();
  }

  const [publishing, setPublishing] = useState(false);
  const [cleaning, setCleaning] = useState(false);

  async function onDeleteUntagged() {
    if (
      !confirm(
        'Удалить ВСЕ товары без «Цели» (без тегов)?\n\n' +
          'Действие необратимо.'
      )
    ) {
      return;
    }
    setCleaning(true);
    try {
      const r = await api.deleteUntaggedProducts();
      alert(`Удалено: ${r.deleted} товаров.`);
      await load({ resetPage: true });
    } catch (e) {
      alert(`Не удалось удалить: ${e}`);
    } finally {
      setCleaning(false);
    }
  }

  async function onDeleteDuplicates() {
    if (
      !confirm(
        'Удалить дублирующиеся товары?\n\n' +
          'В каждой группе с одинаковым брендом и названием останется ' +
          'один (с фото и/или самый старый). Действие необратимо.'
      )
    ) {
      return;
    }
    setCleaning(true);
    try {
      const r = await api.deleteDuplicateProducts();
      alert(`Удалено дубликатов: ${r.deleted}.`);
      await load({ resetPage: true });
    } catch (e) {
      alert(`Не удалось удалить: ${e}`);
    } finally {
      setCleaning(false);
    }
  }

  async function onPublishAllDrafts() {
    if (
      !confirm(
        'Опубликовать ВСЕ черновики в каталоге?\n\n' +
          'Пустые "Подходит для типов кожи" автоматически станут "Все типы".'
      )
    ) {
      return;
    }
    setPublishing(true);
    try {
      const r = await api.publishAllDrafts();
      alert(`Опубликовано: ${r.published} товаров.`);
      await load();
    } catch (e) {
      alert(`Не удалось опубликовать: ${e}`);
    } finally {
      setPublishing(false);
    }
  }

  return (
    <div>
      <div className="flex items-end justify-between mb-6">
        <div>
          <div className="eyebrow text-rose mb-1">Каталог</div>
          <h1 className="font-serif text-4xl">
            Все <span className="italic text-rose">продукты</span>
          </h1>
          <div className="text-sm text-ink2 mt-2">
            Всего в каталоге: <b>{total}</b>
            {(q || kind) && total > 0 && (
              <span> · показано {pageStart}–{pageEnd}</span>
            )}
          </div>
        </div>
        <div className="flex gap-2">
          <button
            onClick={onDeleteUntagged}
            className="btn-ghost"
            disabled={cleaning || loading}
            title="Удалить все товары без «Цели» (без тегов)"
          >
            {cleaning ? 'Чистим…' : '× Удалить товары без «Цели»'}
          </button>
          <button
            onClick={onDeleteDuplicates}
            className="btn-ghost"
            disabled={cleaning || loading}
            title="Удалить товары с одинаковым брендом и названием, оставив по одному"
          >
            {cleaning ? 'Чистим…' : '× Удалить дублирующиеся товары'}
          </button>
          <button
            onClick={onPublishAllDrafts}
            className="btn-ghost"
            disabled={publishing || loading}
            title="Опубликовать все черновики в каталоге"
          >
            {publishing ? 'Публикуем…' : '● Опубликовать черновики'}
          </button>
          <button onClick={() => setCreating(true)} className="btn-primary">
            + Новый продукт
          </button>
        </div>
      </div>

      <div className="flex gap-3 mb-4">
        <input
          className="input flex-1 max-w-sm"
          placeholder="Поиск по названию или бренду…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') load({ resetPage: true });
          }}
        />
        <select
          className="input max-w-xs"
          value={kind}
          onChange={(e) => {
            setKind(e.target.value);
            setTimeout(() => load({ resetPage: true }), 0);
          }}
        >
          <option value="">Все типы</option>
          {PRODUCT_KINDS.map((k) => (
            <option key={k.id} value={k.id}>
              {k.label}
            </option>
          ))}
        </select>
        <button
          className="btn-ghost"
          onClick={() => load({ resetPage: true })}
          disabled={loading}
        >
          Найти
        </button>
      </div>

      <div className="card overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-blush/40 text-ink2">
            <tr>
              <th className="px-4 py-3 text-left font-medium text-xs uppercase tracking-wide">
                Бренд / Название
              </th>
              <th className="px-4 py-3 text-left font-medium text-xs uppercase tracking-wide">
                Статус
              </th>
              <th className="px-4 py-3 text-left font-medium text-xs uppercase tracking-wide">
                Тип
              </th>
              <th className="px-4 py-3 text-left font-medium text-xs uppercase tracking-wide">
                Цена
              </th>
              <th className="px-4 py-3 text-left font-medium text-xs uppercase tracking-wide">
                Цели
              </th>
              <th className="px-4 py-3 text-left font-medium text-xs uppercase tracking-wide">
                Когда
              </th>
              <th className="px-4 py-3 text-right">Действия</th>
            </tr>
          </thead>
          <tbody>
            {items.map((p) => (
              <tr
                key={p.id}
                className="border-t border-black/5 hover:bg-blush/20"
              >
                <td className="px-4 py-3">
                  <div className="flex items-center gap-3">
                    {p.has_photo ? (
                      <img
                        src={api.productPhotoUrl(p.id)}
                        alt=""
                        className="w-8 h-10 object-cover rounded shrink-0 border border-black/5"
                      />
                    ) : (
                      <div
                        className="w-8 h-10 rounded shrink-0"
                        style={{
                          background: `linear-gradient(180deg, white, ${p.accent_color})`,
                          border: '1px solid rgba(0,0,0,0.05)',
                        }}
                      />
                    )}
                    <div>
                      <div className="text-xs text-ink2">{p.brand}</div>
                      <div className="font-medium">{p.name}</div>
                    </div>
                  </div>
                </td>
                <td className="px-4 py-3">
                  {p.status === 'published' ? (
                    <span className="px-2 py-0.5 rounded-full bg-success/15 text-success text-xs">
                      ● опубликован
                    </span>
                  ) : (
                    <span className="px-2 py-0.5 rounded-full bg-ink2/15 text-ink2 text-xs">
                      ○ черновик
                    </span>
                  )}
                </td>
                <td className="px-4 py-3">{kindLabel(p.kind)}</td>
                <td className="px-4 py-3 font-mono">{p.price_rub} ₽</td>
                <td className="px-4 py-3">
                  <div className="flex flex-wrap gap-1">
                    {p.tags.map((t) => (
                      <span
                        key={t}
                        className="px-2 py-0.5 rounded-full bg-blush text-rose text-[10px]"
                      >
                        {t}
                      </span>
                    ))}
                  </div>
                </td>
                <td className="px-4 py-3 text-xs">
                  {p.routine_phase === 'morning'
                    ? '🌅 утро'
                    : p.routine_phase === 'evening'
                    ? '🌙 вечер'
                    : '↻ любое'}
                  {p.is_active && ' · актив'}
                  {p.gentle && ' · деликат.'}
                </td>
                <td className="px-4 py-3 text-right whitespace-nowrap">
                  <button
                    className="btn-ghost h-8 px-3 text-xs"
                    onClick={() => setEditing(p)}
                  >
                    Изменить
                  </button>
                  <button
                    className="ml-2 text-warning hover:underline text-xs"
                    onClick={() => onDelete(p)}
                  >
                    Удалить
                  </button>
                </td>
              </tr>
            ))}
            {!loading && items.length === 0 && (
              <tr>
                <td colSpan={7} className="px-4 py-12 text-center text-ink2">
                  Пока пусто
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {total > 0 && (
        <div className="flex items-center justify-between mt-4 text-sm">
          <div className="text-ink2">
            Показано <b>{pageStart}–{pageEnd}</b> из <b>{total}</b>
          </div>
          <div className="flex items-center gap-2">
            <button
              className="btn-ghost h-9 px-3 text-xs"
              disabled={!canPrev || loading}
              onClick={() =>
                load({ gotoOffset: Math.max(0, offset - PAGE_SIZE) })
              }
            >
              ← Назад
            </button>
            <span className="text-ink2 text-xs px-2">
              Страница {Math.floor(offset / PAGE_SIZE) + 1} из{' '}
              {Math.max(1, Math.ceil(total / PAGE_SIZE))}
            </span>
            <button
              className="btn-ghost h-9 px-3 text-xs"
              disabled={!canNext || loading}
              onClick={() => load({ gotoOffset: offset + PAGE_SIZE })}
            >
              Вперёд →
            </button>
          </div>
        </div>
      )}

      {(creating || editing) && (
        <ProductForm
          initial={editing ?? undefined}
          onCancel={() => {
            setCreating(false);
            setEditing(null);
          }}
          onSave={editing ? onUpdate : onCreate}
        />
      )}
    </div>
  );
}

function kindLabel(id: string) {
  return PRODUCT_KINDS.find((k) => k.id === id)?.label ?? id;
}
