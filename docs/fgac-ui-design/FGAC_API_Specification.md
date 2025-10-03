# FGAC API Specification

## Overview

This document defines the REST API endpoints required to support Fine-Grained Access Control (FGAC) configuration through the Lakekeeper Management UI. These APIs extend the existing OpenFGA-based permission system to support column-level permissions and row-level policies.

## API Endpoints

### Column Permission Management

#### List Column Permissions
```http
GET /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/columns
```

**Parameters:**
- `warehouse_id` (path, required): UUID of the warehouse
- `table_id` (path, required): UUID of the table
- `include_inherited` (query, optional): Include permissions inherited from roles (default: true)
- `user_id` (query, optional): Filter by specific user ID
- `role_id` (query, optional): Filter by specific role ID

**Response:**
```json
{
  "table_id": "12345678-1234-1234-1234-123456789012",
  "table_name": "employees",
  "schema_name": "fgac_test",
  "columns": [
    {
      "column_name": "id",
      "column_type": "INTEGER",
      "permissions": [
        {
          "permission_id": "87654321-4321-4321-4321-210987654321",
          "user_or_role": {
            "type": "user",
            "id": "user-uuid",
            "name": "Anna Chen"
          },
          "permission_type": "allow",
          "masking_rule": null,
          "created_at": "2025-09-29T10:00:00Z",
          "created_by": "admin-user-id"
        }
      ]
    },
    {
      "column_name": "salary",
      "column_type": "DECIMAL",
      "permissions": [
        {
          "permission_id": "87654321-4321-4321-4321-210987654322",
          "user_or_role": {
            "type": "user", 
            "id": "anna-user-uuid",
            "name": "Anna Chen"
          },
          "permission_type": "mask",
          "masking_rule": {
            "method": "null",
            "expression": "NULL"
          },
          "conditions": {
            "time_restrictions": [],
            "ip_restrictions": [],
            "additional_auth_required": false
          },
          "created_at": "2025-09-29T10:00:00Z",
          "created_by": "admin-user-id"
        }
      ]
    }
  ],
  "summary": {
    "total_columns": 7,
    "restricted_columns": 3,
    "total_permissions": 12,
    "affected_users": 4,
    "affected_roles": 2
  }
}
```

#### Create Column Permission
```http
POST /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/columns
```

**Request Body:**
```json
{
  "column_name": "salary",
  "user_or_role": {
    "type": "user",
    "id": "anna-user-uuid"
  },
  "permission_type": "mask",
  "masking_rule": {
    "method": "null",
    "expression": "NULL"
  },
  "conditions": {
    "time_restrictions": [
      {
        "days": ["monday", "tuesday", "wednesday", "thursday", "friday"],
        "start_time": "09:00",
        "end_time": "17:00",
        "timezone": "UTC"
      }
    ],
    "ip_restrictions": ["192.168.1.0/24"],
    "additional_auth_required": false
  }
}
```

**Response:**
```json
{
  "permission_id": "87654321-4321-4321-4321-210987654322",
  "status": "created",
  "validation_result": {
    "is_valid": true,
    "warnings": [],
    "estimated_impact": {
      "affected_queries": 15,
      "performance_impact": "low"
    }
  }
}
```

#### Update Column Permission
```http
PUT /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/columns/{permission_id}
```

**Request/Response:** Similar to create, with permission_id in path.

#### Delete Column Permission
```http
DELETE /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/columns/{permission_id}
```

**Response:**
```json
{
  "status": "deleted",
  "cascade_impact": {
    "dependent_policies": 0,
    "affected_users": 1
  }
}
```

#### Bulk Column Permission Operations
```http
POST /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/columns/bulk
```

**Request Body:**
```json
{
  "operation": "create|update|delete",
  "permissions": [
    {
      "column_name": "salary",
      "user_or_role": {"type": "user", "id": "user1"},
      "permission_type": "mask",
      "masking_rule": {"method": "null"}
    },
    {
      "column_name": "email", 
      "user_or_role": {"type": "role", "id": "role1"},
      "permission_type": "mask",
      "masking_rule": {"method": "partial", "expression": "LEFT(email, 3) || '*****@' || SUBSTRING(email FROM POSITION('@' IN email) + 1)"}
    }
  ]
}
```

### Row Policy Management

#### List Row Policies
```http
GET /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/row-policies
```

**Response:**
```json
{
  "table_id": "12345678-1234-1234-1234-123456789012",
  "policies": [
    {
      "policy_id": "policy-uuid-1",
      "policy_name": "Classification Based Access",
      "description": "Restrict access based on data classification",
      "users_and_roles": [
        {
          "type": "user",
          "id": "anna-user-uuid", 
          "name": "Anna Chen"
        },
        {
          "type": "role",
          "id": "analyst-role-uuid",
          "name": "Data Analyst"
        }
      ],
      "filter_expression": "classification IN ('Public', 'Internal')",
      "policy_type": "predefined",
      "is_active": true,
      "estimated_row_impact": {
        "total_rows": 1250,
        "visible_rows": 750,
        "hidden_rows": 500,
        "percentage_visible": 60.0
      },
      "created_at": "2025-09-29T10:00:00Z",
      "updated_at": "2025-09-29T14:30:00Z",
      "created_by": "admin-user-id"
    }
  ],
  "summary": {
    "total_policies": 2,
    "active_policies": 2,
    "affected_users": 3,
    "affected_roles": 1,
    "overall_row_impact": {
      "most_restrictive_view": 600,
      "least_restrictive_view": 1250
    }
  }
}
```

#### Create Row Policy
```http
POST /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/row-policies
```

**Request Body:**
```json
{
  "policy_name": "Engineering Department Access",
  "description": "Engineers can only see their department data and public info from others",
  "users_and_roles": [
    {
      "type": "user",
      "id": "anna-user-uuid"
    },
    {
      "type": "role", 
      "id": "engineering-role-uuid"
    }
  ],
  "policy_type": "custom",
  "filter_expression": "(department = 'Engineering' OR (department != 'Engineering' AND classification = 'Public')) AND job_level < 8",
  "is_active": true
}
```

#### Validate Row Policy
```http
POST /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/row-policies/validate
```

**Request Body:**
```json
{
  "filter_expression": "classification IN ('Public', 'Internal') AND department != 'Executive'",
  "users_and_roles": [
    {"type": "user", "id": "anna-user-uuid"}
  ]
}
```

**Response:**
```json
{
  "is_valid": true,
  "syntax_errors": [],
  "warnings": [
    "Policy may result in zero rows for some users"
  ],
  "estimated_impact": {
    "total_rows": 1250,
    "affected_users": [
      {
        "user_id": "anna-user-uuid",
        "user_name": "Anna Chen", 
        "visible_rows": 680,
        "percentage": 54.4
      }
    ],
    "performance_impact": "medium",
    "query_complexity": "moderate"
  },
  "sample_query": "SELECT * FROM employees WHERE (classification IN ('Public', 'Internal') AND department != 'Executive')",
  "column_dependencies": ["classification", "department"]
}
```

#### Test Row Policy
```http
POST /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/row-policies/test
```

**Request Body:**
```json
{
  "filter_expression": "department = 'Engineering'",
  "test_user_id": "anna-user-uuid",
  "limit": 10
}
```

**Response:**
```json
{
  "test_results": {
    "query_executed": "SELECT id, name, department FROM employees WHERE department = 'Engineering' LIMIT 10",
    "execution_time_ms": 45,
    "rows_returned": 8,
    "sample_data": [
      {"id": 1, "name": "Anna Chen", "department": "Engineering"},
      {"id": 5, "name": "John Doe", "department": "Engineering"}
    ]
  },
  "performance_metrics": {
    "query_time": "45ms",
    "index_usage": ["idx_department"],
    "estimated_cost": "low"
  }
}
```

### FGAC Configuration Management

#### Get FGAC Configuration Summary
```http
GET /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/fgac-config
```

**Response:**
```json
{
  "table_info": {
    "table_id": "12345678-1234-1234-1234-123456789012",
    "table_name": "employees",
    "schema_name": "fgac_test",
    "total_columns": 7,
    "total_rows": 1250
  },
  "fgac_status": {
    "column_masking_enabled": true,
    "row_filtering_enabled": true,
    "last_updated": "2025-09-29T14:30:00Z",
    "updated_by": "admin-user-id"
  },
  "column_summary": {
    "total_columns": 7,
    "restricted_columns": 3,
    "column_permissions": 12
  },
  "row_policy_summary": {
    "active_policies": 2,
    "affected_users": 3,
    "affected_roles": 1
  },
  "integration_status": {
    "opa_policy_sync": "synchronized",
    "trino_configuration": "active",
    "last_sync": "2025-09-29T14:32:00Z"
  }
}
```

#### Get User Access Summary
```http
GET /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/access-summary
```

**Parameters:**
- `user_id` (query, optional): Filter by specific user
- `include_roles` (query, optional): Include role-based access (default: true)

**Response:**
```json
{
  "table_id": "12345678-1234-1234-1234-123456789012",
  "access_summary": [
    {
      "user": {
        "user_id": "anna-user-uuid",
        "user_name": "Anna Chen",
        "department": "Engineering",
        "roles": ["Engineering", "Employee"]
      },
      "column_access": {
        "total_columns": 7,
        "accessible_columns": 4,
        "masked_columns": 3,
        "blocked_columns": 0,
        "details": [
          {"column": "id", "access": "allow"},
          {"column": "name", "access": "allow"},
          {"column": "department", "access": "allow"},
          {"column": "salary", "access": "mask", "method": "null"},
          {"column": "email", "access": "mask", "method": "null"},
          {"column": "phone", "access": "mask", "method": "null"},
          {"column": "classification", "access": "allow"}
        ]
      },
      "row_access": {
        "total_rows": 1250,
        "visible_rows": 750,
        "percentage_visible": 60.0,
        "applied_policies": [
          "Classification Based Access",
          "Department Restriction"
        ]
      },
      "last_access": "2025-09-29T09:15:00Z",
      "access_frequency": {
        "queries_last_24h": 15,
        "queries_last_7d": 87
      }
    }
  ],
  "summary_statistics": {
    "total_users_with_access": 12,
    "total_roles_with_access": 3,
    "fully_restricted_users": 1,
    "partially_restricted_users": 4,
    "unrestricted_users": 7
  }
}
```

### Policy Templates

#### List Policy Templates
```http
GET /management/v1/permissions/templates
```

**Response:**
```json
{
  "templates": [
    {
      "template_id": "hr-department-template",
      "template_name": "HR Department Access",
      "description": "Full access to all employee data including salary and personal information",
      "category": "department",
      "column_rules": [
        {
          "column_pattern": "*",
          "permission_type": "allow"
        }
      ],
      "row_rules": [],
      "usage_count": 5,
      "last_used": "2025-09-25T10:00:00Z"
    },
    {
      "template_id": "engineering-template", 
      "template_name": "Engineering Team Access",
      "description": "Department-based filtering with personal data masking",
      "category": "department",
      "column_rules": [
        {
          "column_pattern": "salary|email|phone",
          "permission_type": "mask",
          "masking_rule": {"method": "null"}
        }
      ],
      "row_rules": [
        {
          "filter_expression": "department = 'Engineering' OR classification = 'Public'"
        }
      ],
      "usage_count": 3,
      "last_used": "2025-09-28T14:00:00Z"
    }
  ]
}
```

#### Apply Policy Template
```http
POST /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/apply-template
```

**Request Body:**
```json
{
  "template_id": "engineering-template",
  "users_and_roles": [
    {"type": "user", "id": "anna-user-uuid"},
    {"type": "role", "id": "engineering-role-uuid"}
  ],
  "customizations": {
    "column_overrides": [
      {
        "column_name": "email",
        "permission_type": "mask",
        "masking_rule": {"method": "partial"}
      }
    ],
    "row_filter_additions": [
      "job_level < 8"
    ]
  }
}
```

### Audit and Monitoring

#### Get FGAC Audit Log
```http
GET /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/audit-log
```

**Parameters:**
- `start_date` (query): Start date for audit log (ISO 8601)
- `end_date` (query): End date for audit log (ISO 8601)
- `action_type` (query): Filter by action (create|update|delete|access)
- `user_id` (query): Filter by user who performed action

**Response:**
```json
{
  "audit_entries": [
    {
      "entry_id": "audit-uuid-1",
      "timestamp": "2025-09-29T14:30:00Z",
      "action_type": "create",
      "resource_type": "column_permission",
      "resource_id": "permission-uuid",
      "performed_by": {
        "user_id": "admin-user-uuid",
        "user_name": "Admin User"
      },
      "details": {
        "column_name": "salary",
        "target_user": "anna-user-uuid",
        "permission_type": "mask",
        "masking_method": "null"
      },
      "before_state": null,
      "after_state": {
        "permission_type": "mask",
        "masking_rule": {"method": "null"}
      }
    }
  ],
  "pagination": {
    "total_entries": 45,
    "page": 1,
    "page_size": 20,
    "total_pages": 3
  }
}
```

## Data Models

### Column Permission
```typescript
interface ColumnPermission {
  permission_id: string;
  table_id: string;
  column_name: string;
  user_or_role: UserOrRole;
  permission_type: 'allow' | 'block' | 'mask' | 'custom';
  masking_rule?: MaskingRule;
  conditions?: PermissionConditions;
  created_at: string;
  updated_at: string;
  created_by: string;
}

interface MaskingRule {
  method: 'null' | 'hash' | 'partial' | 'encrypt' | 'custom';
  expression?: string; // SQL expression for custom masking
  parameters?: Record<string, any>; // For parameterized masking
}

interface PermissionConditions {
  time_restrictions?: TimeRestriction[];
  ip_restrictions?: string[];
  additional_auth_required?: boolean;
  context_conditions?: Record<string, any>;
}

interface TimeRestriction {
  days: string[]; // ['monday', 'tuesday', ...]
  start_time: string; // 'HH:MM'
  end_time: string; // 'HH:MM'
  timezone: string;
}
```

### Row Policy
```typescript
interface RowPolicy {
  policy_id: string;
  table_id: string;
  policy_name: string;
  description?: string;
  users_and_roles: UserOrRole[];
  filter_expression: string; // SQL WHERE clause
  policy_type: 'predefined' | 'custom' | 'template';
  is_active: boolean;
  priority?: number; // For policy ordering
  estimated_row_impact?: RowImpactEstimate;
  created_at: string;
  updated_at: string;
  created_by: string;
}

interface RowImpactEstimate {
  total_rows: number;
  visible_rows: number;
  hidden_rows: number;
  percentage_visible: number;
  last_calculated: string;
}
```

### Common Types
```typescript
interface UserOrRole {
  type: 'user' | 'role';
  id: string;
  name?: string;
}

interface ValidationResult {
  is_valid: boolean;
  syntax_errors: string[];
  warnings: string[];
  estimated_impact?: any;
}
```

## Error Handling

### Standard Error Response
```json
{
  "error": {
    "code": "FGAC_VALIDATION_ERROR",
    "message": "Column permission validation failed",
    "details": {
      "field": "masking_rule.expression",
      "reason": "Invalid SQL syntax",
      "suggestion": "Check SQL syntax and column references"
    }
  },
  "request_id": "req-uuid-123"
}
```

### Common Error Codes
- `FGAC_COLUMN_NOT_FOUND`: Referenced column doesn't exist in table
- `FGAC_USER_NOT_FOUND`: Referenced user ID doesn't exist
- `FGAC_ROLE_NOT_FOUND`: Referenced role ID doesn't exist
- `FGAC_POLICY_CONFLICT`: New policy conflicts with existing policies
- `FGAC_SYNTAX_ERROR`: Invalid SQL syntax in filter expression
- `FGAC_PERMISSION_DENIED`: Insufficient permissions to create/modify FGAC rules
- `FGAC_DEPENDENCY_ERROR`: Cannot delete due to dependent policies
- `FGAC_PERFORMANCE_WARNING`: Policy may cause performance issues

## Authentication & Authorization

All FGAC API endpoints require:
1. Valid bearer token authentication
2. Appropriate OpenFGA permissions:
   - `CanManageColumnPermissions` for column permission operations
   - `CanManageRowPolicies` for row policy operations
   - `CanReadAssignments` for viewing existing permissions
   - `CanGrantManageGrants` for bulk operations

## Rate Limiting

- Policy validation endpoints: 10 requests per minute per user
- Bulk operations: 5 requests per minute per user
- Standard CRUD operations: 100 requests per minute per user
- Audit log queries: 20 requests per minute per user

## Integration Notes

### OPA Policy Generation
The API automatically generates corresponding OPA policies when FGAC rules are created or updated. The policies are deployed to the configured OPA instance and Trino configuration is updated accordingly.

### Performance Considerations
- Column permission checks are cached for 5 minutes
- Row policy impact estimates are recalculated daily or when table data changes significantly
- Bulk operations are processed asynchronously for large permission sets

### Backward Compatibility
All existing table-level permission APIs remain unchanged. FGAC features are additive and don't affect existing authorization workflows.