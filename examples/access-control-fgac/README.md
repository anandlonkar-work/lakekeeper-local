# Fine-Grained Access Control (FGAC) Example

This example demonstrates lakekeeper's Fine-Grained Access Control (FGAC) capabilities, allowing you to set column-level permissions and row-level policies on Iceberg tables.

## 🚀 Quick Test (Single Command)

**Test the FGAC UI implementation with one command:**

```bash
# From the lakekeeper-local directory
cd examples/access-control-fgac

# Build the latest lakekeeper with FGAC changes
docker-compose -f docker-compose-build.yaml build

# Start all services (uses docker-compose.yaml + docker-compose.override.yml)
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f lakekeeper
```

**Access the UI:**
- 🌐 **Lakekeeper UI**: http://localhost:8181/ui
- 👤 **Login**: alice / alice (or bob / bob)
- 📊 **FGAC Tab**: Navigate to any table and click the "FGAC" tab

**To rebuild after code changes:**
```bash
docker-compose -f docker-compose-build.yaml build
docker-compose up -d --force-recreate lakekeeper
```

**To stop everything:**
```bash
docker-compose down
```

**To clean everything (including volumes):**
```bash
docker-compose down -v
```

## Features

This example includes:

- **Column-level permissions**: Control access to specific columns with support for masking, redaction, and denial
- **Row-level policies**: Apply SQL-like filter expressions to limit data access based on user roles
- **FGAC Management UI**: Web interface to manage permissions and policies (new Vue.js component)
- **REST API**: Programmatic access to FGAC settings
- **OpenFGA Integration**: Authorization backend for fine-grained permissions
- **Keycloak Authentication**: Identity provider with user and role management
- **Jupyter Notebook**: Interactive environment for testing and demonstrations

## Quick Start (Detailed)

### Option 1: Test Latest FGAC Implementation

```bash
# Build with latest changes
docker-compose -f docker-compose-build.yaml build

# Start all services
docker-compose up -d

# Wait for all services to be healthy
docker-compose ps
```

### Option 2: Using Pre-built Images

```bash
# Start the services
docker-compose up -d

# Wait for all services to be healthy
docker-compose ps
```

## Services and Ports

- **Lakekeeper**: http://localhost:8181 - Main catalog service with FGAC APIs
- **Keycloak**: http://localhost:30080 - Identity provider (admin/admin)
- **Jupyter**: http://localhost:8888 - Interactive notebooks
- **MinIO**: http://localhost:9001 - S3-compatible storage (minio-root-user/minio-root-password)
- **Trino**: https://localhost:443 - SQL query engine with FGAC integration (via nginx proxy)
- **OpenFGA**: Internal service for fine-grained authorization
- **OPA**: Internal service for policy enforcement and decision making

## FGAC Management URLs

### ✨ NEW: Vue.js FGAC Tab (Recommended)
Navigate to any table in the UI and click the **FGAC** tab:
```
http://localhost:8181/ui/warehouse/{warehouse_id}/namespace.{namespace_id}/table.{table_id}
```
Then click the **FGAC** tab to:
- View column permissions and row policies
- Add/Edit/Delete column permissions
- Add/Edit/Row policies
- See real-time validation and error messages

### REST API Endpoints (for programmatic access)
```bash
# Get complete FGAC configuration for a table
GET http://localhost:8181/management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/fgac/configuration

# Get summary of FGAC settings
GET http://localhost:8181/management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/fgac/summary

# Create/Update column permission
POST http://localhost:8181/management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/fgac/column-permission

# Delete column permission
DELETE http://localhost:8181/management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/fgac/column-permission/{permission_id}

# Create/Update row policy
POST http://localhost:8181/management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/fgac/row-policy

# Delete row policy
DELETE http://localhost:8181/management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/fgac/row-policy/{policy_id}

# Validate row policy expression
POST http://localhost:8181/management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/fgac/validate-policy
```

### UI Proxy Endpoint (used by Vue.js component)
```
GET http://localhost:8181/ui/api/fgac/{warehouse_id}/{namespace.table}
```
This endpoint proxies to the backend API and returns the complete FGAC configuration.

## Getting Started with FGAC

### 1. Bootstrap the Environment

First, create a warehouse and some sample data:

```bash
# Create a warehouse
curl -X POST "http://localhost:8181/management/v1/warehouse" \
  -H "Content-Type: application/json" \
  -d '{
    "warehouse-name": "demo",
    "project-id": "default",
    "storage-profile": {
      "type": "s3",
      "bucket": "examples",
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

### 2. Create Sample Tables

Use the Jupyter notebook environment to create tables with sample data that you can apply FGAC policies to.

### 3. Access the FGAC Management UI

Navigate to the table-specific FGAC management UI with your warehouse and table IDs to:

- Set column-level permissions (allow, deny, mask)
- Define row-level policies with SQL filter expressions
- Assign permissions to users and roles
- Test your access control policies

## 🧪 Testing the FGAC UI

### Step-by-Step Testing Guide

1. **Start the services:**
   ```bash
   cd examples/access-control-fgac
   docker-compose -f docker-compose-build.yaml build
   docker-compose up -d
   ```

2. **Wait for services to be ready:**
   ```bash
   # Watch the logs
   docker-compose logs -f lakekeeper
   
   # Check health status
   docker-compose ps
   ```

3. **Access the UI:**
   - Open http://localhost:8181/ui
   - Login with: `alice` / `alice`

4. **Navigate to a table:**
   - Go to Warehouses → Select a warehouse
   - Select a namespace
   - Select a table

5. **Test the FGAC Tab:**
   - Click the **FGAC** tab (should be after "Tasks" tab)
   - You should see:
     - Summary section with stats
     - Column Permissions table
     - Row Policies table
     - "Add Permission" and "Add Policy" buttons

6. **Test Creating a Column Permission:**
   - Click "Add Permission"
   - Fill in the form:
     - Column: Select from dropdown
     - Principal Type: user, role, or group
     - Principal ID: e.g., "alice" or "admin-role"
     - Permission Type: read, write, or owner
   - Click "Save"
   - Should see success message and new row in table

7. **Test Creating a Row Policy:**
   - Click "Add Policy"
   - Fill in the form:
     - Policy Name: e.g., "restrict-sales-region"
     - Principal Type: user, role, or group
     - Principal ID: e.g., "alice"
     - Expression: SQL WHERE clause, e.g., "region = 'US'"
     - Policy Type: filter, deny, or allow
     - Priority: Number (higher = higher priority)
     - Active: Toggle on/off
   - Click "Save"
   - Should see success message and new row in table

8. **Test Editing:**
   - Click the edit icon (pencil) on any row
   - Modify values
   - Click "Save"
   - Should see updated values

9. **Test Deleting:**
   - Click the delete icon (trash) on any row
   - Confirm in the dialog
   - Row should disappear

### Troubleshooting

**Services won't start:**
```bash
# Check if ports are already in use
lsof -i :8181 -i :30080 -i :9090 -i :8888

# Clean everything and restart
docker-compose down -v
docker-compose up -d
```

**FGAC tab shows errors:**
```bash
# Check lakekeeper logs
docker-compose logs lakekeeper | grep -i fgac

# Check for backend API responses
docker-compose logs lakekeeper | grep -i "GET /ui/api/fgac"
```

**Can't see the FGAC tab:**
- Make sure you rebuilt the lakekeeper image: `docker-compose -f docker-compose-build.yaml build`
- Force recreate the container: `docker-compose up -d --force-recreate lakekeeper`
- Check if console is loaded: Look for "Serving UI" in logs

**Data isn't loading:**
- Open browser DevTools → Network tab
- Look for API calls to `/ui/api/fgac/`
- Check response status and body
- Verify backend is forwarding to `/management/v1/warehouse/*/namespace/*/table/*/fgac/configuration`

### Useful Commands

```bash
# Rebuild and restart just lakekeeper
docker-compose -f docker-compose-build.yaml build lakekeeper
docker-compose up -d --force-recreate lakekeeper

# View logs for specific service
docker-compose logs -f lakekeeper
docker-compose logs -f keycloak
docker-compose logs -f openfga

# Check service health
docker-compose ps

# Access keycloak admin console
open http://localhost:30080
# Login: admin / admin

# Access MinIO console
open http://localhost:9001
# Login: minio-root-user / minio-root-password

# Stop everything
docker-compose down

# Clean everything (including data)
docker-compose down -v
```

## FGAC Concepts

### Column Permissions

Control access to specific columns:
- **Read**: View column data
- **Write**: Modify column data
- **Owner**: Full control over column permissions

### Row Policies

Filter rows based on conditions:
- **Filter**: Apply WHERE clause to limit visible rows
- **Deny**: Explicitly deny access to matching rows
- **Allow**: Explicitly allow access to matching rows
- SQL-like filter expressions (e.g., `region = 'US' AND year >= 2024`)
- Priority system for resolving conflicts

### Principal Types

- **User**: Individual user accounts (e.g., "alice", "bob")
- **Role**: Groups of permissions (e.g., "admin-role", "analyst-role")
- **Group**: User groups (e.g., "sales-team", "engineering-team")

## Example FGAC Configuration

```json
{
  "column_permissions": [
    {
      "column_name": "ssn",
      "principal_type": "role",
      "principal_id": "data_analyst",
      "permission_type": "mask",
      "masking_method": "hash"
    },
    {
      "column_name": "salary",
      "principal_type": "role",
      "principal_id": "hr_staff",
      "permission_type": "allow"
    }
  ],
  "row_policies": [
    {
      "policy_name": "regional_access",
      "principal_type": "role",
      "principal_id": "sales_rep",
      "policy_expression": "region = 'WEST'",
      "is_active": true
    }
  ]
}
```

## Authentication

This example uses Keycloak for authentication. Default credentials:
- **Keycloak Admin**: admin/admin
- **Test User**: testuser/password

## Troubleshooting

### Services Not Starting
```bash
# Check service logs
docker-compose logs -f lakekeeper
docker-compose logs -f keycloak
docker-compose logs -f openfga
```

### FGAC UI Not Loading
1. Ensure lakekeeper service is healthy: `docker-compose ps`
2. Check that OpenFGA is running and connected
3. Verify warehouse and table IDs in the URL

### Permission Issues
1. Verify OpenFGA authorization model is loaded
2. Check user roles and permissions in Keycloak
3. Review FGAC policy configurations

## Development

To modify the FGAC implementation:

1. Edit the source code in `crates/lakekeeper/src/api/management/v1/fgac_api.rs`
2. Rebuild the Docker image: `docker-compose -f docker-compose-build.yaml build`
3. Restart the services: `docker-compose -f docker-compose-build.yaml up -d`

## Cleanup

```bash
# Stop all services and remove volumes
docker-compose down -v

# Remove unused Docker resources
docker system prune -f
```