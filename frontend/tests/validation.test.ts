/**
 * Pure unit tests for the client-side image validation guard.
 */
import { describe, expect, it } from 'vitest';
import { validateImageFile, ALLOWED_IMAGE_TYPES } from '../src/utils/validation';

function makeFile(name: string, type: string, sizeBytes: number): File {
  // A zero-filled array is enough — validation looks at name/type/size only.
  return new File([new Uint8Array(sizeBytes)], name, { type });
}

describe('validateImageFile', () => {
  it('missing file is rejected', () => {
    const r = validateImageFile(null);
    expect(r.ok).toBe(false);
    expect(r.message).toMatch(/select/i);
  });

  it('accepts a jpeg file under 20 MB', () => {
    const r = validateImageFile(makeFile('scan.jpg', 'image/jpeg', 1024 * 1024));
    expect(r.ok).toBe(true);
  });

  it('accepts a png file under 20 MB', () => {
    const r = validateImageFile(makeFile('scan.png', 'image/png', 1024 * 1024));
    expect(r.ok).toBe(true);
  });

  it('rejects unsupported MIME types', () => {
    const r = validateImageFile(makeFile('scan.bmp', 'image/bmp', 1024));
    expect(r.ok).toBe(false);
    expect(r.message).toMatch(/JPEG or PNG/i);
  });

  it('rejects unsupported file extensions even if MIME looks right', () => {
    const r = validateImageFile(makeFile('scan.txt', 'image/jpeg', 1024));
    expect(r.ok).toBe(false);
    expect(r.message).toMatch(/\.jpg, \.jpeg or \.png/i);
  });

  it('rejects files over the 20 MB limit', () => {
    const r = validateImageFile(makeFile('big.jpg', 'image/jpeg', 21 * 1024 * 1024));
    expect(r.ok).toBe(false);
    expect(r.message).toMatch(/20 MB/i);
  });

  it('rejects empty files', () => {
    const r = validateImageFile(makeFile('empty.jpg', 'image/jpeg', 0));
    expect(r.ok).toBe(false);
  });

  it('ALLOWED_IMAGE_TYPES only lists jpeg/png', () => {
    expect(ALLOWED_IMAGE_TYPES).toEqual(['image/jpeg', 'image/png']);
  });
});