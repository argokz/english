"""add writing_submissions table

Revision ID: 5
Revises: 4
Create Date: 2026-02-10

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, JSONB

revision: str = "5"
down_revision: Union[str, None] = "4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "writing_submissions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("original_text", sa.Text(), nullable=False),
        sa.Column("word_count", sa.Integer(), nullable=False),
        sa.Column("time_used_seconds", sa.Integer(), nullable=True),
        sa.Column("time_limit_minutes", sa.Integer(), nullable=True),
        sa.Column("word_limit_min", sa.Integer(), nullable=True),
        sa.Column("word_limit_max", sa.Integer(), nullable=True),
        sa.Column("task_type", sa.String(32), nullable=True),
        sa.Column("evaluation", sa.Text(), nullable=False, server_default=""),
        sa.Column("corrected_text", sa.Text(), nullable=False, server_default=""),
        sa.Column("errors", JSONB(), nullable=True),
        sa.Column("recommendations", sa.Text(), nullable=False, server_default=""),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_writing_submissions_user_id", "writing_submissions", ["user_id"])
    op.create_index("ix_writing_submissions_created_at", "writing_submissions", ["created_at"])


def downgrade() -> None:
    op.drop_table("writing_submissions")
