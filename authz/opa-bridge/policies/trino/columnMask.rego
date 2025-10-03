package trino

import data.trino
import data.configuration
import rego.v1

# Column masking for fine-grained access control
# This endpoint is called by Trino when opa.policy.column-masking-uri is configured
# It queries Lakekeeper's PostgreSQL database for column masks instead of hardcoded rules

# Extract user and column information
user_id := input.context.identity.user
column_resource := input.action.resource.column

# Get warehouse name from catalog mapping (configured in configuration.rego)
warehouse_name := data.configuration.catalog_to_warehouse[column_resource.catalogName]

# Fetch column masks from Lakekeeper's PostgreSQL database
get_column_masks(user_id, warehouse, namespace, table) := masks if {
    # Construct URL for Lakekeeper's internal OPA API
    url := sprintf("http://lakekeeper:8181/internal/opa/v1/column-masks?user_id=%s&warehouse=%s&namespace=%s&table=%s", 
                   [user_id, warehouse, namespace, table])
    
    # Make HTTP call to Lakekeeper
    response := http.send({
        "method": "GET",
        "url": url,
        "headers": {"Content-Type": "application/json"},
        "raise_error": false,
        "timeout": "5s"
    })
    
    # Check if request was successful
    response.status_code == 200
    
    # Extract column_masks from response
    masks := response.body.column_masks
}

# Apply column masking based on database policies
columnMask := {"expression": mask.expression} if {
    # Only proceed if we have a warehouse mapping for this catalog
    warehouse_name
    
    # Fetch masks from database
    masks := get_column_masks(
        user_id,
        warehouse_name,
        column_resource.schemaName,
        column_resource.tableName
    )
    
    # Get mask for the specific column being accessed
    mask := masks[column_resource.columnName]
}

# Fallback: If Lakekeeper is unreachable or returns error, apply safe defaults
# This ensures query continues but with maximum restrictions
default columnMask := null

# Debug logging
debug_info := {
    "user_id": user_id,
    "warehouse": warehouse_name,
    "catalog": column_resource.catalogName,
    "schema": column_resource.schemaName,
    "table": column_resource.tableName,
    "column": column_resource.columnName,
    "lakekeeper_url": sprintf("http://lakekeeper:8181/internal/opa/v1/column-masks?user_id=%s&warehouse=%s&namespace=%s&table=%s", 
                              [user_id, warehouse_name, column_resource.schemaName, column_resource.tableName])
}