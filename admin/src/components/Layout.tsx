import { ReactNode } from 'react';
import { NavLink } from 'react-router-dom';
import { useAuth } from '../auth';

const NAV = [
  { to: '/', label: 'Дашборд', icon: '◆' },
  { to: '/users', label: 'Юзеры', icon: '◌' },
  { to: '/products', label: 'Каталог', icon: '◇' },
  { to: '/codes', label: 'Коды', icon: '⎘' },
  { to: '/settings', label: 'GigaChat', icon: '✦' },
  { to: '/legal', label: 'Документы', icon: '§' },
];

export default function Layout({ children }: { children: ReactNode }) {
  const { logout } = useAuth();
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
          onClick={logout}
          className="mt-4 text-left px-3 py-2 rounded-xl text-ink2 hover:bg-white text-sm"
        >
          Выйти
        </button>
      </aside>
      <main className="flex-1 p-8 overflow-auto">{children}</main>
    </div>
  );
}
