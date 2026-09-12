/**
 * Client-side fundus image validation.
 *
 * The backend is the authoritative validator (returns INVALID_IMAGE,
 * UNSUPPORTED_FILE_TYPE / 413 IMAGE_TOO_LARGE). These guards give the user
 * instant feedback before any request is sent.
 */

export const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png'];
export const ALLOWED_IMAGE_EXTENSIONS = ['.jpg', '.jpeg', '.png'];
/** Mirror of backend MAX_IMAGE_SIZE_MB (backend/app/config.py). */
export const MAX_IMAGE_SIZE_MB = 20;
export const MAX_IMAGE_SIZE_BYTES = MAX_IMAGE_SIZE_MB * 1024 * 1024;

export interface ValidationResult {
  ok: boolean;
  message: string;
}

export function validateImageFile(file: File | null): ValidationResult {
  if (!file) {
    return { ok: false, message: 'Please select a fundus image to upload.' };
  }
  if (!ALLOWED_IMAGE_TYPES.includes(file.type)) {
    return {
      ok: false,
      message: `Unsupported file type "${file.type || 'unknown'}". Please upload a JPEG or PNG image.`,
    };
  }
  const ext = (file.name.lastIndexOf('.') >= 0 ? file.name.slice(file.name.lastIndexOf('.')) : '').toLowerCase();
  if (!ALLOWED_IMAGE_EXTENSIONS.includes(ext)) {
    return {
      ok: false,
      message: `Unsupported file extension "${ext}". Please upload a .jpg, .jpeg or .png image.`,
    };
  }
  if (file.size > MAX_IMAGE_SIZE_BYTES) {
    return {
      ok: false,
      message: `Image is ${(file.size / (1024 * 1024)).toFixed(1)} MB. Max allowed size is ${MAX_IMAGE_SIZE_MB} MB.`,
    };
  }
  if (file.size === 0) {
    return { ok: false, message: 'The selected file is empty. Please choose a valid image.' };
  }
  return { ok: true, message: '' };
}