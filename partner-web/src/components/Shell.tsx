import { NavLink } from 'react-router-dom';
import type { Partner } from '../api';

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
    </div>
  );
}
