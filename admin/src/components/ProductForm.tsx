import { FormEvent, useState } from 'react';
import {
  AdminProduct,
  PRODUCT_KINDS,
  PRODUCT_TAGS,
  ProductInput,
  ROUTINE_PHASES,
  SKIN_TYPES,
  api,
} from '../api';

export type ProductFormResult = {
  input: ProductInput;
  photo: { dataUrl: string; mime: string } | null;
  /// Optional additional slots 2-4. Only slots that changed are present.
  extraPhotos: {
    slot: number;
    dataUrl: string | null;
    mime: string;
    /// True when user uploaded/replaced. Null dataUrl means user removed.
  }[];
};

export default function ProductForm({
  initial,
  onCancel,
  onSave,
}: {
  initial?: AdminProduct;
  onCancel: () => void;
  onSave: (r: ProductFormResult) => Promise<void>;
}) {
  const [slug, setSlug] = useState(initial?.slug ?? '');
  const [brand, setBrand] = useState(initial?.brand ?? '');
  const [name, setName] = useState(initial?.name ?? '');
  const [kind, setKind] = useState(initial?.kind ?? 'serum');
  const [description, setDescription] = useState(
    initial?.description ?? ''
  );
  const [priceRub, setPriceRub] = useState<number>(
    initial?.price_rub ?? 0
  );
  const [accentColor, setAccentColor] = useState(
    initial?.accent_color ?? '#D98FA3'
  );
  const [routinePhase, setRoutinePhase] = useState(
    initial?.routine_phase ?? 'any'
  );
  const [buyUrl, setBuyUrl] = useState(initial?.buy_url ?? '');
  const [composition, setComposition] = useState(initial?.composition ?? '');
  const [precautions, setPrecautions] = useState(initial?.precautions ?? '');
  const [usage, setUsage] = useState(initial?.usage ?? '');
  const [extraInfo, setExtraInfo] = useState(initial?.extra_info ?? '');
  const [isActive, setIsActive] = useState(initial?.is_active ?? false);
  const [gentle, setGentle] = useState(initial?.gentle ?? false);
  const [tags, setTags] = useState<string[]>(initial?.tags ?? []);
  const [skinTypes, setSkinTypes] = useState<string[]>(
    initial?.skin_types ?? []
  );
  const [ingredients, setIngredients] = useState<string[]>(
    initial?.ingredients ?? []
  );
  const [ingInput, setIngInput] = useState('');
  const [photoUrl, setPhotoUrl] = useState<string | null>(
    initial?.has_photo ? api.productPhotoUrl(initial.id) : null
  );
  const [photoMime, setPhotoMime] = useState<string>('image/jpeg');
  const [photoChanged, setPhotoChanged] = useState(false);
  // Slots 2-4. Each entry tracks its own dataUrl + mime + dirty flag so we
  // only PATCH/DELETE on the server for slots the user actually touched.
  const initialSlots = initial?.photo_slots ?? (initial?.has_photo ? [1] : []);
  const [extraSlots, setExtraSlots] = useState<
    { dataUrl: string | null; mime: string; changed: boolean }[]
  >(() => {
    return [2, 3, 4].map((s) => ({
      dataUrl: initialSlots.includes(s)
        ? api.productPhotoUrl(initial!.id, s)
        : null,
      mime: 'image/jpeg',
      changed: false,
    }));
  });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [pendingStatus, setPendingStatus] = useState<
    'draft' | 'published'
  >(initial?.status ?? 'draft');

  function autoSlug(v: string) {
    if (initial) return;
    setSlug(
      v
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-|-$/g, '')
    );
  }

  function toggleArr(setFn: (a: string[]) => void, arr: string[], v: string) {
    setFn(arr.includes(v) ? arr.filter((x) => x !== v) : [...arr, v]);
  }

  function addIngredient() {
    const v = ingInput.trim();
    if (v && !ingredients.includes(v)) {
      setIngredients([...ingredients, v]);
    }
    setIngInput('');
  }

  function onPickFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 6 * 1024 * 1024) {
      setErr('Фото слишком большое (>6MB)');
      return;
    }
    const reader = new FileReader();
    reader.onload = () => {
      setPhotoUrl(reader.result as string);
      setPhotoMime(file.type || 'image/jpeg');
      setPhotoChanged(true);
      setErr(null);
    };
    reader.readAsDataURL(file);
  }

  async function submit(e: FormEvent, status: 'draft' | 'published') {
    e.preventDefault();
    setErr(null);
    if (!slug.trim() || !brand.trim() || !name.trim() || !kind) {
      setErr('Заполни slug, бренд, название и тип');
      return;
    }
    setBusy(true);
    setPendingStatus(status);
    try {
      const photo =
        photoChanged && photoUrl
          ? {
              dataUrl: photoUrl,
              mime: photoMime,
            }
          : null;
      const extraPhotos = extraSlots
        .map((s, i) => ({
          slot: i + 2,
          dataUrl: s.dataUrl,
          mime: s.mime,
          changed: s.changed,
        }))
        .filter((s) => s.changed)
        .map(({ slot, dataUrl, mime }) => ({ slot, dataUrl, mime }));
      await onSave({
        input: {
          slug: slug.trim(),
          brand: brand.trim(),
          name: name.trim(),
          kind,
          description: description.trim(),
          price_rub: priceRub,
          accent_color: accentColor,
          routine_phase: routinePhase,
          is_active: isActive,
          gentle,
          tags,
          skin_types: skinTypes,
          ingredients,
          status,
          buy_url: buyUrl.trim() ? buyUrl.trim() : null,
          composition: composition.trim() ? composition.trim() : null,
          precautions: precautions.trim() ? precautions.trim() : null,
          usage: usage.trim() ? usage.trim() : null,
          extra_info: extraInfo.trim() ? extraInfo.trim() : null,
        },
        photo,
        extraPhotos,
      });
    } catch (e) {
      setErr(String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/40 backdrop-blur-sm flex items-center justify-center p-4 overflow-auto">
      <form
        onSubmit={(e) => submit(e, pendingStatus)}
        className="bg-white rounded-3xl shadow-lift w-full max-w-2xl my-8"
      >
        <div className="p-6 border-b border-black/5 flex items-start justify-between">
          <div>
            <div className="eyebrow text-rose">
              {initial ? 'Редактирование' : 'Новый продукт'}
            </div>
            <h2 className="font-serif text-3xl">
              {initial ? initial.name : 'Добавить продукт'}
            </h2>
          </div>
          {initial && (
            <span
              className={`px-3 py-1 rounded-full text-xs font-medium ${
                initial.status === 'published'
                  ? 'bg-success/15 text-success'
                  : 'bg-ink2/15 text-ink2'
              }`}
            >
              {initial.status === 'published'
                ? '● опубликован'
                : '○ черновик'}
            </span>
          )}
        </div>
        <div className="p-6 space-y-4">
          <PhotoBlock
            url={photoUrl}
            onPick={onPickFile}
            onRemove={() => {
              setPhotoUrl(null);
              setPhotoChanged(true);
            }}
            accent={accentColor}
          />
          <ExtraPhotosRow
            slots={extraSlots}
            accent={accentColor}
            onPick={(idx, file) => {
              if (file.size > 6 * 1024 * 1024) {
                setErr('Фото слишком большое (>6MB)');
                return;
              }
              const r = new FileReader();
              r.onload = () => {
                setExtraSlots((s) =>
                  s.map((row, i) =>
                    i === idx
                      ? {
                          dataUrl: r.result as string,
                          mime: file.type || 'image/jpeg',
                          changed: true,
                        }
                      : row
                  )
                );
                setErr(null);
              };
              r.readAsDataURL(file);
            }}
            onRemove={(idx) =>
              setExtraSlots((s) =>
                s.map((row, i) =>
                  i === idx
                    ? { dataUrl: null, mime: 'image/jpeg', changed: true }
                    : row
                )
              )
            }
          />

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <Field label="Бренд *">
              <input
                className="input"
                value={brand}
                onChange={(e) => {
                  setBrand(e.target.value);
                  if (!initial) autoSlug(`${e.target.value}-${name}`);
                }}
              />
            </Field>
            <Field label="Название *">
              <input
                className="input"
                value={name}
                onChange={(e) => {
                  setName(e.target.value);
                  if (!initial) autoSlug(`${brand}-${e.target.value}`);
                }}
              />
            </Field>
          </div>
          <Field label="Slug (стабильный URL)">
            <input
              className="input font-mono"
              value={slug}
              onChange={(e) => setSlug(e.target.value)}
              disabled={!!initial}
            />
          </Field>
          <Field label="Описание">
            <textarea
              className="input h-20 py-2"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Что делает продукт. 1–2 предложения."
            />
          </Field>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <Field label="Тип *">
              <select
                className="input"
                value={kind}
                onChange={(e) => setKind(e.target.value)}
              >
                {PRODUCT_KINDS.map((k) => (
                  <option key={k.id} value={k.id}>
                    {k.label}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Цена, ₽">
              <input
                type="number"
                min={0}
                className="input"
                value={priceRub}
                onChange={(e) =>
                  setPriceRub(parseInt(e.target.value) || 0)
                }
              />
            </Field>
            <Field label="Когда применять">
              <select
                className="input"
                value={routinePhase}
                onChange={(e) => setRoutinePhase(e.target.value)}
              >
                {ROUTINE_PHASES.map((r) => (
                  <option key={r.id} value={r.id}>
                    {r.label}
                  </option>
                ))}
              </select>
            </Field>
          </div>

          <Field label="Цвет (фон-флакон, если нет фото)">
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
                placeholder="#D98FA3"
              />
            </div>
          </Field>

          <Field
            label="Ссылка «Купить»"
            help="Куда вести пользователя из приложения по кнопке Купить. Можно оставить пустым."
          >
            <input
              type="url"
              className="input"
              value={buyUrl}
              onChange={(e) => setBuyUrl(e.target.value)}
              placeholder="https://"
            />
          </Field>

          <Field
            label="О составе"
            help="Развёрнутый текст о составе. Лина использует это для подбора и объяснений."
          >
            <textarea
              className="input min-h-[100px] py-2"
              value={composition}
              onChange={(e) => setComposition(e.target.value)}
            />
          </Field>

          <Field
            label="Меры предосторожности"
            help="Противопоказания, аллергии, беременность, тест на запястье и т.п. Лина учитывает их при рекомендациях."
          >
            <textarea
              className="input min-h-[80px] py-2"
              value={precautions}
              onChange={(e) => setPrecautions(e.target.value)}
            />
          </Field>

          <Field label="Как пользоваться">
            <textarea
              className="input min-h-[80px] py-2"
              value={usage}
              onChange={(e) => setUsage(e.target.value)}
            />
          </Field>

          <Field label="Дополнительная информация">
            <textarea
              className="input min-h-[60px] py-2"
              value={extraInfo}
              onChange={(e) => setExtraInfo(e.target.value)}
            />
          </Field>

          <Field label="Помогает с (теги для подбора)">
            <ChipGroup
              options={PRODUCT_TAGS}
              selected={tags}
              onToggle={(v) => toggleArr(setTags, tags, v)}
            />
          </Field>

          <Field label="Подходит для типов кожи">
            <ChipGroup
              options={SKIN_TYPES}
              selected={skinTypes}
              onToggle={(v) => toggleArr(setSkinTypes, skinTypes, v)}
            />
          </Field>

          <Field label="Ключевые ингредиенты (INCI)">
            <div className="flex gap-2 mb-2">
              <input
                className="input flex-1"
                value={ingInput}
                onChange={(e) => setIngInput(e.target.value)}
                placeholder="Например: Niacinamide"
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    addIngredient();
                  }
                }}
              />
              <button
                type="button"
                className="btn-ghost"
                onClick={addIngredient}
              >
                Добавить
              </button>
            </div>
            <div className="flex flex-wrap gap-2">
              {ingredients.map((i) => (
                <span
                  key={i}
                  className="px-3 py-1 rounded-full bg-blush text-rose text-xs flex items-center gap-1"
                >
                  {i}
                  <button
                    type="button"
                    onClick={() =>
                      setIngredients(ingredients.filter((x) => x !== i))
                    }
                    className="text-rose/60 hover:text-rose"
                  >
                    ✕
                  </button>
                </span>
              ))}
            </div>
          </Field>

          <div className="grid grid-cols-2 gap-3">
            <Toggle
              label="Содержит активы"
              hint="ретиноид, AHA/BHA, vitamin C — Лина предупредит чувствительных"
              value={isActive}
              onChange={setIsActive}
            />
            <Toggle
              label="Деликатная формула"
              hint="плюс к match% для чувствительной кожи"
              value={gentle}
              onChange={setGentle}
            />
          </div>

          {err && <div className="text-warning text-sm">{err}</div>}
        </div>
        <div className="p-6 border-t border-black/5 flex flex-wrap items-center justify-end gap-3">
          <button type="button" className="btn-ghost" onClick={onCancel}>
            Отмена
          </button>
          <button
            type="button"
            className="btn-ghost"
            disabled={busy}
            onClick={(e) => submit(e, 'draft')}
          >
            {busy && pendingStatus === 'draft'
              ? 'Сохраняем…'
              : 'Сохранить как черновик'}
          </button>
          <button
            type="button"
            className="btn-primary"
            disabled={busy}
            onClick={(e) => submit(e, 'published')}
          >
            {busy && pendingStatus === 'published'
              ? 'Публикуем…'
              : initial?.status === 'published'
              ? 'Сохранить'
              : 'Опубликовать'}
          </button>
        </div>
      </form>
    </div>
  );
}

function PhotoBlock({
  url,
  onPick,
  onRemove,
  accent,
}: {
  url: string | null;
  onPick: (e: React.ChangeEvent<HTMLInputElement>) => void;
  onRemove: () => void;
  accent: string;
}) {
  return (
    <div className="flex items-start gap-4">
      <div
        className="w-32 h-40 rounded-2xl overflow-hidden flex items-center justify-center shrink-0"
        style={{
          background: url
            ? '#f0f0f0'
            : `linear-gradient(180deg, white, ${accent})`,
          border: '1px solid rgba(0,0,0,0.08)',
        }}
      >
        {url ? (
          <img
            src={url}
            alt=""
            className="w-full h-full object-cover"
          />
        ) : (
          <span className="text-ink2 text-xs">без фото</span>
        )}
      </div>
      <div className="flex-1">
        <div className="eyebrow mb-2">Фото продукта</div>
        <p className="text-sm text-ink2 mb-3">
          JPG / PNG до 6 MB. Если не загрузить — мобильное приложение
          покажет иллюстрацию-флакон с акцент-цветом ниже.
        </p>
        <div className="flex gap-2">
          <label className="btn-ghost cursor-pointer">
            <input
              type="file"
              accept="image/*"
              className="hidden"
              onChange={onPick}
            />
            {url ? 'Заменить' : 'Загрузить'}
          </label>
          {url && (
            <button
              type="button"
              className="text-warning text-sm hover:underline self-center"
              onClick={onRemove}
            >
              Убрать
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

function ExtraPhotosRow({
  slots,
  accent,
  onPick,
  onRemove,
}: {
  slots: { dataUrl: string | null; mime: string; changed: boolean }[];
  accent: string;
  onPick: (idx: number, file: File) => void;
  onRemove: (idx: number) => void;
}) {
  return (
    <div>
      <div className="eyebrow mb-2">Дополнительные фото (слоты 2–4)</div>
      <div className="flex gap-3 flex-wrap">
        {slots.map((s, i) => (
          <div key={i} className="flex flex-col items-center gap-2">
            <label
              className="w-20 h-24 rounded-xl overflow-hidden flex items-center justify-center cursor-pointer"
              style={{
                background: s.dataUrl
                  ? '#f0f0f0'
                  : `linear-gradient(180deg, white, ${accent}33)`,
                border: '1px dashed rgba(0,0,0,0.15)',
              }}
            >
              <input
                type="file"
                accept="image/*"
                className="hidden"
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) onPick(i, file);
                  e.currentTarget.value = '';
                }}
              />
              {s.dataUrl ? (
                <img
                  src={s.dataUrl}
                  alt=""
                  className="w-full h-full object-cover"
                />
              ) : (
                <span className="text-ink2 text-2xl">＋</span>
              )}
            </label>
            <div className="flex gap-1 text-xs">
              <span className="text-ink2">слот {i + 2}</span>
              {s.dataUrl && (
                <button
                  type="button"
                  className="text-warning hover:underline"
                  onClick={() => onRemove(i)}
                >
                  убрать
                </button>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function Field({
  label,
  help,
  children,
}: {
  label: string;
  help?: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <div className="eyebrow mb-1.5">{label}</div>
      {children}
      {help && (
        <div className="text-[11px] text-ink2 mt-1.5">{help}</div>
      )}
    </label>
  );
}

function ChipGroup({
  options,
  selected,
  onToggle,
}: {
  options: Array<{ id: string; label: string }>;
  selected: string[];
  onToggle: (id: string) => void;
}) {
  return (
    <div className="flex flex-wrap gap-2">
      {options.map((o) => {
        const active = selected.includes(o.id);
        return (
          <button
            key={o.id}
            type="button"
            onClick={() => onToggle(o.id)}
            className={`px-3 py-1.5 rounded-full border text-sm transition-colors ${
              active
                ? 'bg-rose text-white border-rose'
                : 'bg-white text-ink border-black/10 hover:border-rose/40'
            }`}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}

function Toggle({
  label,
  hint,
  value,
  onChange,
}: {
  label: string;
  hint?: string;
  value: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <button
      type="button"
      onClick={() => onChange(!value)}
      className={`text-left p-3 rounded-xl border transition-colors ${
        value
          ? 'bg-blush border-rose/30'
          : 'bg-white border-black/10 hover:border-rose/30'
      }`}
    >
      <div className="flex items-center justify-between">
        <div className="font-medium text-sm">{label}</div>
        <div
          className={`w-9 h-5 rounded-full relative transition-colors ${
            value ? 'bg-rose' : 'bg-ink2/30'
          }`}
        >
          <div
            className={`w-4 h-4 bg-white rounded-full absolute top-0.5 transition-all shadow ${
              value ? 'left-4' : 'left-0.5'
            }`}
          />
        </div>
      </div>
      {hint && <div className="text-xs text-ink2 mt-1">{hint}</div>}
    </button>
  );
}
