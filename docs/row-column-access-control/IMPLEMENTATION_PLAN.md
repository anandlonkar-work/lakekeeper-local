# Implementation Plan: Row and Column Level Access Control

## Architecture Overview

### Permission Hierarchy
```
Server
└── Project  
    └── Warehouse
        └── Namespace
            └── Table
                ├── Column 1 (fine-grained permissions)
                ├── Column 2 (fine-grained permissions)
                └── Row Policies (filter-based permissions)
```

### Key Components

1. **OpenFGA Schema Extensions**: New types for `lakekeeper_column` and `lakekeeper_row_policy`
2. **Rust Type System**: `ColumnId`, `RowPolicyId`, and related enums/structs
3. **Authorization Logic**: Extended `Authorizer` trait with column/row methods
4. **REST API**: New endpoints for managing fine-grained permissions
5. **OPA Bridge**: Query rewriting and filtering logic
6. **Database Schema**: Storage for column and row policy metadata

## Detailed Implementation Steps

### Phase 1: Schema and Core Types

#### 1.1 OpenFGA Schema (v4.2)

**Files to create:**
- `authz/openfga/v4.2/README.md`
- `authz/openfga/v4.2/components/lakekeeper_column.fga`
- `authz/openfga/v4.2/components/lakekeeper_row_policy.fga`
- `authz/openfga/v4.2/components/lakekeeper_table.fga` (updated)

**Schema Design:**
```fga
type lakekeeper_column
  relations
    define parent: [lakekeeper_table]
    define ownership: [user, role#assignee]
    define select: [user, role#assignee] or ownership or select from parent
    define modify: [user, role#assignee] or ownership or modify from parent
    define describe: [user, role#assignee] or ownership or select or describe from parent
    # ... additional relations
```

#### 1.2 Rust Types

**Files to modify:**
- `crates/lakekeeper/src/service/mod.rs`
- `crates/lakekeeper/src/service/authz/mod.rs`

**New Types:**
```rust
pub struct ColumnId(uuid::Uuid);
pub struct RowPolicyId(uuid::Uuid);
pub enum CatalogColumnAction { CanReadData, CanWriteData, CanGetMetadata }
pub enum CatalogRowPolicyAction { CanReadData, CanWriteData, CanEvaluatePolicy }
```

#### 1.3 Catalog Trait Extensions

**Files to modify:**
- `crates/lakekeeper/src/service/catalog.rs`

**New Methods:**
```rust
async fn create_column_permission(&self, ...) -> Result<ColumnPermission>;
async fn list_column_permissions(&self, table_id: TableId) -> Result<Vec<ColumnPermission>>;
async fn create_row_policy(&self, ...) -> Result<RowPolicy>;
async fn list_row_policies(&self, table_id: TableId) -> Result<Vec<RowPolicy>>;
```

#### 1.4 Database Schema

**Files to create:**
- `crates/lakekeeper/migrations/20250929000001_add_column_permissions.sql`
- `crates/lakekeeper/migrations/20250929000002_add_row_policies.sql`

### Phase 2: Authorization Logic

#### 2.1 Authorizer Trait Extensions

**Files to modify:**
- `crates/lakekeeper/src/service/authz/mod.rs`

**New Methods:**
```rust
async fn is_allowed_column_action(&self, metadata: &RequestMetadata, column_id: ColumnId, action: CatalogColumnAction) -> Result<MustUse<bool>>;
async fn get_applicable_row_policies(&self, metadata: &RequestMetadata, table_id: TableId) -> Result<Vec<RowPolicy>>;
```

#### 2.2 OpenFGA Implementation

**Files to modify:**
- `crates/lakekeeper/src/service/authz/implementations/openfga/mod.rs`
- `crates/lakekeeper/src/service/authz/implementations/openfga/api.rs`

### Phase 3: API Endpoints

#### 3.1 Column Permission Endpoints

**New Endpoints:**
- `POST /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/columns`
- `GET /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/columns`
- `POST /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/column/{column_id}/access`

#### 3.2 Row Policy Endpoints

**New Endpoints:**
- `POST /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/row-policies`  
- `GET /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/row-policies`
- `POST /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/row-policy/{policy_id}/access`

### Phase 4: OPA Bridge Integration

#### 4.1 Column Access Policies

**Files to create:**
- `authz/opa-bridge/policies/trino/allow_column.rego`
- `authz/opa-bridge/policies/lakekeeper/column_check.rego`

#### 4.2 Row Filtering Policies

**Files to create:**
- `authz/opa-bridge/policies/trino/row_filtering.rego`
- `authz/opa-bridge/policies/lakekeeper/row_policy_check.rego`

#### 4.3 Query Rewriting Logic

**Capabilities:**
- Automatic column masking for unauthorized columns
- Row filtering based on policy expressions
- SQL query transformation for security

### Phase 5: Testing and Validation

#### 5.1 Build Process
- Update Dockerfile with new dependencies
- Build new lakekeeper image
- Update docker-compose configurations

#### 5.2 Integration Testing
- Test column-level permissions with Trino
- Test row-level filtering with sample data
- Verify inheritance from table-level permissions
- Performance testing for query rewriting

## Security Considerations

1. **SQL Injection Prevention**: Validate and sanitize row policy filter expressions
2. **Performance Impact**: Efficient query rewriting to minimize overhead  
3. **Audit Trail**: Log all column and row policy grants/revokes
4. **Backward Compatibility**: Ensure existing table-level permissions continue to work

## Error Handling

1. **Invalid Column Names**: Validate against actual table schema
2. **Invalid Filter Expressions**: Parse and validate SQL expressions
3. **Permission Conflicts**: Clear resolution order for overlapping policies
4. **Performance Degradation**: Fallback mechanisms for complex policies

---

This plan provides a comprehensive roadmap for implementing row and column level access control while maintaining the existing lakekeeper architecture and ensuring security, performance, and usability.