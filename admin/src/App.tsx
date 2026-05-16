import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuth } from './auth';
import Layout from './components/Layout';
import Codes from './pages/Codes';
import Dashboard from './pages/Dashboard';
import Legal from './pages/Legal';
import Login from './pages/Login';
import Moderation from './pages/Moderation';
import Partners from './pages/Partners';
import Products from './pages/Products';
import Settings from './pages/Settings';
import UserDetail from './pages/UserDetail';
import Users from './pages/Users';

export default function App() {
  const { authed } = useAuth();

  if (!authed) {
    return (
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    );
  }

  return (
    <Layout>
      <Routes>
        <Route path="/" element={<Dashboard />} />
        <Route path="/users" element={<Users />} />
        <Route path="/users/:id" element={<UserDetail />} />
        <Route path="/products" element={<Products />} />
        <Route path="/partners" element={<Partners />} />
        <Route path="/moderation" element={<Moderation />} />
        <Route path="/codes" element={<Codes />} />
        <Route path="/settings" element={<Settings />} />
        <Route path="/legal" element={<Legal />} />
        <Route path="/login" element={<Navigate to="/" replace />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Layout>
  );
}
