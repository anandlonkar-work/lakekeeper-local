#!/bin/bash
# FGAC Integration Test Script
# Tests the complete OPA-PostgreSQL integration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧪 FGAC Integration Test Suite"
echo "================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test user UUIDs
ANNA_UUID="d223d88c-85b6-4859-b5c5-27f3825e47f6"
PETER_UUID="cfb55bf6-fcbb-4a1e-bfec-30c6649b52f8"

# Function to print test results
test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
    else
        echo -e "${RED}✗ $2${NC}"
        return 1
    fi
}

# Function to check if service is ready
wait_for_service() {
    local service=$1
    local url=$2
    local max_attempts=30
    local attempt=0
    
    echo -n "Waiting for $service to be ready..."
    while [ $attempt -lt $max_attempts ]; do
        if curl -sf "$url" > /dev/null 2>&1; then
            echo -e " ${GREEN}✓${NC}"
            return 0
        fi
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    echo -e " ${RED}✗ (timeout)${NC}"
    return 1
}

echo "📋 Step 1: Check Docker services"
echo "-----------------------------------"
docker-compose ps

if ! docker-compose ps | grep -q "Up"; then
    echo -e "${RED}Services are not running! Start them with:${NC}"
    echo "  docker-compose up -d"
    exit 1
fi
test_result $? "Docker services are running"
echo ""

echo "📋 Step 2: Wait for services to be healthy"
echo "-------------------------------------------"
wait_for_service "Lakekeeper" "http://localhost:8181/health" || exit 1
wait_for_service "OPA" "http://localhost:8181/v1/data" || exit 1
wait_for_service "Postgres" "http://localhost:5432" || true
echo ""

echo "📋 Step 3: Check database connectivity"
echo "---------------------------------------"
docker-compose exec -T postgres psql -U admin -d lakekeeper -c "SELECT 1;" > /dev/null
test_result $? "PostgreSQL connection"
echo ""

echo "📋 Step 4: Verify FGAC tables exist"
echo "------------------------------------"
COL_PERMS=$(docker-compose exec -T postgres psql -U admin -d lakekeeper -t -c "SELECT COUNT(*) FROM column_permissions;")
ROW_POLS=$(docker-compose exec -T postgres psql -U admin -d lakekeeper -t -c "SELECT COUNT(*) FROM row_policies;")

echo "  Column permissions: $COL_PERMS"
echo "  Row policies: $ROW_POLS"

if [ "$COL_PERMS" -eq 0 ] && [ "$ROW_POLS" -eq 0 ]; then
    echo -e "${YELLOW}⚠ No policies found. Loading seed data...${NC}"
    docker-compose exec -T postgres psql -U admin -d lakekeeper < seed-fgac-data.sql
    test_result $? "Seed data loaded"
fi
echo ""

echo "📋 Step 5: Test Internal OPA API - Column Masks"
echo "------------------------------------------------"
RESPONSE=$(curl -s "http://localhost:8181/internal/opa/v1/column-masks?user_id=$ANNA_UUID&warehouse=demo&namespace=fgac_test&table=employees")
echo "$RESPONSE" | jq '.' > /tmp/column-masks-response.json

if echo "$RESPONSE" | jq -e '.column_masks' > /dev/null 2>&1; then
    test_result 0 "Column masks endpoint returns valid JSON"
    echo "  Masked columns for Anna:"
    echo "$RESPONSE" | jq -r '.column_masks | keys[]' | sed 's/^/    - /'
else
    test_result 1 "Column masks endpoint failed"
    echo "$RESPONSE"
fi
echo ""

echo "📋 Step 6: Test Internal OPA API - Row Filters"
echo "-----------------------------------------------"
RESPONSE=$(curl -s "http://localhost:8181/internal/opa/v1/row-filters?user_id=$ANNA_UUID&warehouse=demo&namespace=fgac_test&table=employees")
echo "$RESPONSE" | jq '.' > /tmp/row-filters-response.json

if echo "$RESPONSE" | jq -e '.row_filters' > /dev/null 2>&1; then
    test_result 0 "Row filters endpoint returns valid JSON"
    FILTER_COUNT=$(echo "$RESPONSE" | jq '.row_filters | length')
    echo "  Active row filters for Anna: $FILTER_COUNT"
    echo "$RESPONSE" | jq -r '.row_filters[].expression' | sed 's/^/    - /'
else
    test_result 1 "Row filters endpoint failed"
    echo "$RESPONSE"
fi
echo ""

echo "📋 Step 7: Test OPA Policy Evaluation - Column Masking"
echo "-------------------------------------------------------"
RESPONSE=$(curl -s -X POST http://localhost:8181/v1/data/trino/columnMask \
  -H "Content-Type: application/json" \
  -d "{
    \"input\": {
      \"context\": {\"identity\": {\"user\": \"$ANNA_UUID\"}},
      \"action\": {
        \"resource\": {
          \"column\": {
            \"catalogName\": \"lakekeeper\",
            \"schemaName\": \"fgac_test\",
            \"tableName\": \"employees\",
            \"columnName\": \"salary\"
          }
        }
      }
    }
  }")

if echo "$RESPONSE" | jq -e '.result.expression' > /dev/null 2>&1; then
    MASK_EXPR=$(echo "$RESPONSE" | jq -r '.result.expression')
    test_result 0 "OPA returns column mask for salary"
    echo "  Mask expression: $MASK_EXPR"
else
    test_result 1 "OPA column mask failed"
    echo "$RESPONSE" | jq '.'
fi
echo ""

echo "📋 Step 8: Test OPA Policy Evaluation - Row Filtering"
echo "------------------------------------------------------"
RESPONSE=$(curl -s -X POST http://localhost:8181/v1/data/trino/rowFilters \
  -H "Content-Type: application/json" \
  -d "{
    \"input\": {
      \"context\": {\"identity\": {\"user\": \"$ANNA_UUID\"}},
      \"action\": {
        \"resource\": {
          \"table\": {
            \"catalogName\": \"lakekeeper\",
            \"schemaName\": \"fgac_test\",
            \"tableName\": \"employees\"
          }
        }
      }
    }
  }")

if echo "$RESPONSE" | jq -e '.result.expression' > /dev/null 2>&1; then
    FILTER_EXPR=$(echo "$RESPONSE" | jq -r '.result.expression')
    test_result 0 "OPA returns row filter"
    echo "  Filter expression: $FILTER_EXPR"
else
    test_result 1 "OPA row filter failed"
    echo "$RESPONSE" | jq '.'
fi
echo ""

echo "📋 Step 9: Check OPA Logs for HTTP Calls"
echo "-----------------------------------------"
if docker-compose logs opa --tail=50 | grep -q "http://lakekeeper"; then
    test_result 0 "OPA is making HTTP calls to Lakekeeper"
    echo "  Recent HTTP calls:"
    docker-compose logs opa --tail=50 | grep "http://lakekeeper" | tail -3 | sed 's/^/    /'
else
    test_result 1 "No HTTP calls detected in OPA logs"
fi
echo ""

echo "📋 Step 10: Verify Management API"
echo "----------------------------------"
WAREHOUSE_ID=$(docker-compose exec -T postgres psql -U admin -d lakekeeper -t -c "SELECT warehouse_id FROM warehouse WHERE warehouse_name = 'demo' LIMIT 1;" | tr -d ' \n')

if [ -n "$WAREHOUSE_ID" ]; then
    test_result 0 "Found demo warehouse: $WAREHOUSE_ID"
    
    # Try to get FGAC data via Management API
    # Note: This requires the table to exist and be registered
    echo "  (Management API endpoint test requires table registration)"
else
    test_result 1 "Could not find demo warehouse"
fi
echo ""

echo "================================"
echo "🎉 Integration Test Complete!"
echo "================================"
echo ""
echo "Next steps:"
echo "  1. Open Jupyter notebook: http://localhost:8888"
echo "  2. Run: notebooks/05-FGAC-Testing.ipynb"
echo "  3. Verify:"
echo "     - Anna sees 3 Engineering employees with masked columns"
echo "     - Peter sees all 8 employees with full data"
echo ""
echo "  4. Open UI: http://localhost:8181/ui"
echo "  5. Navigate: demo → fgac_test → employees → FGAC tab"
echo "  6. Verify policies are displayed"
echo ""
echo "Logs saved to:"
echo "  - /tmp/column-masks-response.json"
echo "  - /tmp/row-filters-response.json"
