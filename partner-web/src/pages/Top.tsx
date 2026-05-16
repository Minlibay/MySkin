import { useEffect, useState } from 'react';
import { api, type TopItem } from '../api';

type Metric = 'impression' | 'open' | 'buy_click';
type Range = '7d' | '30d' | '90d' | 'all';

const METRIC_LABEL: Record<Metric, string> = {
  impression: 'Показы',
  open: 'Открытия',
  buy_click: 'Купить',
};
const RANGE_LABEL: Record<Range, string> = {
  '7d': '7 дней',
  '30d': '30 дней',
  '90d': '90 дней',
  all: 'Всё время',
};

export default function TopPage() {
  const [metric, setMetric] = useState<Metric>('open');
  const [range, setRange] = useState<Range>('7d');
  const [items, setItems] = useState<TopItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    setErr(null);
    api
      .top(metric, range, 20)
      .then((r) => setItems(r.items))
      .catch((e) => setErr(String(e)))
      .finally(() => setLoading(false));
  }, [metric, range]);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <div className="eyebrow text-rose mb-1">Статистика</div>
        <h1 className="font-serif text-3xl">Топ товаров</h1>
        <p className="text-sm text-ink2 mt-1 max-w-lg">
          Живые цифры. Показы дедуплицируются по сессии — один пользователь
          = один показ в день, без накруток.
        </p>
      </div>

      <div className="flex flex-wrap gap-3">
        <Selector
          label="Метрика"
          value={metric}
          options={Object.entries(METRIC_LABEL) as [Metric, string][]}
          onChange={setMetric}
        />
        <Selector
          label="Период"
          value={range}
          options={Object.entries(RANGE_LABEL) as [Range, string][]}
          onChange={setRange}
        />
      </div>

      {err && (
        <div className="card p-4 text-warning border-warning/30">{err}</div>
      )}

      <div className="card overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-blush text-ink2">
            <tr>
              <th className="text-left font-mono text-[10px] uppercase tracking-wider px-4 py-3 w-10">
                #
              </th>
              <th className="text-left font-mono text-[10px] uppercase tracking-wider px-4 py-3">
                Товар
              </th>
              <th className="text-left font-mono text-[10px] uppercase tracking-wider px-4 py-3">
                Бренд
              </th>
              <th className="text-right font-mono text-[10px] uppercase tracking-wider px-4 py-3">
                {METRIC_LABEL[metric]}
              </th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr>
                <td colSpan={4} className="text-center text-ink2 py-10">
                  Загрузка…
                </td>
              </tr>
            ) : items.length === 0 ? (
              <tr>
                <td colSpan={4} className="text-center text-ink2 py-10">
                  За выбранный период данных пока нет.
                </td>
              </tr>
            ) : (
              items.map((it, i) => (
                <tr
                  key={it.product_id}
                  className="border-t border-black/5 hover:bg-blush/40"
                >
                  <td className="px-4 py-3 font-mono text-ink2">{i + 1}</td>
                  <td className="px-4 py-3">{it.name}</td>
                  <td className="px-4 py-3 text-ink2">{it.brand}</td>
                  <td className="px-4 py-3 text-right font-mono">
                    {it.count.toLocaleString('ru-RU')}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function Selector<T extends string>({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: T;
  options: [T, string][];
  onChange: (v: T) => void;
}) {
  return (
    <label className="flex items-center gap-2">
      <span className="eyebrow">{label}</span>
      <select
        className="input h-9 py-0 w-auto pr-8"
        value={value}
        onChange={(e) => onChange(e.target.value as T)}
      >
        {options.map(([k, lbl]) => (
          <option key={k} value={k}>
            {lbl}
          </option>
        ))}
      </select>
    </label>
  );
}
