import { FormEvent, ReactNode, useState } from 'react';
import { NavLink } from 'react-router-dom';
import { api } from '../api';
import { useAuth } from '../auth';

const NAV = [
  { to: '/', label: 'Дашборд', icon: '◆' },
  { to: '/users', label: 'Юзеры', icon: '◌' },
  { to: '/products', label: 'Каталог', icon: '◇' },
  { to: '/import', label: 'Импорт', icon: '⇪' },
  { to: '/partners', label: 'Партнёры', icon: '◐' },
  { to: '/moderation', label: 'Модерация', icon: '◭' },
  { to: '/codes', label: 'Коды', icon: '⎘' },
  { to: '/settings', label: 'GigaChat', icon: '✦' },
  { to: '/legal', label: 'Документы', icon: '§' },
];

export default function Layout({ children }: { children: ReactNode }) {
  const { logout } = useAuth();
  const [showPwd, setShowPwd] = useState(false);
  return (
    <div className="min-h-screen flex">
      <aside className="w-60 shrink-0 p-5 border-r border-black/5 bg-white/40 backdrop-blur-sm flex flex-col">
        <div className="mb-8">
          <div className="font-serif text-2xl text-rose">
            My<span className="italic">Skin</span>
          </div>
          <div className="eyebrow mt-1">Admin · 0.1</div>
        </div>
        <nav className="flex-1 space-y-1">
          {NAV.map((n) => (
            <NavLink
              key={n.to}
              to={n.to}
              end={n.to === '/'}
              className={({ isActive }) =>
                `flex items-center gap-3 px-3 py-2 rounded-xl transition-colors ${
                  isActive
                    ? 'bg-rose text-white'
                    : 'text-ink hover:bg-white'
                }`
              }
            >
              <span className="font-mono text-sm w-5 text-center">
                {n.icon}
              </span>
              <span className="text-sm font-medium">{n.label}</span>
            </NavLink>
          ))}
        </nav>
        <button
          onClick={() => setShowPwd(true)}
          className="mt-4 text-left px-3 py-2 rounded-xl text-ink2 hover:bg-white text-sm"
        >
          Сменить пароль
        </button>
        <button
          onClick={logout}
          className="text-left px-3 py-2 rounded-xl text-ink2 hover:bg-white text-sm"
        >
          Выйти
        </button>
      </aside>
      <main className="flex-1 p-8 overflow-auto">{children}</main>
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
    <div className="fixed inset-0 z-40 bg-black/40 backdrop-blur-sm overflow-y-auto">
      <div className="min-h-full flex items-start sm:items-center justify-center p-4">
        <form
          onSubmit={submit}
          className="card w-full max-w-md p-6 flex flex-col gap-4 my-4"
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
              <button type="submit" className="btn-primary" disabled={busy}>
                {busy ? 'Сохраняем…' : 'Сохранить'}
              </button>
            </div>
          </>
        )}
        </form>
      </div>
    </div>
  );
}
