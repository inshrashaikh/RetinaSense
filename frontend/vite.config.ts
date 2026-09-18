/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// Backend that Vite proxies /api to. Matches the default in client.ts.
const PROXY_TARGET = process.env.VITE_PROXY_TARGET ?? 'http://localhost:8000';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    host: '0.0.0.0',
    // Same-origin /api in dev: the browser only talks to localhost:5173, so no
    // CORS or cross-origin addressing can break connectivity. When
    // VITE_API_BASE_URL is empty the app calls '/api/...' straight here.
    proxy: {
      '/api': {
        target: PROXY_TARGET,
        changeOrigin: false,
      },
    },
  },
  preview: { port: 4173 },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./tests/setup.ts'],
    include: ['tests/**/*.{test,spec}.{ts,tsx}'],
  },
});