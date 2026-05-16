import { FormEvent, useEffect, useMemo, useState } from 'react';
import { api, type Brand, type Product, type ProductInput } from '../api';

const KINDS = [
  ['cleanser', 'Очищение'],
  ['toner', 'Тоник'],
  ['essence', 'Эссенция'],
  ['serum', 'Сыворотка'],
  ['moisturizer', 'Крем'],
  ['spf', 'SPF'],
  ['mask', 'Маска'],
  ['eye_cream', 'Крем для глаз'],
] as const;

const PHASES = [
  ['any', 'Утро и вечер'],
  ['morning', 'Утро'],
  ['evening', 'Вечер'],
] as const;

const STATUS_LABEL: Record<Product['moderation_status'], string> = {
  approved: 'Одобрен',
  pending: 'На модерации',
  rejected: 'Отклонён',
};
const STATUS_CLASS: Record<Product['moderation_status'], string> = {
  approved: 'bg-success/15 text-success',
  pending: 'bg-info/15 text-info',
  rejected: 'bg-warning/15 text-warning',
};

export default function ProductsPage() {
  const [items, setItems] = useState<Product[]>([]);
  const [brands, setBrands] = useState<Brand[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [editing, setEditing] = useState<Product | null>(null);
  const [creating, setCreating] = useState(false);

  function load() {
    setLoading(true);
    Promise.all([api.listProducts(), api.listBrands()])
      .then(([prods, br]) => {
        setItems(prods);
        setBrands(br);
      })
      .catch((e) => setErr(String(e)))
      .finally(() => setLoading(false));
  }
  useEffect(load, []);

  const approvedBrands = useMemo(
    () => brands.filter((b) => b.status === 'approved'),
    [brands]
  );

  async function onDelete(p: Product) {
    if (
      !confirm(
        `Удалить «${p.name}»? Действие нельзя отменить.`
      )
    )
      return;
    try {
      await api.deleteProduct(p.id);
      load();
    } catch (e) {
      const code = String(e).replace(/^Error: /, '');
      alert(
        code === 'cannot_delete_approved'
          ? 'Одобренный товар удалить нельзя — напишите администратору, чтобы снять с публикации.'
          : `Ошибка: ${code}`
      );
    }
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-end justify-between">
        <div>
          <div className="eyebrow text-rose mb-1">Каталог</div>
          <h1 className="font-serif text-3xl">Мои товары</h1>
          <p className="text-sm text-ink2 mt-1 max-w-lg">
            Каждый новый товар уходит на модерацию администратору. После
            одобрения он появляется в каталоге приложения.
          </p>
        </div>
        <button
          className="btn-primary"
          onClick={() => setCreating(true)}
          disabled={approvedBrands.length === 0}
          title={
            approvedBrands.length === 0
              ? 'Сначала нужен одобренный бренд'
              : ''
          }
        >
          + Новый товар
        </button>
      </div>

      {approvedBrands.length === 0 && !loading && (
        <div className="card p-5 border-warning/30">
          <div className="font-medium mb-1">Нет одобренных брендов</div>
          <div className="text-sm text-ink2">
            Чтобы создавать товары, сначала добавьте бренд во вкладке
            «Мои бренды» и дождитесь одобрения администратором.
          </div>
        </div>
      )}

      {err && <div className="card p-4 text-warning">{err}</div>}

      {loading ? (
        <div className="card p-8 text-center text-ink2">Загрузка…</div>
      ) : items.length === 0 ? (
        <div className="card p-10 text-center text-ink2">
          Товаров пока нет.
        </div>
      ) : (
        <div className="card overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-blush text-ink2">
              <tr>
                <Th>Бренд</Th>
                <Th>Название</Th>
                <Th>Тип</Th>
                <Th>Цена</Th>
                <Th>Статус</Th>
                <Th>&nbsp;</Th>
              </tr>
            </thead>
            <tbody>
              {items.map((p) => (
                <tr
                  key={p.id}
                  className="border-t border-black/5 hover:bg-blush/40"
                >
                  <td className="px-4 py-3">{p.brand}</td>
                  <td className="px-4 py-3 font-medium">
                    {p.name}
                    {p.moderation_status === 'rejected' &&
                      p.moderation_reason && (
                        <div className="text-[11px] text-warning mt-1">
                          {p.moderation_reason}
                        </div>
                      )}
                  </td>
                  <td className="px-4 py-3 text-ink2">{p.kind}</td>
                  <td className="px-4 py-3 font-mono">{p.price_rub} ₽</td>
                  <td className="px-4 py-3">
                    <span
                      className={`px-2 py-0.5 rounded-full text-[11px] ${STATUS_CLASS[p.moderation_status]}`}
                    >
                      {STATUS_LABEL[p.moderation_status]}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-right whitespace-nowrap">
                    <button
                      className="text-xs text-rose hover:underline mr-3"
                      onClick={() => setEditing(p)}
                    >
                      Изменить
                    </button>
                    {p.moderation_status !== 'approved' && (
                      <button
                        className="text-xs text-warning hover:underline"
                        onClick={() => onDelete(p)}
                      >
                        Удалить
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {creating && (
        <ProductFormModal
          brands={approvedBrands}
          onClose={() => setCreating(false)}
          onSaved={() => {
            setCreating(false);
            load();
          }}
        />
      )}
      {editing && (
        <ProductFormModal
          brands={approvedBrands}
          initial={editing}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            load();
          }}
        />
      )}
    </div>
  );
}

function Th({ children }: { children: React.ReactNode }) {
  return (
    <th className="text-left font-mono text-[10px] uppercase tracking-wider px-4 py-3">
      {children}
    </th>
  );
}

function ProductFormModal({
  brands,
  initial,
  onClose,
  onSaved,
}: {
  brands: Brand[];
  initial?: Product;
  onClose: () => void;
  onSaved: () => void;
}) {
  const initialBrandId = useMemo(
    () =>
      initial
        ? brands.find((b) => b.name === initial.brand)?.id ?? brands[0]?.id
        : brands[0]?.id,
    [initial, brands]
  );
  const [brandId, setBrandId] = useState<string>(initialBrandId ?? '');
  const [slug, setSlug] = useState(initial?.slug ?? '');
  const [name, setName] = useState(initial?.name ?? '');
  const [kind, setKind] = useState<string>(initial?.kind ?? 'serum');
  const [description, setDescription] = useState(initial?.description ?? '');
  const [priceRub, setPriceRub] = useState<number>(initial?.price_rub ?? 0);
  const [accentColor, setAccentColor] = useState(
    initial?.accent_color ?? '#D98FA3'
  );
  const [routinePhase, setRoutinePhase] = useState(
    initial?.routine_phase ?? 'any'
  );
  const [gentle, setGentle] = useState(initial?.gentle ?? false);
  const [buyUrl, setBuyUrl] = useState(initial?.buy_url ?? '');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  function autoSlug(v: string) {
    if (initial) return; // don't surprise the user on edit
    setSlug(
      v
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-|-$/g, '')
    );
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    setErr(null);
    if (!brandId || !slug.trim() || !name.trim() || !kind) {
      setErr('Заполните бренд, slug, название и тип.');
      return;
    }
    setBusy(true);
    try {
      const input: ProductInput = {
        slug: slug.trim(),
        brand_id: brandId,
        name: name.trim(),
        kind,
        description: description.trim(),
        price_rub: priceRub,
        accent_color: accentColor,
        routine_phase: routinePhase,
        gentle,
        buy_url: buyUrl.trim() ? buyUrl.trim() : null,
      };
      if (initial) {
        await api.updateProduct(initial.id, input);
      } else {
        await api.createProduct(input);
      }
      onSaved();
    } catch (e) {
      const code = String(e).replace(/^Error: /, '');
      setErr(
        code === 'slug_taken'
          ? 'Такой slug уже используется. Подбери другой.'
          : code === 'brand_not_owned'
          ? 'Бренд не принадлежит вашему аккаунту.'
          : code === 'brand_not_approved'
          ? 'Бренд ещё не одобрен модератором.'
          : `Ошибка: ${code}`
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-40 bg-black/40 backdrop-blur-sm flex items-center justify-center p-4 overflow-auto">
      <form
        onSubmit={submit}
        className="card w-full max-w-2xl my-8 flex flex-col"
      >
        <div className="px-6 pt-5 pb-3 border-b border-black/5 flex items-start justify-between">
          <div>
            <div className="eyebrow text-rose mb-1">
              {initial ? 'Редактирование' : 'Новый товар'}
            </div>
            <div className="font-serif text-2xl">
              {initial ? initial.name : 'Подать на модерацию'}
            </div>
            {initial && (
              <div className="text-xs text-ink2 mt-1">
                После сохранения товар снова уйдёт на проверку.
              </div>
            )}
          </div>
          <button
            type="button"
            onClick={onClose}
            className="text-ink2 hover:text-ink text-lg leading-none"
          >
            ×
          </button>
        </div>

        <div className="p-6 grid grid-cols-2 gap-4">
          <Field label="Бренд" className="col-span-2">
            <select
              className="input"
              value={brandId}
              onChange={(e) => setBrandId(e.target.value)}
              disabled={!!initial}
            >
              {brands.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </select>
          </Field>

          <Field label="Название" className="col-span-2">
            <input
              className="input"
              value={name}
              onChange={(e) => {
                setName(e.target.value);
                autoSlug(e.target.value);
              }}
              required
            />
          </Field>

          <Field label="Slug">
            <input
              className="input font-mono"
              value={slug}
              onChange={(e) => setSlug(e.target.value)}
              required
            />
          </Field>
          <Field label="Тип">
            <select
              className="input"
              value={kind}
              onChange={(e) => setKind(e.target.value)}
            >
              {KINDS.map(([id, lbl]) => (
                <option key={id} value={id}>
                  {lbl}
                </option>
              ))}
            </select>
          </Field>

          <Field label="Цена, ₽">
            <input
              type="number"
              className="input"
              min={0}
              value={priceRub}
              onChange={(e) => setPriceRub(parseInt(e.target.value) || 0)}
            />
          </Field>
          <Field label="Когда применять">
            <select
              className="input"
              value={routinePhase}
              onChange={(e) => setRoutinePhase(e.target.value)}
            >
              {PHASES.map(([id, lbl]) => (
                <option key={id} value={id}>
                  {lbl}
                </option>
              ))}
            </select>
          </Field>

          <Field label="Цвет (плашка-флакон)" className="col-span-2">
            <div className="flex items-center gap-3">
              <input
                type="color"
                className="w-12 h-10 rounded-lg border border-black/10 cursor-pointer"
                value={accentColor}
                onChange={(e) => setAccentColor(e.target.value)}
              />
              <input
                className="input flex-1 font-mono"
                value={accentColor}
                onChange={(e) => setAccentColor(e.target.value)}
              />
            </div>
          </Field>

          <Field label="Описание" className="col-span-2">
            <textarea
              className="input min-h-[80px] py-2"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Кратко: для какой задачи и для какой кожи"
            />
          </Field>

          <Field label="Ссылка «Купить»" className="col-span-2">
            <input
              className="input"
              type="url"
              value={buyUrl}
              onChange={(e) => setBuyUrl(e.target.value)}
              placeholder="https://"
            />
            <div className="text-[11px] text-ink2 mt-1.5">
              Куда вести пользователя из приложения. Можно оставить пустым.
            </div>
          </Field>

          <label className="col-span-2 flex items-center gap-2 cursor-pointer">
            <input
              type="checkbox"
              checked={gentle}
              onChange={(e) => setGentle(e.target.checked)}
            />
            <span className="text-sm">Подходит чувствительной коже</span>
          </label>
        </div>

        {err && (
          <div className="mx-6 mb-4 text-sm text-warning bg-warning/10 border border-warning/30 rounded-xl px-3 py-2">
            {err}
          </div>
        )}

        <div className="px-6 pb-6 flex justify-end gap-2 border-t border-black/5 pt-4">
          <button type="button" className="btn-ghost" onClick={onClose}>
            Отмена
          </button>
          <button type="submit" className="btn-primary" disabled={busy}>
            {busy
              ? 'Сохраняем…'
              : initial
              ? 'Сохранить и отправить'
              : 'Подать на модерацию'}
          </button>
        </div>
      </form>
    </div>
  );
}

function Field({
  label,
  children,
  className,
}: {
  label: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <label className={`block ${className ?? ''}`}>
      <div className="eyebrow mb-1.5">{label}</div>
      {children}
    </label>
  );
}
