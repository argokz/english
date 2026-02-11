"""add examples (JSONB) to cards

Revision ID: 7
Revises: 6
Create Date: 2026-02-10

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

revision: str = "7"
down_revision: Union[str, None] = "6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("cards", sa.Column("examples", JSONB, nullable=True))


def downgrade() -> None:
    op.drop_column("cards", "examples")
