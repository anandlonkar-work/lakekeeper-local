package trino

import data.trino
import data.configuration
import future.keywords.if
import future.keywords.in
import future.keywords.contains

# Row filtering for fine-grained access control
# This endpoint is called by Trino when opa.policy.row-filters-uri is configured

# Extract user information
user_id := input.context.identity.user
username := get_username(user_id)

# Get username from user_id (UUID mapping from OPA logs)
get_username(user_id) := "peter" if {
    user_id == "cfb55bf6-fcbb-4a1e-bfec-30c6649b52f8"  # Peter's actual UUID from logs
}

get_username(user_id) := "anna" if {
    user_id == "d223d88c-85b6-4859-b5c5-27f3825e47f6"  # Anna's UUID from previous logs
}

# Default to treating unknown users as restricted
get_username(user_id) := "unknown" if {
    user_id != "cfb55bf6-fcbb-4a1e-bfec-30c6649b52f8"
    user_id != "d223d88c-85b6-4859-b5c5-27f3825e47f6"
}

# Row filtering rules
table_resource := input.action.resource.table

# Filter rows for Anna (and unknown users) - only show Public and Internal classifications
# and exclude Executive department
rowFilters contains {"expression": "classification IN ('Public', 'Internal')"} if {
    username in ["anna", "unknown"]
    table_resource.catalogName == "lakekeeper"
    table_resource.schemaName == "fgac_test"
    table_resource.tableName == "employees"
}

rowFilters contains {"expression": "department != 'Executive'"} if {
    username in ["anna", "unknown"]
    table_resource.catalogName == "lakekeeper"
    table_resource.schemaName == "fgac_test"
    table_resource.tableName == "employees"
}

# Additional row filter: Anna can only see employees from her own department
# (This assumes Anna is in 'Engineering' department)
rowFilters contains {"expression": "department = 'Engineering'"} if {
    username in ["anna"]
    table_resource.catalogName == "lakekeeper"
    table_resource.schemaName == "fgac_test"
    table_resource.tableName == "employees"
}

# Peter (admin) gets no row filters - sees all data
# When no rowFilters are returned, Trino shows all rows

# Debug logging
debug_info := {
    "user_id": user_id,
    "username": username,
    "catalog": table_resource.catalogName,
    "schema": table_resource.schemaName,
    "table": table_resource.tableName,
    "filters_applied": count(rowFilters)
}