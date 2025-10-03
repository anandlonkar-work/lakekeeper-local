# Fine-Grained Access Control (FGAC)

Lakekeeper provides fine-grained access control (FGAC) capabilities that enable column-level masking and row-level filtering on Iceberg tables. This guide explains how FGAC works, how to configure it, and how to manage policies.

## Overview

FGAC in Lakekeeper consists of three main components working together:

1. **PostgreSQL** - Stores column permissions and row policies (source of truth)
2. **Lakekeeper Management API** - Provides CRUD operations for managing FGAC policies
3. **Open Policy Agent (OPA)** - Enforces policies at query time by reading from PostgreSQL

### Architecture

```
┌─────────────────┐
│   UI / Client   │
└────────┬────────┘
         │ CRUD policies
         ▼
┌─────────────────────┐
│  Management API     │
│  /management/v1/... │
└────────┬────────────┘
         │ Write/Read
         ▼
┌──────────────────────┐      ┌────────────────┐
│    PostgreSQL        │◄─────│  Internal OPA  │
│  - column_permissions│ HTTP │     API        │
│  - row_policies      │ Call │ /internal/opa/ │
└──────────────────────┘      └────────┬───────┘
                                       ▲
                                       │ Query data
                                       │
                              ┌────────┴────────┐
                              │      OPA        │
                              │  .rego policies │
                              └────────┬────────┘
                                       ▲
                                       │ Policy check
                                       │
                              ┌────────┴────────┐
                              │     Trino       │
                              │  Query Engine   │
                              └─────────────────┘
```

### How It Works

1. **Policy Creation**: Users create column permissions and row policies via the Management API or UI
2. **Storage**: Policies are stored in PostgreSQL with metadata (who created, when, expiration, etc.)
3. **Query Time**: When Trino processes a query:
   - Trino calls OPA for column masking and row filtering decisions
   - OPA evaluates `.rego` policy logic
   - OPA makes HTTP calls to Lakekeeper's internal API to fetch applicable policies from PostgreSQL
   - OPA returns masking expressions and filter expressions to Trino
   - Trino rewrites the query to apply masks and filters

### Separation of Concerns

- **`.rego` files** = Policy evaluation **logic** (how to apply rules)
- **PostgreSQL** = Policy **data** (what rules to apply, for whom, on which columns/rows)
- **OpenFGA** = Authorization (who can create/modify/delete policies)

## Column-Level Permissions

Column permissions control access to specific columns in a table. Permissions can:

- **Mask columns** - Replace sensitive values with NULL, constants, or transformations
- **Block access** - Prevent certain users from seeing specific columns
- **Apply functions** - Transform column values (e.g., hash email, show only domain)

### Column Permission Schema

```sql
CREATE TABLE column_permissions (
    column_permission_id UUID PRIMARY KEY,
    warehouse_id UUID NOT NULL,
    namespace_name TEXT NOT NULL,
    table_name TEXT NOT NULL,
    column_name TEXT NOT NULL,
    principal_type TEXT NOT NULL,  -- 'user' or 'role'
    principal_id UUID NOT NULL,
    permission_type TEXT NOT NULL,  -- 'mask', 'deny', 'allow'
    masking_method TEXT,            -- 'null', 'constant', 'hash', 'custom'
    masking_expression TEXT,        -- SQL expression for masking
    granted_by UUID NOT NULL,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### Example Column Permissions

**Mask salary column for role 'analyst':**
```json
{
  "column_name": "salary",
  "principal_type": "role",
  "principal_id": "550e8400-e29b-41d4-a716-446655440001",
  "permission_type": "mask",
  "masking_method": "null",
  "masking_expression": "NULL"
}
```

**Partially mask email (show only domain):**
```json
{
  "column_name": "email",
  "principal_type": "user",
  "principal_id": "d223d88c-85b6-4859-b5c5-27f3825e47f6",
  "permission_type": "mask",
  "masking_method": "custom",
  "masking_expression": "substring(email, position('@', email))"
}
```

## Row-Level Policies

Row policies filter which rows a user or role can see when querying a table.

### Row Policy Schema

```sql
CREATE TABLE row_policies (
    row_policy_id UUID PRIMARY KEY,
    warehouse_id UUID NOT NULL,
    namespace_name TEXT NOT NULL,
    table_name TEXT NOT NULL,
    policy_name TEXT NOT NULL,
    principal_type TEXT NOT NULL,   -- 'user' or 'role'
    principal_id UUID NOT NULL,
    policy_expression TEXT NOT NULL, -- SQL WHERE clause
    policy_type TEXT NOT NULL,       -- 'filter', 'allow'
    is_active BOOLEAN NOT NULL DEFAULT true,
    priority INTEGER NOT NULL DEFAULT 0,
    granted_by UUID NOT NULL,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### Example Row Policies

**Filter by department:**
```json
{
  "policy_name": "dept_engineering_only",
  "principal_type": "role",
  "principal_id": "550e8400-e29b-41d4-a716-446655440002",
  "policy_expression": "department = 'Engineering'",
  "policy_type": "filter",
  "priority": 10
}
```

**Filter by classification level:**
```json
{
  "policy_name": "public_internal_only",
  "principal_type": "user",
  "principal_id": "d223d88c-85b6-4859-b5c5-27f3825e47f6",
  "policy_expression": "classification IN ('Public', 'Internal')",
  "policy_type": "filter",
  "priority": 5
}
```

## OPA Integration

### Dynamic Policy Loading

OPA policies use HTTP calls to fetch policy data from PostgreSQL at query time:

```rego
package trino

import future.keywords.if

# Fetch column masks from Lakekeeper's PostgreSQL database
get_column_masks(user_id, warehouse, namespace, table) := masks if {
    response := http.send({
        "method": "GET",
        "url": sprintf("http://lakekeeper:8181/internal/opa/v1/column-masks?user_id=%s&warehouse=%s&namespace=%s&table=%s", 
                       [user_id, warehouse, namespace, table]),
        "headers": {"Content-Type": "application/json"}
    })
    response.status_code == 200
    masks := response.body.column_masks
}

# Apply column masking based on database policies
columnMask := {"expression": mask.expression} if {
    user_id := input.context.identity.user
    column := input.action.resource.column
    
    masks := get_column_masks(user_id, column.catalogName, column.schemaName, column.tableName)
    mask := masks[column.columnName]
}
```

### Internal OPA API Endpoints

Lakekeeper provides internal endpoints that OPA queries:

- `GET /internal/opa/v1/column-masks` - Returns applicable column masks for a user/table
- `GET /internal/opa/v1/row-filters` - Returns applicable row filters for a user/table

**Query Parameters:**
- `user_id` (required) - UUID of the user
- `warehouse` (required) - Warehouse name
- `namespace` (required) - Namespace name
- `table` (required) - Table name

**Response Format:**

```json
{
  "column_masks": {
    "salary": {
      "expression": "NULL",
      "method": "null"
    },
    "email": {
      "expression": "substring(email, position('@', email))",
      "method": "custom"
    }
  }
}
```

### Configuration

OPA must be configured to allow HTTP calls to Lakekeeper:

**docker-compose.yaml:**
```yaml
opa:
  image: openpolicyagent/opa:1.0.0
  environment:
    - OPA_HTTP_SEND_TIMEOUT=10s
  networks:
    - iceberg_net
```

## Management API

### Get FGAC Configuration for Table

**Endpoint:** `GET /management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/fgac/configuration`

**Response:**
```json
{
  "column_permissions": [
    {
      "column_permission_id": "uuid",
      "column_name": "salary",
      "principal_type": "user",
      "principal_id": "uuid",
      "permission_type": "mask",
      "masking_method": "null",
      "masking_expression": "NULL",
      "granted_by": "uuid",
      "granted_at": "2025-10-01T10:00:00Z",
      "expires_at": null
    }
  ],
  "row_policies": [
    {
      "row_policy_id": "uuid",
      "policy_name": "dept_filter",
      "principal_type": "role",
      "principal_id": "uuid",
      "policy_expression": "department = 'Engineering'",
      "policy_type": "filter",
      "is_active": true,
      "priority": 10,
      "granted_by": "uuid",
      "granted_at": "2025-10-01T10:00:00Z",
      "expires_at": null
    }
  ]
}
```

### Create Column Permission

**Endpoint:** `POST /management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/column-permissions`

**Request Body:**
```json
{
  "column_name": "email",
  "principal_type": "user",
  "principal_id": "d223d88c-85b6-4859-b5c5-27f3825e47f6",
  "permission_type": "mask",
  "masking_method": "custom",
  "masking_expression": "substring(email, position('@', email))",
  "expires_at": "2026-01-01T00:00:00Z"
}
```

### Create Row Policy

**Endpoint:** `POST /management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/row-policies`

**Request Body:**
```json
{
  "policy_name": "engineering_only",
  "principal_type": "role",
  "principal_id": "550e8400-e29b-41d4-a716-446655440002",
  "policy_expression": "department = 'Engineering'",
  "policy_type": "filter",
  "priority": 10,
  "expires_at": null
}
```

## Trino Configuration

Configure Trino to use OPA for fine-grained access control:

**access-control.properties:**
```properties
access-control.name=opa
opa.policy.uri=http://opa:8181/v1/data/trino/allow
opa.policy.column-masking-uri=http://opa:8181/v1/data/trino/columnMask
opa.policy.row-filters-uri=http://opa:8181/v1/data/trino/rowFilters
opa.log-requests=true
opa.log-responses=true
opa.policy.batched-uri=http://opa:8181/v1/data/trino/batch
```

## Best Practices

### Policy Design

1. **Use roles over users** - Assign policies to roles for easier management
2. **Set expiration dates** - Time-bound access for temporary permissions
3. **Priority matters** - Higher priority row policies are evaluated first
4. **Test thoroughly** - Use non-production warehouses to test policies

### Performance

1. **Limit HTTP calls** - OPA caches policy data, but minimize policy complexity
2. **Use indexes** - Ensure PostgreSQL indexes on `warehouse_id`, `namespace_name`, `table_name`
3. **Monitor latency** - OPA HTTP calls add ~5-10ms per query

### Security

1. **Audit policy changes** - Track `granted_by` and `granted_at` fields
2. **Review regularly** - Periodically audit policies and remove expired/unused ones
3. **Least privilege** - Only grant permissions that are absolutely necessary

## Troubleshooting

### Policies not applying

1. Check OPA logs: `docker-compose logs opa`
2. Verify OPA can reach Lakekeeper: `curl http://lakekeeper:8181/internal/opa/v1/column-masks`
3. Ensure policies exist in PostgreSQL: `SELECT * FROM column_permissions`

### HTTP timeout errors

1. Increase `OPA_HTTP_SEND_TIMEOUT` environment variable
2. Check network connectivity between OPA and Lakekeeper
3. Verify PostgreSQL query performance

### Column masks not applied

1. Check Trino logs for OPA policy evaluation
2. Verify `opa.policy.column-masking-uri` is set correctly
3. Test OPA endpoint directly: `curl -X POST http://opa:8181/v1/data/trino/columnMask -d @test-input.json`

## Examples

See the [access-control-advanced example](https://github.com/lakekeeper/lakekeeper/tree/main/examples/access-control-advanced) for a complete working setup with:

- PostgreSQL with FGAC tables
- OPA configured to query Lakekeeper
- Trino with column masking and row filtering
- Sample policies and test queries

## API Reference

For complete API documentation, see:
- [Management API - FGAC](./api/management.md#fgac)
- [Internal OPA API](./api/internal-opa.md)
