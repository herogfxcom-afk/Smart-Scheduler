"""migrate_to_timestamptz

Revision ID: 31c39af34a93
Revises: 7f1d828eca42
Create Date: 2026-03-12 04:21:20.429733

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '31c39af34a93'
down_revision: Union[str, Sequence[str], None] = '7f1d828eca42'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # 1. users
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.alter_column('created_at', type_=sa.DateTime(timezone=True))
        batch_op.drop_column('google_refresh_token')
        batch_op.drop_column('apple_auth_data')

    # 2. calendar_connections
    with op.batch_alter_table('calendar_connections', schema=None) as batch_op:
        batch_op.alter_column('created_at', type_=sa.DateTime(timezone=True))
        batch_op.alter_column('last_sync', type_=sa.DateTime(timezone=True))

    # 3. groups
    with op.batch_alter_table('groups', schema=None) as batch_op:
        batch_op.alter_column('created_at', type_=sa.DateTime(timezone=True))

    # 4. group_meetings
    with op.batch_alter_table('group_meetings', schema=None) as batch_op:
        batch_op.alter_column('start_time', type_=sa.DateTime(timezone=True))
        batch_op.alter_column('end_time', type_=sa.DateTime(timezone=True))

    # 5. busy_slots
    with op.batch_alter_table('busy_slots', schema=None) as batch_op:
        batch_op.alter_column('start_time', type_=sa.DateTime(timezone=True))
        batch_op.alter_column('end_time', type_=sa.DateTime(timezone=True))

    # 6. meeting_invites
    with op.batch_alter_table('meeting_invites', schema=None) as batch_op:
        batch_op.alter_column('created_at', type_=sa.DateTime(timezone=True))
        # SQLite workarounds for dropping constraints often require batch mode + recreate
        # but for unique constraints it's safer to just handle it via batch
        batch_op.drop_constraint('_meeting_user_invite_uc', type_='unique')


def downgrade() -> None:
    """Downgrade schema."""
    # 6. meeting_invites
    with op.batch_alter_table('meeting_invites', schema=None) as batch_op:
        batch_op.create_unique_constraint('_meeting_user_invite_uc', ['meeting_id', 'user_id'])
        batch_op.alter_column('created_at', type_=sa.DateTime())

    # 5. busy_slots
    with op.batch_alter_table('busy_slots', schema=None) as batch_op:
        batch_op.alter_column('end_time', type_=sa.DateTime())
        batch_op.alter_column('start_time', type_=sa.DateTime())

    # 4. group_meetings
    with op.batch_alter_table('group_meetings', schema=None) as batch_op:
        batch_op.alter_column('end_time', type_=sa.DateTime())
        batch_op.alter_column('start_time', type_=sa.DateTime())

    # 3. groups
    with op.batch_alter_table('groups', schema=None) as batch_op:
        batch_op.alter_column('created_at', type_=sa.DateTime())

    # 2. calendar_connections
    with op.batch_alter_table('calendar_connections', schema=None) as batch_op:
        batch_op.alter_column('last_sync', type_=sa.DateTime())
        batch_op.alter_column('created_at', type_=sa.DateTime())

    # 1. users
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.add_column(sa.Column('apple_auth_data', sa.TEXT(), nullable=True))
        batch_op.add_column(sa.Column('google_refresh_token', sa.TEXT(), nullable=True))
        batch_op.alter_column('created_at', type_=sa.DateTime())
