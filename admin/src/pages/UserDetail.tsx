import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import {
  AdminScan,
  ShelfProduct,
  UserDetail as UserDetailT,
  api,
} from '../api';

export default function UserDetail() {
  const { id } = useParams<{ id: string }>();
  const nav = useNavigate();
  const [data, setData] = useState<UserDetailT | null>(null);
  const [scans, setScans] = useState<AdminScan[]>([]);
  const [shelf, setShelf] = useState<ShelfProduct[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    let alive = true;
    Promise.all([
      api.userDetail(id),
      api.userScans(id),
      api.userShelf(id),
    ])
      .then(([d, s, sh]) => {
        if (!alive) return;
        setData(d);
        setScans(s.items);
        setShelf(sh.items);
        setLoading(false);
      })
      .catch((e) => {
        if (!alive) return;
        setErr(String(e));
        setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, [id]);

  async function toggleBlock() {
    if (!data) return;
    const u = data.user;
    if (u.is_blocked) await api.unblock(u.id);
    else await api.block(u.id);
    setData({ ...data, user: { ...u, is_blocked: !u.is_blocked } });
  }

  if (loading) return <div className="text-ink2">Загружаем профиль…</div>;
  if (err) return <div className="text-warning">{err}</div>;
  if (!data) return null;

  const { user, profile, scans_count, shelf_count } = data;

  return (
    <div>
      <button
        onClick={() => nav('/users')}
        className="text-ink2 text-sm mb-3 hover:text-rose"
      >
        ← К списку юзеров
      </button>
      <div className="flex items-start justify-between mb-6">
        <div>
          <div className="eyebrow text-rose mb-1">
            {profile?.name ? 'Профиль' : 'Профиль не заполнен'}
          </div>
          <h1 className="font-serif text-4xl">
            {profile?.name || (
              <span className="italic text-ink2">Без имени</span>
            )}
          </h1>
          <div className="text-ink2 mt-1 font-mono text-sm">
            {user.phone} · {user.id.slice(0, 8)}…
          </div>
        </div>
        <button
          onClick={toggleBlock}
          className={user.is_blocked ? 'btn-primary' : 'btn-ghost'}
        >
          {user.is_blocked ? 'Разблокировать' : 'Заблокировать'}
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <Stat label="Сканов" value={scans_count} />
        <Stat label="На полке" value={shelf_count} />
        <Stat label="Создан" value={fmtDate(user.created_at)} />
        <Stat
          label="Последний вход"
          value={user.last_login_at ? fmtDate(user.last_login_at) : '—'}
        />
      </div>

      {profile && <ProfileCard profile={profile} />}

      {data.last_scan && (
        <div className="mt-6">
          <div className="eyebrow mb-2">Последний скан</div>
          <ScanRow scan={data.last_scan} />
        </div>
      )}

      {scans.length > 0 && (
        <Section title="История сканов">
          <div className="space-y-2">
            {scans.map((s) => (
              <ScanRow key={s.id} scan={s} />
            ))}
          </div>
        </Section>
      )}

      {shelf.length > 0 && (
        <Section title="Полка">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {shelf.map((p) => (
              <ShelfCard key={p.id} item={p} />
            ))}
          </div>
        </Section>
      )}
    </div>
  );
}

function Section({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div className="mt-6">
      <div className="eyebrow mb-2">{title}</div>
      {children}
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="card p-4">
      <div className="eyebrow mb-1">{label}</div>
      <div className="text-2xl font-serif text-ink">{value}</div>
    </div>
  );
}

function ProfileCard({
  profile,
}: {
  profile: NonNullable<UserDetailT['profile']>;
}) {
  return (
    <div className="card p-5">
      <div className="grid grid-cols-2 md:grid-cols-3 gap-4 text-sm">
        <Field label="Тип кожи" value={skinTypeLabel(profile.skin_type)} />
        <Field label="Поры" value={profile.pores ?? '—'} />
        <Field label="Бюджет" value={profile.budget ?? '—'} />
        <Field
          label="Чувствительность"
          value={profile.sensitivity ?? '—'}
        />
        <Field
          label="Тип акне"
          value={profile.acne_type ?? '—'}
        />
        <Field
          label="Обновлено"
          value={fmtDate(profile.updated_at)}
        />
      </div>
      {profile.concerns.length > 0 && (
        <div className="mt-4">
          <div className="eyebrow mb-2">Цели</div>
          <div className="flex flex-wrap gap-2">
            {profile.concerns.map((c) => (
              <span
                key={c}
                className="px-3 py-1 rounded-full bg-blush text-rose text-xs"
              >
                {c}
              </span>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="eyebrow mb-1">{label}</div>
      <div className="text-ink">{value}</div>
    </div>
  );
}

function ScanRow({ scan }: { scan: AdminScan }) {
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState<'idle' | 'ok' | 'no_face' | 'err'>(
    'idle'
  );

  async function recompute() {
    if (!scan.has_photo) return;
    setBusy(true);
    setStatus('idle');
    try {
      await api.recomputeScanGeom(scan.id);
      setStatus('ok');
    } catch (e: unknown) {
      const code =
        e && typeof e === 'object' && 'code' in e
          ? (e as { code?: string }).code
          : undefined;
      setStatus(code === 'no_face' ? 'no_face' : 'err');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="card p-3 flex items-center gap-4">
      <div className="font-serif text-3xl text-rose w-12 text-center">
        {scan.score}
      </div>
      <div className="flex-1">
        <div className="text-sm">{scan.insight}</div>
        <div className="text-xs text-ink2 mt-0.5">
          {fmtDate(scan.created_at)}
          {' · '}
          увлажн {scan.hydration} · себум {scan.sebum} · тон {scan.tone}
        </div>
      </div>
      {scan.has_photo && (
        <>
          <button
            onClick={recompute}
            disabled={busy}
            className="text-xs text-rose hover:underline disabled:opacity-50"
            title="Пересчитать карту улучшений через MediaPipe"
          >
            {busy ? '…' : '↻ геом'}
          </button>
          {status === 'ok' && (
            <span className="text-success text-xs">✓</span>
          )}
          {status === 'no_face' && (
            <span className="text-warning text-xs">нет лица</span>
          )}
          {status === 'err' && (
            <span className="text-warning text-xs">ошибка</span>
          )}
          <span className="text-ink2 text-xs">📷</span>
        </>
      )}
    </div>
  );
}

function ShelfCard({ item }: { item: ShelfProduct }) {
  return (
    <div className="card p-3">
      <div className="flex items-center gap-3">
        <div
          className="w-10 h-12 rounded-lg shrink-0"
          style={{
            background: `linear-gradient(180deg, white, ${item.accent_color})`,
            border: '1px solid rgba(0,0,0,0.05)',
          }}
        />
        <div className="flex-1 min-w-0">
          <div className="eyebrow truncate">{item.brand}</div>
          <div className="font-medium truncate">{item.name}</div>
          <div className="text-xs text-ink2 mt-0.5">
            {item.status === 'have'
              ? 'Использует'
              : item.status === 'wishlist'
              ? 'Хочу попробовать'
              : 'Закончилось'}
            {' · '}
            {fmtDate(item.added_at)}
          </div>
        </div>
      </div>
    </div>
  );
}

function fmtDate(iso: string) {
  const d = new Date(iso);
  return `${`${d.getDate()}`.padStart(2, '0')}.${`${
    d.getMonth() + 1
  }`.padStart(2, '0')}.${d.getFullYear() % 100} ${`${d.getHours()}`.padStart(
    2,
    '0'
  )}:${`${d.getMinutes()}`.padStart(2, '0')}`;
}

function skinTypeLabel(id: string | null) {
  switch (id) {
    case 'dry':
      return 'Сухая';
    case 'oily':
      return 'Жирная';
    case 'combo':
      return 'Комбинированная';
    case 'normal':
      return 'Нормальная';
    case 'sensitive':
      return 'Чувствительная';
    default:
      return '—';
  }
}

// silence unused import warning if Link removed
export const _ = Link;
