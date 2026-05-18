import { useEffect, useState } from 'react';
import { Stats, api } from '../api';

export default function Dashboard() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    api
      .stats()
      .then((s) => alive && (setStats(s), setLoading(false)))
      .catch((e) => alive && (setErr(String(e)), setLoading(false)));
    return () => {
      alive = false;
    };
  }, []);

  return (
    <div>
      <div className="eyebrow text-rose mb-1">Обзор</div>
      <h1 className="font-serif text-4xl mb-8">
        Сегодня в <span className="italic text-rose">Моей Коже</span>
      </h1>

      {loading && <div className="text-ink2">Загружаем статистику…</div>}
      {err && <div className="text-warning">{err}</div>}
      {stats && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <Card label="Всего юзеров" value={stats.users_total} />
          <Card
            label="Новых за сегодня"
            value={stats.users_today}
            accent="success"
          />
          <Card
            label="Активные сессии"
            value={stats.active_sessions}
            accent="info"
          />
          <Card
            label="Заблокировано"
            value={stats.users_blocked}
            accent={stats.users_blocked > 0 ? 'warning' : 'ink2'}
          />
        </div>
      )}
    </div>
  );
}

function Card({
  label,
  value,
  accent = 'rose',
}: {
  label: string;
  value: number;
  accent?: 'rose' | 'success' | 'info' | 'warning' | 'ink2';
}) {
  const color = {
    rose: 'text-rose',
    success: 'text-success',
    info: 'text-info',
    warning: 'text-warning',
    ink2: 'text-ink2',
  }[accent];
  return (
    <div className="card p-6">
      <div className="eyebrow mb-2">{label}</div>
      <div className={`font-serif text-4xl ${color}`}>{value}</div>
    </div>
  );
}
