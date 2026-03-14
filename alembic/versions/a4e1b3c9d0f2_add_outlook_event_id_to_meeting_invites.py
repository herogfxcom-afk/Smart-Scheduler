"""add_outlook_event_id_to_meeting_invites

Revision ID: a4e1b3c9d0f2
Revises: 31c39af34a93
Create Date: 2026-03-12 23:20:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a4e1b3c9d0f2'
down_revision: Union[str, Sequence[str], None] = '31c39af34a93'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add outlook_event_id and google_event_id to meeting_invites if not already present."""
    import sqlalchemy.exc
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    tables = inspector.get_table_names()

    if 'meeting_invites' in tables:
        columns = [c['name'] for c in inspector.get_columns('meeting_invites')]

        with op.batch_alter_table('meeting_invites', schema=None) as batch_op:
            if 'outlook_event_id' not in columns:
                batch_op.add_column(sa.Column('outlook_event_id', sa.String(length=512), nullable=True))
            if 'google_event_id' not in columns:
                batch_op.add_column(sa.Column('google_event_id', sa.String(length=512), nullable=True))


def downgrade() -> None:
    """Remove outlook_event_id and google_event_id from meeting_invites."""
    with op.batch_alter_table('meeting_invites', schema=None) as batch_op:
        batch_op.drop_column('outlook_event_id')
        batch_op.drop_column('google_event_id')
