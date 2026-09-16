"""SQLAlchemy ORM models for the RetinaSense backend database (SQLite).

Table separation enforces the core guardrail: the AI screening result
(screening_results) and the human final decision (human_reviews +
final_decisions) live in independent tables.  A human override can never
mutate the AI result row — only the final-decision rows are written.

Nested payloads (quality, aiPrediction, explainability, review entry, report)
are stored as JSON text columns so the original dict shapes round-trip exactly.
"""
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import JSON, Boolean, ForeignKey, Integer, String, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class CaseRecord(Base):
    __tablename__ = "cases"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    case_id: Mapped[str] = mapped_column(String, unique=True, index=True, nullable=False)
    status: Mapped[str] = mapped_column(String, nullable=False, default="created")
    patient_id: Mapped[str] = mapped_column(String, nullable=False, default="")
    eye: Mapped[str] = mapped_column(String, nullable=False, default="")
    phc_id: Mapped[str] = mapped_column(String, nullable=False, default="")
    created_at: Mapped[str] = mapped_column(String, nullable=False, default=_now)


class ImageRecord(Base):
    __tablename__ = "images"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    case_id: Mapped[str] = mapped_column(
        String, ForeignKey("cases.case_id"), nullable=False, index=True
    )
    filename: Mapped[str] = mapped_column(String, nullable=False)
    relative_path: Mapped[str] = mapped_column(String, nullable=False)
    content_type: Mapped[str] = mapped_column(String, nullable=False, default="image/jpeg")
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[str] = mapped_column(String, nullable=False, default=_now)


class ScreeningRecord(Base):
    """AI/quality-gate output.  Written once by the screening pipeline; the
    human-review path NEVER touches this row."""

    __tablename__ = "screening_results"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    case_id: Mapped[str] = mapped_column(
        String, ForeignKey("cases.case_id"), unique=True, nullable=False, index=True
    )
    status: Mapped[str] = mapped_column(String, nullable=False, default="created")
    quality: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    ai_prediction: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    explainability: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[str] = mapped_column(String, nullable=False, default=_now)


class HumanReviewRecord(Base):
    __tablename__ = "human_reviews"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    case_id: Mapped[str] = mapped_column(
        String, ForeignKey("cases.case_id"), unique=True, nullable=False, index=True
    )
    action: Mapped[str] = mapped_column(String, nullable=False)
    reviewer_id: Mapped[str] = mapped_column(String, nullable=False, default="")
    override_grade: Mapped[int | None] = mapped_column(Integer, nullable=True)
    final_referral: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    status: Mapped[str] = mapped_column(String, nullable=False)
    notes: Mapped[str] = mapped_column(Text, nullable=False, default="")
    ai_grade_immutable: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    payload: Mapped[dict] = mapped_column(JSON, nullable=False)
    created_at: Mapped[str] = mapped_column(String, nullable=False, default=_now)


class FinalDecisionRecord(Base):
    __tablename__ = "final_decisions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    case_id: Mapped[str] = mapped_column(
        String, ForeignKey("cases.case_id"), unique=True, nullable=False, index=True
    )
    grade: Mapped[int | None] = mapped_column(Integer, nullable=True)
    grade_label: Mapped[str | None] = mapped_column(String, nullable=True)
    referral: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    created_at: Mapped[str] = mapped_column(String, nullable=False, default=_now)


class ReportRecord(Base):
    __tablename__ = "reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    case_id: Mapped[str] = mapped_column(
        String, ForeignKey("cases.case_id"), unique=True, nullable=False, index=True
    )
    payload: Mapped[dict] = mapped_column(JSON, nullable=False)
    summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    disclaimer: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[str] = mapped_column(String, nullable=False, default=_now)


class UserRecord(Base):
    """Application user with a role-aware account (prototype auth)."""

    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    username: Mapped[str] = mapped_column(String, unique=True, nullable=False, index=True)
    name: Mapped[str] = mapped_column(String, nullable=False, default="")
    role: Mapped[str] = mapped_column(String, nullable=False, default="phc_operator")
    password_hash: Mapped[str] = mapped_column(String, nullable=False)
    created_at: Mapped[str] = mapped_column(String, nullable=False, default=_now)