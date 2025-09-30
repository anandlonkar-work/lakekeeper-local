package trino

import data.trino
import data.configuration
import future.keywords.if
import future.keywords.in

# Column masking for fine-grained access control
# This endpoint is called by Trino when opa.policy.column-masking-uri is configured

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

# Column masking rules
column_resource := input.action.resource.column

# Don't apply column masking for admin users (Peter) - they need full access
# Only mask sensitive columns for Anna (and unknown users)
columnMask := {"expression": "NULL"} if {
    username in ["anna", "unknown"]
    username != "peter"  # Explicitly exclude Peter from masking
    column_resource.catalogName == "lakekeeper"
    column_resource.schemaName == "fgac_test"
    column_resource.tableName == "employees"
    column_resource.columnName in ["salary", "email", "phone"]
}

# Partially mask email for demonstration (show domain only)
columnMask := {"expression": "substring(email, position('@', email))"} if {
    username in ["anna", "unknown"]
    column_resource.catalogName == "lakekeeper"
    column_resource.schemaName == "fgac_test"
    column_resource.tableName == "employees"
    column_resource.columnName == "email_partial"  # Example of partial masking
}

# Allow full access for Peter (admin) - no mask needed
# When no columnMask is returned, Trino shows the column as-is

# Debug logging
debug_info := {
    "user_id": user_id,
    "username": username,
    "catalog": column_resource.catalogName,
    "schema": column_resource.schemaName,
    "table": column_resource.tableName,
    "column": column_resource.columnName
}