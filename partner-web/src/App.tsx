import { useEffect, useState } from 'react';
import {
  Navigate,
  Route,
  Routes,
  useLocation,
  useNavigate,
} from 'react-router-dom';
import { api, getToken, type Partner } from './api';
import LoginPage from './pages/Login';
import BrandsPage from './pages/Brands';
import TopPage from './pages/Top';
import { Shell } from './components/Shell';

type AuthState =
  | { kind: 'loading' }
  | { kind: 'anon' }
  | { kind: 'partner'; partner: Partner };

export default function App() {
  const [auth, setAuth] = useState<AuthState>(
    getToken() ? { kind: 'loading' } : { kind: 'anon' }
  );
  const location = useLocation();
  const navigate = useNavigate();

  useEffect(() => {
    if (auth.kind !== 'loading') return;
    api
      .me()
      .then((p) => setAuth({ kind: 'partner', partner: p }))
      .catch(() => setAuth({ kind: 'anon' }));
  }, [auth.kind]);

  async function onLogout() {
    await api.logout();
    setAuth({ kind: 'anon' });
    navigate('/login', { replace: true });
  }

  if (auth.kind === 'loading') {
    return (
      <div className="h-full flex items-center justify-center">
        <div className="eyebrow">Загрузка…</div>
      </div>
    );
  }

  if (auth.kind === 'anon') {
    if (location.pathname !== '/login') {
      return <Navigate to="/login" replace />;
    }
    return (
      <Routes>
        <Route
          path="/login"
          element={
            <LoginPage
              onLogged={(p) =>
                setAuth({ kind: 'partner', partner: p })
              }
            />
          }
        />
      </Routes>
    );
  }

  // Authenticated.
  return (
    <Shell partner={auth.partner} onLogout={onLogout}>
      <Routes>
        <Route path="/" element={<Navigate to="/brands" replace />} />
        <Route path="/brands" element={<BrandsPage />} />
        <Route path="/top" element={<TopPage />} />
        <Route path="/login" element={<Navigate to="/brands" replace />} />
        <Route
          path="*"
          element={
            <div className="card p-6">Раздел в разработке.</div>
          }
        />
      </Routes>
    </Shell>
  );
}
