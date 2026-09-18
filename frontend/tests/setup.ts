import '@testing-library/jest-dom/vitest';

// Node 22+ exposes an experimental global `localStorage` that shadows jsdom's
// implementation and throws unless `--localstorage-file` is provided. That
// would leave `localStorage` undefined under vitest, so provide a faithful
// in-memory Web Storage implementation and share it between `window` and
// `globalThis` (the session module reads the global directly).
class MemoryStorage implements Storage {
  private store = new Map<string, string>();

  get length(): number {
    return this.store.size;
  }

  clear(): void {
    this.store.clear();
  }

  getItem(key: string): string | null {
    return this.store.has(key) ? (this.store.get(key) as string) : null;
  }

  key(index: number): string | null {
    return Array.from(this.store.keys())[index] ?? null;
  }

  removeItem(key: string): void {
    this.store.delete(key);
  }

  setItem(key: string, value: string): void {
    this.store.set(key, String(value));
  }
}

const memoryStorage = new MemoryStorage();
Object.defineProperty(window, 'localStorage', {
  value: memoryStorage,
  writable: true,
  configurable: true,
});
Object.defineProperty(globalThis, 'localStorage', {
  value: memoryStorage,
  writable: true,
  configurable: true,
});

// jsdom does not implement URL.createObjectURL/revokeObjectURL, which the
// image preview uses to render a fetched Blob. Polyfill with best-effort stubs.
if (typeof URL.createObjectURL !== 'function') {
  URL.createObjectURL = () => 'blob:mock-preview';
  URL.revokeObjectURL = () => {};
}

// jsdom does not implement scrolling. The app uses it for route changes
// (scroll to top) and for landing-page section anchors; stub both so the
// behaviour is exercised without noisy "not implemented" errors.
window.scrollTo = () => {};
Element.prototype.scrollIntoView = () => {};
