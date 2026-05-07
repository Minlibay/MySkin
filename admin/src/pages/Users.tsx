import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AdminUser, api } from '../api';

const PAGE = 20;

export default function Users() {
  const nav = useNavigate();
  const [items, setItems] = useState<AdminUser[]>([]);
  const [total, setTotal] = useState(0);
  const [offset, setOffset] = useState(0);
  const [q, setQ] = useState('');
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [pendingId, setPendingId] = useState<string | null>(null);

  async function load(opts: { offset?: number; q?: string } = {}) {
    setLoading(true);
    setErr(null);
    try {
      const r = await api.users({
        limit: PAGE,
        offset: opts.offset ?? offset,
        q: opts.q ?? q,
      });
      setItems(r.items);
      setTotal(r.total);
      setOffset(r.offset);
    } catch (e) {
      setErr(String(e));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load({ offset: 0 });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function toggleBlock(u: AdminUser) {
    setPendingId(u.id);
    try {
      if (u.is_blocked) await api.unblock(u.id);
      else await api.block(u.id);
      setItems((arr) =>
        arr.map((x) =>
          x.id === u.id ? { ...x, is_blocked: !u.is_blocked } : x
        )
      );
    } catch (e) {
      alert(`Ошибка: ${e}`);
    } finally {
      setPendingId(null);
    }
  }

  return (
    <div>
      <div className="eyebrow text-rose mb-1">Пользователи</div>
      <h1 className="font-serif text-4xl mb-6">
        Все <span className="italic text-rose">аккаунты</span>
      </h1>

      <div className="flex gap-3 mb-4">
        <input
          className="input flex-1 max-w-sm"
          placeholder="Поиск по номеру…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') load({ offset: 0, q });
          }}
        />
        <button
          className="btn-ghost"
          onClick={() => load({ offset: 0, q })}
          disabled={loading}
        >
          Найти
        </button>
        {q && (
          <button
            className="btn-ghost"
            onClick={() => {
              setQ('');
              load({ offset: 0, q: '' });
            }}
          >
            Сбросить
          </button>
        )}
      </div>

      {err && <div className="text-warning mb-4">{err}</div>}

      <div className="card overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-blush/40 text-ink2">
            <tr>
              <Th>Телефон</Th>
              <Th>Создан</Th>
              <Th>Последний вход</Th>
              <Th>Статус</Th>
              <Th>ID</Th>
              <th className="px-4 py-3 text-right">Действия</th>
            </tr>
          </thead>
          <tbody>
            {items.map((u) => (
              <tr
                key={u.id}
                className="border-t border-black/5 hover:bg-blush/20 cursor-pointer"
                onClick={() => nav(`/users/${u.id}`)}
              >
                <Td>
                  <span className="font-mono">{u.phone}</span>
                </Td>
                <Td>{fmt(u.created_at)}</Td>
                <Td>{u.last_login_at ? fmt(u.last_login_at) : '—'}</Td>
                <Td>
                  {u.is_blocked ? (
                    <span className="px-2 py-0.5 rounded-full bg-warning/15 text-warning text-xs">
                      заблокирован
                    </span>
                  ) : (
                    <span className="px-2 py-0.5 rounded-full bg-success/15 text-success text-xs">
                      активен
                    </span>
                  )}
                </Td>
                <Td>
                  <span className="font-mono text-xs text-ink2">
                    {u.id.slice(0, 8)}…
                  </span>
                </Td>
                <td className="px-4 py-3 text-right">
                  <button
                    className="btn-ghost h-8 px-3 text-xs"
                    disabled={pendingId === u.id}
                    onClick={(e) => {
                      e.stopPropagation();
                      toggleBlock(u);
                    }}
                  >
                    {pendingId === u.id
                      ? '…'
                      : u.is_blocked
                      ? 'Разблокировать'
                      : 'Заблокировать'}
                  </button>
                </td>
              </tr>
            ))}
            {!loading && items.length === 0 && (
              <tr>
                <td colSpan={6} className="px-4 py-12 text-center text-ink2">
                  Никого не найдено
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="flex items-center justify-between mt-4">
        <div className="text-ink2 text-sm">
          {loading ? 'Загружаем…' : `${total} всего · показано ${items.length}`}
        </div>
        <div className="flex gap-2">
          <button
            className="btn-ghost"
            disabled={offset === 0 || loading}
            onClick={() => load({ offset: Math.max(0, offset - PAGE) })}
          >
            ←
          </button>
          <button
            className="btn-ghost"
            disabled={offset + PAGE >= total || loading}
            onClick={() => load({ offset: offset + PAGE })}
          >
            →
          </button>
        </div>
      </div>
    </div>
  );
}

function Th({ children }: { children: React.ReactNode }) {
  return (
    <th className="px-4 py-3 text-left font-medium text-xs uppercase tracking-wide">
      {children}
    </th>
  );
}

function Td({ children }: { children: React.ReactNode }) {
  return <td className="px-4 py-3">{children}</td>;
}

function fmt(iso: string) {
  const d = new Date(iso);
  const dd = `${d.getDate()}`.padStart(2, '0');
  const mm = `${d.getMonth() + 1}`.padStart(2, '0');
  const yy = `${d.getFullYear() % 100}`.padStart(2, '0');
  const hh = `${d.getHours()}`.padStart(2, '0');
  const min = `${d.getMinutes()}`.padStart(2, '0');
  return `${dd}.${mm}.${yy} ${hh}:${min}`;
}
