# FGAC Integration Plan

## Current Status

### ✅ Completed
1. **API Proxy Endpoints Created** - Four REST API endpoints in `/crates/lakekeeper-bin/src/ui.rs`:
   - `GET /ui/api/fgac/{warehouse_id}/{table_id}` - Get FGAC configuration for a table
   - `GET /ui/api/warehouses` - List all warehouses
   - `GET /ui/api/schemas/{warehouse_id}` - List schemas in a warehouse
   - `GET /ui/api/tables/{warehouse_id}/{schema_name}` - List tables in a schema

2. **Cleaned Up Invalid Approach** - Removed server-side HTML rendering handler that was bypassing the Vue.js SPA

3. **Identified UI Repository** - Found the Vue.js console repository at:
   - Repository: https://github.com/lakekeeper/console
   - Current version used: `rev = "v0.10.1"`
   - Integrated as: `lakekeeper-console` crate dependency in `crates/lakekeeper-bin/Cargo.toml`

### 🎯 Next Steps

## Vue.js SPA Integration

The Lakekeeper UI is a Vue.js Single Page Application located in a **separate repository**. The source files are not in this repository - only the compiled static assets are embedded via the `lakekeeper-console` crate.

**UI Repository:** https://github.com/lakekeeper/console

### Development Workflow for UI Enhancements

Based on the Lakekeeper developer guide and build system:

1. **Clone the UI Repository**
   ```bash
   git clone https://github.com/lakekeeper/console.git lakekeeper-console
   cd lakekeeper-console
   git checkout v0.10.1  # Current version used by lakekeeper-local
   ```

2. **Work on the UI (in console repository)**
   - Find the table detail view component (likely shows Permissions, Tasks tabs)
   - Add a new "FGAC" tab alongside existing tabs
   - Create a Vue component for FGAC management
   - Test locally against the API endpoints

3. **Build and Publish UI Changes**
   - Build the Vue.js application
   - Create a new release/tag in the console repository
   - Update the git revision in `crates/lakekeeper-bin/Cargo.toml`

4. **Integrate UI into Lakekeeper**
   ```bash
   # Update the console dependency revision
   # In crates/lakekeeper-bin/Cargo.toml:
   # lakekeeper-console = { git = "https://github.com/lakekeeper/console", rev = "v0.10.2" }
   
   # Rebuild lakekeeper with the new UI
   docker compose -f examples/access-control-fgac/docker-compose.yaml \
     -f examples/access-control-fgac/docker-compose-build.yaml up -d --build
   ```

### What Needs to Happen:

1. **Clone and Explore the UI Repository** ✨
   - Repository: https://github.com/lakekeeper/console
   - Current version: v0.10.1
   - Need to understand the Vue.js project structure

2. **Add FGAC Tab to Vue.js Application**
   - Find the table detail view component (likely shows Permissions, Tasks tabs)
   - Add a new "FGAC" tab alongside existing tabs
   - Create a Vue component for FGAC management

3. **FGAC Vue Component Structure**
   ```
   TableDetailView.vue (or similar)
   ├── Permissions Tab
   ├── Tasks Tab
   └── FGAC Tab (NEW)
       ├── Column Permissions Section
       │   ├── Table showing column permissions
       │   └── Add/Edit/Delete controls
       └── Row Policies Section
           ├── Table showing row-level policies
           └── Add/Edit/Delete controls
   ```

4. **API Integration**
   The Vue component should call the proxy endpoints we created:
   ```typescript
   // Get FGAC config for current table
   const response = await fetch(`/ui/api/fgac/${warehouseId}/${tableId}`);
   const fgacData = await response.json();
   ```

5. **UI Considerations**
   - Follow existing Lakekeeper UI patterns (Vuetify/Material Design)
   - Match the styling of other tabs (Permissions, Tasks)
   - Add loading states and error handling
   - Include edit capabilities (Add/Remove permissions, Create/Update/Delete policies)

## API Endpoint Details

### GET `/ui/api/fgac/{warehouse_id}/{table_id}`

Returns mock FGAC configuration:

```json
{
  "table_info": {
    "warehouse_id": "warehouse-uuid",
    "table_id": "schema.table",
    "warehouse_name": "Production Warehouse",
    "namespace_name": "finance",
    "table_name": "sales_data"
  },
  "available_columns": ["id", "user_id", "amount", "region", "created_at"],
  "column_permissions": [
    {
      "column_name": "amount",
      "principal_id": "user:john@example.com",
      "permission_type": "read",
      "masking_method": "hash"
    },
    {
      "column_name": "user_id",
      "principal_id": "role:analysts",
      "permission_type": "read",
      "masking_method": null
    }
  ],
  "row_policies": [
    {
      "policy_name": "regional_access",
      "principal_id": "user:jane@example.com",
      "policy_expression": "region = 'WEST'",
      "is_active": true
    }
  ]
}
```

### GET `/ui/api/warehouses`
Returns list of warehouses (mock data currently)

### GET `/ui/api/schemas/{warehouse_id}`
Returns list of schemas in a warehouse (mock data currently)

### GET `/ui/api/tables/{warehouse_id}/{schema_name}`  
Returns list of tables in a schema (mock data currently)

## Repository Structure

```
lakekeeper-local/                  # Main Lakekeeper repository (this repo)
├── crates/
│   ├── lakekeeper-bin/
│   │   └── src/
│   │       └── ui.rs            # ✅ API proxy endpoints added here
│   └── lakekeeper/
│       └── src/
│           └── api/
│               └── management/  # Real FGAC API endpoints (future)
│
lakekeeper-console/                # UI Repository (separate repo - needs work)
└── src/
    ├── components/
    │   └── tables/
    │       └── TableDetail.vue  # Add FGAC tab here
    └── services/
        └── api.ts               # Add FGAC API calls here
```

## Implementation Checklist

- [x] Create API proxy endpoints in Rust backend
- [x] Remove invalid server-side rendering approach  
- [ ] Find/clone the `lakekeeper-console` UI repository
- [ ] Add FGAC tab to table detail view
- [ ] Create FGAC Vue component with proper styling
- [ ] Integrate API calls to fetch FGAC data
- [ ] Add UI controls for managing permissions
- [ ] Build and test the UI
- [ ] Publish new UI version
- [ ] Update Rust dependency to new UI version
- [ ] Replace mock API responses with real database queries

## Technical Notes

- **Authentication**: The proxy endpoints inherit session-based authentication from the UI router
- **URL Pattern**: Following existing pattern `/ui/warehouse/{id}/namespace/{name}/table/{name}`
- **SPA Routing**: All UI routes are handled by Vue Router, not Axum
- **Build Process**: UI is built separately and embedded as static files in the Rust binary

## Questions to Answer

1. Where is the lakekeeper-console repository?
2. What's the build/release process for the UI?
3. Should we create real backend API endpoints first, or continue with mock data?
4. What's the data model for FGAC storage in the database?

## References

- Lakekeeper main repo: https://github.com/lakekeeper/lakekeeper
- Documentation: https://docs.lakekeeper.io
- UI endpoints defined in: `crates/lakekeeper-bin/src/ui.rs`
