import { useEffect, useState } from 'react';
import { GigaSettings, api } from '../api';

export default function Settings() {
  const [data, setData] = useState<GigaSettings | null>(null);
  const [chatModel, setChatModel] = useState('');
  const [visionModel, setVisionModel] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [savedAt, setSavedAt] = useState<Date | null>(null);

  async function load() {
    setErr(null);
    try {
      const r = await api.getGigaSettings();
      setData(r);
      setChatModel(r.chat_model ?? '');
      setVisionModel(r.vision_model ?? '');
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
      await api.setGigaSettings({
        chat_model: chatModel.trim() || undefined,
        vision_model: visionModel.trim() || undefined,
      });
      setSavedAt(new Date());
      await load();
    } catch (e) {
      setErr(String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="max-w-2xl">
      <div className="mb-6">
        <div className="eyebrow text-rose mb-1">Конфигурация</div>
        <h1 className="font-serif text-4xl">
          Настройки <span className="italic text-rose">GigaChat</span>
        </h1>
        <p className="text-ink2 text-sm mt-2">
          Выбери модель для свободного чата и для анализа фото-сканов.
          Изменения применяются сразу — на следующий запрос. Пустое поле
          — используется значение по умолчанию из env (для чата —{' '}
          <code className="font-mono">GigaChat-2-Lite</code>, для зрения —{' '}
          <code className="font-mono">GigaChat-2-Max</code>).
        </p>
      </div>

      {err && (
        <div className="mb-4 px-4 py-3 rounded-xl bg-warning/10 text-warning text-sm">
          {err}
        </div>
      )}

      <div className="card p-6 space-y-5">
        <ModelField
          label="Модель для чата (Лина)"
          hint="Используется для свободного диалога с пользователем. Lite — быстрее и дешевле."
          value={chatModel}
          onChange={setChatModel}
          options={data?.available_models ?? []}
          placeholder="GigaChat-2-Lite"
        />
        <ModelField
          label="Модель для анализа фото"
          hint="Должна поддерживать vision. Max — самая точная."
          value={visionModel}
          onChange={setVisionModel}
          options={data?.available_models ?? []}
          placeholder="GigaChat-2-Max"
        />

        <div className="flex items-center gap-3 pt-2">
          <button
            className="btn-primary"
            onClick={save}
            disabled={busy}
          >
            {busy ? 'Сохраняем…' : 'Сохранить'}
          </button>
          {savedAt && !busy && (
            <span className="text-success text-sm">
              ✓ Сохранено {savedAt.toLocaleTimeString('ru-RU')}
            </span>
          )}
        </div>
      </div>
    </div>
  );
}

function ModelField({
  label,
  hint,
  value,
  onChange,
  options,
  placeholder,
}: {
  label: string;
  hint: string;
  value: string;
  onChange: (v: string) => void;
  options: string[];
  placeholder: string;
}) {
  return (
    <div>
      <div className="eyebrow mb-1.5">{label}</div>
      <div className="flex gap-2">
        <select
          className="input flex-1"
          value={options.includes(value) ? value : ''}
          onChange={(e) => onChange(e.target.value)}
        >
          <option value="">— по умолчанию —</option>
          {options.map((o) => (
            <option key={o} value={o}>
              {o}
            </option>
          ))}
        </select>
        <input
          className="input flex-1 font-mono"
          placeholder={placeholder}
          value={value}
          onChange={(e) => onChange(e.target.value)}
        />
      </div>
      <div className="text-ink2 text-xs mt-1.5">{hint}</div>
    </div>
  );
}
