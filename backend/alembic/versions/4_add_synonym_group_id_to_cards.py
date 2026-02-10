"""add synonym_group_id to cards

Revision ID: 4
Revises: 3bf53dd3541d
Create Date: 2026-02-10

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision: str = "4"
down_revision: Union[str, None] = "3bf53dd3541d"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("cards", sa.Column("synonym_group_id", UUID(as_uuid=True), nullable=True))


def downgrade() -> None:
    op.drop_column("cards", "synonym_group_id")
