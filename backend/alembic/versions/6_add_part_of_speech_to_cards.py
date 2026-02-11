"""add part_of_speech to cards

Revision ID: 6
Revises: 5
Create Date: 2026-02-10

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "6"
down_revision: Union[str, None] = "5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("cards", sa.Column("part_of_speech", sa.String(32), nullable=True))


def downgrade() -> None:
    op.drop_column("cards", "part_of_speech")
