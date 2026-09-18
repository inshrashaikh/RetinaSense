/**
 * DEMO / MOCK client for frontend development only.
 *
 *   ⚠️  THIS MODULE RETURNS SIMULATED DATA.
 *   It is used ONLY when VITE_DEMO_MODE=true and the UI always shows a
 *   persistent "DEMO MODE — simulated data, not a real screening" banner.
 *   It is NEVER used in production/API mode (see endpoints.ts) and its
 *   medical-looking values are figures for exercising the UI, not results.
 *
 * The demo is a tiny in-browser store (sessionStorage) so the case → result
 * → review → report flow works end-to-end inside a tab, mirroring the real
 * backend contract shape exactly.
 */
import type {
  AiPrediction,
  CaseListItem,
  CaseResponse,
  CaseStats,
  CreateCaseRequest,
  CreateCaseResponse,
  Explainability,
  HealthResponse,
  HumanReview,
  QualityResult,
  ReportResponse,
  ReviewRequest,
  ReviewResponse,
  SimulationCapacityResponse,
  FinalDecision,
} from './types';

export type DemoScenario = 'good' | 'borderline' | 'ungradable' | 'good-review';

const STORE_KEY = 'retinasense.demo.cases';
const DEFAULT_CASE_ID = 'RS-2026-90001';

function delay(ms = 600): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function thumbnailDataUrl(_file: File): string {
  // In a real client the uploaded file would be previewed via URL.createObjectURL.
  // The demo does not render or analyse the image; this helper exists so the
  // demo path does not pretend to process pixels.
  return '';
}

export const noExplainability: Explainability = {
  gradCamAvailable: false,
  gradCamPath: null,
  evidenceAvailable: false,
  evidencePath: null,
};

function buildCase(scenario: DemoScenario): CaseResponse {
  let quality: QualityResult;
  let aiPrediction: AiPrediction | null = null;
  let status = 'recapture_required';

  if (scenario === 'ungradable') {
    quality = {
      class: 'ungradable',
      score: 0.14,
      failureReasons: ['illumination', 'fovCoverage'],
      recaptureReason: 'LOW_ILLUMINATION',
      recaptureInstruction:
        'Image is too dark and covers too little of the retina. Please ensure ' +
        'adequate lighting and re-capture the fundus image.',
    };
  } else {
    status = 'completed';
    if (scenario === 'borderline') {
      quality = {
        class: 'borderline',
        score: 0.48,
        failureReasons: ['illumination'],
        recaptureReason: null,
        recaptureInstruction: null,
      };
      aiPrediction = {
        grade: 1,
        gradeLabel: 'Mild NPDR',
        probabilities: null,
        referable: false,
        confidence: 0.61,
        uncertainty: 0.34,
        reviewRequired: true,
      };
    } else {
      const reviewRequired = scenario === 'good-review';
      quality = {
        class: 'good',
        score: 0.92,
        failureReasons: [],
        recaptureReason: null,
        recaptureInstruction: null,
      };
      aiPrediction = {
        grade: 2,
        gradeLabel: 'Moderate NPDR',
        probabilities: null,
        referable: true,
        confidence: reviewRequired ? 0.58 : 0.81,
        uncertainty: reviewRequired ? 0.38 : 0.11,
        reviewRequired,
      };
    }
  }

  return {
    caseId: DEFAULT_CASE_ID,
    status,
    quality,
    aiPrediction,
    explainability: noExplainability,
    humanReview: null,
    finalDecision: null,
  };
}

function store(c: CaseResponse): void {
  const map: Record<string, CaseResponse> = readStore();
  map[c.caseId] = c;
  sessionStorage.setItem(STORE_KEY, JSON.stringify(map));
}

function readStore(): Record<string, CaseResponse> {
  try {
    const raw = sessionStorage.getItem(STORE_KEY);
    return raw ? (JSON.parse(raw) as Record<string, CaseResponse>) : {};
  } catch {
    return {};
  }
}

export function getCurrentScenario(): DemoScenario {
  const s = sessionStorage.getItem('retinasense.demo.scenario') as DemoScenario | null;
  return s ?? 'good';
}

export function setCurrentScenario(s: DemoScenario): void {
  sessionStorage.setItem('retinasense.demo.scenario', s);
}

// ------------------------------------------------------------------------
// Endpoint implementations (DEMO ONLY)
// ------------------------------------------------------------------------

export async function createCase(_meta: CreateCaseRequest): Promise<CreateCaseResponse> {
  await delay();
  return { caseId: DEFAULT_CASE_ID, status: 'created' };
}

export async function screenCase(
  _caseId: string,
  file: File,
  _meta: CreateCaseRequest,
): Promise<CaseResponse> {
  await delay(1200);
  thumbnailDataUrl(file); // deliberately unused — demo does not process the image
  const c = buildCase(getCurrentScenario());
  store(c);
  return c;
}

export async function getCase(caseId: string): Promise<CaseResponse> {
  await delay();
  const c = readStore()[caseId];
  if (!c) {
    throw { kind: 'http', code: 'CASE_NOT_FOUND', message: `Case '${caseId}' not found.`, httpStatus: 404 };
  }
  return c;
}

export async function listCases(): Promise<CaseListItem[]> {
  await delay();
  return Object.values(readStore())
    .map((c) => ({
      caseId: c.caseId,
      status: c.status,
      patientId: '',
      eye: '',
      phcId: '',
      createdAt: null,
    }))
    .sort((a, b) => (a.caseId < b.caseId ? 1 : -1));
}

export async function fetchCaseImage(_caseId: string): Promise<Blob> {
  await delay();
  // The demo client stores no image data — an honest IMAGE_UNAVAILABLE, never
  // a fabricated picture.
  throw {
    kind: 'http',
    code: 'IMAGE_UNAVAILABLE',
    message: 'The demo client does not store or serve fundus images.',
    httpStatus: 404,
  };
}

export async function fetchCaseArtifact(_caseId: string, _name: string): Promise<Blob> {
  await delay();
  // The demo client produces no real attention/evidence artifacts — an honest
  // ARTIFACT_UNAVAILABLE, never a fabricated overlay.
  throw {
    kind: 'http',
    code: 'ARTIFACT_UNAVAILABLE',
    message: 'The demo client does not store or serve explainability artifacts.',
    httpStatus: 404,
  };
}

export async function submitReview(
  caseId: string,
  review: ReviewRequest,
): Promise<ReviewResponse> {
  await delay();
  const c = readStore()[caseId];
  if (!c) {
    throw { kind: 'http', code: 'CASE_NOT_FOUND', message: `Case '${caseId}' not found.`, httpStatus: 404 };
  }
  if (!c.aiPrediction) {
    throw { kind: 'http', code: 'INVALID_REVIEW', message: 'No AI prediction to review.', httpStatus: 400 };
  }

  const humanReview: HumanReview = {
    action: review.action,
    reviewerId: review.reviewerId || 'demo-reviewer',
    overrideGrade: review.overrideGrade ?? (review.action === 'override' ? c.aiPrediction.grade : null),
    finalReferral: null,
    status:
      review.action === 'approve' ? 'approved'
      : review.action === 'override' ? 'overridden'
      : 'recapture',
    notes: review.notes ?? '',
    timestamp: new Date().toISOString(),
  };

  const aiGrade = c.aiPrediction.grade;
  let finalGrade: number | null;
  let referral: boolean;
  if (review.action === 'override') {
    finalGrade = review.overrideGrade ?? aiGrade;
    referral = finalGrade !== null && finalGrade >= 2;
  } else if (review.action === 'approve') {
    finalGrade = aiGrade;
    referral = aiGrade !== null && aiGrade >= 2;
  } else {
    finalGrade = null;
    referral = false;
  }
  const finalDecision: FinalDecision = {
    grade: finalGrade,
    gradeLabel: finalGrade === null ? 'Pending recapture' : labelFor(finalGrade),
    referral,
  };
  humanReview.finalReferral = finalDecision.referral;

  c.humanReview = humanReview;
  c.finalDecision = finalDecision;
  store(c);

  return { caseId, review: humanReview, finalDecision };
}

function labelFor(grade: number): string {
  const map: Record<number, string> = {
    0: 'No DR',
    1: 'Mild NPDR',
    2: 'Moderate NPDR',
    3: 'Severe NPDR',
    4: 'Proliferative DR',
  };
  return map[grade] ?? 'Unknown';
}

export function buildReportResponse(caseId: string): ReportResponse {
  const c = readStore()[caseId];
  if (!c) {
    throw { kind: 'http', code: 'CASE_NOT_FOUND', message: `Case '${caseId}' not found.`, httpStatus: 404 };
  }
  if (c.status === 'recapture_required') {
    throw {
      kind: 'http',
      code: 'REPORT_UNAVAILABLE',
      message: 'No report available for this case yet. Reports are generated after a completed screening.',
      httpStatus: 404,
    };
  }
  const reviewAction = c.humanReview?.action ?? 'none';
  return {
    caseId,
    report: {
      // Structured placeholder mirroring reporting/buildReport.m output shape.
      patientId: '',
      eye: '',
      phcId: '',
      status: c.status,
      quality: c.quality,
      aiPrediction: c.aiPrediction,
      explainability: c.explainability,
      humanReview: c.humanReview,
      finalDecision: c.finalDecision,
      reviewAction,
      disclaimer: 'Screening decision-support only. Not a diagnosis or a replacement for an ophthalmologist.',
    },
    summary: `Demo report for case ${caseId}. Quality ${c.quality.class}. ` +
      `AI grade ${c.aiPrediction?.grade ?? 'n/a'} (${c.aiPrediction?.gradeLabel ?? '-'}), ` +
      `referable ${String(c.aiPrediction?.referable)}. Review: ${reviewAction}.`,
    disclaimer: 'Screening decision-support only. Not a diagnosis or a replacement for an ophthalmologist.',
  };
}

export async function fetchHealth(): Promise<HealthResponse> {
  await delay();
  // Simulated engine status for DEMO ONLY.
  return { status: 'ok', matlabEngine: true, version: 'demo', database: 'ok' };
}

export async function fetchCaseStats(): Promise<CaseStats> {
  await delay();
  const cases = Object.values(readStore());
  return {
    totalCases: cases.length,
    screeningsCompleted: cases.filter((c) => c.status === 'completed').length,
    pendingReviews: cases.filter((c) => c.status === 'completed' && !c.humanReview).length,
    recaptureRequired: cases.filter((c) => c.status === 'recapture_required').length,
    reviewed: cases.filter((c) => Boolean(c.humanReview)).length,
    created: cases.filter((c) => c.status === 'created').length,
  };
}

/**
 * DEMO counterpart of the district-capacity endpoint. Every figure below is
 * clearly SIMULATED for exercising the UI — the capacity dashboard banner
 * disclaims it. Distinct per-scenario numbers keep the scenario table honest
 * about the SHAPE of the API; they are never presented as measured results.
 */
export async function fetchSimulationCapacity(): Promise<SimulationCapacityResponse> {
  await delay();
  return {
    available: true,
    latest: {
      generatedAt: 'DEMO — simulated scenario set',
      matlabVersion: 'demo',
      simulinkVersion: 'demo',
      simEventsVersion: 'demo',
      modelFile: 'DRTelemedicine.slx',
      dataSourcePolicy:
        'DEMO MODE: simulated values for UI exercise only. Not measured from a SimEvents run.',
      results: [
        {
          scenario: 'baseline',
          executionStatus: 'DEMO',
          measurementWindow: 'FULL_WORKDAY',
          patientsPerDay: 274,
          bandwidthMbps: 2.0,
          numReviewers: 2,
          simTimeHours: 8,
          completedPatients: 150,
          throughput: 150.0,
          annualCapacity: 54750,
          averageWaitingTime: 4000,
          meanWaitingTime: 1500,
          maxWaitingTime: 4500,
          queueLength: 28,
          acqUtilization: 0.9,
          networkUtilization: 0.2,
          aiUtilization: 0.3,
          revUtilization: 0.05,
          reviewerUtilization: 0.05,
          bottleneck: 'Acquisition',
        },
        {
          scenario: 'team_5_reviewers',
          executionStatus: 'DEMO',
          measurementWindow: 'FULL_WORKDAY',
          patientsPerDay: 274,
          bandwidthMbps: 2.0,
          numReviewers: 5,
          simTimeHours: 8,
          completedPatients: 180,
          throughput: 180.0,
          annualCapacity: 65700,
          averageWaitingTime: 3200,
          meanWaitingTime: 1300,
          maxWaitingTime: 3900,
          queueLength: 22,
          acqUtilization: 0.9,
          networkUtilization: 0.2,
          aiUtilization: 0.3,
          revUtilization: 0.02,
          reviewerUtilization: 0.02,
          bottleneck: 'Acquisition',
        },
      ],
    },
    runs: [],
    target: {
      annualPatients: 100_000,
      dailyEquivalent: 274,
      note:
        '100,000 patients/year is the reference scalability target. Demo figures never reach it by assumption.',
    },
  };
}

export async function generateReport(caseId: string): Promise<ReportResponse> {
  await delay();
  return buildReportResponse(caseId);
}

/** DEMO sessions are implicit — a clearly-labelled pretend profile. */
export async function fetchMe(): Promise<import('./types').UserInfo> {
  await delay();
  return { id: 0, username: 'demo', name: 'Demo Operator', role: 'ophthalmologist' };
}

/**
 * DEMO mode has no real backend, so no PDF is fabricated. Refuses honestly —
 * the UI shows an error instead of inventing a document.
 */
export async function fetchReportPdf(_caseId: string): Promise<Blob> {
  await delay();
  throw new Error('PDF reports are only available against the real (non-demo) backend.');
}