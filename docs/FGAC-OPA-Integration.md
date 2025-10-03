# FGAC-OPA Integration for Lakekeeper

This document describes the complete Fine-Grained Access Control (FGAC) integration with Open Policy Agent (OPA) for Lakekeeper, providing a comprehensive UI-driven approach to managing column-level masking and row-level filtering policies.

## Overview

The FGAC-OPA integration bridges Lakekeeper's database-driven permission system with OPA's policy evaluation engine, enabling:

- **UI-Driven Policy Configuration**: Configure column permissions and row policies through an intuitive web interface
- **Automatic Policy Generation**: Generate OPA policies (columnMask.rego, rowFilters.rego, allow_column.rego) from UI configuration
- **Real-Time Policy Deployment**: Deploy policies to OPA with validation and testing
- **Comprehensive Audit Trail**: Track all permission changes and policy deployments

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   FGAC UI       │    │  Lakekeeper      │    │      OPA       │
│   (Frontend)    │◄──►│   (Backend)      │◄──►│   (Policies)    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         │              ┌────────▼────────┐             │
         │              │   PostgreSQL    │             │
         │              │   (FGAC Data)   │             │
         │              └─────────────────┘             │
         │                                              │
         └──────────────────────────────────────────────┘
                         Trino Integration
```

## Components

### 1. Database Schema Extensions

**File**: `migrations/20250930100001_fgac_ui_extensions.sql`

Extended the existing FGAC database schema with:
- Enhanced `column_permissions` table with masking capabilities
- `fgac_policy_templates` for reusable policy templates
- `fgac_audit_log` for comprehensive audit logging
- Performance-optimized views for UI operations

### 2. Rust Data Models

**File**: `src/service/fgac_models.rs`

Comprehensive data structures including:
- `ExtendedColumnPermission` - Column-level permissions with masking
- `ColumnPermissionMatrix` - UI matrix representation
- `ExtendedRowPolicy` - Row-level security policies
- `FgacPolicyTemplate` - Reusable policy templates
- Validation and serialization types

### 3. Database Service Layer

**File**: `src/implementations/postgres/fgac_service.rs`

Database operations for FGAC including:
- Matrix queries for UI display
- CRUD operations for permissions and policies
- Bulk operations and validation
- Audit logging and performance optimization

### 4. OPA Policy Generator

**File**: `src/service/opa_fgac_generator.rs`

Generates OPA policies from UI configuration:
- **columnMask.rego**: Column masking with SHA256, partial masking, NULL, custom expressions
- **rowFilters.rego**: Row-level filtering with SQL WHERE clauses
- **allow_column.rego**: Column access control for SELECT/INSERT operations
- User/role/group mapping and identity integration

### 5. OPA Integration Service

**File**: `src/service/opa_integration_service.rs`

Bridges FGAC database with OPA:
- Policy generation and validation
- Deployment and synchronization
- Status monitoring and health checks
- Integration with identity providers

### 6. REST API Endpoints

**File**: `src/api/management/v1/opa_handlers.rs`

HTTP API for OPA integration:
- `POST /api/v1/opa/policies/table/{warehouse_id}/{namespace}/{table}/generate`
- `GET /api/v1/opa/policies/table/{warehouse_id}/{namespace}/{table}/status`
- `POST /api/v1/opa/policies/deploy-all`
- `GET /api/v1/opa/deployment/status`

### 7. Interactive UI Components

**Files**: 
- `ui/fgac_ui.html` - Main FGAC management interface
- `ui/fgac-matrix.js` - Interactive permission matrix
- `examples/fgac-opa-integration-demo.html` - Complete demo

Features:
- Responsive permission matrix
- Real-time policy generation
- Bulk operations and templates
- Audit log and status monitoring

### 8. CLI Management Tools

**File**: `src/cli/opa_commands.rs`

Command-line interface for:
- `lakekeeper opa generate-table` - Generate policies for specific table
- `lakekeeper opa generate-all` - Generate policies for all tables
- `lakekeeper opa deploy` - Deploy policies to OPA
- `lakekeeper opa validate` - Validate FGAC configuration
- `lakekeeper opa status` - Show policy status

## Usage Examples

### 1. Configure Column Permissions via UI

1. Navigate to the FGAC UI at `http://localhost:8080/fgac`
2. Select a table from the dropdown
3. Use the permission matrix to set column permissions:
   - **Allow**: Full access to column data
   - **Mask**: Apply masking (hash, partial, null, custom)
   - **Block**: Deny all access to column
4. Assign permissions to users, roles, or groups

### 2. Configure Row Policies

1. In the Row Policies section, click "Add Policy"
2. Enter policy details:
   - **Name**: "Department Filter"
   - **Expression**: `department = get_user_department()`
   - **Description**: "Restrict rows to user's department"
3. Assign the policy to specific principals

### 3. Generate and Deploy OPA Policies

```bash
# Generate policies for a specific table
lakekeeper opa generate-table \
  --warehouse-id warehouse1 \
  --namespace sales \
  --table customers \
  --deploy

# Generate and deploy all policies
lakekeeper opa generate-all --deploy

# Validate configuration
lakekeeper opa validate --verbose

# Check deployment status
lakekeeper opa status --verbose
```

### 4. API Integration

```bash
# Generate policies via API
curl -X POST "http://localhost:8080/api/v1/opa/policies/table/warehouse1/sales/customers/generate?deploy=true"

# Check policy status
curl "http://localhost:8080/api/v1/opa/policies/table/warehouse1/sales/customers/status"

# Validate policies
curl "http://localhost:8080/api/v1/opa/policies/table/warehouse1/sales/customers/validate"
```

## Generated OPA Policies

### Column Masking Policy (columnMask.rego)

```rego
package trino

# Column masking for sensitive data
columnMask := {"expression": "SHA256(CAST(column_value AS VARCHAR))"} if {
    username == "analyst"
    column_resource.catalogName == "warehouse1"
    column_resource.schemaName == "sales"
    column_resource.tableName == "customers"
    column_resource.columnName == "email"
}

columnMask := {"expression": "CONCAT(LEFT(column_value, 3), '***')"} if {
    user_has_role("junior_analyst")
    column_resource.columnName == "customer_name"
}
```

### Row Filtering Policy (rowFilters.rego)

```rego
package trino

# Department-based row filtering
rowFilters contains {"expression": "department = get_user_department()"} if {
    table_resource.catalogName == "warehouse1"
    table_resource.schemaName == "hr"
    table_resource.tableName == "employees"
}

# Region-based filtering
rowFilters contains {"expression": "region IN (get_user_regions())"} if {
    table_resource.catalogName == "warehouse1"
    table_resource.schemaName == "sales"
    table_resource.tableName == "customers"
}
```

### Column Access Control (allow_column.rego)

```rego
package trino

# Allow SELECT operations with column permissions
allow if {
    input.action.operation == "SelectFromColumns"
    catalog := input.action.resource.table.catalogName
    schema := input.action.resource.table.schemaName
    table := input.action.resource.table.tableName
    column := input.action.resource.columns[_]
    
    has_column_access(catalog, schema, table, column, "read_data")
}
```

## Integration with Trino

Configure Trino to use the generated OPA policies:

**trino-coordinator/etc/catalog/lakehouse.properties**:
```properties
# OPA integration
opa.policy.uri=http://localhost:8181/v1/data/trino/allow
opa.policy.column-masking-uri=http://localhost:8181/v1/data/trino/columnMask
opa.policy.row-filters-uri=http://localhost:8181/v1/data/trino/rowFilters
```

## Identity Provider Integration

The system supports integration with various identity providers:

### Keycloak Integration
```yaml
identity:
  provider: "keycloak"
  keycloak:
    server_url: "http://localhost:8080/auth"
    realm: "lakekeeper"
    client_id: "trino-client"
```

### User Mapping Functions
```rego
# Identity functions in OPA policies
user_has_role(role) if {
    roles := input.context.identity.groups[_]
    role in roles
}

get_user_department() := dept if {
    dept := input.context.identity.department
}
```

## Monitoring and Observability

### Health Checks
- OPA connectivity status
- Policy validation results
- Deployment success/failure tracking

### Metrics
- Policy generation time
- Number of active policies
- Permission change frequency
- Policy evaluation performance

### Audit Logging
- All permission changes
- Policy generation and deployment
- User access attempts
- Configuration modifications

## Security Considerations

### Policy Validation
- SQL injection prevention in row policies
- Malicious expression detection
- Permission conflict resolution
- Privilege escalation prevention

### Access Control
- API authentication and authorization
- UI session management
- Audit trail integrity
- Secure policy storage

## Performance Optimization

### Database Optimization
- Indexed permission queries
- Materialized views for UI
- Connection pooling
- Query result caching

### OPA Integration
- Policy bundle optimization
- Evaluation result caching
- Incremental policy updates
- Batch operations

## Testing

### Unit Tests
```bash
cargo test fgac_models
cargo test opa_integration
cargo test policy_generation
```

### Integration Tests
```bash
# Test OPA policy generation
cargo test test_generate_column_mask_policy

# Test policy deployment
cargo test test_deploy_policies

# Test API endpoints
cargo test test_opa_handlers
```

### End-to-End Testing
1. Configure FGAC permissions via UI
2. Generate OPA policies
3. Deploy to OPA server
4. Execute Trino queries
5. Verify column masking and row filtering

## Troubleshooting

### Common Issues

**Policy Generation Fails**
```bash
# Check FGAC configuration
lakekeeper opa validate --warehouse-id warehouse1 --verbose

# Check database connectivity
lakekeeper opa status
```

**OPA Deployment Issues**
```bash
# Verify OPA server connectivity
curl http://localhost:8181/health

# Check policy syntax
lakekeeper opa validate --verbose
```

**Permission Matrix Not Loading**
- Check database connection
- Verify table exists in metadata
- Check API endpoint status

### Debug Mode
Enable debug logging in configuration:
```yaml
logging:
  level: "debug"
  audit:
    enabled: true
    log_all_operations: true
```

## Configuration

See `config/fgac-opa-integration.yaml` for complete configuration options including:
- Database connection settings
- OPA server configuration
- Identity provider integration
- UI customization options
- Performance tuning parameters

## Contributing

1. Follow Rust coding standards
2. Add tests for new functionality
3. Update documentation
4. Validate OPA policy generation
5. Test UI components thoroughly

## License

This integration is part of the Lakekeeper project and follows the same licensing terms.