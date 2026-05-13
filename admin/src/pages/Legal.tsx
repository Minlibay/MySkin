import { useEffect, useState } from 'react';
import { LegalDocs, api } from '../api';

type Field = 'terms' | 'privacy' | 'consent';

const FIELDS: { key: Field; title: string; hint: string }[] = [
  {
    key: 'terms',
    title: 'Пользовательское соглашение',
    hint: 'Условия использования приложения. Показывается при регистрации.',
  },
  {
    key: 'privacy',
    title: 'Политика конфиденциальности',
    hint: 'Как мы обрабатываем данные. Обязательно для App Store / Google Play.',
  },
  {
    key: 'consent',
    title: 'Согласие на обработку персональных данных',
    hint: '152-ФЗ. Должно быть отдельным документом для пользователей из РФ.',
  },
];

export default function Legal() {
  const [docs, setDocs] = useState<LegalDocs>({
    terms: '',
    privacy: '',
    consent: '',
  });
  const [loaded, setLoaded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [savedAt, setSavedAt] = useState<Date | null>(null);

  async function load() {
    setErr(null);
    try {
      const r = await api.getLegal();
      setDocs(r);
      setLoaded(true);
    } catch (e) {
      setErr(String(e));
    }
  }

  useEffect(() => {
    load();
  }, []);

  async function save() {
    setBusy(true);
    setErr(null);
    try {
      await api.setLegal(docs);
      setSavedAt(new Date());
    } catch (e) {
      setErr(String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="max-w-4xl">
      <div className="mb-6">
        <div className="eyebrow text-rose mb-1">Юридические документы</div>
        <h1 className="font-serif text-4xl">
          Документы для <span className="italic text-rose">регистрации</span>
        </h1>
        <p className="text-ink2 text-sm mt-2">
          Три текста, на которые ссылается чекбокс согласия на экране ввода
          номера. Поддерживается простая разметка: строки <code className="font-mono">#&nbsp;Заголовок</code>{' '}
          превращаются в крупный заголовок, <code className="font-mono">##&nbsp;Подзаголовок</code> — в средний,
          остальное — параграфы.
        </p>
      </div>

      {err && (
        <div className="mb-4 px-4 py-3 rounded-xl bg-warning/10 text-warning text-sm">
          {err}
        </div>
      )}

      {!loaded ? (
        <div className="text-ink2 text-sm">Загрузка…</div>
      ) : (
        <div className="space-y-4">
          {FIELDS.map((f) => (
            <div key={f.key} className="card p-6">
              <div className="eyebrow mb-1">{f.title}</div>
              <div className="text-ink2 text-xs mb-3">{f.hint}</div>
              <textarea
                className="input w-full font-mono text-sm"
                rows={12}
                value={docs[f.key]}
                onChange={(e) =>
                  setDocs((d) => ({ ...d, [f.key]: e.target.value }))
                }
                placeholder={`# ${f.title}\n\nТекст документа…`}
              />
              <div className="text-ink2 text-xs mt-1.5">
                {docs[f.key].length.toLocaleString('ru-RU')} символов
              </div>
            </div>
          ))}

          <div className="flex items-center gap-3">
            <button className="btn-primary" onClick={save} disabled={busy}>
              {busy ? 'Сохраняем…' : 'Сохранить все три'}
            </button>
            {savedAt && !busy && (
              <span className="text-success text-sm">
                ✓ Сохранено {savedAt.toLocaleTimeString('ru-RU')}
              </span>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
