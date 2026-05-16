import { FormEvent, useState } from 'react';
import { NavLink } from 'react-router-dom';
import { api, type Partner } from '../api';

type Props = {
  partner: Partner;
  onLogout: () => void;
  children: React.ReactNode;
};

const NAV = [
  { to: '/brands', label: 'Мои бренды' },
  { to: '/products', label: 'Мои товары' },
  { to: '/top', label: 'Топ товаров' },
];

export function Shell({ partner, onLogout, children }: Props) {
  const [showPwd, setShowPwd] = useState(false);
  return (
    <div className="min-h-full flex flex-col">
      <header className="sticky top-0 z-30 bg-background/85 backdrop-blur border-b border-black/5">
        <div className="max-w-6xl mx-auto px-6 py-4 flex items-center gap-6">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-full bg-gradient-to-br from-white via-primary to-accent shadow-soft" />
            <div>
              <div className="eyebrow text-rose">Партнёр</div>
              <div className="font-serif text-xl leading-none">
                {partner.company_name}
              </div>
            </div>
          </div>
          <nav className="flex items-center gap-1 ml-6">
            {NAV.map((n) => (
              <NavLink
                key={n.to}
                to={n.to}
                className={({ isActive }) =>
                  `px-3 py-1.5 rounded-full text-sm transition-colors ${
                    isActive
                      ? 'bg-rose text-white'
                      : 'text-ink2 hover:text-ink'
                  }`
                }
              >
                {n.label}
              </NavLink>
            ))}
          </nav>
          <div className="flex-1" />
          <div className="text-right">
            <div className="text-xs text-ink2">{partner.login}</div>
            <button
              type="button"
              onClick={() => setShowPwd(true)}
              className="text-xs text-ink2 hover:underline mr-3"
            >
              Сменить пароль
            </button>
            <button
              type="button"
              onClick={onLogout}
              className="text-xs text-rose hover:underline"
            >
              Выйти
            </button>
          </div>
        </div>
      </header>
      <main className="max-w-6xl mx-auto w-full px-6 py-8 flex-1">
        {children}
      </main>
      {showPwd && (
        <ChangePasswordModal onClose={() => setShowPwd(false)} />
      )}
    </div>
  );
}

function ChangePasswordModal({ onClose }: { onClose: () => void }) {
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setErr(null);
    if (next.length < 8) {
      setErr('Новый пароль должен быть от 8 символов.');
      return;
    }
    if (next !== confirm) {
      setErr('Подтверждение не совпадает.');
      return;
    }
    setBusy(true);
    try {
      await api.changePassword(current, next);
      setDone(true);
    } catch (e) {
      const code = String(e).replace(/^Error: /, '');
      setErr(
        code === 'wrong_current_password'
          ? 'Текущий пароль неверный.'
          : code === 'weak_password'
          ? 'Слишком короткий новый пароль.'
          : `Ошибка: ${code}`
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-40 bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
      <form
        onSubmit={submit}
        className="card w-full max-w-md p-6 flex flex-col gap-4"
      >
        <div>
          <div className="eyebrow text-rose mb-1">Безопасность</div>
          <div className="font-serif text-2xl">Смена пароля</div>
        </div>
        {done ? (
          <>
            <div className="text-sm text-success bg-success/10 border border-success/30 rounded-xl px-3 py-2">
              Пароль обновлён.
            </div>
            <div className="flex justify-end">
              <button
                type="button"
                className="btn-primary"
                onClick={onClose}
              >
                Закрыть
              </button>
            </div>
          </>
        ) : (
          <>
            <label className="block">
              <div className="eyebrow mb-1.5">Текущий пароль</div>
              <input
                className="input"
                type="password"
                value={current}
                onChange={(e) => setCurrent(e.target.value)}
                required
              />
            </label>
            <label className="block">
              <div className="eyebrow mb-1.5">Новый пароль</div>
              <input
                className="input"
                type="password"
                value={next}
                onChange={(e) => setNext(e.target.value)}
                required
              />
            </label>
            <label className="block">
              <div className="eyebrow mb-1.5">Повторите новый пароль</div>
              <input
                className="input"
                type="password"
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                required
              />
            </label>
            {err && (
              <div className="text-sm text-warning bg-warning/10 border border-warning/30 rounded-xl px-3 py-2">
                {err}
              </div>
            )}
            <div className="flex justify-end gap-2 pt-1">
              <button
                type="button"
                className="btn-ghost"
                onClick={onClose}
                disabled={busy}
              >
                Отмена
              </button>
              <button
                type="submit"
                className="btn-primary"
                disabled={busy}
              >
                {busy ? 'Сохраняем…' : 'Сохранить'}
              </button>
            </div>
          </>
        )}
      </form>
    </div>
  );
}
