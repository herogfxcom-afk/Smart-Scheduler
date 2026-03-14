"""add_user_timezone

Revision ID: abeac989d112
Revises: a4e1b3c9d0f2
Create Date: 2026-03-12 23:54:47.159469

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'abeac989d112'
down_revision: Union[str, Sequence[str], None] = 'a4e1b3c9d0f2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    tables = inspector.get_table_names()
    
    if 'users' in tables:
        columns = [c['name'] for c in inspector.get_columns('users')]
        if 'timezone' not in columns:
            with op.batch_alter_table('users', schema=None) as batch_op:
                batch_op.add_column(sa.Column('timezone', sa.String(length=50), nullable=True, server_default='UTC'))

def downgrade() -> None:
    """Downgrade schema."""
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    tables = inspector.get_table_names()
    
    if 'users' in tables:
        columns = [c['name'] for c in inspector.get_columns('users')]
        if 'timezone' in columns:
            with op.batch_alter_table('users', schema=None) as batch_op:
                batch_op.drop_column('timezone')
