import { FormEvent, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ApiError } from '../api';
import { useAuth } from '../auth';

export default function Login() {
  const { login } = useAuth();
  const nav = useNavigate();
  const [loginInput, setLoginInput] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await login(loginInput.trim(), password);
      nav('/', { replace: true });
    } catch (e) {
      const code = e instanceof ApiError ? e.code : 'network_error';
      setError(_errorText(code));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-6">
      <form onSubmit={onSubmit} className="card w-full max-w-sm p-8">
        <div className="eyebrow text-rose mb-2">Доступ только для админов</div>
        <h1 className="font-serif text-3xl mb-1">
          MySkin <span className="italic text-rose">admin</span>
        </h1>
        <p className="text-ink2 text-sm mb-6">
          Войди логином и паролем, выданным при настройке сервера.
        </p>
        <div className="space-y-3">
          <input
            type="text"
            placeholder="Логин"
            className="input"
            value={loginInput}
            onChange={(e) => setLoginInput(e.target.value)}
            autoFocus
          />
          <input
            type="password"
            placeholder="Пароль"
            className="input"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
          {error && (
            <div className="text-warning text-sm">{error}</div>
          )}
        </div>
        <button
          type="submit"
          className="btn-primary w-full mt-6"
          disabled={busy || !loginInput || !password}
        >
          {busy ? 'Входим...' : 'Войти'}
        </button>
      </form>
    </div>
  );
}

function _errorText(code: string) {
  switch (code) {
    case 'invalid_credentials':
      return 'Неверный логин или пароль';
    case 'invalid_request':
      return 'Заполни оба поля';
    case 'network_error':
      return 'Нет связи с сервером';
    default:
      return `Ошибка: ${code}`;
  }
}
