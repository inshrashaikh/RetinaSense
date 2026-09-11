import '@testing-library/jest-dom/vitest';

// jsdom does not implement URL.createObjectURL/revokeObjectURL, which the
// image preview uses to render a fetched Blob. Polyfill with best-effort stubs.
if (typeof URL.createObjectURL !== 'function') {
  URL.createObjectURL = () => 'blob:mock-preview';
  URL.revokeObjectURL = () => {};
}