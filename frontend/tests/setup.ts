import '@testing-library/jest-dom/vitest';

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
