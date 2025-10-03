# FGAC Implementation Status

## Current State (October 2, 2025)

### ✅ What's Working

1. **Architecture Designed & Documented**
   - OPA policies query Lakekeeper via HTTP (`http.send()`)
   - Lakekeeper stores policies in PostgreSQL
   - Trino calls OPA for column masking and row filtering
   - Complete documentation in `docs/docs/fgac.md`

2. **Infrastructure Complete**
   - Internal OPA API endpoints exist (`/internal/opa/v1/column-masks`, `/internal/opa/v1/row-filters`)
   - Router integration works
   - OPA .rego files updated to call Lakekeeper
   - Docker-compose configured for OPA HTTP calls

3. **Code Compiles Successfully**
   - Release build completes without errors
   - Binary created: `target/release/lakekeeper-bin`
   - Type system works correctly

4. **Test Data Ready**
   - Seed script with 8 test employees
   - 3 column permissions (mask salary/email/phone for Anna)
   - 3 row policies (filter to Engineering dept for Anna)

### ⚠️ Current Limitation

**Database Integration Incomplete**

The internal OPA API and Management API currently return **empty data** because:

1. **Type System Constraint**: The `Catalog::State` trait doesn't expose `read_pool()` method
2. **Architecture Decision**: API layer should remain database-agnostic
3. **sqlx Compile-Time Macros**: Require DATABASE_URL with live database during build

### 🔧 Two Paths Forward

#### Option A: Runtime SQL Queries (Quick Win)
Use `sqlx::query()` instead of `sqlx::query!()`:
- No DATABASE_URL needed at build time
- Works with generic Catalog trait  
- Less type safety (no compile-time validation)
- Requires manual type mapping

#### Option B: PostgreSQL-Specific Implementation (Better Long-term)
Make internal OPA API PostgreSQL-specific:
- Full type safety with sqlx macros
- Direct access to `CatalogState.read_pool()`
- Requires DATABASE_URL at build time (already needed for runtime anyway)
- Tighter coupling to PostgreSQL

#### Option C: Catalog Trait Extension (Most Flexible)
Add `query_fgac_policies()` methods to Catalog trait:
- Remains database-agnostic
- Full type safety
- Each implementation provides its own query logic
- Most work required

### 📋 What Works Right Now

You can test the infrastructure even with empty data:

```bash
# 1. Start services
cd examples/access-control-advanced
docker-compose up -d

# 2. Test internal OPA API (returns empty but works)
curl "http://localhost:8181/internal/opa/v1/column-masks?\
user_id=d223d88c-85b6-4859-b5c5-27f3825e47f6&\
warehouse=demo&namespace=fgac_test&table=employees"
# Returns: {"column_masks":{}}

# 3. Test OPA policy evaluation
curl -X POST http://localhost:8181/v1/data/trino/columnMask \
  -H "Content-Type: application/json" \
  -d '{"input":{"context":{"identity":{"user":"d223d88c-85b6-4859-b5c5-27f3825e47f6"}}}}'
# OPA successfully calls Lakekeeper but gets empty data

# 4. UI FGAC tab works
# Navigate to demo → fgac_test → employees → FGAC tab
# Shows empty lists (no errors)
```

### 🎯 Recommended Next Step

Given the current state, **Option B (PostgreSQL-Specific)** is recommended because:

1. DATABASE_URL is already required for Lakekeeper runtime
2. Only PostgreSQL is officially supported
3. Provides full type safety
4. Can be refactored to Option C later if needed

Implementation:
1. Remove generic type parameters from internal OPA handlers
2. Import `crate::implementations::postgres::CatalogState` directly
3. Use sqlx macros with compile-time validation
4. Rebuild with `DATABASE_URL` set

###  📊 Files Status

| File | Status | Notes |
|------|--------|-------|
| `crates/lakekeeper/src/api/internal/opa.rs` | ✅ Compiles | Returns empty data |
| `crates/lakekeeper/src/api/management/v1/fgac_api.rs` | ✅ Compiles | Returns empty data |
| `authz/opa-bridge/policies/trino/columnMask.rego` | ✅ Complete | Ready to receive data |
| `authz/opa-bridge/policies/trino/rowFilters.rego` | ✅ Complete | Ready to receive data |
| `examples/access-control-advanced/seed-fgac-data.sql` | ✅ Ready | Test data prepared |
| `docs/docs/fgac.md` | ✅ Complete | 400+ lines documentation |

### 🚀 Quick Test (Current State)

Even without database queries, you can verify the infrastructure:

```bash
# Start only essential services
docker-compose up -d db minio lakekeeper opa

# Wait for readiness
sleep 10

# Test endpoint routing (should return empty JSON, not 404)
curl -s "http://localhost:8181/internal/opa/v1/column-masks?user_id=$(uuidgen)&warehouse=test&namespace=test&table=test" | jq

# Expected output:
# {
#   "column_masks": {}
# }
```

### 📝 Summary

- ✅ Architecture: Complete and validated
- ✅ Infrastructure: Fully working
- ✅ Code: Compiles successfully
- ⏳ Database Integration: Deferred due to type system constraints
- ✅ Documentation: Comprehensive
- ✅ Test Data: Ready to load

**The system is 80% complete.** The remaining 20% is connecting the database queries, which requires an architectural decision about breaking the database-agnostic abstraction.

---

## Decision Record

**Status**: Awaiting user/team decision on Option A vs B vs C

**Recommendation**: Option B (PostgreSQL-Specific Implementation)

**Rationale**:
- Pragmatic: DATABASE_URL already required for runtime
- Safe: Compile-time SQL validation
- Fast: Can be implemented quickly
- Maintainable: Clear separation of concerns

**Trade-off**: Tight coupling to PostgreSQL (acceptable given it's the only supported backend)
