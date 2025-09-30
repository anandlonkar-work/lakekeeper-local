-- FGAC Column Permissions Table
-- This table stores fine-grained column-level access permissions

CREATE TABLE column_permissions (
    column_permission_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    warehouse_id UUID NOT NULL,
    namespace_name VARCHAR NOT NULL,
    table_name VARCHAR NOT NULL,
    column_name VARCHAR NOT NULL,
    principal_type VARCHAR NOT NULL CHECK (principal_type IN ('user', 'role', 'group')),
    principal_id VARCHAR NOT NULL,
    permission_type VARCHAR NOT NULL CHECK (permission_type IN ('read', 'write', 'owner')),
    granted_by TEXT NOT NULL,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Ensure unique permission per column per principal
    UNIQUE(warehouse_id, namespace_name, table_name, column_name, principal_type, principal_id, permission_type),
    
    -- Foreign key constraints
    CONSTRAINT fk_column_permissions_warehouse 
        FOREIGN KEY (warehouse_id) 
        REFERENCES warehouse (warehouse_id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_column_permissions_granted_by 
        FOREIGN KEY (granted_by) 
        REFERENCES users (id) 
        ON DELETE RESTRICT
);

-- Indexes for performance
CREATE INDEX idx_column_permissions_warehouse_table 
    ON column_permissions (warehouse_id, namespace_name, table_name);

CREATE INDEX idx_column_permissions_principal 
    ON column_permissions (principal_type, principal_id);

CREATE INDEX idx_column_permissions_column 
    ON column_permissions (warehouse_id, namespace_name, table_name, column_name);

CREATE INDEX idx_column_permissions_expires_at 
    ON column_permissions (expires_at) 
    WHERE expires_at IS NOT NULL;

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_column_permissions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update updated_at
CREATE TRIGGER trigger_column_permissions_updated_at
    BEFORE UPDATE ON column_permissions
    FOR EACH ROW
    EXECUTE FUNCTION update_column_permissions_updated_at();

-- Comments for documentation
COMMENT ON TABLE column_permissions IS 'Fine-grained column-level access control permissions';
COMMENT ON COLUMN column_permissions.column_permission_id IS 'Unique identifier for the column permission';
COMMENT ON COLUMN column_permissions.warehouse_id IS 'Reference to the warehouse containing the table';
COMMENT ON COLUMN column_permissions.namespace_name IS 'Namespace/schema name containing the table';
COMMENT ON COLUMN column_permissions.table_name IS 'Name of the table containing the column';
COMMENT ON COLUMN column_permissions.column_name IS 'Name of the column being protected';
COMMENT ON COLUMN column_permissions.principal_type IS 'Type of principal (user, role, group)';
COMMENT ON COLUMN column_permissions.principal_id IS 'Identifier of the principal';
COMMENT ON COLUMN column_permissions.permission_type IS 'Type of permission (read, write, owner)';
COMMENT ON COLUMN column_permissions.granted_by IS 'User who granted this permission';
COMMENT ON COLUMN column_permissions.expires_at IS 'Optional expiration timestamp for the permission';