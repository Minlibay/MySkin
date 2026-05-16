import { FormEvent, useEffect, useState } from 'react';
import { api, type Brand } from '../api';

const STATUS_LABEL: Record<Brand['status'], string> = {
  approved: 'Одобрен',
  pending: 'На модерации',
  rejected: 'Отклонён',
};
const STATUS_CLASS: Record<Brand['status'], string> = {
  approved: 'bg-success/15 text-success',
  pending: 'bg-info/15 text-info',
  rejected: 'bg-warning/15 text-warning',
};

export default function BrandsPage() {
  const [items, setItems] = useState<Brand[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);

  function load() {
    setLoading(true);
    api
      .listBrands()
      .then(setItems)
      .catch((e) => setErr(String(e)))
      .finally(() => setLoading(false));
  }

  useEffect(load, []);

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-end justify-between gap-4">
        <div>
          <div className="eyebrow text-rose mb-1">Каталог</div>
          <h1 className="font-serif text-3xl">Мои бренды</h1>
          <p className="text-sm text-ink2 mt-1 max-w-lg">
            Создавай бренды и закрепляй за ними товары. Новый бренд попадает
            на модерацию — обычно занимает 1–2 рабочих дня.
          </p>
        </div>
        <button
          type="button"
          className="btn-primary"
          onClick={() => setShowCreate(true)}
        >
          + Новый бренд
        </button>
      </div>

      {err && (
        <div className="card p-4 text-warning border-warning/30">{err}</div>
      )}

      {loading ? (
        <div className="card p-8 text-center text-ink2">Загрузка…</div>
      ) : items.length === 0 ? (
        <div className="card p-10 text-center">
          <div className="font-serif text-2xl mb-1">Пока пусто</div>
          <div className="text-ink2 text-sm">
            Создай первый бренд — после одобрения сможешь добавлять товары.
          </div>
        </div>
      ) : (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {items.map((b) => (
            <div key={b.id} className="card p-5 flex flex-col gap-3">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="font-serif text-xl leading-tight">
                    {b.name}
                  </div>
                  <div className="font-mono text-xs text-ink2 mt-1">
                    {b.slug}
                  </div>
                </div>
                <span
                  className={`px-2.5 py-0.5 rounded-full text-[11px] font-medium ${STATUS_CLASS[b.status]}`}
                >
                  {STATUS_LABEL[b.status]}
                </span>
              </div>
              {b.moderation_reason && b.status === 'rejected' && (
                <div className="text-xs text-warning bg-warning/10 rounded-lg px-3 py-2 leading-snug">
                  {b.moderation_reason}
                </div>
              )}
              <div className="text-[11px] text-ink2 font-mono">
                Создан{' '}
                {new Date(b.created_at).toLocaleDateString('ru-RU')}
              </div>
            </div>
          ))}
        </div>
      )}

      {showCreate && (
        <CreateBrandModal
          onClose={() => setShowCreate(false)}
          onCreated={() => {
            setShowCreate(false);
            load();
          }}
        />
      )}
    </div>
  );
}

function CreateBrandModal({
  onClose,
  onCreated,
}: {
  onClose: () => void;
  onCreated: () => void;
}) {
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setErr(null);
    setBusy(true);
    try {
      await api.createBrand(name.trim());
      onCreated();
    } catch (e) {
      const code = String(e).replace(/^Error: /, '');
      setErr(
        code === 'brand_name_taken'
          ? 'Такой бренд уже есть в системе. Если он ваш — напишите администратору, прикрепим к аккаунту.'
          : code === 'invalid_name'
          ? 'Слишком короткое название.'
          : `Ошибка: ${code}`
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-40 bg-black/40 backdrop-blur-sm overflow-y-auto">
      <div className="min-h-full flex items-start sm:items-center justify-center p-4">
        <form
          onSubmit={submit}
          className="card w-full max-w-md p-6 flex flex-col gap-4 my-4"
        >
        <div>
          <div className="eyebrow text-rose mb-1">Новый бренд</div>
          <div className="font-serif text-2xl">Подать на модерацию</div>
        </div>
        <label className="block">
          <div className="eyebrow mb-1.5">Название бренда</div>
          <input
            className="input"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Например, ACME"
            required
          />
        </label>
        {err && (
          <div className="text-sm text-warning bg-warning/10 border border-warning/30 rounded-xl px-3 py-2">
            {err}
          </div>
        )}
        <div className="flex justify-end gap-2 pt-2">
          <button
            type="button"
            className="btn-ghost"
            onClick={onClose}
            disabled={busy}
          >
            Отмена
          </button>
          <button type="submit" className="btn-primary" disabled={busy}>
            {busy ? 'Отправляем…' : 'Отправить на модерацию'}
          </button>
        </div>
        </form>
      </div>
    </div>
  );
}
