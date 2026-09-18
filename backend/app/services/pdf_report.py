"""PDF report generation for RetinaSense (reportlab).

Builds a real, downloadable screening report for a case from the SAME stored
data the API already exposes (never fabricates new values):

  * patient/eye/phc identifiers (opaque non-PII)
  * the fundus image and the Grad-CAM attention overlay when available
  * AI grade + confidence + uncertainty + referable flag
  * advisory findings summary
  * human review status + final decision (when recorded)
  * generation timestamp + disclaimer

The file is cached per case at backend/data/reports/<caseId>.pdf and rebuilt
when the stored report state changes.
"""
from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import (
    Image,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

from ..config import DATA_DIR, IMAGES_DIR, REPORTS_DIR, REFER_THRESHOLD
from ..storage import database_store
from ..utils.errors import ErrorCode, RetinaSenseError

_ARTIFACTS_DIR = DATA_DIR / "artifacts"


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _load_case_payload(case_id: str) -> dict:
    if not database_store.case_exists(case_id):
        raise RetinaSenseError(
            ErrorCode.CASE_NOT_FOUND,
            f"Case '{case_id}' not found.",
            stage="storage",
        )
    screening = database_store.load_screening(case_id)
    if screening is None:
        raise RetinaSenseError(
            ErrorCode.REPORT_UNAVAILABLE,
            "No screening has been run for this case yet.",
            stage="reporting",
        )
    meta = database_store.load_metadata(case_id) or {}
    review_data = database_store.load_review(case_id) or {}
    return {
        "caseId": case_id,
        "meta": meta,
        "screening": screening,
        "review": review_data,
    }


def _image_path(case_id: str) -> Path | None:
    path = database_store.load_image_path(case_id)
    return path if path is not None else None


def _artifact_path(case_id: str, name: str, explainability: dict) -> Path | None:
    available_key = "gradCamAvailable" if name == "gradcam" else "evidenceAvailable"
    if not explainability.get(available_key):
        return None
    path = _ARTIFACTS_DIR / case_id / f"{name}.png"
    return path if path.is_file() else None


def _label(grade):
    from ..config import GRADE_LABELS

    return GRADE_LABELS.get(grade, "Unknown") if grade is not None else "—"


def _render_html_field(field: tuple[str, str | None]) -> str:
    label, value = field
    value = "—" if value is None or value == "" else str(value)
    return f"<b>{label}:</b> {value}"


def build_report_pdf(case_id: str) -> Path:
    """Build (or refresh) the PDF for a case and return its file path."""
    data = _load_case_payload(case_id)
    screening = data["screening"]
    meta = data["meta"]
    review = data["review"]

    quality = screening.get("quality", {})
    ai_pred = screening.get("aiPrediction") or {}
    explain = screening.get("explainability") or {}
    human_review = review.get("review") or {}
    final_decision = review.get("finalDecision") or {}

    out_dir = REPORTS_DIR / case_id
    out_dir.mkdir(parents=True, exist_ok=True)
    pdf_path = out_dir / f"{case_id}.pdf"

    doc = SimpleDocTemplate(
        str(pdf_path),
        pagesize=A4,
        leftMargin=1.5 * cm,
        rightMargin=1.5 * cm,
        topMargin=1.2 * cm,
        bottomMargin=1.2 * cm,
        title=f"RetinaSense Screening Report {case_id}",
        author="RetinaSense",
    )

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        "RSTitle", parent=styles["Title"], textColor=colors.HexColor("#176b5b"), fontSize=20
    )
    h2_style = ParagraphStyle(
        "RSH2", parent=styles["Heading2"], textColor=colors.HexColor("#102b29"), fontSize=13
    )
    body = styles["BodyText"]
    small_style = ParagraphStyle(
        "RSSmall", parent=styles["BodyText"], fontSize=8.5, leading=11,
        textColor=colors.HexColor("#5e6e68"),
    )

    story: list = []

    story.append(Paragraph(f"RetinaSense Screening Report", title_style))
    story.append(Paragraph(
        f"DIABETIC RETINOPATHY SCREENING &nbsp;|&nbsp; {case_id} &nbsp;|&nbsp; "
        f"Generated {_now_iso()}",
        small_style,
    ))
    story.append(Spacer(1, 0.4 * cm))

    # ---- Case + patient identifiers (opaque, non-PII) ----
    story.append(Paragraph("Case Details", h2_style))
    case_rows = [
        ("Case", case_id),
        ("Patient ID", meta.get("patientId") or "—"),
        ("Eye", meta.get("eye") or "—"),
        ("PHC", meta.get("phcId") or "—"),
        ("Screening date/time", screening.get("createdAt") or "—"),
        ("Status", screening.get("status", "created")),
    ]
    case_tbl = Table([[Paragraph(_render_html_field(r), body)] for r in case_rows], colWidths=[16.5 * cm])
    case_tbl.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#dde8e1")),
        ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#f0f8f4")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    story.append(case_tbl)
    story.append(Spacer(1, 0.5 * cm))

    # ---- Quality gate ----
    story.append(Paragraph("Image Quality Gate", h2_style))
    q_class = quality.get("class") or "—"
    q_score = quality.get("score")
    story.append(Paragraph(
        _render_html_field(("Quality", f"{str(q_class).capitalize()} (score {q_score:.0%})" if q_score is not None else str(q_class).capitalize())),
        body,
    ))
    if quality.get("failureReasons"):
        story.append(Paragraph(
            f"Failure reasons: {', '.join(str(r) for r in quality['failureReasons'])}", body
        ))
    if quality.get("recaptureInstruction"):
        story.append(Paragraph(
            f"<b>Recapture guidance:</b> {quality['recaptureInstruction']}", body
        ))
    story.append(Spacer(1, 0.3 * cm))

    # ---- Fundus image + Grad-CAM ----
    story.append(Paragraph("Fundus Image &amp; Model Attention", h2_style))
    img_path = _image_path(case_id)
    if img_path is not None:
        img_cols: list = []
        try:
            # reportlab defers image decode to build time, so a stored file
            # that does not actually decode would 500 the whole download.
            # Validate up-front so it falls back to the honest placeholder.
            with PILImage.open(str(img_path)) as _im:
                _im.load()
            img_cols.append(Image(str(img_path), width=7.5 * cm, height=7.5 * cm))
        except Exception:
            img_cols.append(Paragraph("<i>Fundus image unavailable for embedding.</i>", body))
        for artifact_name in ("gradcam", "evidence"):
            artifact_path = _artifact_path(case_id, artifact_name, explain)
            if artifact_path is None:
                continue
            try:
                with PILImage.open(str(artifact_path)) as _im:
                    _im.load()
                img_cols.append(Image(str(artifact_path), width=5.2 * cm, height=5.2 * cm))
            except Exception:
                pass
        if len(img_cols) == 1:
            story.append(img_cols[0])
        else:
            img_tbl = Table([img_cols], colWidths=[5.5 * cm] * len(img_cols))
            img_tbl.setStyle(TableStyle([
                ("ALIGN", (0, 0), (-1, -1), "LEFT"),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ]))
            story.append(img_tbl)
        story.append(Paragraph(
            "<small>Images: fundus photo; model Grad-CAM attention when available; "
            "retinal evidence overlay when produced. Model attention — not proof of causality.</small>",
            small_style,
        ))
        story.append(Spacer(1, 0.3 * cm))
    else:
        story.append(Paragraph("<i>No fundus image stored for this case.</i>", body))
        story.append(Spacer(1, 0.2 * cm))

    # ---- AI prediction ----
    story.append(Paragraph("AI Prediction", h2_style))
    grade = ai_pred.get("grade")
    ref = ai_pred.get("referable")
    ai_rows = [
        ("DR Grade", f"{grade} — {_label(grade)}" if grade is not None else "Not assessed"),
        ("Referable (≥ L2)", "Yes" if ref else ("No" if ref is False else "—")),
    ]
    if ai_pred.get("confidence") is not None:
        ai_rows.append(("Calibrated Confidence", f"{ai_pred['confidence']:.0%}"))
    if ai_pred.get("uncertainty") is not None:
        ai_rows.append(("Uncertainty", f"{ai_pred['uncertainty']:.0%}"))
    ai_rows.append(("Human review required", "Yes" if ai_pred.get("reviewRequired") else "No"))
    ai_tbl = Table([[Paragraph(_render_html_field(r), body)] for r in ai_rows], colWidths=[16.5 * cm])
    ai_tbl.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#dde8e1")),
        ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#e9f2f8")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    story.append(ai_tbl)
    story.append(Spacer(1, 0.4 * cm))

    # ---- Advisory analyses ----
    story.append(Paragraph("Advisory Findings (non-blocking)", h2_style))
    evidence_note = "Advisory retinal/lesion analysis was advisory and non-blocking."
    story.append(Paragraph(evidence_note, body))
    story.append(Spacer(1, 0.3 * cm))

    # ---- Human review + final decision ----
    story.append(Paragraph("Human Review &amp; Final Decision", h2_style))
    if human_review.get("action"):
        hr_rows = [
            ("Action", str(human_review.get("action", "—"))),
            ("Reviewer", str(human_review.get("reviewerId") or "—")),
            ("Status", str(human_review.get("status") or "—")),
        ]
        if human_review.get("notes"):
            hr_rows.append(("Notes", str(human_review["notes"])))
        if final_decision.get("grade") is not None:
            fd_grade = final_decision["grade"]
            hr_rows.append(
                ("Final grade", f"{fd_grade} — {_label(fd_grade)}")
            )
        if final_decision.get("referral") is not None:
            hr_rows.append(
                ("Final referral", "Yes" if final_decision["referral"] else "No")
            )
        hr_tbl = Table([[Paragraph(_render_html_field(r), body)] for r in hr_rows], colWidths=[16.5 * cm])
        hr_tbl.setStyle(TableStyle([
            ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#dde8e1")),
            ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#fdf3e2")),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 6),
            ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ]))
        story.append(hr_tbl)
    else:
        if screening.get("status") == "recapture_required":
            story.append(Paragraph(
                "Recapture required — no final decision until a gradable image is provided.",
                body,
            ))
        else:
            story.append(Paragraph("No human review recorded yet.", body))
    story.append(Spacer(1, 0.5 * cm))

    # ---- Disclaimer ----
    disclaimer = (
        "Screening decision-support only. Not a diagnosis and not a replacement "
        "for an ophthalmologist. Referable screening (grade ≥ 2) requires "
        "specialist confirmation."
    )
    disc_style = ParagraphStyle(
        "RSDisc", parent=small_style, textColor=colors.HexColor("#5e6e68")
    )
    story.append(Spacer(1, 0.3 * cm))
    story.append(Paragraph(disclaimer, disc_style))

    doc.build(story)
    return pdf_path