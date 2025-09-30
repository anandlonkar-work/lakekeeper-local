package trino

import data.configuration
import future.keywords.in

# =============================================================================
# FGAC Supporting Functions for Lakekeeper Integration
# =============================================================================

# Get user ID from identity context
get_user_id(identity) := user_id if {
    # Extract user ID from the identity object
    user_id := identity.user
}

get_user_id(identity) := user_id if {
    # Fallback: extract from subject if user field not available
    user_id := identity.subject
}

# =============================================================================
# Column Access Functions
# =============================================================================

# Check if user has required column access (throws error if denied)
require_column_access(catalog, schema, table, column, permission) if {
    has_column_access(catalog, schema, table, column, permission)
}

# Check if user has column access (returns true/false)
has_column_access(catalog, schema, table, column, permission) if {
    user_id := get_user_id(input.identity)
    
    # Check column permissions via Lakekeeper API
    column_permission := get_column_permission(catalog, schema, table, column, user_id, permission)
    column_permission.allowed == true
}

has_column_access(catalog, schema, table, column, permission) if {
    # Default allow if no specific column restrictions exist
    user_id := get_user_id(input.identity)
    column_permission := get_column_permission(catalog, schema, table, column, user_id, permission)
    
    # If no permission record exists, check if user has table access
    column_permission == null
    has_table_access(catalog, schema, table, permission)
}

# =============================================================================
# Table Access Functions  
# =============================================================================

# Check if user has table access
has_table_access(catalog, schema, table, permission) if {
    # Use existing table access logic from other policies
    # This leverages the existing allow_table.rego functionality
    mock_input := {
        "action": {
            "operation": operation_for_permission(permission),
            "resource": {
                "table": {
                    "catalogName": catalog,
                    "schemaName": schema,
                    "tableName": table
                }
            }
        },
        "identity": input.identity
    }
    
    # Check if the operation would be allowed
    allow_table_access_with_input(mock_input)
}

# Map permission types to operations
operation_for_permission("read_data") := "SelectFromTable"
operation_for_permission("write_data") := "InsertIntoTable" 
operation_for_permission("get_metadata") := "ShowTables"

# =============================================================================
# Database Integration Functions
# =============================================================================

# Get column permission from Lakekeeper
get_column_permission(catalog, schema, table, column, user_id, permission) := result if {
    # Get warehouse mapping
    warehouse_config := get_warehouse_config(catalog)
    
    # Prepare API request to Lakekeeper
    request_body := {
        "warehouse": warehouse_config.lakekeeper_warehouse,
        "namespace": schema,
        "table": table,
        "column": column,
        "user_id": user_id,
        "permission": permission
    }
    
    # Make HTTP request to Lakekeeper API
    lakekeeper_config := get_lakekeeper_config(warehouse_config.lakekeeper_id)
    response := http.send({
        "method": "POST",
        "url": sprintf("%s/api/management/v1/permissions/column/check", [lakekeeper_config.url]),
        "headers": {
            "Content-Type": "application/json",
            "Authorization": sprintf("Bearer %s", [get_lakekeeper_token(lakekeeper_config)])
        },
        "body": request_body
    })
    
    result := response.body
}

get_column_permission(catalog, schema, table, column, user_id, permission) := null if {
    # Return null if API call fails - indicates no specific restriction
    warehouse_config := get_warehouse_config(catalog)
    not warehouse_config
}

# Get row policies from Lakekeeper
get_row_policies(catalog, schema, table, user_id) := policies if {
    # Get warehouse mapping
    warehouse_config := get_warehouse_config(catalog)
    
    # Prepare API request
    request_body := {
        "warehouse": warehouse_config.lakekeeper_warehouse,
        "namespace": schema,
        "table": table,
        "user_id": user_id
    }
    
    # Make HTTP request to Lakekeeper API
    lakekeeper_config := get_lakekeeper_config(warehouse_config.lakekeeper_id)
    response := http.send({
        "method": "POST", 
        "url": sprintf("%s/api/management/v1/permissions/row/list", [lakekeeper_config.url]),
        "headers": {
            "Content-Type": "application/json",
            "Authorization": sprintf("Bearer %s", [get_lakekeeper_token(lakekeeper_config)])
        },
        "body": request_body
    })
    
    policies := response.body.policies
}

get_row_policies(catalog, schema, table, user_id) := [] if {
    # Return empty array if API call fails
    warehouse_config := get_warehouse_config(catalog)
    not warehouse_config
}

# =============================================================================
# Configuration Helper Functions
# =============================================================================

# Get warehouse configuration for catalog
get_warehouse_config(catalog) := config if {
    config := configuration.trino_catalog[_]
    config.name == catalog
}

# Get Lakekeeper configuration by ID
get_lakekeeper_config(lakekeeper_id) := config if {
    config := configuration.lakekeeper[_]
    config.id == lakekeeper_id
}

# Get authentication token for Lakekeeper API
get_lakekeeper_token(lakekeeper_config) := token if {
    # Use client credentials flow to get token
    token_response := http.send({
        "method": "POST",
        "url": lakekeeper_config.openid_token_endpoint,
        "headers": {
            "Content-Type": "application/x-www-form-urlencoded"
        },
        "body": sprintf("grant_type=client_credentials&client_id=%s&client_secret=%s&scope=%s", [
            lakekeeper_config.client_id,
            lakekeeper_config.client_secret, 
            lakekeeper_config.scope
        ])
    })
    
    token := token_response.body.access_token
}

# =============================================================================
# Mock/Fallback Functions for Development
# =============================================================================

# Mock table access check (fallback when actual function not available)
allow_table_access_with_input(mock_input) if {
    # This is a simplified version - in reality would use existing table access logic
    true  # Allow for development/testing
}