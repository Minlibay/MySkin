import { useEffect, useState } from 'react';
import { PendingCode, api } from '../api';

export default function Codes() {
  const [items, setItems] = useState<PendingCode[]>([]);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [now, setNow] = useState(() => Date.now());

  async function load() {
    setLoading(true);
    setErr(null);
    try {
      const r = await api.pendingCodes();
      setItems(r.items);
    } catch (e) {
      setErr(String(e));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
    const t = setInterval(load, 5000);
    return () => clearInterval(t);
  }, []);

  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  function copyCode(code: string) {
    navigator.clipboard?.writeText(code);
  }

  return (
    <div>
      <div className="flex items-end justify-between mb-6">
        <div>
          <div className="eyebrow text-rose mb-1">Авторизация</div>
          <h1 className="font-serif text-4xl">
            Активные <span className="italic text-rose">коды</span>
          </h1>
          <p className="text-ink2 text-sm mt-2 max-w-xl">
            Здесь видно все запрошенные пользователями SMS-коды, ещё
            действительные. Если SMS не дошло (баланс на SMSC закончился —
            помечено{' '}
            <span className="px-1.5 py-0.5 rounded bg-warning/15 text-warning text-[10px]">
              без SMS
            </span>
            ), скажи код юзеру вручную.
          </p>
        </div>
        <button
          className="btn-ghost"
          onClick={load}
          disabled={loading}
        >
          {loading ? 'Обновляю…' : 'Обновить'}
        </button>
      </div>

      {err && <div className="text-warning text-sm mb-3">{err}</div>}

      <div className="card overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-blush/40 text-ink2">
            <tr>
              <th className="px-4 py-3 text-left font-medium text-xs uppercase tracking-wide">
                Телефон
              </th>
              <th className="px-4 py-3 text-left font-medium text-xs uppercase tracking-wide">
                Код
              </th>
              <th className="px-4 py-3 text-left font-medium text-xs uppercase tracking-wide">
                SMS
              </th>
              <th className="px-4 py-3 text-left font-medium text-xs uppercase tracking-wide">
                Попыток
              </th>
              <th className="px-4 py-3 text-left font-medium text-xs uppercase tracking-wide">
                Истекает через
              </th>
            </tr>
          </thead>
          <tbody>
            {items.map((c) => {
              const secLeft = Math.max(
                0,
                Math.floor(
                  (new Date(c.expires_at).getTime() - now) / 1000
                )
              );
              const mm = Math.floor(secLeft / 60);
              const ss = secLeft % 60;
              return (
                <tr
                  key={c.phone}
                  className="border-t border-black/5 hover:bg-blush/20"
                >
                  <td className="px-4 py-3 font-mono">{c.phone}</td>
                  <td className="px-4 py-3">
                    <button
                      onClick={() => copyCode(c.code)}
                      title="Скопировать"
                      className="font-mono text-2xl tracking-widest text-rose hover:bg-blush rounded-lg px-2 py-1"
                    >
                      {c.code}
                    </button>
                  </td>
                  <td className="px-4 py-3">
                    {c.sms_sent ? (
                      <span className="px-2 py-0.5 rounded-full bg-success/15 text-success text-xs">
                        ● доставлено
                      </span>
                    ) : (
                      <span className="px-2 py-0.5 rounded-full bg-warning/15 text-warning text-xs">
                        без SMS
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-3 font-mono text-xs">
                    {c.attempts}/5
                  </td>
                  <td className="px-4 py-3 font-mono text-xs">
                    {mm}:{String(ss).padStart(2, '0')}
                  </td>
                </tr>
              );
            })}
            {!loading && items.length === 0 && (
              <tr>
                <td
                  colSpan={5}
                  className="px-4 py-12 text-center text-ink2"
                >
                  Активных кодов нет
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
