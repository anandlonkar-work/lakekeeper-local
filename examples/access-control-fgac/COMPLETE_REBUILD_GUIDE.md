# 🚀 Complete Rebuild & FGAC Testing Guide

## 📋 Current Status

✅ **Volumes Cleaned**: All old data removed
⏳ **Building**: Fresh Docker image with your FGAC implementation
🎯 **Goal**: Bootstrap environment and test FGAC features end-to-end

## 🔧 Step 1: Complete the Build

**Current Command Running:**
```bash
cd /Users/anand.lonkar/code/lakekeeper/lakekeeper-local/examples/access-control-fgac
docker-compose -f docker-compose-build.yaml build --no-cache lakekeeper
```

**What's happening:**
- ✅ Installing Rust dependencies
- ⏳ Building lakekeeper with your GitHub fork
- ⏳ Downloading your console (feature/fgac-management-tab)
- ⏳ Running npm build to compile Vue.js
- ⏳ Embedding FGAC UI into binary

**Estimated time:** 5-10 minutes

---

## 🎬 Step 2: Start All Services

Once the build completes:

```bash
cd /Users/anand.lonkar/code/lakekeeper/lakekeeper-local/examples/access-control-fgac

# Start all services
docker-compose up -d

# Wait for services to be healthy (takes ~1-2 minutes)
docker-compose ps

# Watch lakekeeper logs
docker-compose logs -f lakekeeper
```

**Expected Output:**
```
NAME                                  STATUS
access-control-fgac-db-1              Up (healthy)
access-control-fgac-keycloak-1        Up (healthy)
access-control-fgac-lakekeeper-1      Up (healthy)
access-control-fgac-minio-1           Up (healthy)
access-control-fgac-openfga-1         Up (healthy)
access-control-fgac-trino-1           Up (healthy)
access-control-fgac-opa-1             Up
access-control-fgac-jupyter-1         Up
```

---

## 📊 Step 3: Bootstrap the Environment

### 3.1 Create a Warehouse

```bash
curl -X POST "http://localhost:8181/management/v1/warehouse" \
  -H "Content-Type: application/json" \
  -d '{
    "warehouse-name": "demo",
    "project-id": "00000000-0000-0000-0000-000000000000",
    "storage-profile": {
      "type": "s3",
      "bucket": "warehouse",
      "key-prefix": "demo/",
      "endpoint": "http://minio:9000",
      "path-style-access": true,
      "region": "us-east-1"
    },
    "storage-credential": {
      "type": "s3",
      "credential-type": "access-key",
      "aws-access-key-id": "minio-root-user",
      "aws-secret-access-key": "minio-root-password"
    }
  }'
```

**Expected Response:**
```json
{
  "warehouse-id": "demo",
  "project-id": "00000000-0000-0000-0000-000000000000",
  "warehouse-name": "demo",
  "storage-profile": { ... },
  "storage-credential": { "credential-type": "access-key" }
}
```

### 3.2 Create a Namespace

```bash
curl -X POST "http://localhost:8181/catalog/v1/demo/namespaces" \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": ["sales"],
    "properties": {
      "description": "Sales department data"
    }
  }'
```

### 3.3 Create a Sample Table

Use Jupyter notebook or create via API:

**Option A: Via Jupyter** (http://localhost:8888)

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("LakekeeperTest") \
    .config("spark.jars.packages", "org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.5.0") \
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
    .config("spark.sql.catalog.demo", "org.apache.iceberg.spark.SparkCatalog") \
    .config("spark.sql.catalog.demo.type", "rest") \
    .config("spark.sql.catalog.demo.uri", "http://lakekeeper:8181/catalog") \
    .config("spark.sql.catalog.demo.warehouse", "demo") \
    .getOrCreate()

# Create a sample table
spark.sql("""
    CREATE TABLE demo.sales.customers (
        customer_id INT,
        customer_name STRING,
        email STRING,
        phone STRING,
        ssn STRING,
        credit_score INT,
        region STRING,
        created_at TIMESTAMP
    )
    USING iceberg
""")

# Insert sample data
spark.sql("""
    INSERT INTO demo.sales.customers VALUES
    (1, 'Alice Johnson', 'alice@example.com', '555-0101', '123-45-6789', 750, 'US-WEST', CURRENT_TIMESTAMP),
    (2, 'Bob Smith', 'bob@example.com', '555-0102', '987-65-4321', 680, 'US-EAST', CURRENT_TIMESTAMP),
    (3, 'Carol White', 'carol@example.com', '555-0103', '456-78-9012', 820, 'US-CENTRAL', CURRENT_TIMESTAMP),
    (4, 'David Brown', 'david@example.com', '555-0104', '321-54-9876', 590, 'EU-WEST', CURRENT_TIMESTAMP),
    (5, 'Eve Davis', 'eve@example.com', '555-0105', '654-32-1098', 710, 'APAC', CURRENT_TIMESTAMP)
""")

# Verify
spark.sql("SELECT * FROM demo.sales.customers").show()
```

---

## 🎯 Step 4: Test FGAC UI

### 4.1 Access the UI

1. **Open Browser**: http://localhost:8181/ui
2. **Login**: 
   - Username: `alice`
   - Password: `alice`

### 4.2 Navigate to FGAC Tab

1. Click **Warehouses** → **demo**
2. Click **Namespaces** → **sales**
3. Click **Tables** → **customers**
4. Click the **FGAC** tab (should be after "Tasks" tab)

**Expected UI:**
- Summary section showing:
  - Total columns
  - Columns with permissions
  - Active row policies
  - Protected columns
- Column Permissions table (initially empty)
- Row Policies table (initially empty)
- "Add Permission" button
- "Add Policy" button

---

## 🧪 Step 5: Test FGAC Features

### Test 1: Create Column Permission

**Steps:**
1. Click **"Add Permission"**
2. Fill in the form:
   - **Column**: `ssn`
   - **Principal Type**: `user`
   - **Principal ID**: `bob`
   - **Permission Type**: `read`
3. Click **"Save"**

**Expected Result:**
- ✅ Success message appears
- ✅ New row appears in Column Permissions table
- ✅ Row shows: ssn, user, bob, read, granted_by, granted_at

### Test 2: Create Row Policy

**Steps:**
1. Click **"Add Policy"**
2. Fill in the form:
   - **Policy Name**: `restrict-by-region`
   - **Principal Type**: `user`
   - **Principal ID**: `alice`
   - **Expression**: `region = 'US-WEST'`
   - **Policy Type**: `filter`
   - **Priority**: `100`
   - **Active**: Toggle ON
3. Click **"Save"**

**Expected Result:**
- ✅ Success message appears
- ✅ New row appears in Row Policies table
- ✅ Row shows: restrict-by-region, user, alice, region = 'US-WEST', filter, 100, Active, Actions

### Test 3: Edit Permission

**Steps:**
1. Click **Edit icon** (pencil) on the SSN permission
2. Change **Permission Type** to `owner`
3. Click **"Save"**

**Expected Result:**
- ✅ Success message
- ✅ Permission updated in table
- ✅ Shows "owner" instead of "read"

### Test 4: Delete Policy

**Steps:**
1. Click **Delete icon** (trash) on a row policy
2. Confirm deletion in dialog
3. Click **"Delete"**

**Expected Result:**
- ✅ Confirmation dialog appears
- ✅ Success message after deletion
- ✅ Row disappears from table

---

## 🔍 Step 6: Verify Backend API

### Check API Endpoints Directly

```bash
# Get FGAC configuration
curl -X GET "http://localhost:8181/management/v1/warehouse/demo/namespace/sales/table/customers/fgac/configuration" \
  -H "Accept: application/json"

# Get FGAC summary
curl -X GET "http://localhost:8181/management/v1/warehouse/demo/namespace/sales/table/customers/fgac/summary" \
  -H "Accept: application/json"

# Create column permission via API
curl -X POST "http://localhost:8181/management/v1/warehouse/demo/namespace/sales/table/customers/fgac/column-permission" \
  -H "Content-Type: application/json" \
  -d '{
    "column_name": "email",
    "principal_type": "user",
    "principal_id": "alice",
    "permission_type": "write"
  }'

# Create row policy via API
curl -X POST "http://localhost:8181/management/v1/warehouse/demo/namespace/sales/table/customers/fgac/row-policy" \
  -H "Content-Type: application/json" \
  -d '{
    "policy_name": "alice-region-filter",
    "principal_type": "user",
    "principal_id": "alice",
    "policy_expression": "region IN (\"US-WEST\", \"US-EAST\")",
    "policy_type": "filter",
    "priority": 100,
    "is_active": true
  }'
```

---

## 📝 Step 7: Check Database

Verify FGAC data is stored in PostgreSQL:

```bash
# Connect to database
docker-compose exec db psql -U postgres

# Check column permissions
SELECT * FROM column_permission;

# Check row policies
SELECT * FROM row_policy;

# Exit
\q
```

**Expected Tables:**
```sql
-- column_permission columns:
column_permission_id | warehouse_id | namespace_name | table_name | column_name | 
principal_type | principal_id | permission_type | granted_by | granted_at | expires_at

-- row_policy columns:
row_policy_id | warehouse_id | namespace_name | table_name | policy_name | 
principal_type | principal_id | policy_expression | policy_type | priority | 
is_active | granted_by | granted_at | expires_at
```

---

## 🐛 Troubleshooting

### Issue 1: FGAC Tab Not Visible

**Check:**
```bash
# Verify console is loaded
docker-compose logs lakekeeper | grep "Serving UI"

# Check for errors
docker-compose logs lakekeeper | grep -i error | grep -i fgac
```

**Solution:**
```bash
# Rebuild if needed
docker-compose -f docker-compose-build.yaml build lakekeeper
docker-compose up -d --force-recreate lakekeeper
```

### Issue 2: API Returns 404

**Check:**
```bash
# Test proxy endpoint
curl -v http://localhost:8181/ui/api/fgac/demo/sales.customers

# Test backend endpoint
curl -v http://localhost:8181/management/v1/warehouse/demo/namespace/sales/table/customers/fgac/configuration
```

**Check logs:**
```bash
docker-compose logs lakekeeper | grep "GET /ui/api/fgac"
docker-compose logs lakekeeper | grep "GET /management/v1"
```

### Issue 3: Data Not Saving

**Check database connection:**
```bash
docker-compose exec db psql -U postgres -c "SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_name LIKE '%permission%' OR table_name LIKE '%policy%';"
```

**Check migrations:**
```bash
docker-compose logs migrate | grep -i fgac
```

---

## ✅ Success Criteria

Your FGAC implementation is working correctly if:

- ✅ FGAC tab appears in table detail page
- ✅ Can create column permissions via UI
- ✅ Can create row policies via UI
- ✅ Can edit existing permissions/policies
- ✅ Can delete permissions/policies
- ✅ Data persists after page refresh
- ✅ API endpoints return correct data
- ✅ Database contains FGAC records
- ✅ Summary statistics update correctly

---

## 📚 Next Steps

Once testing is complete:

1. **Document any issues** found during testing
2. **Create test data** for different scenarios
3. **Test with Trino** to verify query enforcement
4. **Add more sample policies** for complex cases
5. **Create PR** to upstream (optional)

---

## 🎊 You're Ready!

The build is running and will complete soon. Follow this guide step-by-step to bootstrap and thoroughly test your FGAC implementation! 🚀
