import { useEffect, useState } from 'react';
import { AiSettings, api } from '../api';

export default function Settings() {
  const [data, setData] = useState<AiSettings | null>(null);
  const [provider, setProvider] = useState<'gigachat' | 'qwen'>('gigachat');
  const [gigaChat, setGigaChat] = useState('');
  const [gigaVision, setGigaVision] = useState('');
  const [qwenChat, setQwenChat] = useState('');
  const [qwenVision, setQwenVision] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [savedAt, setSavedAt] = useState<Date | null>(null);

  async function load() {
    setErr(null);
    try {
      const r = await api.getAiSettings();
      setData(r);
      setProvider(r.provider);
      setGigaChat(r.gigachat.chat_model ?? '');
      setGigaVision(r.gigachat.vision_model ?? '');
      setQwenChat(r.qwen.chat_model ?? '');
      setQwenVision(r.qwen.vision_model ?? '');
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
      await api.setAiSettings({
        provider,
        gigachat: {
          chat_model: gigaChat.trim() || undefined,
          vision_model: gigaVision.trim() || undefined,
        },
        qwen: {
          chat_model: qwenChat.trim() || undefined,
          vision_model: qwenVision.trim() || undefined,
        },
      });
      setSavedAt(new Date());
      await load();
    } catch (e) {
      setErr(String(e));
    } finally {
      setBusy(false);
    }
  }

  if (!data) {
    return <div className="max-w-2xl text-ink2">Загрузка…</div>;
  }

  const qwenAvailable = data.available_providers.includes('qwen');
  const gigaAvailable = data.available_providers.includes('gigachat');

  return (
    <div className="max-w-2xl">
      <div className="mb-6">
        <div className="eyebrow text-rose mb-1">Конфигурация</div>
        <h1 className="font-serif text-4xl">
          Настройки <span className="italic text-rose">AI</span>
        </h1>
        <p className="text-ink2 text-sm mt-2">
          Выбери активного AI-провайдера и модели для чата с Линой и анализа
          фото-сканов. Изменения применяются сразу — на следующий запрос.
          Пустое поле модели — используется значение по умолчанию.
        </p>
      </div>

      {err && (
        <div className="mb-4 px-4 py-3 rounded-xl bg-warning/10 text-warning text-sm">
          {err}
        </div>
      )}

      <div className="card p-6 mb-4">
        <div className="eyebrow mb-2">Активный провайдер</div>
        <div className="flex gap-3">
          <ProviderTile
            label="GigaChat"
            sub="Sber, на русском, низкая задержка из РФ"
            active={provider === 'gigachat'}
            available={gigaAvailable}
            onClick={() => setProvider('gigachat')}
          />
          <ProviderTile
            label="Qwen"
            sub="Alibaba, сильнее на нюансах и мультимодал-задачах"
            active={provider === 'qwen'}
            available={qwenAvailable}
            onClick={() => setProvider('qwen')}
          />
        </div>
        {!qwenAvailable && (
          <div className="text-ink2 text-xs mt-3">
            Чтобы включить Qwen, добавь{' '}
            <code className="font-mono">DASHSCOPE_API_KEY</code> в env
            бэкенда и перезапусти.
          </div>
        )}
      </div>

      <div className="card p-6 mb-4 space-y-5">
        <div className="flex items-center justify-between">
          <div className="font-serif text-xl">GigaChat</div>
          {provider === 'gigachat' && (
            <span className="text-xs px-2 py-0.5 rounded-full bg-rose/10 text-rose font-semibold">
              активен
            </span>
          )}
        </div>
        <ModelField
          label="Чат (Лина)"
          hint="Используется для свободного диалога. Lite — быстрее, Max — точнее."
          value={gigaChat}
          onChange={setGigaChat}
          options={data.gigachat.available_models}
          placeholder="GigaChat-2-Lite"
        />
        <ModelField
          label="Анализ фото"
          hint="Должна поддерживать vision. Max — самая точная."
          value={gigaVision}
          onChange={setGigaVision}
          options={data.gigachat.available_models}
          placeholder="GigaChat-2-Max"
        />
      </div>

      <div className="card p-6 mb-4 space-y-5">
        <div className="flex items-center justify-between">
          <div className="font-serif text-xl">Qwen</div>
          {provider === 'qwen' && (
            <span className="text-xs px-2 py-0.5 rounded-full bg-rose/10 text-rose font-semibold">
              активен
            </span>
          )}
        </div>
        <ModelField
          label="Чат (Лина)"
          hint="qwen-plus — баланс цены и качества; qwen-max — максимальная точность."
          value={qwenChat}
          onChange={setQwenChat}
          options={data.qwen.available_models}
          placeholder="qwen-plus"
          disabled={!qwenAvailable}
        />
        <ModelField
          label="Анализ фото"
          hint="qwen-vl-max — лучшая мультимодальная для анализа лица."
          value={qwenVision}
          onChange={setQwenVision}
          options={data.qwen.available_models}
          placeholder="qwen-vl-max"
          disabled={!qwenAvailable}
        />
      </div>

      <div className="flex items-center gap-3">
        <button className="btn-primary" onClick={save} disabled={busy}>
          {busy ? 'Сохраняем…' : 'Сохранить'}
        </button>
        {savedAt && !busy && (
          <span className="text-success text-sm">
            ✓ Сохранено {savedAt.toLocaleTimeString('ru-RU')}
          </span>
        )}
      </div>
    </div>
  );
}

function ProviderTile({
  label,
  sub,
  active,
  available,
  onClick,
}: {
  label: string;
  sub: string;
  active: boolean;
  available: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={available ? onClick : undefined}
      disabled={!available}
      className={[
        'flex-1 text-left p-4 rounded-2xl border transition-colors',
        active
          ? 'border-rose bg-rose/5'
          : 'border-divider hover:border-rose/50',
        !available && 'opacity-50 cursor-not-allowed',
      ]
        .filter(Boolean)
        .join(' ')}
    >
      <div className="font-serif text-lg">{label}</div>
      <div className="text-ink2 text-xs mt-1">{sub}</div>
      {!available && (
        <div className="text-warning text-xs mt-2">ключ не настроен</div>
      )}
    </button>
  );
}

function ModelField({
  label,
  hint,
  value,
  onChange,
  options,
  placeholder,
  disabled = false,
}: {
  label: string;
  hint: string;
  value: string;
  onChange: (v: string) => void;
  options: string[];
  placeholder: string;
  disabled?: boolean;
}) {
  return (
    <div>
      <div className="eyebrow mb-1.5">{label}</div>
      <div className="flex gap-2">
        <select
          className="input flex-1"
          value={options.includes(value) ? value : ''}
          onChange={(e) => onChange(e.target.value)}
          disabled={disabled}
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
          disabled={disabled}
        />
      </div>
      <div className="text-ink2 text-xs mt-1.5">{hint}</div>
    </div>
  );
}
