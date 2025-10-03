# FGAC Quick Start Guide

## 🚀 5-Minute Setup

### Step 1: Start Services
```bash
cd examples/access-control-advanced
docker-compose up -d
```

Wait for all services to be healthy (~30 seconds):
```bash
docker-compose ps
```

### Step 2: Load FGAC Policies
```bash
# Load the seed data with sample policies
docker-compose exec -T postgres psql -U admin -d lakekeeper < seed-fgac-data.sql
```

**Expected Output:**
```
✓ Found demo warehouse: <uuid>
✓ Inserted 3 column permissions for Anna
✓ Inserted 3 row policies for Anna
```

### Step 3: Test the Integration

**Test Internal OPA API:**
```bash
curl -s "http://localhost:8181/internal/opa/v1/column-masks?user_id=d223d88c-85b6-4859-b5c5-27f3825e47f6&warehouse=demo&namespace=fgac_test&table=employees" | jq
```

**Expected Response:**
```json
{
  "column_masks": {
    "salary": {"expression": "NULL", "method": "null"},
    "email": {"expression": "NULL", "method": "null"},
    "phone": {"expression": "NULL", "method": "null"}
  }
}
```

### Step 4: Test in UI

1. Open: http://localhost:8181/ui
2. Navigate: Warehouses → demo → Namespaces → fgac_test → Tables → employees
3. Click: **FGAC** tab
4. Verify: You see 3 column permissions and 3 row policies

### Step 5: Run Jupyter Notebook

1. Open: http://localhost:8888
2. Navigate: `notebooks/05-FGAC-Testing.ipynb`
3. Run all cells
4. Verify:
   - Peter sees 8 employees with all columns
   - Anna sees 3 employees (Engineering only) with masked sensitive columns

## 📊 What You'll See

### Database Policies

**Column Permissions (Anna):**
| Column | Mask Method | Expression |
|--------|-------------|------------|
| salary | null | NULL |
| email  | null | NULL |
| phone  | null | NULL |

**Row Policies (Anna):**
| Policy Name | Expression | Priority |
|-------------|------------|----------|
| public_internal_only | classification IN ('Public', 'Internal') | 10 |
| no_executive_dept | department != 'Executive' | 9 |
| engineering_only | department = 'Engineering' | 8 |

### Test Data

**All Employees (Peter sees all 8):**
1. John Doe - Engineering, Public, $85k
2. Jane Smith - Engineering, Public, $95k
3. Bob Johnson - HR, Confidential, $70k
4. Alice Brown - Finance, Confidential, $65k
5. Charlie Wilson - Engineering, Public, $110k
6. Diana Lee - Sales, Public, $78k
7. Eve Davis - HR, Internal, $55k
8. Frank Miller - Executive, Restricted, $250k

**Anna sees (3 employees):**
1. John Doe - Engineering, Public, NULL (salary masked)
2. Jane Smith - Engineering, Public, NULL (salary masked)
3. Charlie Wilson - Engineering, Public, NULL (salary masked)

## 🔧 Common Tasks

### Verify Policies in Database

```bash
docker-compose exec postgres psql -U admin -d lakekeeper -c "
SELECT 
    cp.column_name,
    cp.masking_expression,
    u.user_name as restricted_user
FROM column_permissions cp
JOIN warehouse w ON cp.warehouse_id = w.warehouse_id
JOIN \"user\" u ON cp.principal_id = u.user_id
WHERE w.warehouse_name = 'demo'
ORDER BY cp.column_name;
"
```

### Check OPA Logs

```bash
# See OPA making HTTP calls to Lakekeeper
docker-compose logs opa | grep -i "http://lakekeeper"
```

### Check Lakekeeper Logs

```bash
# See internal OPA API requests
docker-compose logs lakekeeper | grep "internal/opa"
```

### Test with Different Users

**Test Anna's access:**
```bash
# In notebook, use anna_cur cursor
anna_cur.execute("SELECT * FROM fgac_test.employees")
```

**Test Peter's access:**
```bash
# In notebook, use peter_cur cursor
peter_cur.execute("SELECT * FROM fgac_test.employees")
```

## ⚙️ Configuration Files

### OPA Environment
`docker-compose.yaml`:
```yaml
opa:
  environment:
    - OPA_HTTP_SEND_TIMEOUT=10s  # Enable HTTP calls
```

### Trino Configuration
`trino/access-control.properties`:
```properties
opa.policy.column-masking-uri=http://opa:8181/v1/data/trino/columnMask
opa.policy.row-filters-uri=http://opa:8181/v1/data/trino/rowFilters
```

## 🐛 Troubleshooting

### Issue: Policies not applying

**Check if policies exist in database:**
```bash
docker-compose exec postgres psql -U admin -d lakekeeper -c "
SELECT COUNT(*) as column_perms FROM column_permissions;
SELECT COUNT(*) as row_policies FROM row_policies;
"
```

**Expected:** Each query returns count > 0

### Issue: OPA can't reach Lakekeeper

**Test connectivity:**
```bash
docker-compose exec opa curl -s http://lakekeeper:8181/health
```

**Expected:** `{"status":"healthy"}`

### Issue: Column masks not working

**Test OPA endpoint directly:**
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

**Expected:** Returns `{"result": {"expression": "NULL"}}`

### Issue: Internal API returns empty

**Check if warehouse exists:**
```bash
docker-compose exec postgres psql -U admin -d lakekeeper -c "
SELECT warehouse_id, warehouse_name FROM warehouse;
"
```

**Expected:** Shows `demo` warehouse

## 📚 Additional Resources

- **Full Documentation:** `docs/docs/fgac.md`
- **Setup Guide:** `examples/access-control-advanced/FGAC-README.md`
- **Implementation Details:** `FGAC_IMPLEMENTATION_SUMMARY.md`
- **Jupyter Notebook:** `examples/access-control-advanced/notebooks/05-FGAC-Testing.ipynb`

## 🎯 Next Steps

1. ✅ Complete this quick start
2. 📖 Read full FGAC documentation
3. 🧪 Experiment with different policies
4. 🚀 Implement CRUD APIs for policy management
5. 🔐 Add role-based policies (not just user-based)
6. 📊 Add audit logging and monitoring

## 💡 Pro Tips

- **Restart OPA** after changing `.rego` files (not needed for database changes)
- **Use priority** on row policies to control evaluation order
- **Set expiration dates** for temporary access
- **Test in dev** before applying policies to production tables
- **Monitor latency** - OPA HTTP calls add ~5-10ms per query

---

**Status:** ✅ Ready for production testing  
**Version:** OPA-PostgreSQL Integration v1.0  
**Last Updated:** October 2, 2025
