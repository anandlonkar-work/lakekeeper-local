# FGAC Implementation - Current State & Next Steps

## ✅ What's Working Now

**Build Status:** ✅ **COMPLETE** - Compiled successfully with warnings only

### Infrastructure Ready:
1. ✅ **Internal OPA API Endpoints** - Exist at `/internal/opa/v1/column-masks` and `/internal/opa/v1/row-filters`
2. ✅ **Router Integration** - Properly nested in main Lakekeeper router
3. ✅ **Type System** - All Rust types compile correctly
4. ✅ **OPA Policy Files** - Updated to call Lakekeeper via `http.send()`
5. ✅ **Docker Configuration** - OPA configured with `OPA_HTTP_SEND_TIMEOUT=10s`
6. ✅ **Seed Data Script** - Ready with 8 test employees and policies
7. ✅ **Documentation** - Complete guides (fgac.md, QUICKSTART.md, etc.)

### Current Behavior:
- Endpoints return **empty JSON**: `{"column_masks": {}}` and `{"row_filters": []}`
- OPA can call endpoints without errors
- No actual database queries executed

---

## 🔧 Next Step: Enable Full Database Integration

### Why It Was Disabled:
The sqlx compile-time macros (`sqlx::query!`) require `DATABASE_URL` during build to:
- Validate SQL syntax
- Check table/column existence  
- Verify type compatibility

### The Simple Fix:

Since Lakekeeper **already requires** DATABASE_URL at runtime, we just need to provide it during build too.

---

## 🚀 Implementation Plan

### Step 1: Start PostgreSQL
```bash
cd examples/access-control-advanced
docker-compose up -d postgres

# Wait for it to be ready
docker-compose exec postgres pg_isready
```

### Step 2: Set DATABASE_URL
```bash
export DATABASE_URL="postgresql://admin:admin@localhost:5432/lakekeeper"
```

### Step 3: Revert Code Changes

**File 1:** `crates/lakekeeper/src/api/internal/opa.rs`
- Remove the stub implementation
- Add back actual sqlx queries to PostgreSQL
- Query `column_permissions` and `row_policies` tables

**File 2:** `crates/lakekeeper/src/api/management/v1/fgac_api.rs`
- Uncomment the sqlx queries
- Re-enable `query_column_permissions_for_ui()` and `query_row_policies_for_ui()`
- Return real data instead of empty Vec

### Step 4: Rebuild
```bash
cd /Users/anand.lonkar/code/lakekeeper/lakekeeper-local
cargo build --release
```

### Step 5: Test End-to-End
```bash
cd examples/access-control-advanced

# 1. Restart with new binary
docker-compose down
docker-compose up -d

# 2. Load seed data
docker-compose exec -T postgres psql -U admin -d lakekeeper < seed-fgac-data.sql

# 3. Run integration tests
./test-fgac-integration.sh

# 4. Test in Jupyter notebook
# Open http://localhost:8888
# Run notebooks/05-FGAC-Testing.ipynb
```

---

## 📋 Detailed Code Changes Needed

### Change 1: Internal OPA API

**File:** `crates/lakekeeper/src/api/internal/opa.rs`

Need to add database connection pool access and implement queries:

```rust
use sqlx::PgPool;

pub(crate) async fn get_column_masks(
    State(pool): State<PgPool>,  // Get database pool
    Query(params): Query<ColumnMasksQuery>,
) -> Result<impl IntoResponse, (StatusCode, String)> {
    let rows = sqlx::query!(
        r#"
        SELECT column_name, masking_expression, masking_method
        FROM column_permissions cp
        JOIN warehouse w ON cp.warehouse_id = w.warehouse_id
        WHERE w.warehouse_name = $1
          AND cp.namespace_name = $2
          AND cp.table_name = $3
          AND cp.principal_id = $4
        "#,
        params.warehouse,
        params.namespace,
        params.table,
        params.user_id
    )
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    
    let masks = rows.into_iter()
        .filter_map(|row| {
            row.masking_expression.and_then(|expr| {
                row.masking_method.map(|method| {
                    (row.column_name.clone(), ColumnMask { expression: expr, method })
                })
            })
        })
        .collect();
    
    Ok(Json(ColumnMaskResponse { column_masks: masks }))
}
```

### Change 2: Management API

**File:** `crates/lakekeeper/src/api/management/v1/fgac_api.rs`

Simply uncomment the existing sqlx queries that are currently disabled.

---

## 🎯 Expected Results After Implementation

### Internal OPA API Response:
```bash
curl "http://localhost:8181/internal/opa/v1/column-masks?\
user_id=d223d88c-85b6-4859-b5c5-27f3825e47f6&\
warehouse=demo&\
namespace=fgac_test&\
table=employees"
```

**Returns:**
```json
{
  "column_masks": {
    "salary": {"expression": "NULL", "method": "null"},
    "email": {"expression": "NULL", "method": "null"},
    "phone": {"expression": "NULL", "method": "null"}
  }
}
```

### OPA Policy Evaluation:
```bash
curl -X POST http://localhost:8181/v1/data/trino/columnMask \
  -d '{"input": {"context": {"identity": {"user": "d223d88c-85b6-4859-b5c5-27f3825e47f6"}}, ...}}'
```

**Returns:**
```json
{
  "result": {"expression": "NULL"}
}
```

### Trino Query Results:
**Anna's query:**
```sql
SELECT * FROM fgac_test.employees;
```

**Sees:**
- 3 rows (Engineering dept only)
- salary, email, phone columns show NULL
- Other columns visible

**Peter's query:**
```sql
SELECT * FROM fgac_test.employees;
```

**Sees:**
- 8 rows (all employees)
- All columns with real data

---

## 🔍 Alternative: Use sqlx prepare (No DATABASE_URL during build)

If you want to avoid needing DATABASE_URL during every build:

### One-Time Setup:
```bash
# With database running and DATABASE_URL set:
cargo sqlx prepare

# This generates .sqlx/ directory
git add .sqlx/
git commit -m "Add sqlx prepared queries"
```

### Future Builds:
```bash
# Now anyone can build without DATABASE_URL
cargo build --release  # Works offline!
```

### When to Re-run:
Only when SQL queries change in the code.

---

## 📊 Summary

| Component | Status | Notes |
|-----------|--------|-------|
| Internal OPA API | ✅ Compiles | Returns empty data |
| Management API | ✅ Compiles | Returns empty data |
| Router Integration | ✅ Working | Endpoints accessible |
| OPA Policies | ✅ Updated | Uses http.send() |
| Docker Config | ✅ Ready | OPA_HTTP_SEND_TIMEOUT set |
| Seed Data | ✅ Ready | 8 employees + policies |
| Documentation | ✅ Complete | Multiple guides |
| **Database Queries** | ⏳ **PENDING** | Need DATABASE_URL + code changes |

---

## 🚦 Current Decision Point

You have a **working build** with infrastructure in place. To get full functionality:

**Option A:** Use current build to test infrastructure (OPA can call endpoints, but gets empty data)

**Option B:** Implement database queries now (requires code changes + DATABASE_URL)

**Recommendation:** **Go with Option B** - since database is already running, it's a small incremental change to get full functionality.

---

## 📞 Ready to Proceed?

When ready to enable database queries, let me know and I'll:
1. Check database is running
2. Revert the stub implementations
3. Add proper sqlx queries
4. Rebuild with DATABASE_URL
5. Test end-to-end

Current binary location: `/Users/anand.lonkar/code/lakekeeper/lakekeeper-local/target/release/lakekeeper-bin`
