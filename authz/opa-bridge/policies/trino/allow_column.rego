package trino

import data.trino
import data.configuration

# Column-level access control (simplified demo version)
allow if {
    input.action.operation in ["SelectFromColumns", "ShowColumns", "FilterColumns"]
    catalog := input.action.resource.table.catalogName
    schema := input.action.resource.table.schemaName
    table := input.action.resource.table.tableName
    
    # Check each requested column using demo FGAC
    column := input.action.resource.columns[_]
    has_column_access(catalog, schema, table, column, "read_data")
}

# Allow column access for INSERT/UPDATE operations
allow if {
    input.action.operation in ["InsertIntoTable", "UpdateTableColumns"]
    catalog := input.action.resource.table.catalogName
    schema := input.action.resource.table.schemaName
    table := input.action.resource.table.tableName
    
    # Check write access to columns
    column := input.action.resource.columns[_]
    has_column_access(catalog, schema, table, column, "write_data")
}

allow_column_modify if {
    input.action.operation in ["InsertIntoTable", "UpdateTableColumns", "AddColumn", "AlterColumn", "DropColumn"]
    catalog := input.action.resource.table.catalogName
    schema := input.action.resource.table.schemaName
    table := input.action.resource.table.tableName
    
    # Check if user can modify columns
    column := input.action.resource.columns[_]
    require_column_access(catalog, schema, table, column, "write_data")
}

allow_column_describe if {
    input.action.operation in ["ShowColumns", "FilterColumns"]
    catalog := input.action.resource.table.catalogName
    schema := input.action.resource.table.schemaName
    table := input.action.resource.table.tableName
    
    # Allow describing only accessible columns
    column := input.action.resource.columns[_]
    require_column_access(catalog, schema, table, column, "get_metadata")
}

# Filter columns based on permissions
filter_columns(catalog_name, schema_name, table_name) := filtered_columns if {
    all_columns := get_table_columns(catalog_name, schema_name, table_name)
    accessible_columns := [col | 
        col := all_columns[_]
        has_column_access(catalog_name, schema_name, table_name, col.name, "read_data")
    ]
    filtered_columns := accessible_columns
}

# Get all columns for a table (placeholder - would be replaced with actual table schema lookup)
get_table_columns(catalog_name, schema_name, table_name) := columns if {
    # This would interface with the table metadata to get column information
    # For now, return empty array - actual implementation would query lakekeeper
    columns := []
}