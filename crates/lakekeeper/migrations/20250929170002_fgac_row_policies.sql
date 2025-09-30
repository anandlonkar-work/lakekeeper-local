-- FGAC Row Policies Table
-- This table stores fine-grained row-level access policies

CREATE TABLE row_policies (
    row_policy_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    warehouse_id UUID NOT NULL,
    namespace_name VARCHAR NOT NULL,
    table_name VARCHAR NOT NULL,
    policy_name VARCHAR NOT NULL,
    principal_type VARCHAR NOT NULL CHECK (principal_type IN ('user', 'role', 'group')),
    principal_id VARCHAR NOT NULL,
    policy_expression TEXT NOT NULL, -- SQL WHERE clause expression
    policy_type VARCHAR NOT NULL CHECK (policy_type IN ('filter', 'deny', 'allow')) DEFAULT 'filter',
    is_active BOOLEAN NOT NULL DEFAULT true,
    priority INTEGER NOT NULL DEFAULT 100, -- Higher priority = applied first
    granted_by TEXT NOT NULL,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Ensure unique policy name per table per principal
    UNIQUE(warehouse_id, namespace_name, table_name, policy_name, principal_type, principal_id),
    
    -- Foreign key constraints
    CONSTRAINT fk_row_policies_warehouse 
        FOREIGN KEY (warehouse_id) 
        REFERENCES warehouse (warehouse_id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_row_policies_granted_by 
        FOREIGN KEY (granted_by) 
        REFERENCES users (id) 
        ON DELETE RESTRICT
);

-- Indexes for performance
CREATE INDEX idx_row_policies_warehouse_table 
    ON row_policies (warehouse_id, namespace_name, table_name);

CREATE INDEX idx_row_policies_principal 
    ON row_policies (principal_type, principal_id);

CREATE INDEX idx_row_policies_active 
    ON row_policies (warehouse_id, namespace_name, table_name, is_active) 
    WHERE is_active = true;

CREATE INDEX idx_row_policies_priority 
    ON row_policies (warehouse_id, namespace_name, table_name, priority DESC)
    WHERE is_active = true;

CREATE INDEX idx_row_policies_expires_at 
    ON row_policies (expires_at) 
    WHERE expires_at IS NOT NULL;

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_row_policies_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update updated_at
CREATE TRIGGER trigger_row_policies_updated_at
    BEFORE UPDATE ON row_policies
    FOR EACH ROW
    EXECUTE FUNCTION update_row_policies_updated_at();

-- Function to validate policy expressions (basic validation)
CREATE OR REPLACE FUNCTION validate_row_policy_expression(expression TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    -- Basic validation: check for dangerous keywords
    IF expression ~* '\b(drop|delete|insert|update|create|alter|grant|revoke)\b' THEN
        RETURN false;
    END IF;
    
    -- Check for balanced parentheses
    IF (LENGTH(expression) - LENGTH(REPLACE(expression, '(', ''))) != 
       (LENGTH(expression) - LENGTH(REPLACE(expression, ')', ''))) THEN
        RETURN false;
    END IF;
    
    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Check constraint to validate policy expressions
ALTER TABLE row_policies 
ADD CONSTRAINT check_valid_policy_expression 
CHECK (validate_row_policy_expression(policy_expression));

-- Comments for documentation
COMMENT ON TABLE row_policies IS 'Fine-grained row-level access control policies';
COMMENT ON COLUMN row_policies.row_policy_id IS 'Unique identifier for the row policy';
COMMENT ON COLUMN row_policies.warehouse_id IS 'Reference to the warehouse containing the table';
COMMENT ON COLUMN row_policies.namespace_name IS 'Namespace/schema name containing the table';
COMMENT ON COLUMN row_policies.table_name IS 'Name of the table the policy applies to';
COMMENT ON COLUMN row_policies.policy_name IS 'Human-readable name for the policy';
COMMENT ON COLUMN row_policies.principal_type IS 'Type of principal (user, role, group)';
COMMENT ON COLUMN row_policies.principal_id IS 'Identifier of the principal';
COMMENT ON COLUMN row_policies.policy_expression IS 'SQL WHERE clause expression for row filtering';
COMMENT ON COLUMN row_policies.policy_type IS 'Type of policy: filter (WHERE clause), deny (block access), allow (grant access)';
COMMENT ON COLUMN row_policies.is_active IS 'Whether the policy is currently active';
COMMENT ON COLUMN row_policies.priority IS 'Policy priority (higher number = applied first)';
COMMENT ON COLUMN row_policies.granted_by IS 'User who created this policy';
COMMENT ON COLUMN row_policies.expires_at IS 'Optional expiration timestamp for the policy';