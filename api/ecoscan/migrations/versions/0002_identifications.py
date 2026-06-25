"""Add persistent plant identifications."""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0002"
down_revision: Union[str, Sequence[str], None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "identifications",
        sa.Column("plant_name", sa.String(), nullable=False),
        sa.Column("plant_slug", sa.String(), nullable=True),
        sa.Column("confidence", sa.Float(), nullable=False),
        sa.Column("recognized", sa.Boolean(), nullable=False),
        sa.Column("image_data", sa.LargeBinary(), nullable=False),
        sa.Column("image_content_type", sa.String(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("in_library", sa.Boolean(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_identifications_created_at",
        "identifications",
        ["created_at"],
    )
    op.create_index(
        "ix_identifications_user_id",
        "identifications",
        ["user_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_identifications_user_id", table_name="identifications")
    op.drop_index("ix_identifications_created_at", table_name="identifications")
    op.drop_table("identifications")
