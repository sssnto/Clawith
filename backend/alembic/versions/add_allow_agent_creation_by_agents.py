"""Add allow_agent_creation_by_agents field to tenants table.

Idempotent — uses IF NOT EXISTS for ALTER statements.
"""

from alembic import op

revision = "add_allow_agent_creation_by_agents"
down_revision = "add_llm_max_output_tokens"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE tenants ADD COLUMN IF NOT EXISTS allow_agent_creation_by_agents BOOLEAN DEFAULT FALSE"
    )


def downgrade() -> None:
    pass  # Not reversible safely (column may have data)