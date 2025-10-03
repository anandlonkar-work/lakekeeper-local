-- FGAC UI Extensions
-- This migration extends the existing FGAC tables to support UI-based configuration
-- with column masking and enhanced row policy management

-- Add masking capabilities to column permissions
ALTER TABLE column_permissions 
ADD COLUMN masking_enabled BOOLEAN DEFAULT false,
ADD COLUMN masking_method VARCHAR(50) CHECK (masking_method IN ('null', 'hash', 'partial', 'encrypt', 'custom')),
ADD COLUMN masking_expression TEXT,
ADD COLUMN masking_parameters JSONB,
ADD COLUMN conditions JSONB; -- For time restrictions, IP restrictions, etc.

-- Update permission types to include masking
ALTER TABLE column_permissions 
DROP CONSTRAINT column_permissions_permission_type_check,
ADD CONSTRAINT column_permissions_permission_type_check 
    CHECK (permission_type IN ('allow', 'block', 'mask', 'custom', 'read', 'write', 'owner'));

-- Create policy templates table for UI
CREATE TABLE fgac_policy_templates (
    template_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    category VARCHAR(100),
    column_rules JSONB NOT NULL DEFAULT '[]',
    row_rules JSONB NOT NULL DEFAULT '[]',
    usage_count INTEGER DEFAULT 0,
    last_used TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL REFERENCES users(id)
);

-- Create FGAC audit log for UI operations
CREATE TABLE fgac_audit_log (
    entry_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    warehouse_id UUID NOT NULL REFERENCES warehouse(warehouse_id) ON DELETE CASCADE,
    namespace_name VARCHAR NOT NULL,
    table_name VARCHAR NOT NULL,
    action_type VARCHAR(50) NOT NULL CHECK (action_type IN ('create', 'update', 'delete', 'access', 'policy_applied', 'bulk_operation')),
    resource_type VARCHAR(50) NOT NULL CHECK (resource_type IN ('column_permission', 'row_policy', 'template', 'bulk_operation')),
    resource_id UUID,
    performed_by TEXT NOT NULL REFERENCES users(id),
    before_state JSONB,
    after_state JSONB,
    details JSONB,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create row policy assignments table (many-to-many for UI flexibility)
CREATE TABLE row_policy_assignments (
    assignment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    row_policy_id UUID NOT NULL REFERENCES row_policies(row_policy_id) ON DELETE CASCADE,
    principal_type VARCHAR NOT NULL CHECK (principal_type IN ('user', 'role', 'group')),
    principal_id VARCHAR NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by TEXT NOT NULL REFERENCES users(id),
    
    -- Unique constraint to prevent duplicate assignments
    UNIQUE(row_policy_id, principal_type, principal_id)
);

-- Add estimated impact columns to row policies for UI display
ALTER TABLE row_policies 
ADD COLUMN estimated_total_rows BIGINT,
ADD COLUMN estimated_visible_rows BIGINT,
ADD COLUMN estimated_percentage_visible DECIMAL(5,2),
ADD COLUMN last_impact_calculated TIMESTAMPTZ;

-- Indexes for UI performance
CREATE INDEX idx_column_permissions_masking ON column_permissions(warehouse_id, namespace_name, table_name) 
    WHERE masking_enabled = true;

CREATE INDEX idx_fgac_audit_log_table ON fgac_audit_log(warehouse_id, namespace_name, table_name);
CREATE INDEX idx_fgac_audit_log_timestamp ON fgac_audit_log(timestamp);
CREATE INDEX idx_fgac_audit_log_performed_by ON fgac_audit_log(performed_by);

CREATE INDEX idx_row_policy_assignments_policy ON row_policy_assignments(row_policy_id);
CREATE INDEX idx_row_policy_assignments_principal ON row_policy_assignments(principal_type, principal_id);

CREATE INDEX idx_fgac_templates_category ON fgac_policy_templates(category);
CREATE INDEX idx_fgac_templates_usage ON fgac_policy_templates(usage_count DESC);

-- Update existing views to include new columns
DROP VIEW IF EXISTS active_column_permissions;
CREATE VIEW active_column_permissions AS
SELECT 
    cp.column_permission_id,
    cp.warehouse_id,
    w.warehouse_name,
    cp.namespace_name,
    cp.table_name,
    cp.column_name,
    cp.principal_type,
    cp.principal_id,
    cp.permission_type,
    cp.masking_enabled,
    cp.masking_method,
    cp.masking_expression,
    cp.masking_parameters,
    cp.conditions,
    cp.granted_by,
    u.name as granted_by_name,
    cp.granted_at,
    cp.expires_at,
    cp.created_at,
    cp.updated_at,
    CASE 
        WHEN cp.expires_at IS NULL THEN true
        WHEN cp.expires_at > now() THEN true
        ELSE false
    END as is_currently_valid
FROM column_permissions cp
JOIN warehouse w ON cp.warehouse_id = w.warehouse_id
JOIN users u ON cp.granted_by = u.id
WHERE (cp.expires_at IS NULL OR cp.expires_at > now());

-- View for UI to get column permission matrix data
CREATE VIEW column_permission_matrix AS
SELECT 
    cp.warehouse_id,
    cp.namespace_name,
    cp.table_name,
    cp.column_name,
    cp.principal_type,
    cp.principal_id,
    cp.permission_type,
    cp.masking_enabled,
    cp.masking_method,
    CASE 
        WHEN cp.permission_type = 'allow' THEN 'allow'
        WHEN cp.permission_type = 'block' THEN 'block'
        WHEN cp.permission_type = 'mask' OR cp.masking_enabled = true THEN 'mask'
        WHEN cp.permission_type = 'custom' THEN 'custom'
        ELSE 'allow'
    END as ui_permission_type
FROM active_column_permissions cp;

-- View for UI to get table FGAC summary
CREATE VIEW table_fgac_summary AS
SELECT 
    t.warehouse_id,
    t.namespace_name,
    t.table_name,
    COUNT(DISTINCT cp.column_name) as total_restricted_columns,
    COUNT(DISTINCT cp.column_permission_id) as total_column_permissions,
    COUNT(DISTINCT rp.row_policy_id) as total_row_policies,
    COUNT(DISTINCT CASE WHEN rp.is_active = true THEN rp.row_policy_id END) as active_row_policies,
    COUNT(DISTINCT cp.principal_id) + COUNT(DISTINCT rp.principal_id) as total_affected_principals,
    MAX(cp.updated_at) as last_column_permission_update,
    MAX(rp.updated_at) as last_row_policy_update
FROM (
    SELECT DISTINCT warehouse_id, namespace_name, table_name FROM column_permissions
    UNION
    SELECT DISTINCT warehouse_id, namespace_name, table_name FROM row_policies
) t
LEFT JOIN active_column_permissions cp ON (
    t.warehouse_id = cp.warehouse_id AND 
    t.namespace_name = cp.namespace_name AND 
    t.table_name = cp.table_name
)
LEFT JOIN row_policies rp ON (
    t.warehouse_id = rp.warehouse_id AND 
    t.namespace_name = rp.namespace_name AND 
    t.table_name = rp.table_name
)
GROUP BY t.warehouse_id, t.namespace_name, t.table_name;

-- Function to log FGAC operations for audit trail
CREATE OR REPLACE FUNCTION log_fgac_operation(
    p_warehouse_id UUID,
    p_namespace_name VARCHAR,
    p_table_name VARCHAR,
    p_action_type VARCHAR,
    p_resource_type VARCHAR,
    p_resource_id UUID,
    p_performed_by VARCHAR,
    p_before_state JSONB DEFAULT NULL,
    p_after_state JSONB DEFAULT NULL,
    p_details JSONB DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    audit_id UUID;
BEGIN
    INSERT INTO fgac_audit_log (
        warehouse_id,
        namespace_name,
        table_name,
        action_type,
        resource_type,
        resource_id,
        performed_by,
        before_state,
        after_state,
        details
    ) VALUES (
        p_warehouse_id,
        p_namespace_name,
        p_table_name,
        p_action_type,
        p_resource_type,
        p_resource_id,
        p_performed_by,
        p_before_state,
        p_after_state,
        p_details
    ) RETURNING entry_id INTO audit_id;
    
    RETURN audit_id;
END;
$$ LANGUAGE plpgsql;

-- Comments for new tables and columns
COMMENT ON COLUMN column_permissions.masking_enabled IS 'Whether masking is enabled for this column permission';
COMMENT ON COLUMN column_permissions.masking_method IS 'Method used for masking (null, hash, partial, encrypt, custom)';
COMMENT ON COLUMN column_permissions.masking_expression IS 'Custom SQL expression for masking';
COMMENT ON COLUMN column_permissions.masking_parameters IS 'JSON parameters for masking configuration';
COMMENT ON COLUMN column_permissions.conditions IS 'JSON conditions like time restrictions, IP restrictions';

COMMENT ON TABLE fgac_policy_templates IS 'Templates for common FGAC policy configurations';
COMMENT ON TABLE fgac_audit_log IS 'Audit trail for all FGAC operations';
COMMENT ON TABLE row_policy_assignments IS 'Many-to-many assignments of row policies to principals';

COMMENT ON COLUMN row_policies.estimated_total_rows IS 'Estimated total rows in the table';
COMMENT ON COLUMN row_policies.estimated_visible_rows IS 'Estimated rows visible after applying this policy';
COMMENT ON COLUMN row_policies.estimated_percentage_visible IS 'Percentage of rows visible after applying this policy';