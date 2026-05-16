import { FormEvent, useEffect, useState } from 'react';
import { api, type AdminPartner } from '../api';

export default function PartnersPage() {
  const [items, setItems] = useState<AdminPartner[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [createOpen, setCreateOpen] = useState(false);
  const [resetTarget, setResetTarget] = useState<AdminPartner | null>(null);

  function load() {
    setLoading(true);
    api
      .listPartners()
      .then((r) => setItems(r.items))
      .catch((e) => setErr(String(e)))
      .finally(() => setLoading(false));
  }
  useEffect(load, []);

  async function toggleBlock(p: AdminPartner) {
    if (p.is_blocked) await api.unblockPartner(p.id);
    else await api.blockPartner(p.id);
    load();
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-end justify-between">
        <div>
          <div className="eyebrow text-rose mb-1">Аккаунты</div>
          <h1 className="font-serif text-3xl">Партнёры</h1>
          <p className="text-sm text-ink2 mt-1 max-w-lg">
            Производители/бренды. Сам логиниться не может — учётку выдаёшь ты.
          </p>
        </div>
        <button className="btn-primary" onClick={() => setCreateOpen(true)}>
          + Новый партнёр
        </button>
      </div>

      {err && <div className="card p-4 text-warning">{err}</div>}

      <div className="card overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-blush text-ink2">
            <tr>
              <Th>Логин</Th>
              <Th>Компания</Th>
              <Th>Контакт</Th>
              <Th>Создан</Th>
              <Th>Последний вход</Th>
              <Th>Статус</Th>
              <Th>&nbsp;</Th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr>
                <td colSpan={7} className="text-center text-ink2 py-10">
                  Загрузка…
                </td>
              </tr>
            ) : items.length === 0 ? (
              <tr>
                <td colSpan={7} className="text-center text-ink2 py-10">
                  Партнёров пока нет.
                </td>
              </tr>
            ) : (
              items.map((p) => (
                <tr
                  key={p.id}
                  className="border-t border-black/5 hover:bg-blush/40"
                >
                  <td className="px-4 py-3 font-mono">{p.login}</td>
                  <td className="px-4 py-3">{p.company_name}</td>
                  <td className="px-4 py-3 text-ink2">
                    {p.contact_email || p.contact_phone || '—'}
                  </td>
                  <td className="px-4 py-3 text-ink2 text-xs font-mono">
                    {new Date(p.created_at).toLocaleDateString('ru-RU')}
                  </td>
                  <td className="px-4 py-3 text-ink2 text-xs font-mono">
                    {p.last_login_at
                      ? new Date(p.last_login_at).toLocaleString('ru-RU')
                      : '—'}
                  </td>
                  <td className="px-4 py-3">
                    {p.is_blocked ? (
                      <span className="px-2 py-0.5 rounded-full text-xs bg-warning/15 text-warning">
                        Заблокирован
                      </span>
                    ) : (
                      <span className="px-2 py-0.5 rounded-full text-xs bg-success/15 text-success">
                        Активен
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-right">
                    <button
                      className="text-xs text-rose hover:underline mr-3"
                      onClick={() => setResetTarget(p)}
                    >
                      Сменить пароль
                    </button>
                    <button
                      className="text-xs text-ink2 hover:underline"
                      onClick={() => toggleBlock(p)}
                    >
                      {p.is_blocked ? 'Разблокировать' : 'Заблокировать'}
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {createOpen && (
        <CreatePartnerModal
          onClose={() => setCreateOpen(false)}
          onCreated={() => {
            setCreateOpen(false);
            load();
          }}
        />
      )}
      {resetTarget && (
        <ResetPasswordModal
          partner={resetTarget}
          onClose={() => setResetTarget(null)}
          onDone={() => setResetTarget(null)}
        />
      )}
    </div>
  );
}

function Th({ children }: { children: React.ReactNode }) {
  return (
    <th className="text-left font-mono text-[10px] uppercase tracking-wider px-4 py-3">
      {children}
    </th>
  );
}

function CreatePartnerModal({
  onClose,
  onCreated,
}: {
  onClose: () => void;
  onCreated: () => void;
}) {
  const [login, setLogin] = useState('');
  const [password, setPassword] = useState('');
  const [companyName, setCompanyName] = useState('');
  const [contactEmail, setContactEmail] = useState('');
  const [contactPhone, setContactPhone] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setErr(null);
    if (login.length < 3 || password.length < 8 || !companyName.trim()) {
      setErr('Логин ≥3 символов, пароль ≥8, название компании обязательно.');
      return;
    }
    setBusy(true);
    try {
      await api.createPartner({
        login: login.trim().toLowerCase(),
        password,
        company_name: companyName.trim(),
        contact_email: contactEmail.trim() || undefined,
        contact_phone: contactPhone.trim() || undefined,
        note: note.trim() || undefined,
      });
      onCreated();
    } catch (e) {
      const code = String(e).replace(/^Error: /, '');
      setErr(code === 'login_taken' ? 'Такой логин уже занят.' : code);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal onClose={onClose} title="Новый партнёр">
      <form onSubmit={submit} className="flex flex-col gap-4 p-6">
        <Field label="Логин">
          <input
            className="input"
            value={login}
            onChange={(e) => setLogin(e.target.value)}
            placeholder="acme"
          />
        </Field>
        <Field label="Пароль">
          <input
            className="input"
            type="text"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="≥ 8 символов"
          />
        </Field>
        <Field label="Название компании">
          <input
            className="input"
            value={companyName}
            onChange={(e) => setCompanyName(e.target.value)}
          />
        </Field>
        <Field label="Контактный email">
          <input
            className="input"
            type="email"
            value={contactEmail}
            onChange={(e) => setContactEmail(e.target.value)}
          />
        </Field>
        <Field label="Контактный телефон">
          <input
            className="input"
            value={contactPhone}
            onChange={(e) => setContactPhone(e.target.value)}
          />
        </Field>
        <Field label="Заметка (только для админа)">
          <textarea
            className="input min-h-[72px] py-2"
            value={note}
            onChange={(e) => setNote(e.target.value)}
          />
        </Field>
        {err && <div className="text-sm text-warning">{err}</div>}
        <div className="flex justify-end gap-2">
          <button type="button" className="btn-ghost" onClick={onClose}>
            Отмена
          </button>
          <button type="submit" className="btn-primary" disabled={busy}>
            {busy ? 'Создаём…' : 'Создать'}
          </button>
        </div>
      </form>
    </Modal>
  );
}

function ResetPasswordModal({
  partner,
  onClose,
  onDone,
}: {
  partner: AdminPartner;
  onClose: () => void;
  onDone: () => void;
}) {
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setErr(null);
    if (password.length < 8) {
      setErr('Пароль должен быть от 8 символов.');
      return;
    }
    setBusy(true);
    try {
      await api.resetPartnerPassword(partner.id, password);
      onDone();
    } catch (e) {
      setErr(String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal onClose={onClose} title={`Сменить пароль · ${partner.login}`}>
      <form onSubmit={submit} className="flex flex-col gap-4 p-6">
        <Field label="Новый пароль">
          <input
            className="input"
            type="text"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </Field>
        {err && <div className="text-sm text-warning">{err}</div>}
        <div className="flex justify-end gap-2">
          <button type="button" className="btn-ghost" onClick={onClose}>
            Отмена
          </button>
          <button type="submit" className="btn-primary" disabled={busy}>
            {busy ? 'Сохраняем…' : 'Сохранить'}
          </button>
        </div>
      </form>
    </Modal>
  );
}

function Modal({
  title,
  onClose,
  children,
}: {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
}) {
  return (
    <div className="fixed inset-0 z-40 bg-black/40 backdrop-blur-sm overflow-y-auto">
      <div className="min-h-full flex items-start sm:items-center justify-center p-4">
        <div className="card w-full max-w-md my-4">
          <div className="px-6 pt-5 pb-3 border-b border-black/5 flex items-start justify-between sticky top-0 bg-white rounded-t-2xl z-10">
            <div className="font-serif text-xl">{title}</div>
            <button
              onClick={onClose}
              className="text-ink2 hover:text-ink text-2xl leading-none px-2"
              aria-label="Закрыть"
            >
              ×
            </button>
          </div>
          {children}
        </div>
      </div>
    </div>
  );
}

function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <div className="eyebrow mb-1.5">{label}</div>
      {children}
    </label>
  );
}
