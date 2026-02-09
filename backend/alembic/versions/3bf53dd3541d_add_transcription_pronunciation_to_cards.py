"""add_transcription_pronunciation_to_cards

Revision ID: 3bf53dd3541d
Revises: 001
Create Date: 2026-02-09 22:58:17.523477

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '3bf53dd3541d'
down_revision: Union[str, None] = '001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('cards', sa.Column('transcription', sa.String(100), nullable=True))
    op.add_column('cards', sa.Column('pronunciation_url', sa.String(512), nullable=True))


def downgrade() -> None:
    op.drop_column('cards', 'pronunciation_url')
    op.drop_column('cards', 'transcription')
