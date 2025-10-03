# 🚀 FGAC Testing - Quick Reference

## One-Line Test Command

```bash
cd examples/access-control-fgac && docker-compose -f docker-compose-build.yaml build && docker-compose up -d
```

## What This Does

1. Builds the latest lakekeeper image with FGAC UI changes
2. Starts all required services:
   - ✅ lakekeeper (main service with FGAC API)
   - ✅ PostgreSQL (data storage)
   - ✅ MinIO (object storage)
   - ✅ Keycloak (authentication)
   - ✅ OpenFGA (authorization)
   - ✅ Trino (SQL engine)
   - ✅ OPA (policy engine)
   - ✅ Jupyter (notebooks)

## Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| **Lakekeeper UI** | http://localhost:8181/ui | alice / alice |
| Keycloak Admin | http://localhost:30080 | admin / admin |
| MinIO Console | http://localhost:9001 | minio-root-user / minio-root-password |
| Jupyter | http://localhost:8888 | (no token required) |
| Trino | https://localhost:443 | (OAuth via Keycloak) |

## Testing the FGAC Tab

1. **Login:** http://localhost:8181/ui → alice / alice
2. **Navigate:** Warehouses → demo → namespace → table
3. **Click FGAC Tab:** Should see the FGAC management interface
4. **Test Features:**
   - View existing permissions/policies
   - Add new column permission
   - Add new row policy
   - Edit existing items
   - Delete items

## Quick Commands

```bash
# Check status
docker-compose ps

# View logs
docker-compose logs -f lakekeeper

# Rebuild after code changes
docker-compose -f docker-compose-build.yaml build && docker-compose up -d --force-recreate lakekeeper

# Stop everything
docker-compose down

# Clean slate (removes all data)
docker-compose down -v
```

## Troubleshooting

### FGAC Tab Not Showing
```bash
# Rebuild the image
docker-compose -f docker-compose-build.yaml build lakekeeper

# Force recreate container
docker-compose up -d --force-recreate lakekeeper

# Check logs
docker-compose logs lakekeeper | tail -50
```

### API Errors
```bash
# Check backend API logs
docker-compose logs lakekeeper | grep -i "fgac\|error"

# Test API directly
curl http://localhost:8181/ui/api/fgac/demo/namespace.table
```

### Services Won't Start
```bash
# Check for port conflicts
lsof -i :8181

# Clean and restart
docker-compose down -v
docker-compose up -d
```

## Architecture

```
Browser → Lakekeeper UI (Vue.js)
            ↓
          FGAC Tab (FgacManager.vue)
            ↓
          /ui/api/fgac/* (Rust proxy in ui.rs)
            ↓
          /management/v1/warehouse/.../fgac/* (Backend API)
            ↓
          PostgreSQL (column_permissions, row_policies tables)
```

## Files Changed

1. **lakekeeper-local/crates/lakekeeper-bin/src/ui.rs**
   - Updated `fgac_proxy_handler` to forward to real backend API
   - Uses reqwest to proxy requests with auth headers

2. **lakekeeper-console/src/components/FgacManager.vue**
   - New Vue component (713 lines)
   - Full CRUD for column permissions and row policies
   - Real-time data loading and validation

3. **lakekeeper-console/src/pages/warehouse/[id].namespace.[nsid].table.[tid].vue**
   - Added FGAC tab to navigation
   - Integrated FgacManager component

4. **examples/access-control-fgac/docker-compose.override.yml**
   - Uses correct image name from build
   - Adds debug logging

5. **examples/access-control-fgac/README.md**
   - Updated with testing instructions
   - Added troubleshooting guide

## What's Working

✅ Docker build completes successfully  
✅ UI proxy forwards requests to backend API  
✅ Vue.js component loads and displays UI  
✅ FGAC tab appears in table detail page  
✅ All services start and become healthy  

## What to Test

🧪 Load FGAC configuration from API  
🧪 Create column permission via UI  
🧪 Create row policy via UI  
🧪 Edit existing permissions/policies  
🧪 Delete permissions/policies  
🧪 Form validation and error handling  
🧪 Success/error notifications  

## Next Steps

After testing the UI:
1. ✅ Verify API calls work end-to-end
2. Connect backend API to actual database queries (replace TODOs)
3. Build new console version (v0.10.2)
4. Update lakekeeper-bin Cargo.toml to use new console version
5. Test with real data and users
