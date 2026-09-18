// @ts-nocheck
/**
 * Final-verification render guard — reads the REAL git-ignored Simulink output
 * (simulink/output/district_capacity_results_*.json) and renders the district
 * dashboard with it, mirroring the exact normalization the backend performs
 * (MATLAB [] -> null). SKIPPED unless a real run exists, so a fresh clone or
 * CI box without MATLAB stays green. Never fabricates figures.
 */
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { render, screen } from '@testing-library/react';

const api = vi.hoisted(() => ({
  login: vi.fn(),
  createCase: vi.fn(),
  screenCase: vi.fn(),
  getCase: vi.fn(),
  listCases: vi.fn(),
  fetchCaseImage: vi.fn(async () => new Blob()),
  submitReview: vi.fn(),
  fetchHealth: vi.fn(),
  fetchCaseStats: vi.fn(),
  generateReport: vi.fn(),
  fetchSimulationCapacity: vi.fn(),
}));

vi.mock('../src/api/endpoints', () => ({
  isDemoMode: false,
  login: api.login,
  createCase: api.createCase,
  screenCase: api.screenCase,
  getCase: api.getCase,
  listCases: api.listCases,
  fetchCaseImage: api.fetchCaseImage,
  submitReview: api.submitReview,
  fetchHealth: api.fetchHealth,
  fetchCaseStats: api.fetchCaseStats,
  generateReport: api.generateReport,
  fetchSimulationCapacity: api.fetchSimulationCapacity,
}));

import App from '../src/App';
import { saveSession } from '../src/auth/session';

const outDir = join(__dirname, '..', '..', 'simulink', 'output');

function hasRealRun(): boolean {
  try {
    const files = readdirSync(outDir).filter((f) => f.startsWith('district_capacity_results_') && f.endsWith('.json'));
    return files.length > 0;
  } catch {
    return false;
  }
}

function clean(value: unknown): unknown {
  if (Array.isArray(value)) {
    if (value.length === 0) return null;
    return value.map(clean);
  }
  if (value !== null && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value)) out[k] = clean(v);
    return out;
  }
  return value;
}

function loadLatestRun(): {
  latest: { generatedAt: string | null; matlabVersion: string | null; simulinkVersion: string | null; simEventsVersion: string | null; modelFile: string | null; dataSourcePolicy: string | null; results: unknown[] };
  runs: { file: string; generatedAt: string | null; results: unknown[] }[];
  target: { annualPatients: number; dailyEquivalent: number; note: string };
} {
  const files = readdirSync(outDir).filter((f) => f.startsWith('district_capacity_results_') && f.endsWith('.json'));
  files.sort();
  const file = files[files.length - 1];
  const payload = clean(JSON.parse(readFileSync(join(outDir, file), 'utf-8')));
  return {
    latest: {
      generatedAt: payload.generatedAt,
      matlabVersion: payload.matlabVersion,
      simulinkVersion: payload.simulinkVersion,
      simEventsVersion: payload.simEventsVersion,
      modelFile: payload.modelFile,
      dataSourcePolicy: payload.dataSourcePolicy,
      results: payload.results,
    },
    runs: [{ file, generatedAt: payload.generatedAt, results: payload.results }],
    target: {
      annualPatients: 100_000,
      dailyEquivalent: 274,
      note: '100,000 patients/year is the SIH 2026 scalability target — a reference figure.',
    },
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  window.localStorage.clear();
  window.location.hash = '';
  api.fetchHealth.mockResolvedValue({ status: 'ok', matlabEngine: true, version: '0.1.0', database: 'ok' });
  api.fetchCaseStats.mockResolvedValue({
    totalCases: 0, screeningsCompleted: 0, pendingReviews: 0, recaptureRequired: 0, reviewed: 0, created: 0,
  });
  api.listCases.mockResolvedValue([]);
});

describe('FINAL VERIFICATION: real Simulink JSON renders', () => {
  it.skipIf(!hasRealRun())('renders the measured figures from the actual generated JSON', async () => {
    const real = loadLatestRun();
    api.fetchSimulationCapacity.mockResolvedValue({ available: true, ...real });

    saveSession('token', { id: 3, username: 'admin', name: 'District Admin', role: 'admin' });
    window.location.hash = '#/dashboard';
    render(<App />);

    expect(await screen.findByRole('heading', { name: 'Capacity & district operations' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Measured baseline capacity' })).toBeInTheDocument();

    // Real measured baseline values (from the actual MATLAB run).
    expect(screen.getAllByText('143/day').length).toBeGreaterThan(0);
    expect(screen.getAllByText('52,195').length).toBeGreaterThan(0);
    expect(screen.getAllByText('Acquisition').length).toBeGreaterThan(0);
    // Measured wait + queue length + reviewer utilization are shown.
    expect(screen.getAllByText('5,225 s').length).toBeGreaterThan(0);
    expect(screen.getAllByText('36.8').length).toBeGreaterThan(0);
    expect(screen.getAllByText('5%').length).toBeGreaterThan(0);
    // High-load measured annual capacity is rendered in the comparison table.
    expect(screen.getAllByText('52,560').length).toBeGreaterThan(0);

    // All real scenarios are present in the comparison table (humanized labels).
    for (const name of ['Baseline (district load)', 'Low load', 'High load', 'Rural 1 Mbps', 'Rural 4 Mbps', 'Single reviewer', '5 reviewers']) {
      expect(screen.getByText(name, { exact: true })).toBeInTheDocument();
    }
  });
});