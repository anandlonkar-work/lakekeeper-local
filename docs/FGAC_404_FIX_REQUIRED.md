# FGAC Implementation Status and Fix Required

## Current Situation 🎯

**Good News**: The FGAC tab is visible in the UI! ✅

**Issue**: Getting "404 Not Found" error when loading FGAC data ❌

## Root Cause Analysis

### What Exists ✅
1. **Database Schema**: 4 migrations completed
   - `20250929170001_fgac_column_permissions.sql`
   - `20250929170002_fgac_row_policies.sql`
   - `20250929170003_fgac_helper_functions.sql`
   - `20250930100001_fgac_ui_extensions.sql`

2. **Backend API**: Implemented in Rust
   - File: `crates/lakekeeper/src/api/management/v1/fgac_api.rs`
   - Registered in router at line 1954 of `mod.rs`
   - Route: `/management/v1/warehouse/{warehouse_id}/table/{table_id}/fgac`

3. **UI Component**: Vue.js FGAC Manager
   - File: `lakekeeper-console/src/components/FgacManager.vue` (625 lines)
   - Integrated into table detail page with FGAC tab

4. **UI Proxy Handler**: Rust proxy in lakekeeper-bin
   - File: `crates/lakekeeper-bin/src/ui.rs`
   - Route: `/ui/api/fgac/{warehouse_id}/{namespace_table}`

### The Mismatch 🔴

**Backend API Expects**:
```
/management/v1/warehouse/{warehouse_id}/table/{table_id}/fgac
                                              ^^^^^^^^
                                              UUID (e.g., 123e4567-e89b-12d3-a456-426614174000)
```

**UI/Proxy is Sending**:
```
/ui/api/fgac/37ba6278-9f0b-11f0-bdfa-4f960c0758c9/finance.revenue
                                                   ^^^^^^^^^^^^^^^
                                                   namespace.table (names not UUIDs)
```

**Browser Error**:
```
GET http://localhost:8181/ui/api/fgac/37ba6278-9f0b-11f0-bdfa-4f960c0758c9/finance.revenue 404 (Not Found)
```

## The Problem

The proxy handler in `ui.rs` (line 159) forwards to:
```rust
"http://localhost:8181/management/v1/warehouse/{}/namespace/{}/table/{}/fgac/configuration"
```

But the actual backend route is:
```rust
"/warehouse/{warehouse_id}/table/{table_id}/fgac"
```

Two issues:
1. **Route pattern mismatch**: Backend uses `/warehouse/.../table/...` not `/warehouse/.../namespace/.../table/...`
2. **Parameter type mismatch**: Backend expects `table_id` (UUID) not `namespace.table` (names)

## Solutions

### Option 1: Update Proxy Handler (Recommended) ✅

Modify `crates/lakekeeper-bin/src/ui.rs` line 139-200:

**Current**:
```rust
pub(crate) async fn fgac_proxy_handler(
    axum::extract::Path((warehouse_id, namespace_table)): axum::extract::Path<(String, String)>,
    headers: HeaderMap,
) -> impl IntoResponse {
    // Parses namespace.table
    let (namespace, table) = ...;
    
    // Wrong URL format
    let backend_url = format!(
        "http://localhost:8181/management/v1/warehouse/{}/namespace/{}/table/{}/fgac/configuration",
        warehouse_id, namespace, table
    );
```

**Need**:
```rust
pub(crate) async fn fgac_proxy_handler(
    axum::extract::Path((warehouse_id, table_id)): axum::extract::Path<(String, String)>,
    headers: HeaderMap,
) -> impl IntoResponse {
    // Correct URL format matching backend route
    let backend_url = format!(
        "http://localhost:8181/management/v1/warehouse/{}/table/{}/fgac",
        warehouse_id, table_id
    );
```

**UI Change Required**:
The Vue.js component needs to pass `tableId` (UUID) instead of `namespace.table`:

```javascript
// Current (in FgacManager.vue)
const url = `/ui/api/fgac/${warehouseId}/${namespaceId}.${tableName}`;

// Should be
const url = `/ui/api/fgac/${warehouseId}/${tableId}`;
```

### Option 2: Add Backend Route with Namespace/Table Names

Add a new backend route that resolves namespace/table names to table_id:

```rust
// In crates/lakekeeper/src/api/management/mod.rs
.route(
    "/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/fgac/configuration",
    get(fgac_api::get_table_fgac_by_name),
)
```

Then implement lookup logic in `fgac_api.rs`:
```rust
pub async fn get_table_fgac_by_name<C: Catalog, A: Authorizer, S: SecretStore>(
    Path((warehouse_id, namespace, table_name)): Path<(WarehouseId, String, String)>,
    // ... look up table_id from namespace/table_name
    // ... call existing get_table_fgac()
) -> Result<Json<FgacTableResponse>, StatusCode> {
    // Implementation
}
```

## Recommendation

**Option 1** is simpler and cleaner:
1. UI already has `tableId` from the route params
2. No additional database lookups needed
3. Aligns with existing REST API patterns (use IDs not names)

## Implementation Steps

1. **Update Vue.js Component**:
   - File: `lakekeeper-console/src/components/FgacManager.vue`
   - Change API call from `${namespaceId}.${tableName}` to `${tableId}`

2. **Update Proxy Handler**:
   - File: `crates/lakekeeper-bin/src/ui.rs`
   - Change route parameter from `namespace_table` to `table_id`
   - Update backend URL format to match actual API route

3. **Rebuild and Test**:
   ```bash
   cd lakekeeper-console
   git add src/components/FgacManager.vue
   git commit -m "fix: Use tableId instead of namespace.table in FGAC API calls"
   git push origin feature/fgac-management-tab
   
   cd ../lakekeeper-local/examples/access-control-fgac
   docker-compose -f docker-compose-build.yaml build --no-cache lakekeeper
   docker-compose up -d --force-recreate lakekeeper
   ```

## Testing Plan

Once fixed:
1. Navigate to table detail page: http://localhost:8181/ui
2. Go to: Warehouses → demo → Namespaces → finance → Tables → products
3. Click FGAC tab
4. Should see mock data load:
   - Available columns list
   - Example column permission (ssn masked for data_analyst role)
   - Example row policies

## Next Steps After Fix

1. **Replace Mock Data**: Update `fgac_api.rs` to query actual database
2. **Implement POST/DELETE**: Add endpoints for creating/deleting permissions
3. **Add Validation**: Validate column names exist in table schema
4. **Test End-to-End**: Create permissions via UI, verify in database

---

**Status**: Ready to implement fix
**Estimated Time**: 30 minutes
**Risk**: Low (isolated changes, easy to rollback)
