# Fine-Grained Access Control (FGAC) UI Design

## Overview

This document outlines the design for integrating Fine-Grained Access Control (FGAC) features into the Lakekeeper Management UI. The design extends the existing Swagger UI-based interface to support configurable column-level and row-level permissions at the table level.

## Current State Analysis

### Existing Permission System
Based on the codebase analysis, Lakekeeper currently provides:

1. **Table-level permissions** via OpenFGA with these actions:
   - `CanReadData`, `CanWriteData`, `CanGetMetadata`, `CanCommit`, `CanDrop`, `CanRename`
   - Permission assignments through `/management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/assignments`

2. **Role-based access control** with hierarchical permissions:
   - Users and Roles can be assigned to various entities (Server, Project, Warehouse, Namespace, Table, View)
   - OpenFGA handles the authorization logic

3. **Swagger UI interface** served at `/swagger-ui` for API management:
   - Interactive API documentation for all management endpoints
   - Current table protection settings (deletion protection only)

### Current Limitations
- No column-level access control in the UI
- No row-level filtering configuration
- FGAC policies are only configurable via OPA files, not through the management interface

## FGAC UI Architecture

### Design Principles
1. **Extend existing patterns**: Build upon the current Swagger UI and API structure
2. **Progressive disclosure**: Show simple table permissions first, with expandable FGAC sections
3. **Matrix-based column permissions**: Intuitive grid layout for user/role vs. column permissions
4. **Flexible row filtering**: Support both predefined rules and custom SQL expressions
5. **Real-time validation**: Immediate feedback on permission changes and policy syntax

### Component Hierarchy
```
Table Management UI
├── Table Information (existing)
├── Basic Permissions (existing)
│   ├── User/Role Assignments
│   └── Table-level Actions
└── Fine-Grained Access Control (NEW)
    ├── Column-Level Permissions
    │   ├── Column Permission Matrix
    │   ├── Permission Templates
    │   └── Column Masking Rules
    └── Row-Level Filtering
        ├── Predefined Filter Rules
        ├── Custom SQL Expressions
        └── User/Role-specific Policies
```

## Screen Mockups

### 1. Table Permissions Overview (Enhanced)

```ascii
┌─────────────────────────────────────────────────────────────────┐
│ Table: employees (lakekeeper.fgac_test.employees)               │
├─────────────────────────────────────────────────────────────────┤
│ Basic Information                                               │
│ • Table ID: 12345-67890-abcde                                  │
│ • Schema: fgac_test                                            │
│ • Columns: id, name, department, salary, email, phone, class   │
│ • Rows: ~1,250 records                                         │
├─────────────────────────────────────────────────────────────────┤
│ Protection Status: 🛡️ Protected from deletion                 │
│ FGAC Status: ✅ Column masking active | ✅ Row filtering active│
├─────────────────────────────────────────────────────────────────┤
│ Quick Actions:                                                  │
│ [View Data Sample] [Edit Schema] [🔧 Configure FGAC] [Settings]│
└─────────────────────────────────────────────────────────────────┘
```

### 2. Fine-Grained Access Control Dashboard

```ascii
┌─────────────────────────────────────────────────────────────────────────────────┐
│ Fine-Grained Access Control Configuration                                      │
│ Table: employees                                                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│ 📊 Overview                                                                     │
│ • Column Permissions: 3 restricted columns, 4 users/roles configured          │
│ • Row Filtering: 2 active policies, affects 850 rows for restricted users     │  
│ • Last Updated: 2025-09-29 14:30 UTC by admin                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│ 🔍 Quick Preview                                                                │
│ • Anna (Engineering): ✅ name, department | ❌ salary, email, phone | 🔍 750 rows│
│ • Bob (HR): ✅ All columns | 🔍 1,250 rows                                     │
│ • Manager Role: ✅ All columns except phone | 🔍 1,100 rows                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│ [📋 Column Permissions] [🎯 Row Filtering] [👥 User Summary] [⚙️ Advanced]     │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 3. Column Permission Matrix

```ascii
┌─────────────────────────────────────────────────────────────────────────────────┐
│ Column-Level Permissions Matrix                                                 │
│ Table: employees                                                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│          │  id  │ name │ dept │salary│email │phone │classification│              │
├─────────────────────────────────────────────────────────────────────────────────┤
│Users     │      │      │      │      │      │      │             │ Actions      │
├─────────────────────────────────────────────────────────────────────────────────┤
│👤 Anna   │  ✅  │  ✅  │  ✅  │  🚫  │  🚫  │  🚫  │      ✅     │[Edit][Remove]│
│👤 Peter  │  ✅  │  ✅  │  ✅  │  ✅  │  ✅  │  ✅  │      ✅     │[Edit][Remove]│
│👤 Bob    │  ✅  │  ✅  │  ✅  │  ⚪  │  ✅  │  🚫  │      ✅     │[Edit][Remove]│
├─────────────────────────────────────────────────────────────────────────────────┤
│Roles     │      │      │      │      │      │      │             │              │
├─────────────────────────────────────────────────────────────────────────────────┤
│👥 Manager│  ✅  │  ✅  │  ✅  │  ✅  │  ✅  │  🚫  │      ✅     │[Edit][Remove]│
│👥 HR     │  ✅  │  ✅  │  ✅  │  ✅  │  ✅  │  ✅  │      ✅     │[Edit][Remove]│
│👥 Analyst│  ✅  │  ✅  │  ✅  │  ⚪  │  🚫  │  🚫  │      ✅     │[Edit][Remove]│
├─────────────────────────────────────────────────────────────────────────────────┤
│Legend: ✅ Full Access | 🚫 Blocked/Masked | ⚪ Partial/Custom | 🔍 Filtered    │
├─────────────────────────────────────────────────────────────────────────────────┤
│Column Actions:                                                                  │
│ [+ Add User/Role] [📋 Bulk Edit] [📥 Import CSV] [📤 Export] [🔧 Templates]   │
├─────────────────────────────────────────────────────────────────────────────────┤
│Masking Options:                                                                 │
│ 🚫 NULL/Hidden  ⚪ Partial (email → *****@domain.com)  🎭 Hash/Encrypt         │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 4. Column Permission Detail Modal

```ascii
┌─────────────────────────────────────────────────────────────────┐
│ Configure Column Access: "salary"                              │
├─────────────────────────────────────────────────────────────────┤
│ User/Role: Anna (Engineering Department)                       │
│                                                                 │
│ Permission Type:                                                │
│ ◉ Block/Mask Column    ○ Allow Full Access    ○ Custom Rule    │
│                                                                 │
│ Masking Method:                                                 │
│ ◉ Return NULL          ○ Show "*****"         ○ Hash Value     │
│ ○ Custom Expression: [________________]                         │
│                                                                 │
│ Conditions (Optional):                                          │
│ ☑ Apply only during business hours (9 AM - 5 PM)              │
│ ☐ Allow access from specific IP ranges                         │
│ ☐ Require additional authentication                             │
│                                                                 │
│ Preview SQL:                                                    │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ CASE WHEN user_id = 'd223d88c-...' THEN NULL               │ │
│ │      ELSE salary END AS salary                              │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│                    [Cancel] [Test Policy] [Save]               │
└─────────────────────────────────────────────────────────────────┘
```

### 5. Row Filtering Configuration

```ascii
┌─────────────────────────────────────────────────────────────────────────────────┐
│ Row-Level Filtering Policies                                                    │
│ Table: employees                                                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Active Policies (2)                                              [+ Add Policy] │
├─────────────────────────────────────────────────────────────────────────────────┤
│ 1. Classification-Based Filtering                              [Edit] [Delete] │
│    Users: Anna, Analyst Role                                                    │
│    Rule: classification IN ('Public', 'Internal')                              │
│    Impact: ~400 rows hidden                                                     │
│                                                                                 │
│ 2. Department Restriction                                       [Edit] [Delete] │
│    Users: Anna                                                                  │
│    Rule: department != 'Executive'                                              │  
│    Impact: ~50 rows hidden                                                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Policy Builder                                                                  │
│                                                                                 │
│ Apply to: [Dropdown: Select Users/Roles ▾]                                     │
│          [👤 Anna] [👥 Engineering] [+ Add]                                    │
│                                                                                 │
│ Filter Type:                                                                    │
│ ◉ Predefined Rule    ○ Custom SQL Expression    ○ Template                     │
│                                                                                 │
│ Column: [Dropdown: classification ▾]                                           │
│ Operator: [Dropdown: IN ▾]                                                     │
│ Values: [☑ Public] [☑ Internal] [☐ Confidential] [☐ Secret]                   │
│                                                                                 │
│ Preview Query:                                                                  │
│ ┌─────────────────────────────────────────────────────────────────────────────┐ │
│ │ SELECT * FROM employees                                                     │ │
│ │ WHERE classification IN ('Public', 'Internal')                             │ │
│ │   AND department != 'Executive'                                             │ │
│ └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                 │
│ Expected Result: 750 rows (out of 1,250 total)                                │
│                                                                                 │
│                         [Test Query] [Save Policy]                             │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 6. Advanced Row Filtering (Custom SQL)

```ascii
┌─────────────────────────────────────────────────────────────────────────────────┐
│ Advanced Row Filtering - Custom SQL Expression                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Policy Name: [Engineering Team Access Rule_______________]                     │
│                                                                                 │
│ Apply to: [👤 Anna] [👥 Engineering] [👥 Contractor]                          │
│                                                                                 │
│ SQL Expression:                                                                 │
│ ┌─────────────────────────────────────────────────────────────────────────────┐ │
│ │ -- Engineering team can only see their department                          │ │ 
│ │ -- and public information from other departments                            │ │
│ │                                                                             │ │
│ │ (department = 'Engineering' OR                                              │ │
│ │  (department != 'Engineering' AND classification = 'Public'))              │ │
│ │   AND                                                                       │ │
│ │ -- Exclude executives and confidential records                              │ │
│ │ (job_level < 8 AND classification != 'Confidential')                       │ │
│ └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                 │
│ Available Columns: id, name, department, salary, email, phone,                 │
│                   classification, job_level, hire_date, manager_id             │
│                                                                                 │
│ ✅ Syntax Valid                                                                │
│ 📊 Estimated Result: 680 rows (54% of total)                                  │
│                                                                                 │
│ Test Results:                                                                   │
│ ┌─────────────────────────────────────────────────────────────────────────────┐ │
│ │ ✅ Anna will see: 680 rows                                                 │ │
│ │ ✅ Engineering role members will see: 680 rows                             │ │
│ │ ⚠️  Contractor role members will see: 45 rows (mostly public records)      │ │
│ └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                 │
│ Policy Options:                                                                 │
│ ☑ Enable policy immediately    ☐ Require manager approval                     │
│ ☐ Log all filtered queries     ☑ Alert on policy violations                   │
│                                                                                 │
│              [Validate] [Test with Sample Data] [Save Policy]                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 7. User Access Summary

```ascii
┌─────────────────────────────────────────────────────────────────────────────────┐
│ User Access Summary - Table: employees                                         │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Search: [Anna________________] [🔍]  Filter: [All Users ▾] [Export Summary]    │
├─────────────────────────────────────────────────────────────────────────────────┤
│ 👤 Anna Chen (Engineering)                                    [View Details]   │
│    Columns: ✅ 4 visible | 🚫 3 masked (salary, email, phone)                 │
│    Rows: 🔍 750 visible (60% of table) | Policies: Classification, Department │
│    Last Access: 2025-09-29 09:15 UTC                                          │
│                                                                                 │
│ 👤 Peter Admin (IT Admin)                                     [View Details]   │
│    Columns: ✅ 7 visible | 🚫 0 masked                                        │
│    Rows: 🔍 1,250 visible (100% of table) | Policies: None                    │
│    Last Access: 2025-09-29 14:22 UTC                                          │
│                                                                                 │
│ 👤 Bob Smith (HR Manager)                                     [View Details]   │
│    Columns: ✅ 6 visible | ⚪ 1 partial (phone masked)                        │
│    Rows: 🔍 1,250 visible (100% of table) | Policies: None                    │
│    Last Access: 2025-09-28 16:45 UTC                                          │
│                                                                                 │
│ 👥 Manager Role (5 members)                                   [View Details]   │
│    Columns: ✅ 6 visible | 🚫 1 masked (phone)                                │
│    Rows: 🔍 1,100 visible (88% of table) | Policies: Executive exclusion     │
│    Members: Alice Johnson, David Wilson, Sarah Lee, Mike Brown, Lisa Taylor   │
├─────────────────────────────────────────────────────────────────────────────────┤
│ 📊 Access Statistics                                                           │
│ • Total Users with Access: 12 users, 3 roles                                 │
│ • Fully Restricted Users: 1 (Anna)                                            │
│ • Partially Restricted: 4 users, 1 role                                       │
│ • Unrestricted Access: 7 users, 1 role (Admin)                               │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 8. FGAC Policy Templates

```ascii
┌─────────────────────────────────────────────────────────────────────────────────┐
│ FGAC Policy Templates                                                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Quick Setup Templates:                                            [Create New]  │
├─────────────────────────────────────────────────────────────────────────────────┤
│ 🏢 HR Department Access                                          [Apply] [Edit] │
│    • Full access to all employee data                                          │
│    • Includes salary and personal information                                  │
│    • No row filtering restrictions                                             │
│                                                                                 │
│ 👨‍💼 Manager Level Access                                          [Apply] [Edit] │
│    • Access to team member data only                                           │
│    • Salary visible for direct reports                                         │
│    • Restricted from executive compensation                                     │
│                                                                                 │
│ 📊 Analyst/Reporting Access                                      [Apply] [Edit] │
│    • Aggregated data access (no PII)                                          │
│    • Email and phone numbers masked                                            │
│    • Department and job level visible                                          │
│                                                                                 │
│ 🔒 Security/Compliance Team                                      [Apply] [Edit] │
│    • Access to security classification only                                    │
│    • Personal data masked unless under investigation                           │
│    • Full audit trail logging                                                  │
│                                                                                 │
│ 👨‍💻 Engineering Team Access                                      [Apply] [Edit] │
│    • Department-based row filtering                                            │
│    • Personal contact info masked                                              │
│    • Public and internal classification data only                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Custom Template Builder:                                                        │
│                                                                                 │
│ Template Name: [________________________]                                      │
│ Description: [_____________________________________________]                  │
│                                                                                 │
│ Column Permissions:                                                             │
│ [+ Add Column Rule] [+ Add Masking Rule] [+ Add Condition]                    │
│                                                                                 │
│ Row Filtering:                                                                  │
│ [+ Add Row Filter] [+ Add Business Rule] [+ Add Time Restriction]             │
│                                                                                 │
│                                        [Save Template] [Preview]               │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Technical Implementation Requirements

### API Extensions Required

The current permission system needs these new endpoints:

#### Column Permission Management
```
GET    /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/columns
POST   /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/columns
PUT    /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/columns/{column_id}
DELETE /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/columns/{column_id}
```

#### Row Policy Management  
```
GET    /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/row-policies
POST   /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/row-policies
PUT    /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/row-policies/{policy_id}
DELETE /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/row-policies/{policy_id}
```

#### FGAC Configuration
```
GET    /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/fgac-config
POST   /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/fgac-config/validate
GET    /management/v1/permissions/warehouse/{warehouse_id}/table/{table_id}/access-summary
```

### Data Models

#### Column Permission Model
```json
{
  "column_id": "uuid",
  "table_id": "uuid", 
  "column_name": "string",
  "user_or_role": {
    "type": "user|role",
    "id": "uuid",
    "name": "string"
  },
  "permission_type": "allow|block|mask|custom",
  "masking_rule": {
    "method": "null|hash|partial|custom",
    "expression": "SQL expression for custom masking"
  },
  "conditions": {
    "time_restrictions": [],
    "ip_restrictions": [],
    "additional_auth_required": false
  },
  "created_at": "timestamp",
  "updated_at": "timestamp",
  "created_by": "user_id"
}
```

#### Row Policy Model
```json
{
  "policy_id": "uuid",
  "table_id": "uuid",
  "policy_name": "string",
  "users_and_roles": [
    {
      "type": "user|role",
      "id": "uuid",
      "name": "string"  
    }
  ],
  "filter_expression": "SQL WHERE clause expression",
  "policy_type": "predefined|custom|template",
  "is_active": true,
  "estimated_row_impact": 450,
  "created_at": "timestamp",
  "updated_at": "timestamp",
  "created_by": "user_id"
}
```

### Integration Points

#### OpenFGA Extensions
- New relation types: `lakekeeper_column`, `lakekeeper_row_policy`
- Column-level permission checks via existing authorization framework
- Row policy authorization using existing `is_allowed_row_policy_action` methods

#### OPA Policy Updates
- Dynamic policy generation from UI configuration 
- Real-time policy validation and testing
- Integration with existing `columnMask.rego` and `rowFilters.rego` policies

#### Database Schema Changes
- `column_permissions` table with foreign keys to tables and columns
- `row_policies` table with policy definitions and user/role assignments
- Migration scripts to extend existing authorization tables

## Implementation Phases

### Phase 1: API Foundation (2-3 weeks)
- Extend existing OpenFGA API with column and row policy endpoints
- Add database schema for FGAC metadata storage
- Implement basic CRUD operations for column permissions and row policies
- Update OpenAPI specifications

### Phase 2: Core UI Components (3-4 weeks)  
- Enhance existing table management interface with FGAC sections
- Implement column permission matrix component
- Build row filtering configuration interface
- Add user access summary views

### Phase 3: Advanced Features (2-3 weeks)
- Policy templates and bulk operations
- Advanced custom SQL expression builder
- Real-time policy validation and testing
- Integration with existing OPA policies

### Phase 4: Polish & Integration (1-2 weeks)
- Performance optimization for large permission matrices
- Comprehensive error handling and validation
- Documentation and help system integration
- End-to-end testing with existing FGAC implementation

## Success Metrics

1. **Usability**: Administrators can configure column masking and row filtering without editing OPA files
2. **Performance**: UI responds within 2 seconds for tables with up to 100 columns and 50 users/roles
3. **Accuracy**: UI-configured policies match exactly with OPA policy behavior  
4. **Adoptability**: Existing table permission workflows remain unchanged
5. **Scalability**: System supports enterprise-scale deployments with 1000+ users and complex permission matrices

This design provides a comprehensive, user-friendly interface for managing Fine-Grained Access Control while maintaining backward compatibility with existing Lakekeeper functionality.