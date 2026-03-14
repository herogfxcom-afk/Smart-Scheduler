"""add_outlook_event_id

Revision ID: 7f1d828eca42
Revises: db7ffc2db40e
Create Date: 2026-03-12 01:15:06.382970

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7f1d828eca42'
down_revision: Union[str, Sequence[str], None] = 'db7ffc2db40e'
branch_labels: Union[str, Sequence[str], None] = None
def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    tables = inspector.get_table_names()
    
    if 'group_meetings' in tables:
        columns = [c['name'] for c in inspector.get_columns('group_meetings')]
        if 'outlook_event_id' not in columns:
            with op.batch_alter_table('group_meetings', schema=None) as batch_op:
                batch_op.add_column(sa.Column('outlook_event_id', sa.String(length=255), nullable=True))

def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table('group_meetings', schema=None) as batch_op:
        batch_op.drop_column('outlook_event_id')
