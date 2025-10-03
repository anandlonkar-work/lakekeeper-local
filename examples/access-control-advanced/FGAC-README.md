# FGAC Integration - OPA with PostgreSQL

This directory demonstrates how Lakekeeper's Fine-Grained Access Control (FGAC) works with OPA querying PostgreSQL for dynamic policy enforcement.

## Architecture Overview

```
┌─────────────┐
│ Management  │
│     UI      │──────┐
└─────────────┘      │ CRUD Policies
                     ▼
              ┌──────────────┐
              │  Management  │
              │     API      │
              └──────┬───────┘
                     │ Write/Read
                     ▼
              ┌─────────────────┐      HTTP Call      ┌──────────┐
              │   PostgreSQL    │◄────────────────────│   OPA    │
              │ - column_perms  │   Fetch Policies    │ (.rego)  │
              │ - row_policies  │                     └────┬─────┘
              └─────────────────┘                          │
                                                           │ Policy Check
                                                           ▼
                                                    ┌────────────┐
                                                    │   Trino    │
                                                    └────────────┘
```

**Key Points:**
- **PostgreSQL** = Source of truth for policy data
- **OPA `.rego` files** = Policy evaluation logic
- **Management API** = CRUD interface for policies
- **Internal OPA API** = Bridge between OPA and PostgreSQL

## How It Works

### 1. Create Policies via Management API

```bash
# Create column permission to mask salary for Anna
curl -X POST http://localhost:8181/management/v1/warehouse/demo/namespace/fgac_test/table/employees/column-permissions \
  -H "Content-Type: application/json" \
  -d '{
    "column_name": "salary",
    "principal_type": "user",
    "principal_id": "d223d88c-85b6-4859-b5c5-27f3825e47f6",
    "permission_type": "mask",
    "masking_method": "null",
    "masking_expression": "NULL"
  }'
```

### 2. Policies Stored in PostgreSQL

The policy is inserted into the `column_permissions` table:

```sql
SELECT * FROM column_permissions;
```

### 3. Query Execution Flow

When Anna queries the table:

1. **Trino** executes: `SELECT * FROM fgac_test.employees`
2. **Trino** calls **OPA**: "What column masks apply for Anna on fgac_test.employees?"
3. **OPA** evaluates `columnMask.rego` which calls Lakekeeper's Internal API:
   ```
   GET http://lakekeeper:8181/internal/opa/v1/column-masks?user_id=d223d88c-85b6-4859-b5c5-27f3825e47f6&warehouse=demo&namespace=fgac_test&table=employees
   ```
4. **Lakekeeper** queries PostgreSQL and returns:
   ```json
   {
     "column_masks": {
       "salary": {"expression": "NULL", "method": "null"},
       "email": {"expression": "NULL", "method": "null"},
       "phone": {"expression": "NULL", "method": "null"}
     }
   }
   ```
5. **OPA** returns mask to **Trino**: `{"expression": "NULL"}` for salary, email, phone columns
6. **Trino** rewrites query: `SELECT ..., NULL AS salary, NULL AS email, NULL AS phone FROM ...`

## Setup Instructions

### Step 1: Start Services

```bash
cd examples/access-control-advanced
docker-compose up -d
```

Wait for all services to be healthy:
```bash
docker-compose ps
```

### Step 2: Load Seed Data

The seed data script populates the database with sample FGAC policies that match the original hardcoded OPA rules:

```bash
# Connect to PostgreSQL
docker-compose exec postgres psql -U admin -d lakekeeper

# Load seed data
\i /path/to/seed-fgac-data.sql
```

Or using docker exec:
```bash
docker-compose exec -T postgres psql -U admin -d lakekeeper < seed-fgac-data.sql
```

This creates:
- **3 column permissions** for Anna (mask salary, email, phone)
- **3 row policies** for Anna (classification filter, exclude executive, engineering only)

### Step 3: Verify Policies

**Check UI:**
```
http://localhost:8181/ui
```
Navigate to: Warehouses → demo → Namespaces → fgac_test → Tables → employees → FGAC tab

**Check Database:**
```sql
-- View column permissions
SELECT cp.column_name, cp.masking_expression, cp.principal_id
FROM column_permissions cp
JOIN warehouse w ON cp.warehouse_id = w.warehouse_id
WHERE w.warehouse_name = 'demo';

-- View row policies
SELECT rp.policy_name, rp.policy_expression, rp.priority
FROM row_policies rp
JOIN warehouse w ON rp.warehouse_id = w.warehouse_id
WHERE w.warehouse_name = 'demo'
ORDER BY rp.priority DESC;
```

**Check OPA API:**
```bash
# Test internal OPA endpoint
curl "http://localhost:8181/internal/opa/v1/column-masks?user_id=d223d88c-85b6-4859-b5c5-27f3825e47f6&warehouse=demo&namespace=fgac_test&table=employees" | jq
```

### Step 4: Run FGAC Tests

Open the Jupyter notebook:
```bash
open http://localhost:8888
```

Run: `05-FGAC-Testing.ipynb`

This notebook:
1. Creates the `fgac_test.employees` table
2. Inserts test data
3. Tests column masking (Anna should see NULL for salary, email, phone)
4. Tests row filtering (Anna should only see Engineering dept, Public/Internal classification)

## Configuration

### OPA Configuration

The OPA service is configured to make HTTP calls to Lakekeeper:

```yaml
# docker-compose.yaml
opa:
  environment:
    - OPA_HTTP_SEND_TIMEOUT=10s  # Allow HTTP calls
```

### Trino Configuration

```properties
# trino/access-control.properties
access-control.name=opa
opa.policy.column-masking-uri=http://opa:8181/v1/data/trino/columnMask
opa.policy.row-filters-uri=http://opa:8181/v1/data/trino/rowFilters
```

## API Endpoints

### Management API (for UI/clients)

**Get FGAC Configuration:**
```
GET /management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/fgac/configuration
```

**Create Column Permission:**
```
POST /management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/column-permissions
```

**Create Row Policy:**
```
POST /management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/row-policies
```

### Internal OPA API (called by OPA policies)

**Get Column Masks:**
```
GET /internal/opa/v1/column-masks?user_id={uuid}&warehouse={name}&namespace={name}&table={name}
```

**Get Row Filters:**
```
GET /internal/opa/v1/row-filters?user_id={uuid}&warehouse={name}&namespace={name}&table={name}
```

## Troubleshooting

### Policies Not Applying

1. **Check OPA can reach Lakekeeper:**
   ```bash
   docker-compose exec opa curl http://lakekeeper:8181/health
   ```

2. **Check OPA logs:**
   ```bash
   docker-compose logs opa | grep -i error
   ```

3. **Verify policies exist in database:**
   ```bash
   docker-compose exec postgres psql -U admin -d lakekeeper \
     -c "SELECT COUNT(*) FROM column_permissions;"
   ```

### HTTP Timeout Errors

Increase timeout in `docker-compose.yaml`:
```yaml
opa:
  environment:
    - OPA_HTTP_SEND_TIMEOUT=30s
```

### Column Masks Not Working

1. Check Trino logs:
   ```bash
   docker-compose logs trino-opa | grep -i opa
   ```

2. Test OPA endpoint directly:
   ```bash
   curl -X POST http://localhost:8181/v1/data/trino/columnMask \
     -H "Content-Type: application/json" \
     -d '{
       "input": {
         "context": {"identity": {"user": "d223d88c-85b6-4859-b5c5-27f3825e47f6"}},
         "action": {
           "resource": {
             "column": {
               "catalogName": "lakekeeper",
               "schemaName": "fgac_test",
               "tableName": "employees",
               "columnName": "salary"
             }
           }
         }
       }
     }' | jq
   ```

## Performance Considerations

- **OPA caches policy data** - Policies are fetched once and cached
- **Database queries are indexed** - `warehouse_id`, `namespace_name`, `table_name` are indexed
- **HTTP overhead** - Each query adds ~5-10ms latency
- **Connection pooling** - Lakekeeper uses connection pooling to PostgreSQL

## Next Steps

1. **Implement policy CRUD endpoints** - Add POST/PUT/DELETE endpoints for policies
2. **Add policy validation** - Validate SQL expressions before storing
3. **Implement policy testing** - Dry-run policies before activating
4. **Add audit logging** - Track who created/modified policies
5. **Support role-based policies** - Currently only user-based policies are shown

## Documentation

See the full FGAC documentation:
- [FGAC Overview](../../docs/docs/fgac.md)
- [OPA Integration](../../docs/docs/opa.md)
- [Management API](../../docs/docs/api/management.md)
