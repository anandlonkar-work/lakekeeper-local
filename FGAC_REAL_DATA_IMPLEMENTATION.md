# FGAC Real Data Implementation - Complete Guide

## ✅ What's Already Done

### Database Schema (Already Migrated)
The following migrations exist and create the FGAC tables:

1. **`20250929170001_fgac_column_permissions.sql`** - Column permissions table
2. **`20250929170002_fgac_row_policies.sql`** - Row policies table  
3. **`20250929170003_fgac_helper_functions.sql`** - Helper functions
4. **`20250930100001_fgac_ui_extensions.sql`** - UI extensions

### Backend API (Already Implemented)
The FGAC management API is fully implemented in:
- **`crates/lakekeeper/src/api/management/v1/fgac.rs`** - Service trait and implementations
- **`crates/lakekeeper/src/api/management/v1/fgac_api.rs`** - HTTP handlers

Available endpoints:
- `GET /management/v1/warehouse/{id}/namespace/{ns}/table/{table}/fgac/configuration`
- `GET /management/v1/warehouse/{id}/namespace/{ns}/table/{table}/fgac/summary`
- `POST /management/v1/warehouse/{id}/namespace/{ns}/table/{table}/fgac/column-permission`
- `DELETE /management/v1/warehouse/{id}/namespace/{ns}/table/{table}/fgac/column-permission/{perm_id}`
- `POST /management/v1/warehouse/{id}/namespace/{ns}/table/{table}/fgac/row-policy`
- `DELETE /management/v1/warehouse/{id}/namespace/{ns}/table/{table}/fgac/row-policy/{policy_id}`
- `POST /management/v1/warehouse/{id}/namespace/{ns}/table/{table}/fgac/validate-policy`

### UI Proxy Updated (Just Completed)
The proxy handler in `crates/lakekeeper-bin/src/ui.rs` has been updated to:
- Forward requests to the real backend API
- Pass through authentication headers (cookies, authorization)
- Handle errors properly
- Route: `/ui/api/fgac/{warehouse_id}/{namespace.table}`

## 📋 What Needs to Be Done

### 1. Update Vue.js FgacManager Component

The component needs to be updated to work with the real API response structure.

#### Current Mock Data Structure:
```typescript
{
  table_info: { warehouse_id, table_id, warehouse_name, namespace_name, table_name },
  available_columns: string[],
  column_permissions: [...],
  row_policies: [...],
  available_principals: string[]
}
```

#### Real API Response Structure:
```typescript
{
  summary: {
    warehouse_id: UUID,
    namespace: string,
    table_name: string,
    total_column_permissions: number,
    total_row_policies: number,
    columns_with_permissions: string[],
    affected_principals: string[],
    last_modified_at: string
  },
  table_info: {
    warehouse_id: UUID,
    namespace: string,
    table_name: string,
    table_id: UUID,
    location: string,
    table_format: string
  },
  columns: [
    {
      name: string,
      type: string,
      nullable: boolean,
      comment: string | null
    }
  ],
  column_permissions: [
    {
      column_permission_id: UUID,
      column_name: string,
      principal_type: "user" | "role" | "group",
      principal_id: string,
      permission_type: "read" | "write" | "owner",
      granted_by: string,
      granted_at: string,
      expires_at: string | null
    }
  ],
  row_policies: [
    {
      row_policy_id: UUID,
      policy_name: string,
      principal_type: "user" | "role" | "group",
      principal_id: string,
      policy_expression: string,
      policy_type: "filter" | "deny" | "allow",
      is_active: boolean,
      priority: number,
      granted_by: string,
      granted_at: string,
      expires_at: string | null
    }
  ],
  templates: [...],
  permissions_matrix: {...}
}
```

### 2. Update FgacManager.vue Component

File: `/Users/anand.lonkar/code/lakekeeper/lakekeeper-console/src/components/FgacManager.vue`

Update the data fetching and display to use real structure:

```vue
<script lang="ts" setup>
// ... existing imports ...

// Type definitions matching real API
interface TableFgacConfiguration {
  summary: {
    warehouse_id: string;
    namespace: string;
    table_name: string;
    total_column_permissions: number;
    total_row_policies: number;
    columns_with_permissions: string[];
    affected_principals: string[];
    last_modified_at: string;
  };
  table_info: {
    warehouse_id: string;
    namespace: string;
    table_name: string;
    table_id: string;
    location: string;
    table_format: string;
  };
  columns: Array<{
    name: string;
    type: string;
    nullable: boolean;
    comment: string | null;
  }>;
  column_permissions: Array<{
    column_permission_id: string;
    column_name: string;
    principal_type: 'user' | 'role' | 'group';
    principal_id: string;
    permission_type: 'read' | 'write' | 'owner';
    granted_by: string;
    granted_at: string;
    expires_at: string | null;
  }>;
  row_policies: Array<{
    row_policy_id: string;
    policy_name: string;
    principal_type: 'user' | 'role' | 'group';
    principal_id: string;
    policy_expression: string;
    policy_type: 'filter' | 'deny' | 'allow';
    is_active: boolean;
    priority: number;
    granted_by: string;
    granted_at: string;
    expires_at: string | null;
  }>;
}

const fgacData = ref<TableFgacConfiguration | null>(null);

async function loadFgacData() {
  loading.value = true;
  error.value = null;
  
  try {
    // Construct the path: namespace.table or namespace₁ftable
    const tableIdentifier = `${props.namespaceId}.${props.tableName}`;
    
    const response = await fetch(
      `/ui/api/fgac/${props.warehouseId}/${encodeURIComponent(tableIdentifier)}`
    );
    
    if (!response.ok) {
      throw new Error(`Failed to load FGAC data: ${response.statusText}`);
    }
    
    fgacData.value = await response.json();
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Unknown error loading FGAC data';
    console.error('Error loading FGAC data:', e);
  } finally {
    loading.value = false;
  }
}

// Update table headers to match real data
const columnPermissionHeaders = [
  { title: 'Column', key: 'column_name' },
  { title: 'Principal Type', key: 'principal_type' },
  { title: 'Principal', key: 'principal_id' },
  { title: 'Permission', key: 'permission_type' },
  { title: 'Granted By', key: 'granted_by' },
  { title: 'Granted At', key: 'granted_at' },
  { title: 'Actions', key: 'actions', sortable: false },
];

const rowPolicyHeaders = [
  { title: 'Policy Name', key: 'policy_name' },
  { title: 'Principal Type', key: 'principal_type' },
  { title: 'Principal', key: 'principal_id' },
  { title: 'Expression', key: 'policy_expression' },
  { title: 'Type', key: 'policy_type' },
  { title: 'Priority', key: 'priority' },
  { title: 'Status', key: 'is_active' },
  { title: 'Actions', key: 'actions', sortable: false },
];
</script>
```

### 3. Add Create/Edit/Delete Operations

The FgacManager component needs dialogs and methods for:

**Column Permissions:**
- Create: `POST /management/v1/warehouse/{id}/namespace/{ns}/table/{table}/fgac/column-permission`
- Update: Same POST endpoint (upsert)
- Delete: `DELETE /management/v1/warehouse/{id}/namespace/{ns}/table/{table}/fgac/column-permission/{perm_id}`

**Row Policies:**
- Create: `POST /management/v1/warehouse/{id}/namespace/{ns}/table/{table}/fgac/row-policy`
- Update: Same POST endpoint (upsert)
- Delete: `DELETE /management/v1/warehouse/{id}/namespace/{ns}/table/{table}/fgac/row-policy/{policy_id}`

### 4. Build and Test

```bash
cd /Users/anand.lonkar/code/lakekeeper/lakekeeper-console

# Install dependencies
npm install

# Run development server
npm run dev

# Test against running lakekeeper instance at localhost:8181
```

### 5. Update lakekeeper-local to Use New Console

Once the console changes are tested:

```bash
cd /Users/anand.lonkar/code/lakekeeper/lakekeeper-local

# Rebuild with the updated UI
docker-compose -f examples/access-control-fgac/docker-compose.yaml \
  -f examples/access-control-fgac/docker-compose-build.yaml up -d --build
```

## 🔧 API Request Examples

### Get FGAC Configuration
```bash
curl -X GET http://localhost:8181/management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/fgac/configuration \
  -H "Authorization: Bearer <token>"
```

### Create Column Permission
```bash
curl -X POST http://localhost:8181/management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/fgac/column-permission \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{
    "column_name": "ssn",
    "principal_type": "role",
    "principal_id": "data_analyst",
    "permission_type": "read",
    "granted_by": "admin@example.com"
  }'
```

### Create Row Policy
```bash
curl -X POST http://localhost:8181/management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/fgac/row-policy \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{
    "policy_name": "regional_access",
    "principal_type": "user",
    "principal_id": "alice@example.com",
    "policy_expression": "region = '\''WEST'\''",
    "policy_type": "filter",
    "is_active": true,
    "priority": 100,
    "granted_by": "admin@example.com"
  }'
```

## 📝 Summary

**Backend**: ✅ Complete - All FGAC APIs implemented
**Database**: ✅ Complete - Migrations exist and create tables
**UI Proxy**: ✅ Complete - Updated to call real API
**Vue.js Component**: ⚠️  Needs Update - Structure change required
**CRUD Operations**: ⚠️  Needs Implementation - Dialogs and API calls

The heavy lifting is done! Just need to update the Vue.js component to match the real API response structure and add the create/edit/delete dialogs.
