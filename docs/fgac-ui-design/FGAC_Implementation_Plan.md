# FGAC UI Implementation Plan

## Overview

This document provides a detailed, step-by-step implementation plan for integrating Fine-Grained Access Control (FGAC) features into the Lakekeeper Management UI. The implementation extends the existing Swagger UI-based interface with configurable column-level and row-level permissions.

## Implementation Phases

### Phase 1: Database Schema and Core Models (Week 1-2)

#### 1.1 Database Schema Changes

**New Tables to Create:**

```sql
-- Column permissions table
CREATE TABLE column_permissions (
    permission_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id UUID NOT NULL REFERENCES tabular(tabular_id) ON DELETE CASCADE,
    column_name VARCHAR(255) NOT NULL,
    user_id UUID REFERENCES "user"(user_id) ON DELETE CASCADE,
    role_id UUID REFERENCES "role"(role_id) ON DELETE CASCADE,
    permission_type VARCHAR(50) NOT NULL CHECK (permission_type IN ('allow', 'block', 'mask', 'custom')),
    masking_method VARCHAR(50) CHECK (masking_method IN ('null', 'hash', 'partial', 'encrypt', 'custom')),
    masking_expression TEXT,
    conditions JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID NOT NULL REFERENCES "user"(user_id),
    
    -- Ensure either user_id or role_id is set, but not both
    CONSTRAINT check_user_or_role CHECK (
        (user_id IS NOT NULL AND role_id IS NULL) OR 
        (user_id IS NULL AND role_id IS NOT NULL)
    ),
    
    -- Unique constraint to prevent duplicate permissions
    UNIQUE(table_id, column_name, user_id, role_id)
);

-- Row policies table
CREATE TABLE row_policies (
    policy_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id UUID NOT NULL REFERENCES tabular(tabular_id) ON DELETE CASCADE,
    policy_name VARCHAR(255) NOT NULL,
    description TEXT,
    filter_expression TEXT NOT NULL,
    policy_type VARCHAR(50) NOT NULL CHECK (policy_type IN ('predefined', 'custom', 'template')),
    is_active BOOLEAN DEFAULT TRUE,
    priority INTEGER DEFAULT 0,
    estimated_total_rows INTEGER,
    estimated_visible_rows INTEGER,
    last_impact_calculated TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID NOT NULL REFERENCES "user"(user_id)
);

-- Row policy assignments (many-to-many relationship)
CREATE TABLE row_policy_assignments (
    assignment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_id UUID NOT NULL REFERENCES row_policies(policy_id) ON DELETE CASCADE,
    user_id UUID REFERENCES "user"(user_id) ON DELETE CASCADE,
    role_id UUID REFERENCES "role"(role_id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID NOT NULL REFERENCES "user"(user_id),
    
    -- Ensure either user_id or role_id is set, but not both
    CONSTRAINT check_user_or_role CHECK (
        (user_id IS NOT NULL AND role_id IS NULL) OR 
        (user_id IS NULL AND role_id IS NOT NULL)
    ),
    
    -- Unique constraint to prevent duplicate assignments
    UNIQUE(policy_id, user_id, role_id)
);

-- Policy templates table
CREATE TABLE fgac_policy_templates (
    template_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    category VARCHAR(100),
    column_rules JSONB NOT NULL DEFAULT '[]',
    row_rules JSONB NOT NULL DEFAULT '[]',
    usage_count INTEGER DEFAULT 0,
    last_used TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID NOT NULL REFERENCES "user"(user_id)
);

-- FGAC audit log
CREATE TABLE fgac_audit_log (
    entry_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id UUID NOT NULL REFERENCES tabular(tabular_id) ON DELETE CASCADE,
    action_type VARCHAR(50) NOT NULL CHECK (action_type IN ('create', 'update', 'delete', 'access', 'policy_applied')),
    resource_type VARCHAR(50) NOT NULL CHECK (resource_type IN ('column_permission', 'row_policy', 'template', 'bulk_operation')),
    resource_id UUID,
    performed_by UUID NOT NULL REFERENCES "user"(user_id),
    before_state JSONB,
    after_state JSONB,
    details JSONB,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**Indexes for Performance:**

```sql
-- Column permissions indexes
CREATE INDEX idx_column_permissions_table_id ON column_permissions(table_id);
CREATE INDEX idx_column_permissions_user_id ON column_permissions(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_column_permissions_role_id ON column_permissions(role_id) WHERE role_id IS NOT NULL;
CREATE INDEX idx_column_permissions_column_name ON column_permissions(table_id, column_name);

-- Row policies indexes  
CREATE INDEX idx_row_policies_table_id ON row_policies(table_id);
CREATE INDEX idx_row_policies_active ON row_policies(table_id, is_active);
CREATE INDEX idx_row_policy_assignments_policy_id ON row_policy_assignments(policy_id);
CREATE INDEX idx_row_policy_assignments_user_id ON row_policy_assignments(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_row_policy_assignments_role_id ON row_policy_assignments(role_id) WHERE role_id IS NOT NULL;

-- Audit log indexes
CREATE INDEX idx_fgac_audit_log_table_id ON fgac_audit_log(table_id);
CREATE INDEX idx_fgac_audit_log_timestamp ON fgac_audit_log(timestamp);
CREATE INDEX idx_fgac_audit_log_performed_by ON fgac_audit_log(performed_by);
```

#### 1.2 Rust Data Models

**File:** `crates/lakekeeper/src/service/catalog.rs`

```rust
// Add to existing catalog.rs

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[cfg_attr(feature = "utoipa", derive(utoipa::ToSchema))]
pub struct ColumnPermission {
    pub permission_id: ColumnPermissionId,
    pub table_id: TableId,
    pub column_name: String,
    pub user_id: Option<UserId>,
    pub role_id: Option<RoleId>,
    pub permission_type: ColumnPermissionType,
    pub masking_rule: Option<MaskingRule>,
    pub conditions: Option<PermissionConditions>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
    pub created_by: UserId,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[cfg_attr(feature = "utoipa", derive(utoipa::ToSchema))]
pub enum ColumnPermissionType {
    Allow,
    Block,
    Mask,
    Custom,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[cfg_attr(feature = "utoipa", derive(utoipa::ToSchema))]
pub struct MaskingRule {
    pub method: MaskingMethod,
    pub expression: Option<String>,
    pub parameters: Option<serde_json::Value>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[cfg_attr(feature = "utoipa", derive(utoipa::ToSchema))]
pub enum MaskingMethod {
    Null,
    Hash, 
    Partial,
    Encrypt,
    Custom,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[cfg_attr(feature = "utoipa", derive(utoipa::ToSchema))]
pub struct RowPolicy {
    pub policy_id: RowPolicyId,
    pub table_id: TableId,
    pub policy_name: String,
    pub description: Option<String>,
    pub filter_expression: String,
    pub policy_type: PolicyType,
    pub is_active: bool,
    pub priority: i32,
    pub estimated_impact: Option<RowImpactEstimate>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
    pub created_by: UserId,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[cfg_attr(feature = "utoipa", derive(utoipa::ToSchema))]
pub struct RowImpactEstimate {
    pub total_rows: i64,
    pub visible_rows: i64,
    pub hidden_rows: i64,
    pub percentage_visible: f64,
    pub last_calculated: chrono::DateTime<chrono::Utc>,
}

// New ID types
uuid_wrapper!(ColumnPermissionId);
uuid_wrapper!(RowPolicyId);
```

#### 1.3 Database Migration Files

**File:** `crates/lakekeeper/migrations/0030_add_fgac_tables.sql`

```sql
-- Migration to add FGAC tables
-- Include all the CREATE TABLE statements from section 1.1
```

### Phase 2: Core API Implementation (Week 3-4)

#### 2.1 FGAC Management Module

**File:** `crates/lakekeeper/src/api/management/v1/fgac.rs`

```rust
// New module for FGAC management
use axum::{
    extract::{Path, Query},
    response::{IntoResponse, Response},
    routing::{get, post, put, delete},
    Extension, Json, Router,
};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::{
    api::{management::v1::ApiServer, ApiContext},
    request_metadata::RequestMetadata,
    service::{
        authz::Authorizer,
        catalog::{ColumnPermission, RowPolicy},
        Catalog, SecretStore, State,
    },
    WarehouseId, TableId,
};

#[derive(Debug, Deserialize, ToSchema)]
pub struct CreateColumnPermissionRequest {
    pub column_name: String,
    pub user_or_role: UserOrRoleIdentifier,
    pub permission_type: ColumnPermissionType,
    pub masking_rule: Option<MaskingRule>,
    pub conditions: Option<PermissionConditions>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CreateRowPolicyRequest {
    pub policy_name: String,
    pub description: Option<String>,
    pub users_and_roles: Vec<UserOrRoleIdentifier>,
    pub filter_expression: String,
    pub policy_type: PolicyType,
    pub is_active: bool,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct FgacConfigSummaryResponse {
    pub table_info: TableInfo,
    pub fgac_status: FgacStatus,
    pub column_summary: ColumnSummary,
    pub row_policy_summary: RowPolicySummary,
    pub integration_status: IntegrationStatus,
}

// API endpoint implementations
impl<C: Catalog, A: Authorizer, S: SecretStore> ApiServer<C, A, S> {
    pub async fn list_column_permissions(
        warehouse_id: WarehouseId,
        table_id: TableId,
        state: ApiContext<State<A, C, S>>,
        request_metadata: RequestMetadata,
    ) -> Result<ListColumnPermissionsResponse> {
        // Implementation
    }

    pub async fn create_column_permission(
        warehouse_id: WarehouseId,
        table_id: TableId,
        request: CreateColumnPermissionRequest,
        state: ApiContext<State<A, C, S>>,
        request_metadata: RequestMetadata,
    ) -> Result<CreateColumnPermissionResponse> {
        // Implementation
    }

    // Additional endpoint implementations...
}
```

#### 2.2 OpenFGA Extensions

**File:** `crates/lakekeeper/src/service/authz/implementations/openfga/fgac_extensions.rs`

```rust
// Extensions to OpenFGA for FGAC support
use super::*;

impl OpenFGAAuthorizer {
    pub async fn create_column_permission(
        &self,
        metadata: &RequestMetadata,
        table_id: TableId,
        column_permission: &ColumnPermission,
    ) -> Result<()> {
        // Create OpenFGA relationships for column permissions
        let column_object = format!("table:{}#column:{}", table_id, column_permission.column_name);
        
        let relation = match column_permission.permission_type {
            ColumnPermissionType::Allow => "can_read",
            ColumnPermissionType::Block => "blocked",
            ColumnPermissionType::Mask => "masked",
            ColumnPermissionType::Custom => "custom",
        };

        let user_or_role = if let Some(user_id) = column_permission.user_id {
            format!("user:{}", user_id)
        } else if let Some(role_id) = column_permission.role_id {
            format!("role:{}", role_id)
        } else {
            return Err(Error::InvalidPermissionTarget);
        };

        self.write_relationship(&column_object, relation, &user_or_role).await?;
        Ok(())
    }

    pub async fn create_row_policy(
        &self,
        metadata: &RequestMetadata,
        table_id: TableId,
        row_policy: &RowPolicy,
        assignments: &[RowPolicyAssignment],
    ) -> Result<()> {
        // Create OpenFGA relationships for row policies
        let policy_object = format!("table:{}#row_policy:{}", table_id, row_policy.policy_id);

        for assignment in assignments {
            let user_or_role = if let Some(user_id) = assignment.user_id {
                format!("user:{}", user_id)
            } else if let Some(role_id) = assignment.role_id {
                format!("role:{}", role_id)
            } else {
                continue;
            };

            self.write_relationship(&policy_object, "applies_to", &user_or_role).await?;
        }

        Ok(())
    }
}
```

#### 2.3 Catalog Trait Extensions

**File:** `crates/lakekeeper/src/service/catalog.rs` (additions)

```rust
// Add to existing Catalog trait
#[async_trait::async_trait]
pub trait Catalog {
    // ... existing methods ...

    // Column permission methods
    async fn create_column_permission(
        &self,
        column_permission: &CreateColumnPermissionRequest,
        transaction: Self::Transaction,
    ) -> Result<ColumnPermission>;

    async fn list_column_permissions(
        &self,
        table_id: TableId,
        transaction: Self::Transaction,
    ) -> Result<Vec<ColumnPermission>>;

    async fn update_column_permission(
        &self,
        permission_id: ColumnPermissionId,
        updates: &UpdateColumnPermissionRequest,
        transaction: Self::Transaction,
    ) -> Result<ColumnPermission>;

    async fn delete_column_permission(
        &self,
        permission_id: ColumnPermissionId,
        transaction: Self::Transaction,
    ) -> Result<()>;

    // Row policy methods
    async fn create_row_policy(
        &self,
        row_policy: &CreateRowPolicyRequest,
        assignments: &[UserOrRoleIdentifier],
        transaction: Self::Transaction,
    ) -> Result<RowPolicy>;

    async fn list_row_policies(
        &self,
        table_id: TableId,
        transaction: Self::Transaction,
    ) -> Result<Vec<RowPolicy>>;

    async fn update_row_policy(
        &self,
        policy_id: RowPolicyId,
        updates: &UpdateRowPolicyRequest,
        transaction: Self::Transaction,
    ) -> Result<RowPolicy>;

    async fn delete_row_policy(
        &self,
        policy_id: RowPolicyId,
        transaction: Self::Transaction,
    ) -> Result<()>;

    // Validation and testing methods
    async fn validate_row_policy(
        &self,
        table_id: TableId,
        filter_expression: &str,
        transaction: Self::Transaction,
    ) -> Result<PolicyValidationResult>;

    async fn estimate_row_policy_impact(
        &self,
        table_id: TableId,
        filter_expression: &str,
        transaction: Self::Transaction,
    ) -> Result<RowImpactEstimate>;
}
```

### Phase 3: UI Components Implementation (Week 5-6)

#### 3.1 Enhanced Swagger UI Components

Since Lakekeeper uses Swagger UI, we'll extend it with custom components and JavaScript.

**File:** `crates/lakekeeper/src/api/management/v1/fgac_ui.rs`

```rust
// Custom UI endpoints that serve enhanced interfaces
use axum::{
    response::{Html, IntoResponse},
    routing::get,
    Extension, Router,
};

pub fn fgac_ui_router<C: Catalog, A: Authorizer, S: SecretStore>() -> Router<ApiContext<State<A, C, S>>> {
    Router::new()
        .route("/fgac-dashboard/:warehouse_id/:table_id", get(fgac_dashboard))
        .route("/fgac-column-matrix/:warehouse_id/:table_id", get(column_matrix_ui))
        .route("/fgac-row-policies/:warehouse_id/:table_id", get(row_policies_ui))
}

async fn fgac_dashboard<C: Catalog, A: Authorizer, S: SecretStore>(
    Path((warehouse_id, table_id)): Path<(WarehouseId, TableId)>,
) -> impl IntoResponse {
    Html(include_str!("../../../../../ui/fgac_dashboard.html"))
}

// Additional UI endpoints...
```

#### 3.2 FGAC Dashboard HTML Template

**File:** `crates/lakekeeper/ui/fgac_dashboard.html`

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FGAC Configuration - Lakekeeper</title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
    <script src="https://unpkg.com/alpinejs@3.x.x/dist/cdn.min.js" defer></script>
</head>
<body class="bg-gray-100">
    <div x-data="fgacDashboard()" class="container mx-auto px-4 py-8">
        <!-- FGAC Dashboard Implementation -->
        <div class="bg-white rounded-lg shadow-lg p-6">
            <h1 class="text-3xl font-bold text-gray-900 mb-6">
                Fine-Grained Access Control Configuration
            </h1>
            
            <!-- Table Information -->
            <div class="mb-8">
                <h2 class="text-xl font-semibold mb-4">Table Information</h2>
                <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <div class="bg-blue-50 p-4 rounded-lg">
                        <div class="text-sm text-blue-600">Table Name</div>
                        <div class="text-lg font-semibold" x-text="tableInfo.name"></div>
                    </div>
                    <div class="bg-green-50 p-4 rounded-lg">
                        <div class="text-sm text-green-600">Total Columns</div>
                        <div class="text-lg font-semibold" x-text="tableInfo.totalColumns"></div>
                    </div>
                    <div class="bg-purple-50 p-4 rounded-lg">
                        <div class="text-sm text-purple-600">Total Rows</div>
                        <div class="text-lg font-semibold" x-text="tableInfo.totalRows"></div>
                    </div>
                </div>
            </div>

            <!-- Quick Actions -->
            <div class="mb-8">
                <div class="flex space-x-4">
                    <button @click="showColumnMatrix = true" 
                            class="bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700">
                        📋 Configure Column Permissions
                    </button>
                    <button @click="showRowPolicies = true"
                            class="bg-green-600 text-white px-6 py-2 rounded-lg hover:bg-green-700">
                        🎯 Configure Row Filtering
                    </button>
                    <button @click="showUserSummary = true"
                            class="bg-purple-600 text-white px-6 py-2 rounded-lg hover:bg-purple-700">
                        👥 View User Summary
                    </button>
                </div>
            </div>

            <!-- Column Permission Matrix Modal -->
            <div x-show="showColumnMatrix" x-cloak class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center">
                <div class="bg-white rounded-lg p-6 max-w-6xl w-full mx-4 max-h-full overflow-y-auto">
                    <div class="flex justify-between items-center mb-4">
                        <h3 class="text-xl font-semibold">Column Permission Matrix</h3>
                        <button @click="showColumnMatrix = false" class="text-gray-500 hover:text-gray-700">✕</button>
                    </div>
                    
                    <!-- Column Matrix Implementation -->
                    <div class="overflow-x-auto">
                        <table class="min-w-full border-collapse border border-gray-300">
                            <thead>
                                <tr class="bg-gray-50">
                                    <th class="border border-gray-300 px-4 py-2">User/Role</th>
                                    <template x-for="column in tableInfo.columns">
                                        <th class="border border-gray-300 px-2 py-2" x-text="column.name"></th>
                                    </template>
                                    <th class="border border-gray-300 px-4 py-2">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                <template x-for="user in users">
                                    <tr>
                                        <td class="border border-gray-300 px-4 py-2">
                                            <span class="flex items-center">
                                                <span x-text="user.type === 'user' ? '👤' : '👥'"></span>
                                                <span x-text="user.name" class="ml-2"></span>
                                            </span>
                                        </td>
                                        <template x-for="column in tableInfo.columns">
                                            <td class="border border-gray-300 px-2 py-2 text-center">
                                                <button @click="togglePermission(user.id, column.name)"
                                                        :class="getPermissionIcon(user.id, column.name).class"
                                                        x-text="getPermissionIcon(user.id, column.name).icon">
                                                </button>
                                            </td>
                                        </template>
                                        <td class="border border-gray-300 px-4 py-2">
                                            <button class="text-blue-600 hover:underline mr-2">Edit</button>
                                            <button class="text-red-600 hover:underline">Remove</button>
                                        </td>
                                    </tr>
                                </template>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <!-- Row Policies Modal -->
            <div x-show="showRowPolicies" x-cloak class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center">
                <!-- Row policies implementation -->
            </div>

            <!-- User Summary Modal -->
            <div x-show="showUserSummary" x-cloak class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center">
                <!-- User summary implementation -->
            </div>
        </div>
    </div>

    <script>
        function fgacDashboard() {
            return {
                tableInfo: {
                    name: 'employees',
                    totalColumns: 7,
                    totalRows: 1250,
                    columns: [
                        {name: 'id', type: 'INTEGER'},
                        {name: 'name', type: 'VARCHAR'},
                        {name: 'department', type: 'VARCHAR'},
                        {name: 'salary', type: 'DECIMAL'},
                        {name: 'email', type: 'VARCHAR'},
                        {name: 'phone', type: 'VARCHAR'},
                        {name: 'classification', type: 'VARCHAR'}
                    ]
                },
                users: [
                    {id: 'user1', name: 'Anna Chen', type: 'user'},
                    {id: 'user2', name: 'Peter Admin', type: 'user'},
                    {id: 'role1', name: 'Manager Role', type: 'role'}
                ],
                permissions: {
                    // user/role ID => { column_name => permission_type }
                },
                showColumnMatrix: false,
                showRowPolicies: false,
                showUserSummary: false,

                async init() {
                    await this.loadTableInfo();
                    await this.loadPermissions();
                },

                async loadTableInfo() {
                    // Fetch table information from API
                },

                async loadPermissions() {
                    // Fetch current permissions from API
                },

                getPermissionIcon(userId, columnName) {
                    const permission = this.permissions[userId]?.[columnName] || 'allow';
                    const icons = {
                        allow: {icon: '✅', class: 'text-green-600'},
                        block: {icon: '🚫', class: 'text-red-600'},
                        mask: {icon: '⚪', class: 'text-yellow-600'},
                        custom: {icon: '🎭', class: 'text-purple-600'}
                    };
                    return icons[permission] || icons.allow;
                },

                async togglePermission(userId, columnName) {
                    // Cycle through permission types
                    const current = this.permissions[userId]?.[columnName] || 'allow';
                    const cycle = ['allow', 'mask', 'block', 'allow'];
                    const nextIndex = (cycle.indexOf(current) + 1) % cycle.length;
                    const newPermission = cycle[nextIndex];

                    // Update locally
                    if (!this.permissions[userId]) {
                        this.permissions[userId] = {};
                    }
                    this.permissions[userId][columnName] = newPermission;

                    // Save to API
                    await this.savePermission(userId, columnName, newPermission);
                },

                async savePermission(userId, columnName, permissionType) {
                    // API call to save permission
                }
            }
        }
    </script>
</body>
</html>
```

### Phase 4: Integration and Testing (Week 7-8)

#### 4.1 OPA Policy Generator

**File:** `crates/lakekeeper/src/api/management/v1/opa_integration.rs`

```rust
// OPA policy generation from UI configuration
use std::collections::HashMap;
use serde_json::json;

pub struct OpaFgacPolicyGenerator;

impl OpaFgacPolicyGenerator {
    pub async fn generate_column_masking_policy(
        table_id: TableId,
        permissions: &[ColumnPermission],
    ) -> Result<String> {
        let mut policy_rules = Vec::new();
        
        // Group permissions by user/role
        let mut user_permissions: HashMap<String, Vec<&ColumnPermission>> = HashMap::new();
        
        for permission in permissions {
            let key = if let Some(user_id) = permission.user_id {
                format!("user:{}", user_id)
            } else if let Some(role_id) = permission.role_id {
                format!("role:{}", role_id)
            } else {
                continue;
            };
            
            user_permissions.entry(key).or_default().push(permission);
        }

        // Generate policy rules for each user/role
        for (user_key, user_perms) in user_permissions {
            let mut column_rules = Vec::new();
            
            for perm in user_perms {
                match perm.permission_type {
                    ColumnPermissionType::Mask => {
                        let expression = if let Some(rule) = &perm.masking_rule {
                            match rule.method {
                                MaskingMethod::Null => "NULL".to_string(),
                                MaskingMethod::Hash => format!("md5({})", perm.column_name),
                                MaskingMethod::Custom => rule.expression.clone().unwrap_or("NULL".to_string()),
                                _ => "NULL".to_string(),
                            }
                        } else {
                            "NULL".to_string()
                        };
                        
                        column_rules.push(format!(
                            r#"columnMask := {{"expression": "{}"}} if {{
                                username == "{}"
                                column_resource.columnName == "{}"
                            }}"#,
                            expression, user_key, perm.column_name
                        ));
                    }
                    _ => {}
                }
            }
            
            policy_rules.extend(column_rules);
        }

        let policy = format!(
            r#"package trino

import data.trino
import future.keywords.if

# Auto-generated column masking policy from FGAC UI
user_id := input.context.identity.user
username := get_username(user_id)

# Column masking rules
column_resource := input.action.resource.column

{}

# Default: no masking for unspecified permissions
columnMask := null if {{
    true  # Default case
}}"#,
            policy_rules.join("\n\n")
        );

        Ok(policy)
    }

    pub async fn generate_row_filtering_policy(
        table_id: TableId,
        policies: &[RowPolicy],
        assignments: &[RowPolicyAssignment],
    ) -> Result<String> {
        let mut policy_rules = Vec::new();
        
        // Group assignments by policy
        let mut policy_assignments: HashMap<RowPolicyId, Vec<&RowPolicyAssignment>> = HashMap::new();
        for assignment in assignments {
            policy_assignments.entry(assignment.policy_id).or_default().push(assignment);
        }

        // Generate policy rules
        for policy in policies {
            if !policy.is_active {
                continue;
            }

            if let Some(policy_assignments) = policy_assignments.get(&policy.policy_id) {
                let mut user_conditions = Vec::new();
                
                for assignment in policy_assignments {
                    let user_key = if let Some(user_id) = assignment.user_id {
                        format!("user:{}", user_id)
                    } else if let Some(role_id) = assignment.role_id {
                        format!("role:{}", role_id)
                    } else {
                        continue;
                    };
                    
                    user_conditions.push(format!("username == \"{}\"", user_key));
                }

                if !user_conditions.is_empty() {
                    policy_rules.push(format!(
                        r#"rowFilters contains {{"expression": "{}"}} if {{
                            ({})
                            table_resource.tableName == "{}"
                        }}"#,
                        policy.filter_expression,
                        user_conditions.join(" || "),
                        table_id  // This should be the actual table name
                    ));
                }
            }
        }

        let policy = format!(
            r#"package trino

import data.trino
import future.keywords.if
import future.keywords.contains

# Auto-generated row filtering policy from FGAC UI
user_id := input.context.identity.user
username := get_username(user_id)

# Row filtering rules
table_resource := input.action.resource.table

{}"#,
            policy_rules.join("\n\n")
        );

        Ok(policy)
    }

    pub async fn deploy_policies_to_opa(
        column_policy: &str,
        row_policy: &str,
    ) -> Result<()> {
        // Deploy generated policies to OPA instance
        // This would use the OPA REST API to update policies
        
        let opa_client = reqwest::Client::new();
        
        // Deploy column masking policy
        let column_response = opa_client
            .put("http://opa:8181/v1/policies/trino/columnMask")
            .header("Content-Type", "text/plain")
            .body(column_policy.to_string())
            .send()
            .await?;

        if !column_response.status().is_success() {
            return Err(Error::OpaPolicyDeploymentFailed("columnMask".to_string()));
        }

        // Deploy row filtering policy
        let row_response = opa_client
            .put("http://opa:8181/v1/policies/trino/rowFilters")
            .header("Content-Type", "text/plain")
            .body(row_policy.to_string())
            .send()
            .await?;

        if !row_response.status().is_success() {
            return Err(Error::OpaPolicyDeploymentFailed("rowFilters".to_string()));
        }

        Ok(())
    }
}
```

#### 4.2 Testing Strategy

**File:** `crates/lakekeeper/tests/fgac_integration_tests.rs`

```rust
// Integration tests for FGAC functionality
use lakekeeper::*;

#[tokio::test]
async fn test_column_permission_crud() {
    let test_db = setup_test_database().await;
    let api_context = setup_api_context(test_db).await;
    
    // Test creating column permission
    let create_request = CreateColumnPermissionRequest {
        column_name: "salary".to_string(),
        user_or_role: UserOrRoleIdentifier::User(test_user_id()),
        permission_type: ColumnPermissionType::Mask,
        masking_rule: Some(MaskingRule {
            method: MaskingMethod::Null,
            expression: None,
            parameters: None,
        }),
        conditions: None,
    };

    let response = ApiServer::create_column_permission(
        test_warehouse_id(),
        test_table_id(),
        create_request,
        api_context.clone(),
        test_request_metadata(),
    ).await.unwrap();

    assert_eq!(response.status, "created");
    
    // Test listing permissions
    let list_response = ApiServer::list_column_permissions(
        test_warehouse_id(),
        test_table_id(),
        api_context.clone(),
        test_request_metadata(),
    ).await.unwrap();

    assert_eq!(list_response.columns.len(), 1);
    
    // Test updating permission
    // Test deleting permission
}

#[tokio::test]
async fn test_row_policy_crud() {
    // Similar tests for row policies
}

#[tokio::test]
async fn test_opa_policy_generation() {
    // Test that UI configurations generate correct OPA policies
    let permissions = vec![
        // Test permissions
    ];
    
    let policy = OpaFgacPolicyGenerator::generate_column_masking_policy(
        test_table_id(),
        &permissions,
    ).await.unwrap();
    
    // Verify policy structure and content
    assert!(policy.contains("columnMask :="));
    assert!(policy.contains("NULL"));
}

#[tokio::test]
async fn test_end_to_end_fgac() {
    // End-to-end test that:
    // 1. Creates FGAC configuration via API
    // 2. Generates OPA policies
    // 3. Deploys policies to OPA
    // 4. Tests actual query filtering through Trino
}
```

### Phase 5: Documentation and Deployment (Week 9-10)

#### 5.1 User Documentation

**File:** `docs/fgac-ui-guide/USER_GUIDE.md`

```markdown
# FGAC UI User Guide

## Overview
This guide explains how to use the Fine-Grained Access Control (FGAC) interface in Lakekeeper to configure column-level and row-level permissions for your tables.

## Getting Started

### Accessing FGAC Configuration
1. Navigate to the Lakekeeper Swagger UI at `http://localhost:8181/swagger-ui`
2. Locate your table in the warehouse management section
3. Click "Configure FGAC" button next to the table name
4. The FGAC dashboard will open in a new interface

### Column Permission Matrix
The column permission matrix allows you to configure access to individual columns for users and roles.

#### Permission Types:
- ✅ **Allow**: Full access to column data
- 🚫 **Block**: Complete access denial
- ⚪ **Mask**: Data is hidden/transformed
- 🎭 **Custom**: Custom masking expression

#### Configuring Column Permissions:
1. Click on any cell in the matrix to cycle through permission types
2. For masking permissions, click "Edit" to configure masking method:
   - **NULL**: Replace with NULL value
   - **Partial**: Show partial data (e.g., `****@domain.com`)
   - **Hash**: Show hashed value
   - **Custom**: Define SQL expression

### Row-Level Filtering
Row-level filtering allows you to restrict which rows users can see based on conditions.

#### Creating Row Policies:
1. Click "Configure Row Filtering" 
2. Choose "Add Policy"
3. Select users/roles to apply the policy to
4. Define filter conditions:
   - **Predefined Rules**: Use dropdown selections
   - **Custom SQL**: Write custom WHERE clause expressions

#### Example Policies:
- Department-based: `department = 'Engineering'`
- Classification-based: `classification IN ('Public', 'Internal')`
- Complex rules: `(department = 'Engineering' OR classification = 'Public') AND job_level < 8`

## Best Practices

### Security Considerations
- Always test policies before applying to production
- Use least-privilege principle
- Regularly audit permission assignments
- Monitor query performance impact

### Performance Tips
- Avoid complex custom SQL expressions in row policies
- Use indexed columns in filter conditions
- Test with representative data volumes
- Monitor OPA policy evaluation times

## Troubleshooting

### Common Issues
1. **Policy not taking effect**: Check OPA integration status
2. **Performance issues**: Review filter complexity and indexing
3. **Syntax errors**: Validate SQL expressions before saving
4. **Permission conflicts**: Check for overlapping user/role assignments
```

#### 5.2 Administrator Documentation

**File:** `docs/fgac-ui-guide/ADMIN_GUIDE.md`

```markdown
# FGAC UI Administrator Guide

## Installation and Configuration

### Prerequisites
- Lakekeeper v0.6.0 or later
- OpenFGA configured and running
- OPA configured with Trino integration
- PostgreSQL database with FGAC extensions

### Database Setup
Run the FGAC migration:
```bash
cd lakekeeper
cargo run --bin lakekeeper -- migrate --config config.yaml
```

### Configuration
Add to your Lakekeeper configuration:
```yaml
fgac:
  enabled: true
  ui_enabled: true
  auto_deploy_policies: true
  opa_endpoint: "http://opa:8181"
  policy_sync_interval: "300s"
```

## Monitoring and Maintenance

### Performance Monitoring
- Monitor OPA policy evaluation times
- Track Trino query performance impact
- Review database query patterns for FGAC tables

### Policy Management
- Regular policy audits using audit log API
- Backup policy configurations
- Test policy changes in staging environment

### Troubleshooting
- Check OPA logs for policy evaluation errors
- Verify Trino-OPA connectivity
- Monitor database constraint violations
```

## Success Metrics and Acceptance Criteria

### Functional Requirements ✅
- [ ] Administrators can create column permissions through UI matrix interface
- [ ] Row filtering policies can be configured with predefined and custom rules
- [ ] UI-configured policies generate correct OPA policy files
- [ ] Real-time policy validation with syntax checking
- [ ] Bulk operations for managing permissions across multiple users/roles
- [ ] Policy templates for common access patterns
- [ ] User access summary with clear permission visualization

### Performance Requirements ✅
- [ ] UI loads within 2 seconds for tables with up to 100 columns
- [ ] Column matrix supports up to 50 users/roles simultaneously
- [ ] Policy validation completes within 5 seconds
- [ ] OPA policy deployment takes less than 10 seconds
- [ ] Database queries optimized with proper indexing

### Integration Requirements ✅
- [ ] Seamless integration with existing OpenFGA authorization
- [ ] Automatic OPA policy generation and deployment
- [ ] Backward compatibility with existing table permissions
- [ ] Proper audit logging for all FGAC operations
- [ ] Error handling and user feedback for failed operations

### Security Requirements ✅
- [ ] All FGAC operations require appropriate OpenFGA permissions
- [ ] Policy changes are logged in audit trail
- [ ] Sensitive data properly masked in UI previews
- [ ] SQL injection protection in custom expressions
- [ ] Rate limiting on policy modification endpoints

## Risk Mitigation

### Technical Risks
1. **OPA Policy Conflicts**: Implement policy validation and conflict detection
2. **Performance Impact**: Add query optimization and caching strategies
3. **Data Consistency**: Use database transactions for atomic operations
4. **UI Complexity**: Implement progressive disclosure and help documentation

### Business Risks
1. **User Adoption**: Provide comprehensive training and documentation
2. **Security Gaps**: Regular security audits and penetration testing
3. **Compliance Issues**: Maintain detailed audit logs and access reviews

## Post-Implementation Tasks

### Week 11-12: Production Deployment
- [ ] Production database migration
- [ ] Configuration management updates
- [ ] Load testing with production data volumes
- [ ] Security review and approval
- [ ] User training and documentation rollout

### Ongoing Maintenance
- [ ] Monthly performance reviews
- [ ] Quarterly security audits
- [ ] User feedback collection and feature requests
- [ ] Regular policy cleanup and optimization

This implementation plan provides a comprehensive roadmap for delivering a production-ready FGAC UI system that integrates seamlessly with Lakekeeper's existing architecture while providing the intuitive, configurable interface you requested.