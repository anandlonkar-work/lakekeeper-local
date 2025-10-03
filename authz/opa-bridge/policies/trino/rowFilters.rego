package trino

import data.trino
import data.configuration
import rego.v1

# Row filtering for fine-grained access control
# This endpoint is called by Trino when opa.policy.row-filters-uri is configured
# It queries Lakekeeper's PostgreSQL database for row filters instead of hardcoded rules

# Extract user and table information
user_id := input.context.identity.user
table_resource := input.action.resource.table

# Get warehouse name from catalog mapping (configured in configuration.rego)
warehouse_name := data.configuration.catalog_to_warehouse[table_resource.catalogName]

# Fetch row filters from Lakekeeper's PostgreSQL database
get_row_filters(user_id, warehouse, namespace, table) := filters if {
    # Construct URL for Lakekeeper's internal OPA API
    url := sprintf("http://lakekeeper:8181/internal/opa/v1/row-filters?user_id=%s&warehouse=%s&namespace=%s&table=%s", 
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
    
    # Extract row_filters from response
    filters := response.body.row_filters
}

# Apply row filtering based on database policies
rowFilters contains {"expression": filter.expression} if {
    # Only proceed if we have a warehouse mapping for this catalog
    warehouse_name
    
    # Fetch filters from database
    filters := get_row_filters(
        user_id,
        warehouse_name,
        table_resource.schemaName,
        table_resource.tableName
    )
    
    # Iterate through all filters and apply them
    # Filters are already sorted by priority (descending) in the database query
    filter := filters[_]
}

# Fallback: If Lakekeeper is unreachable or returns error, apply safe defaults
# Empty rowFilters means no restrictions (allow all rows)
default rowFilters := set()

# Debug logging
debug_info := {
    "user_id": user_id,
    "warehouse": warehouse_name,
    "catalog": table_resource.catalogName,
    "schema": table_resource.schemaName,
    "table": table_resource.tableName,
    "filters_applied": count(rowFilters),
    "lakekeeper_url": sprintf("http://lakekeeper:8181/internal/opa/v1/row-filters?user_id=%s&warehouse=%s&namespace=%s&table=%s", 
                              [user_id, warehouse_name, table_resource.schemaName, table_resource.tableName])
}