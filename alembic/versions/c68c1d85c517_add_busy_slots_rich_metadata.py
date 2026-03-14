"""add_busy_slots_rich_metadata

Revision ID: c68c1d85c517
Revises: abeac989d112
Create Date: 2026-03-14 16:40:21.474610

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c68c1d85c517'
down_revision: Union[str, Sequence[str], None] = 'abeac989d112'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema - Add metadata columns to busy_slots."""
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    tables = inspector.get_table_names()

    if 'busy_slots' in tables:
        columns = [c['name'] for c in inspector.get_columns('busy_slots')]
        with op.batch_alter_table('busy_slots', schema=None) as batch_op:
            if 'summary' not in columns:
                batch_op.add_column(sa.Column('summary', sa.String(length=255), nullable=True))
            if 'external_id' not in columns:
                batch_op.add_column(sa.Column('external_id', sa.String(length=255), nullable=True))
            if 'is_external' not in columns:
                batch_op.add_column(sa.Column('is_external', sa.Boolean(), nullable=True))


def downgrade() -> None:
    """Downgrade schema - Remove metadata columns from busy_slots."""
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    tables = inspector.get_table_names()

    if 'busy_slots' in tables:
        columns = [c['name'] for c in inspector.get_columns('busy_slots')]
        with op.batch_alter_table('busy_slots', schema=None) as batch_op:
            if 'summary' in columns:
                batch_op.drop_column('summary')
            if 'external_id' in columns:
                batch_op.drop_column('external_id')
            if 'is_external' in columns:
                batch_op.drop_column('is_external')
