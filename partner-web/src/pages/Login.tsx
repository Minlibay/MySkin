import { FormEvent, useState } from 'react';
import { api, type Partner } from '../api';

export default function LoginPage({
  onLogged,
}: {
  onLogged: (p: Partner) => void;
}) {
  const [login, setLogin] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setErr(null);
    setBusy(true);
    try {
      const partner = await api.login(login.trim().toLowerCase(), password);
      onLogged(partner);
    } catch (e) {
      const code = String(e).replace(/^Error: /, '');
      setErr(
        code === 'invalid_credentials'
          ? 'Неверный логин или пароль.'
          : code === 'partner_blocked'
          ? 'Аккаунт заблокирован. Свяжитесь с поддержкой.'
          : `Ошибка входа: ${code}`
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="min-h-full flex items-center justify-center p-6">
      <form
        onSubmit={submit}
        className="w-full max-w-sm card p-8 flex flex-col gap-5"
      >
        <div>
          <div className="w-12 h-12 rounded-full bg-gradient-to-br from-white via-primary to-accent shadow-soft mb-4" />
          <div className="eyebrow text-rose mb-1">Партнёр</div>
          <h1 className="font-serif text-3xl leading-tight">
            Кабинет&nbsp;партнёра
          </h1>
          <p className="text-sm text-ink2 mt-2">
            Логин и пароль выдаёт администратор. Самостоятельная регистрация
            не предусмотрена.
          </p>
        </div>
        <label className="block">
          <div className="eyebrow mb-1.5">Логин</div>
          <input
            className="input"
            autoComplete="username"
            value={login}
            onChange={(e) => setLogin(e.target.value)}
            placeholder="acme"
            required
          />
        </label>
        <label className="block">
          <div className="eyebrow mb-1.5">Пароль</div>
          <input
            className="input"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </label>
        {err && (
          <div className="text-sm text-warning bg-warning/10 border border-warning/30 rounded-xl px-3 py-2">
            {err}
          </div>
        )}
        <button type="submit" className="btn-primary" disabled={busy}>
          {busy ? 'Входим…' : 'Войти'}
        </button>
      </form>
    </div>
  );
}
