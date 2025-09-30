package trino

import data.trino
import data.configuration

# Row-level access control (simplified demo version)
allow if {
    input.action.operation in ["SelectFromTable", "FilterTable", "ExecuteQuery"]
    catalog := input.action.resource.table.catalogName
    schema := input.action.resource.table.schemaName
    table := input.action.resource.table.tableName
    
    # For demo purposes, allow row access but filtering will be applied
    # In production, this would check row-level policies from database
    has_table_access(catalog, schema, table, "read_data")
}

# Row filtering is now handled by the dedicated rowFilters.rego policy
# This file focuses on basic allow/deny authorization

# Determine if user has row access
has_row_access(catalog, schema, table, user_id) if {
    # Check if user has direct table access without restrictions
    has_table_access(catalog, schema, table, "read_data")
    
    # Get applicable row policies for this user
    policies := get_row_policies(catalog, schema, table, user_id)
    
    # If no restrictive policies exist, allow access
    count(policies) == 0
}

has_row_access(catalog, schema, table, user_id) if {
    # User has table access and at least one permissive policy
    has_table_access(catalog, schema, table, "read_data")
    
    policies := get_row_policies(catalog, schema, table, user_id)
    policy := policies[_]
    policy.policy_type == "filter"
}

# Get row policies applicable to user
get_row_policies(catalog, schema, table, user_id) := policies if {
    # This would query lakekeeper for row policies
    # For now, return empty - actual implementation would call lakekeeper API
    policies := []
}

# Generate row filter conditions
row_filter_conditions(catalog, schema, table) := conditions if {
    user_id := get_user_id(input.identity)
    policies := get_row_policies(catalog, schema, table, user_id)
    
    # Combine all policy conditions
    permissive_conditions := [policy.condition | 
        policy := policies[_]
        policy.policy_type == "permissive"
    ]
    
    restrictive_conditions := [policy.condition |
        policy := policies[_]
        policy.policy_type == "restrictive"
    ]
    
    # Combine conditions (OR for permissive, AND for restrictive)
    conditions := {
        "permissive": permissive_conditions,
        "restrictive": restrictive_conditions
    }
}

# Transform query to include row-level filters
apply_row_filters(query, catalog, schema, table) := filtered_query if {
    conditions := row_filter_conditions(catalog, schema, table)
    
    # Build WHERE clause from conditions
    where_clause := build_where_clause(conditions)
    
    # Apply filters to query (simplified - actual implementation would parse SQL)
    filtered_query := sprintf("%s WHERE %s", [query, where_clause])
}

# Build WHERE clause from policy conditions
build_where_clause(conditions) := clause if {
    permissive := conditions.permissive
    restrictive := conditions.restrictive
    
    # OR together permissive conditions
    permissive_clause := join_conditions(permissive, "OR")
    
    # AND together restrictive conditions  
    restrictive_clause := join_conditions(restrictive, "AND")
    
    # Combine both types
    clause := combine_clauses(permissive_clause, restrictive_clause)
}

# Helper to join conditions with operator
join_conditions(conditions, operator) := result if {
    count(conditions) == 0
    result := ""
}

join_conditions(conditions, operator) := result if {
    count(conditions) == 1
    result := conditions[0]
}

join_conditions(conditions, operator) := result if {
    count(conditions) > 1
    joined := sprintf("(%s)", [concat(sprintf(" %s ", [operator]), conditions)])
    result := joined
}

# Combine permissive and restrictive clauses
combine_clauses(permissive, restrictive) := result if {
    permissive == ""
    restrictive == ""
    result := "TRUE"
}

combine_clauses(permissive, restrictive) := result if {
    permissive != ""
    restrictive == ""
    result := permissive
}

combine_clauses(permissive, restrictive) := result if {
    permissive == ""
    restrictive != ""
    result := restrictive
}

combine_clauses(permissive, restrictive) := result if {
    permissive != ""
    restrictive != ""
    result := sprintf("(%s) AND (%s)", [permissive, restrictive])
}