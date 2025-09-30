package trino

# =============================================================================
# Simple FGAC Demo Implementation
# =============================================================================
# This is a simplified implementation for demonstration purposes
# In production, this would integrate with Lakekeeper's actual FGAC APIs

# Simple column access rules for demo
# Peter (admin) can access everything, Anna (restricted) blocked from sensitive columns
demo_column_restrictions := {
    "fgac_test.employees": {
        "anna": ["salary", "email", "phone"],  # Anna blocked from these columns
        "peter": []  # Peter can access all columns (empty restrictions)
    }
}

# Simple row access rules for demo  
# Anna can only see Public/Internal classification and non-Executive departments
demo_row_restrictions := {
    "fgac_test.employees": {
        "anna": {
            "allowed_classifications": ["Public", "Internal"],
            "blocked_departments": ["Executive"]
        },
        "peter": {
            # Peter has no restrictions (admin)
        }
    }
}

# =============================================================================
# FGAC Functions (Simplified Demo Version)
# =============================================================================

# Get user ID from identity (handle both UUID and username)
get_user_id(identity) := user_id if {
    user_id := identity.user
}

get_user_id(identity) := user_id if {
    user_id := identity.subject  
}

# Extract username from various identity formats
get_username(identity) := username if {
    # Try to get preferred_username first (from JWT token)
    username := identity.preferred_username
}

get_username(identity) := username if {
    # Try username field
    username := identity.username
}

get_username(identity) := username if {
    # Fall back to user field if it looks like a username (not UUID)
    user_id := identity.user
    not regex.match("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", user_id)
    username := user_id
}

get_username(identity) := username if {
    # Map known UUIDs to usernames (temporary solution)
    user_id := identity.user
    uuid_to_username_map := {
        "d223d88c-85b6-4859-b5c5-27f3825e47f6": "anna",
        # Add more mappings as we discover them
    }
    username := uuid_to_username_map[user_id]
}

# Default to UUID if no username mapping available
get_username(identity) := user_id if {
    user_id := identity.user
    # No other username extraction worked
    not identity.preferred_username
    not identity.username
    # And it's a UUID format
    regex.match("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", user_id)
}

# Check column access (demo implementation)
has_column_access(catalog, schema, table, column, permission) if {
    username := get_username(input.identity)
    table_key := sprintf("%s.%s", [schema, table])
    
    # Debug logging - print identity info
    print("=== FGAC DEBUG ===")
    print("Identity object:", input.identity)
    print("Extracted username:", username)
    print("Table key:", table_key)
    print("Column:", column)
    
    # Get user's column restrictions for this table
    restrictions := demo_column_restrictions[table_key][username]
    print("Restrictions for user:", restrictions)
    
    # Allow access if column is not in restrictions list
    not column in restrictions
}

has_column_access(catalog, schema, table, column, permission) if {
    username := get_username(input.identity)
    table_key := sprintf("%s.%s", [schema, table])
    
    # Allow access if no restrictions defined for this user/table combo
    not demo_column_restrictions[table_key][username]
}

# Require column access (throws error if denied)
require_column_access(catalog, schema, table, column, permission) if {
    has_column_access(catalog, schema, table, column, permission)
}

# Check table access (simplified - allows basic access)
has_table_access(catalog, schema, table, permission) if {
    # For demo purposes, allow table access if user can authenticate
    # In real implementation, this would check table-level permissions
    input.identity.user
}

# =============================================================================
# Column Filtering Logic
# =============================================================================

# Filter columns based on access permissions
filter_accessible_columns(catalog, schema, table, requested_columns) := accessible if {
    username := get_username(input.identity)
    table_key := sprintf("%s.%s", [schema, table])
    restrictions := demo_column_restrictions[table_key][username]
    
    # Return columns that are not restricted
    accessible := [col | 
        col := requested_columns[_]
        not col in restrictions
    ]
}

filter_accessible_columns(catalog, schema, table, requested_columns) := accessible if {
    username := get_username(input.identity)
    table_key := sprintf("%s.%s", [schema, table])
    
    # If no restrictions exist, return all requested columns
    not demo_column_restrictions[table_key][username]
    accessible := requested_columns
}

# =============================================================================
# Row Filtering Logic  
# =============================================================================

# Check if user can access specific row based on row content
allow_row_access(catalog, schema, table, row_data) if {
    username := get_username(input.identity)
    table_key := sprintf("%s.%s", [schema, table])
    restrictions := demo_row_restrictions[table_key][username]
    
    # Check classification restrictions
    allowed_classifications := restrictions.allowed_classifications
    row_data.classification in allowed_classifications
    
    # Check department restrictions  
    blocked_departments := restrictions.blocked_departments
    not row_data.department in blocked_departments
}

allow_row_access(catalog, schema, table, row_data) if {
    username := get_username(input.identity)
    table_key := sprintf("%s.%s", [schema, table])
    
    # Allow access if no row restrictions defined
    not demo_row_restrictions[table_key][username]
}

# Generate SQL WHERE clause for row filtering
generate_row_filter(catalog, schema, table) := filter_clause if {
    username := get_username(input.identity)
    table_key := sprintf("%s.%s", [schema, table])
    restrictions := demo_row_restrictions[table_key][username]
    
    # Build WHERE clause based on restrictions
    classification_filter := sprintf("classification IN (%s)", [
        concat(", ", [sprintf("'%s'", [c]) | c := restrictions.allowed_classifications[_]])
    ])
    
    department_filter := sprintf("department NOT IN (%s)", [
        concat(", ", [sprintf("'%s'", [d]) | d := restrictions.blocked_departments[_]])
    ])
    
    filter_clause := sprintf("(%s) AND (%s)", [classification_filter, department_filter])
}

generate_row_filter(catalog, schema, table) := "1=1" if {
    username := get_username(input.identity)
    table_key := sprintf("%s.%s", [schema, table])
    
    # No filtering needed if no restrictions
    not demo_row_restrictions[table_key][username]
}

# =============================================================================
# Debug/Logging Functions
# =============================================================================

# Log access attempts for debugging
log_access_attempt(operation, catalog, schema, table, user_id) := logged if {
    logged := {
        "timestamp": time.now_ns(),
        "operation": operation,
        "resource": sprintf("%s.%s.%s", [catalog, schema, table]),
        "user": user_id,
        "allowed": true
    }
}