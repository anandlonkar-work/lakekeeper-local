-- FGAC Helper Views and Functions
-- This migration creates utility views and functions for FGAC operations

-- View to easily query active column permissions
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
    cp.granted_by,
    u.name as granted_by_name,
    cp.granted_at,
    cp.expires_at,
    CASE 
        WHEN cp.expires_at IS NULL THEN true
        WHEN cp.expires_at > now() THEN true
        ELSE false
    END as is_currently_valid
FROM column_permissions cp
JOIN warehouse w ON cp.warehouse_id = w.warehouse_id
JOIN users u ON cp.granted_by = u.id
WHERE (cp.expires_at IS NULL OR cp.expires_at > now());

-- View to easily query active row policies
CREATE VIEW active_row_policies AS
SELECT 
    rp.row_policy_id,
    rp.warehouse_id,
    w.warehouse_name,
    rp.namespace_name,
    rp.table_name,
    rp.policy_name,
    rp.principal_type,
    rp.principal_id,
    rp.policy_expression,
    rp.policy_type,
    rp.priority,
    rp.granted_by,
    u.name as granted_by_name,
    rp.granted_at,
    rp.expires_at,
    CASE 
        WHEN rp.expires_at IS NULL THEN true
        WHEN rp.expires_at > now() THEN true
        ELSE false
    END as is_currently_valid
FROM row_policies rp
JOIN warehouse w ON rp.warehouse_id = w.warehouse_id
JOIN users u ON rp.granted_by = u.id
WHERE rp.is_active = true 
  AND (rp.expires_at IS NULL OR rp.expires_at > now())
ORDER BY rp.priority DESC;

-- Function to get column permissions for a specific principal
CREATE OR REPLACE FUNCTION get_column_permissions(
    p_warehouse_id UUID,
    p_namespace_name VARCHAR,
    p_table_name VARCHAR,
    p_principal_type VARCHAR,
    p_principal_id VARCHAR
)
RETURNS TABLE (
    column_name VARCHAR,
    permission_type VARCHAR,
    granted_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cp.column_name,
        cp.permission_type,
        cp.granted_at,
        cp.expires_at
    FROM active_column_permissions cp
    WHERE cp.warehouse_id = p_warehouse_id
      AND cp.namespace_name = p_namespace_name
      AND cp.table_name = p_table_name
      AND cp.principal_type = p_principal_type
      AND cp.principal_id = p_principal_id
      AND cp.is_currently_valid = true
    ORDER BY cp.column_name, cp.permission_type;
END;
$$ LANGUAGE plpgsql;

-- Get row policies for a specific user and table
CREATE OR REPLACE VIEW get_row_policies AS
SELECT 
    rp.row_policy_id,
    rp.warehouse_id,
    rp.namespace_name,
    rp.table_name,
    rp.principal_type,
    rp.principal_id,
    rp.policy_expression,
    rp.priority,
    rp.policy_name,
    u.name as user_name,
    u.email as user_email
FROM row_policies rp
LEFT JOIN users u ON rp.principal_id = u.id AND rp.principal_type = 'user'
WHERE rp.is_active = true
ORDER BY rp.warehouse_id, rp.namespace_name, rp.table_name, rp.priority DESC;

-- Function to check if a principal has column access
CREATE OR REPLACE FUNCTION has_column_permission(
    p_warehouse_id UUID,
    p_namespace_name VARCHAR,
    p_table_name VARCHAR,
    p_column_name VARCHAR,
    p_principal_type VARCHAR,
    p_principal_id VARCHAR,
    p_permission_type VARCHAR DEFAULT 'read'
)
RETURNS BOOLEAN AS $$
DECLARE
    permission_exists BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 
        FROM active_column_permissions cp
        WHERE cp.warehouse_id = p_warehouse_id
          AND cp.namespace_name = p_namespace_name
          AND cp.table_name = p_table_name
          AND cp.column_name = p_column_name
          AND cp.principal_type = p_principal_type
          AND cp.principal_id = p_principal_id
          AND cp.permission_type = p_permission_type
          AND cp.is_currently_valid = true
    ) INTO permission_exists;
    
    RETURN permission_exists;
END;
$$ LANGUAGE plpgsql;

-- Function to get combined row policy expression for a principal
CREATE OR REPLACE FUNCTION get_combined_row_policy(
    p_warehouse_id UUID,
    p_namespace_name VARCHAR,
    p_table_name VARCHAR,
    p_principal_type VARCHAR,
    p_principal_id VARCHAR
)
RETURNS TEXT AS $$
DECLARE
    combined_expression TEXT := '';
    policy_record RECORD;
    first_policy BOOLEAN := true;
BEGIN
    -- Get all active policies for this principal, ordered by priority
    FOR policy_record IN
        SELECT 
            policy_expression,
            policy_type
        FROM active_row_policies rp
        WHERE rp.warehouse_id = p_warehouse_id
          AND rp.namespace_name = p_namespace_name
          AND rp.table_name = p_table_name
          AND rp.principal_type = p_principal_type
          AND rp.principal_id = p_principal_id
          AND rp.is_currently_valid = true
        ORDER BY rp.priority DESC
    LOOP
        IF policy_record.policy_type = 'deny' THEN
            -- Deny policies create NOT conditions
            IF first_policy THEN
                combined_expression := 'NOT (' || policy_record.policy_expression || ')';
                first_policy := false;
            ELSE
                combined_expression := combined_expression || ' AND NOT (' || policy_record.policy_expression || ')';
            END IF;
        ELSIF policy_record.policy_type = 'filter' OR policy_record.policy_type = 'allow' THEN
            -- Filter and allow policies create AND conditions
            IF first_policy THEN
                combined_expression := '(' || policy_record.policy_expression || ')';
                first_policy := false;
            ELSE
                combined_expression := combined_expression || ' AND (' || policy_record.policy_expression || ')';
            END IF;
        END IF;
    END LOOP;
    
    -- If no policies found, return NULL (no restrictions)
    IF combined_expression = '' THEN
        RETURN NULL;
    END IF;
    
    RETURN combined_expression;
END;
$$ LANGUAGE plpgsql;

-- Comments for documentation
COMMENT ON VIEW active_column_permissions IS 'View showing all currently active column permissions with warehouse and user details';
COMMENT ON VIEW active_row_policies IS 'View showing all currently active row policies with warehouse and user details, ordered by priority';
COMMENT ON FUNCTION get_column_permissions IS 'Function to retrieve column permissions for a specific principal';
COMMENT ON VIEW get_row_policies IS 'View to retrieve row policies for a specific principal';
COMMENT ON FUNCTION has_column_permission IS 'Function to check if a principal has a specific column permission';
COMMENT ON FUNCTION get_combined_row_policy IS 'Function to get combined row policy expression for a principal';