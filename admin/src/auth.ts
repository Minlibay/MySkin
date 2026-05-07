import { useSyncExternalStore } from 'react';
import { api } from './api';

// Shared token store — one source of truth across all useAuth() consumers.
const listeners = new Set<() => void>();
const notify = () => listeners.forEach((l) => l());

function subscribe(cb: () => void) {
  listeners.add(cb);
  // Cross-tab logout (storage event fires in OTHER tabs only).
  const onStorage = () => cb();
  window.addEventListener('storage', onStorage);
  return () => {
    listeners.delete(cb);
    window.removeEventListener('storage', onStorage);
  };
}

const getSnapshot = () => api.getToken();

export function useAuth() {
  const token = useSyncExternalStore(subscribe, getSnapshot);
  return {
    authed: !!token,
    async login(loginInput: string, password: string) {
      const r = await api.login(loginInput, password);
      api.setToken(r.token);
      notify();
    },
    logout() {
      api.setToken(null);
      notify();
    },
  };
}
