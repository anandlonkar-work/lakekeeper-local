# 🎯 FGAC Testing Quick Start

## ✅ Services Status

All services are UP and HEALTHY! 🎉

- **Lakekeeper**: http://localhost:8181 (✅ Healthy)
- **Keycloak**: http://localhost:30080 (✅ Healthy)
- **Jupyter**: http://localhost:8888 (✅ Healthy)
- **MinIO**: http://localhost:9001 (✅ Healthy)
- **Trino**: https://localhost:38191 (✅ Healthy)

---

## 🚀 Step 1: Access the UI

Open your browser to: **http://localhost:8181/ui**

You should see the Lakekeeper web interface!

---

## 🔐 Step 2: Bootstrap (First Time Setup)

Since this is a fresh instance, you need to bootstrap the system first.

### Option A: Via UI (Recommended)
1. Go to http://localhost:8181/ui
2. You should see a Bootstrap page
3. Fill in the bootstrap form to create the first admin user

### Option B: Via API
```bash
curl -X POST "http://localhost:8181/management/v1/bootstrap" \
  -H "Content-Type: application/json" \
  -d '{
    "admin": {
      "user-id": "admin"
    }
  }'
```

---

## 🏗️ Step 3: Create a Warehouse

```bash
curl -X POST "http://localhost:8181/management/v1/warehouse" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
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
  "warehouse-name": "demo",
  "project-id": "00000000-0000-0000-0000-000000000000",
  "storage-profile": {...},
  "storage-credential": {...}
}
```

---

## 📊 Step 4: Create Test Data via Jupyter

1. **Open Jupyter**: http://localhost:8888
2. **Create a new notebook**
3. **Run this code**:

```python
from pyspark.sql import SparkSession
from pyspark.sql.types import *

# Create Spark session with Iceberg
spark = SparkSession.builder \
    .appName("FGAC Test") \
    .config("spark.jars.packages", "org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.5.0") \
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
    .config("spark.sql.catalog.demo", "org.apache.iceberg.spark.SparkCatalog") \
    .config("spark.sql.catalog.demo.type", "rest") \
    .config("spark.sql.catalog.demo.uri", "http://lakekeeper:8181/catalog") \
    .config("spark.sql.catalog.demo.warehouse", "demo") \
    .config("spark.sql.catalog.demo.token", "YOUR_TOKEN_HERE") \
    .getOrCreate()

# Create namespace
spark.sql("CREATE NAMESPACE IF NOT EXISTS demo.sales")

# Create customers table
spark.sql("""
    CREATE TABLE IF NOT EXISTS demo.sales.customers (
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
    (1, 'Alice Johnson', 'alice@example.com', '555-0101', '123-45-6789', 750, 'US-WEST', CURRENT_TIMESTAMP()),
    (2, 'Bob Smith', 'bob@example.com', '555-0102', '987-65-4321', 680, 'US-EAST', CURRENT_TIMESTAMP()),
    (3, 'Carol White', 'carol@example.com', '555-0103', '456-78-9012', 820, 'US-CENTRAL', CURRENT_TIMESTAMP()),
    (4, 'David Brown', 'david@example.com', '555-0104', '321-54-9876', 590, 'EU-WEST', CURRENT_TIMESTAMP()),
    (5, 'Eve Davis', 'eve@example.com', '555-0105', '654-32-1098', 710, 'APAC', CURRENT_TIMESTAMP())
""")

# Verify data
spark.sql("SELECT * FROM demo.sales.customers").show()
```

**Expected Output:**
```
+-----------+--------------+-------------------+----------+-----------+------------+----------+-------------------+
|customer_id|customer_name|             email|     phone|        ssn|credit_score|    region|         created_at|
+-----------+--------------+-------------------+----------+-----------+------------+----------+-------------------+
|          1| Alice Johnson|alice@example.com|555-0101  |123-45-6789|         750|   US-WEST|2025-10-01 21:09:...|
|          2|    Bob Smith|  bob@example.com|555-0102  |987-65-4321|         680|   US-EAST|2025-10-01 21:09:...|
|          3|  Carol White|carol@example.com|555-0103  |456-78-9012|         820|US-CENTRAL|2025-10-01 21:09:...|
|          4|  David Brown|david@example.com|555-0104  |321-54-9876|         590|   EU-WEST|2025-10-01 21:09:...|
|          5|    Eve Davis|  eve@example.com|555-0105  |654-32-1098|         710|      APAC|2025-10-01 21:09:...|
+-----------+--------------+-------------------+----------+-----------+------------+----------+-------------------+
```

---

## 🎨 Step 5: Test FGAC UI

### 5.1 Navigate to Table

1. **Login to UI**: http://localhost:8181/ui
   - Use your bootstrapped credentials
2. **Navigate**: Warehouses → demo → Namespaces → sales → Tables → customers
3. **Click the FGAC tab** (next to Tasks)

### 5.2 You Should See:

**Summary Section:**
- Total Columns: 8
- Columns with Permissions: 0
- Active Row Policies: 0
- Protected Columns: 0

**Two Empty Tables:**
- Column Permissions (with "Add Permission" button)
- Row Policies (with "Add Policy" button)

---

## 🧪 Step 6: Test FGAC Features

### Test 1: Create Column Permission

**Action:**
1. Click **"Add Permission"**
2. Fill in:
   - Column: `ssn`
   - Principal Type: `user`
   - Principal ID: `bob`
   - Permission Type: `read`
3. Click **"Save"**

**Expected Result:**
- ✅ Success snackbar: "Permission saved successfully"
- ✅ New row in Column Permissions table
- ✅ Summary updates: "Columns with Permissions: 1", "Protected Columns: 1"

### Test 2: Create Row Policy

**Action:**
1. Click **"Add Policy"**
2. Fill in:
   - Policy Name: `alice-region-filter`
   - Principal Type: `user`
   - Principal ID: `alice`
   - Expression: `region = 'US-WEST'`
   - Policy Type: `filter`
   - Priority: `100`
   - Active: Toggle ON
3. Click **"Save"**

**Expected Result:**
- ✅ Success snackbar: "Policy saved successfully"
- ✅ New row in Row Policies table
- ✅ Summary updates: "Active Row Policies: 1"

### Test 3: Edit Permission

**Action:**
1. Click **Edit icon** (pencil) on the SSN permission
2. Change Permission Type to `owner`
3. Click **"Save"**

**Expected Result:**
- ✅ Success message
- ✅ Table updates to show "owner"

### Test 4: Delete Policy

**Action:**
1. Click **Delete icon** (trash) on the row policy
2. Confirm in dialog
3. Click **"Delete"**

**Expected Result:**
- ✅ Confirmation dialog appears
- ✅ Success message after deletion
- ✅ Row disappears from table
- ✅ Summary updates: "Active Row Policies: 0"

### Test 5: Refresh Page

**Action:**
1. Refresh the browser page (F5)
2. Navigate back to the FGAC tab

**Expected Result:**
- ✅ Data persists (column permission still shows)
- ✅ Summary is correct
- ✅ No errors in console

---

## 🔍 Step 7: Verify Backend API

### Check FGAC Configuration
```bash
curl -X GET "http://localhost:8181/management/v1/warehouse/demo/namespace/sales/table/customers/fgac/configuration" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Accept: application/json" | jq
```

### Check FGAC Summary
```bash
curl -X GET "http://localhost:8181/management/v1/warehouse/demo/namespace/sales/table/customers/fgac/summary" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Accept: application/json" | jq
```

### Create Column Permission via API
```bash
curl -X POST "http://localhost:8181/management/v1/warehouse/demo/namespace/sales/table/customers/fgac/column-permission" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "column_name": "email",
    "principal_type": "user",
    "principal_id": "alice",
    "permission_type": "write"
  }' | jq
```

---

## 🗄️ Step 8: Verify Database

```bash
# Connect to PostgreSQL
docker-compose exec db psql -U postgres

# Check column permissions
SELECT * FROM column_permission;

# Check row policies
SELECT * FROM row_policy;

# Check migrations
SELECT * FROM __refinery_migrations WHERE name LIKE '%fgac%';

# Exit
\q
```

**Expected Tables:**

```sql
-- column_permission should have:
column_permission_id | warehouse_id | namespace_name | table_name | column_name | 
principal_type | principal_id | permission_type | granted_by | granted_at | expires_at

-- row_policy should have:
row_policy_id | warehouse_id | namespace_name | table_name | policy_name | 
principal_type | principal_id | policy_expression | policy_type | priority | 
is_active | granted_by | granted_at | expires_at
```

---

## ✅ Success Checklist

Your FGAC implementation is working if:

- [ ] FGAC tab appears in table detail page
- [ ] Summary section displays correct statistics
- [ ] Can create column permissions via UI
- [ ] Can create row policies via UI
- [ ] Can edit existing permissions/policies
- [ ] Can delete permissions/policies
- [ ] Data persists after page refresh
- [ ] API endpoints return correct data
- [ ] Database contains FGAC records
- [ ] No errors in browser console
- [ ] No errors in lakekeeper logs

---

## 🐛 Troubleshooting

### Issue: FGAC Tab Not Visible

**Check:**
```bash
# Check if UI is loading
docker-compose logs lakekeeper | grep -i "serving ui"

# Check for errors
docker-compose logs lakekeeper | grep -i error | tail -20
```

**Solution:**
```bash
# Restart lakekeeper
docker-compose restart lakekeeper
```

### Issue: API Returns 404

**Check:**
```bash
# Test proxy endpoint
curl -v http://localhost:8181/ui/api/fgac/demo/sales.customers

# Check logs
docker-compose logs lakekeeper | grep "fgac" | tail -20
```

### Issue: Data Not Saving

**Check database:**
```bash
docker-compose exec db psql -U postgres -c "SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND (table_name LIKE '%permission%' OR table_name LIKE '%policy%');"
```

---

## 📚 Additional Resources

- **COMPLETE_REBUILD_GUIDE.md**: Full rebuild instructions
- **Lakekeeper Docs**: /docs in the repository
- **Your Fork**: https://github.com/anandlonkar-work/lakekeeper-console
- **Branch**: feature/fgac-management-tab

---

## 🎉 Ready to Test!

Your environment is fully configured with:
- ✅ Fresh Docker build with FGAC features
- ✅ All services running and healthy
- ✅ Clean database (no old data)
- ✅ GitHub fork with your changes
- ✅ UI proxy configured
- ✅ Backend API ready

**Start with Step 1 above and work through each test!**

Good luck! 🚀
