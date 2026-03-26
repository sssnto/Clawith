"""Add agent_relations table.

Idempotent — uses IF NOT EXISTS for ALTER statements.
"""

from alembic import op

revision = "add_agent_relations"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE IF NOT EXISTS agent_relations (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            from_agent_id UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
            to_agent_id UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
            relationship_type VARCHAR(50) NOT NULL,
            description TEXT,
            metadata JSONB DEFAULT '{}',
            created_at TIMESTAMP DEFAULT NOW()
        )
    """)
    op.execute("CREATE INDEX IF NOT EXISTS idx_agent_relations_from ON agent_relations(from_agent_id)")
    op.execute("CREATE INDEX IF NOT EXISTS idx_agent_relations_to ON agent_relations(to_agent_id)")


def downgrade() -> None:
    pass