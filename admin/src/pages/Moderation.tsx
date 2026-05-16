import { useEffect, useState } from 'react';
import {
  api,
  type AdminBrand,
  type AdminProduct,
  type AdminPartner,
} from '../api';

export default function ModerationPage() {
  const [tab, setTab] = useState<'brands' | 'products'>('brands');
  return (
    <div className="flex flex-col gap-6">
      <div>
        <div className="eyebrow text-rose mb-1">Очередь</div>
        <h1 className="font-serif text-3xl">Модерация</h1>
        <p className="text-sm text-ink2 mt-1 max-w-lg">
          Бренды и товары, поданные партнёрами. Принимаешь — становится
          видно в каталоге приложения. Отклоняешь — партнёр видит причину.
        </p>
      </div>
      <div className="inline-flex bg-white rounded-full p-1 border border-black/5 self-start">
        <Tab active={tab === 'brands'} onClick={() => setTab('brands')}>
          Бренды
        </Tab>
        <Tab active={tab === 'products'} onClick={() => setTab('products')}>
          Товары
        </Tab>
      </div>
      {tab === 'brands' ? <BrandQueue /> : <ProductQueue />}
    </div>
  );
}

function Tab({
  active,
  children,
  onClick,
}: {
  active: boolean;
  children: React.ReactNode;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`px-4 py-1.5 rounded-full text-sm transition-colors ${
        active ? 'bg-rose text-white' : 'text-ink2 hover:text-ink'
      }`}
    >
      {children}
    </button>
  );
}

function BrandQueue() {
  const [items, setItems] = useState<AdminBrand[]>([]);
  const [partners, setPartners] = useState<AdminPartner[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  function load() {
    setLoading(true);
    Promise.all([api.listBrands('pending'), api.listPartners()])
      .then(([b, p]) => {
        setItems(b.items);
        setPartners(p.items);
      })
      .catch((e) => setErr(String(e)))
      .finally(() => setLoading(false));
  }
  useEffect(load, []);

  async function approve(b: AdminBrand) {
    await api.approveBrand(b.id);
    load();
  }
  async function reject(b: AdminBrand) {
    const reason = prompt(
      `Причина отклонения «${b.name}»?`,
      'Не подходит под правила каталога.'
    );
    if (reason === null) return;
    await api.rejectBrand(b.id, reason);
    load();
  }

  if (loading) {
    return <div className="card p-8 text-center text-ink2">Загрузка…</div>;
  }
  if (err) return <div className="card p-4 text-warning">{err}</div>;
  if (items.length === 0) {
    return (
      <div className="card p-10 text-center text-ink2">
        Очередь пуста — всё одобрено.
      </div>
    );
  }
  return (
    <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
      {items.map((b) => {
        const partner = partners.find((p) => p.id === b.owner_partner_id);
        return (
          <div key={b.id} className="card p-5 flex flex-col gap-3">
            <div>
              <div className="font-serif text-xl leading-tight">
                {b.name}
              </div>
              <div className="font-mono text-xs text-ink2 mt-1">{b.slug}</div>
            </div>
            <div className="text-xs text-ink2">
              Подал:&nbsp;
              <span className="text-ink">
                {partner
                  ? `${partner.company_name} (${partner.login})`
                  : 'неизвестный партнёр'}
              </span>
            </div>
            <div className="text-[11px] text-ink2 font-mono">
              {b.submitted_at
                ? new Date(b.submitted_at).toLocaleString('ru-RU')
                : '—'}
            </div>
            <div className="flex gap-2 pt-2 border-t border-black/5">
              <button
                className="btn-primary flex-1 h-9 text-sm"
                onClick={() => approve(b)}
              >
                Одобрить
              </button>
              <button
                className="btn-ghost flex-1 h-9 text-sm"
                onClick={() => reject(b)}
              >
                Отклонить
              </button>
            </div>
          </div>
        );
      })}
    </div>
  );
}

function ProductQueue() {
  const [items, setItems] = useState<AdminProduct[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  function load() {
    setLoading(true);
    api
      .listPendingProducts()
      .then((r) => setItems(r.items))
      .catch((e) => setErr(String(e)))
      .finally(() => setLoading(false));
  }
  useEffect(load, []);

  async function approve(p: AdminProduct) {
    await api.approveProductModeration(p.id);
    load();
  }
  async function reject(p: AdminProduct) {
    const reason = prompt(
      `Причина отклонения «${p.name}»?`,
      'Карточка не соответствует правилам каталога.'
    );
    if (reason === null) return;
    await api.rejectProductModeration(p.id, reason);
    load();
  }

  if (loading) {
    return <div className="card p-8 text-center text-ink2">Загрузка…</div>;
  }
  if (err) return <div className="card p-4 text-warning">{err}</div>;
  if (items.length === 0) {
    return (
      <div className="card p-10 text-center text-ink2">
        Очередь пуста — товаров на модерации нет.
      </div>
    );
  }

  return (
    <div className="card overflow-hidden">
      <table className="w-full text-sm">
        <thead className="bg-blush text-ink2">
          <tr>
            <Th>Бренд</Th>
            <Th>Название</Th>
            <Th>Тип</Th>
            <Th>Цена</Th>
            <Th>Купить URL</Th>
            <Th>Slug</Th>
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
              <td className="px-4 py-3 font-medium">{p.name}</td>
              <td className="px-4 py-3 text-ink2">{p.kind}</td>
              <td className="px-4 py-3 font-mono">{p.price_rub} ₽</td>
              <td className="px-4 py-3 text-ink2 max-w-[200px] truncate">
                {p.buy_url ? (
                  <a
                    href={p.buy_url}
                    target="_blank"
                    rel="noreferrer"
                    className="text-rose hover:underline"
                  >
                    {p.buy_url}
                  </a>
                ) : (
                  '—'
                )}
              </td>
              <td className="px-4 py-3 font-mono text-xs">{p.slug}</td>
              <td className="px-4 py-3 text-right whitespace-nowrap">
                <button
                  className="text-xs text-success hover:underline mr-3"
                  onClick={() => approve(p)}
                >
                  Одобрить
                </button>
                <button
                  className="text-xs text-warning hover:underline"
                  onClick={() => reject(p)}
                >
                  Отклонить
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
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
