/**
 * FGAC Matrix JavaScript - Fine-Grained Access Control UI
 * Handles column permission matrix, row policies, and audit log
 */

class FgacMatrix {
    constructor() {
        this.currentTab = 'matrix';
        this.warehouseId = null;
        this.namespaceName = null;
        this.tableName = null;
        this.matrixData = null;
        this.policies = [];
        this.auditLog = [];
        
        // Get table info from URL parameters or configuration
        this.initializeFromUrl();
        
        // Initialize the interface
        this.initialize();
    }

    initializeFromUrl() {
        const urlParams = new URLSearchParams(window.location.search);
        this.warehouseId = urlParams.get('warehouse_id') || 'demo-warehouse';
        this.namespaceName = urlParams.get('namespace') || 'default';
        this.tableName = urlParams.get('table') || 'sample_table';
        
        // Update breadcrumb
        document.getElementById('warehouse-name').textContent = this.warehouseId;
        document.getElementById('namespace-name').textContent = this.namespaceName;
        document.getElementById('table-name').textContent = this.tableName;
    }

    async initialize() {
        try {
            await this.loadFgacSummary();
            await this.loadMatrix();
            await this.loadRowPolicies();
        } catch (error) {
            console.error('Failed to initialize FGAC interface:', error);
            this.showError('Failed to load FGAC configuration. Please check your connection and try again.');
        }
    }

    async loadFgacSummary() {
        try {
            const response = await fetch(
                `/management/v1/warehouses/${this.warehouseId}/namespaces/${this.namespaceName}/tables/${this.tableName}/fgac/summary`
            );
            
            if (response.ok) {
                const summary = await response.json();
                this.updateSummaryCards(summary);
            } else {
                // Use demo data if API not available
                this.updateSummaryCards({
                    total_restricted_columns: 5,
                    total_column_permissions: 12,
                    total_row_policies: 3,
                    active_row_policies: 2,
                    total_affected_principals: 8
                });
            }
        } catch (error) {
            console.warn('Using demo summary data:', error);
            this.updateSummaryCards({
                total_restricted_columns: 5,
                total_column_permissions: 12,
                total_row_policies: 3,
                active_row_policies: 2,
                total_affected_principals: 8
            });
        }
    }

    updateSummaryCards(summary) {
        document.getElementById('total-columns').textContent = 
            (summary.total_restricted_columns || 0) + (summary.total_column_permissions || 0);
        document.getElementById('restricted-columns').textContent = 
            summary.total_restricted_columns || 0;
        document.getElementById('active-policies').textContent = 
            summary.active_row_policies || 0;
        document.getElementById('affected-principals').textContent = 
            summary.total_affected_principals || 0;
    }

    async loadMatrix() {
        try {
            const response = await fetch(
                `/management/v1/warehouses/${this.warehouseId}/namespaces/${this.namespaceName}/tables/${this.tableName}/fgac/matrix`
            );
            
            if (response.ok) {
                this.matrixData = await response.json();
                this.renderMatrix();
            } else {
                // Use demo data if API not available
                this.matrixData = this.generateDemoMatrix();
                this.renderMatrix();
            }
        } catch (error) {
            console.warn('Using demo matrix data:', error);
            this.matrixData = this.generateDemoMatrix();
            this.renderMatrix();
        }
    }

    generateDemoMatrix() {
        return {
            warehouse_id: this.warehouseId,
            namespace_name: this.namespaceName,
            table_name: this.tableName,
            columns: [
                { column_name: 'customer_id', column_type: 'bigint', is_nullable: false, has_permissions: true },
                { column_name: 'customer_name', column_type: 'varchar', is_nullable: false, has_permissions: true },
                { column_name: 'email', column_type: 'varchar', is_nullable: true, has_permissions: true },
                { column_name: 'phone', column_type: 'varchar', is_nullable: true, has_permissions: true },
                { column_name: 'ssn', column_type: 'varchar', is_nullable: true, has_permissions: true },
                { column_name: 'credit_score', column_type: 'integer', is_nullable: true, has_permissions: true },
                { column_name: 'created_at', column_type: 'timestamp', is_nullable: false, has_permissions: false }
            ],
            principals: [
                { principal_type: 'user', principal_id: 'john.doe@company.com', display_name: 'John Doe' },
                { principal_type: 'user', principal_id: 'jane.smith@company.com', display_name: 'Jane Smith' },
                { principal_type: 'role', principal_id: 'data_analyst', display_name: 'Data Analyst Role' },
                { principal_type: 'role', principal_id: 'admin', display_name: 'Administrator Role' },
                { principal_type: 'group', principal_id: 'finance_team', display_name: 'Finance Team' }
            ],
            permissions: {
                customer_id: {
                    'user:john.doe@company.com': { permission_type: 'allow', masking_enabled: false },
                    'role:data_analyst': { permission_type: 'allow', masking_enabled: false },
                    'role:admin': { permission_type: 'allow', masking_enabled: false }
                },
                customer_name: {
                    'user:john.doe@company.com': { permission_type: 'allow', masking_enabled: false },
                    'user:jane.smith@company.com': { permission_type: 'mask', masking_enabled: true, masking_method: 'partial' },
                    'role:data_analyst': { permission_type: 'allow', masking_enabled: false },
                    'role:admin': { permission_type: 'allow', masking_enabled: false }
                },
                email: {
                    'user:john.doe@company.com': { permission_type: 'mask', masking_enabled: true, masking_method: 'hash' },
                    'role:admin': { permission_type: 'allow', masking_enabled: false },
                    'group:finance_team': { permission_type: 'block', masking_enabled: false }
                },
                phone: {
                    'role:admin': { permission_type: 'allow', masking_enabled: false },
                    'group:finance_team': { permission_type: 'mask', masking_enabled: true, masking_method: 'partial' }
                },
                ssn: {
                    'role:admin': { permission_type: 'allow', masking_enabled: false }
                },
                credit_score: {
                    'user:jane.smith@company.com': { permission_type: 'allow', masking_enabled: false },
                    'role:admin': { permission_type: 'allow', masking_enabled: false },
                    'group:finance_team': { permission_type: 'allow', masking_enabled: false }
                }
            }
        };
    }

    renderMatrix() {
        const loading = document.getElementById('matrix-loading');
        const container = document.getElementById('matrix-container');
        const table = document.getElementById('permissions-matrix');
        
        loading.style.display = 'none';
        container.style.display = 'block';
        
        // Build header row
        const thead = table.querySelector('thead tr');
        // Clear existing column headers (keep principal header)
        while (thead.children.length > 1) {
            thead.removeChild(thead.lastChild);
        }
        
        // Add column headers
        this.matrixData.columns.forEach(column => {
            const th = document.createElement('th');
            th.className = 'column-header';
            th.innerHTML = `
                <div class="fgac-tooltip" data-tooltip="${column.column_type}${column.is_nullable ? ' (nullable)' : ''}">
                    ${column.column_name}
                </div>
            `;
            thead.appendChild(th);
        });

        // Build matrix rows
        const tbody = table.querySelector('tbody');
        tbody.innerHTML = '';
        
        this.matrixData.principals.forEach(principal => {
            const row = document.createElement('tr');
            
            // Principal header cell
            const principalCell = document.createElement('td');
            principalCell.className = 'principal-header';
            principalCell.innerHTML = `
                <div>
                    <strong>${principal.display_name}</strong>
                    <br>
                    <small>${principal.principal_type}: ${principal.principal_id}</small>
                </div>
            `;
            row.appendChild(principalCell);
            
            // Permission cells for each column
            this.matrixData.columns.forEach(column => {
                const cell = document.createElement('td');
                cell.className = 'fgac-permission-cell';
                
                const principalKey = `${principal.principal_type}:${principal.principal_id}`;
                const permission = this.matrixData.permissions[column.column_name]?.[principalKey];
                
                if (permission) {
                    const badge = this.createPermissionBadge(permission);
                    cell.appendChild(badge);
                    cell.onclick = () => this.editPermission(column.column_name, principal, permission);
                } else {
                    const badge = document.createElement('span');
                    badge.className = 'fgac-permission-badge fgac-permission-none';
                    badge.textContent = 'None';
                    cell.appendChild(badge);
                    cell.onclick = () => this.editPermission(column.column_name, principal, null);
                }
                
                row.appendChild(cell);
            });
            
            tbody.appendChild(row);
        });
    }

    createPermissionBadge(permission) {
        const badge = document.createElement('span');
        badge.className = `fgac-permission-badge fgac-permission-${permission.permission_type}`;
        
        let text = permission.permission_type.toUpperCase();
        if (permission.masking_enabled && permission.masking_method) {
            text += ` (${permission.masking_method})`;
        }
        
        badge.textContent = text;
        
        // Add tooltip with more details
        if (permission.has_conditions || permission.expires_at) {
            let tooltip = `Granted by: ${permission.granted_by || 'System'}`;
            if (permission.expires_at) {
                tooltip += `\nExpires: ${new Date(permission.expires_at).toLocaleDateString()}`;
            }
            if (permission.has_conditions) {
                tooltip += '\nHas conditions';
            }
            badge.className += ' fgac-tooltip';
            badge.setAttribute('data-tooltip', tooltip);
        }
        
        return badge;
    }

    async loadRowPolicies() {
        try {
            // For demo purposes, create sample row policies
            this.policies = [
                {
                    policy_name: 'region_filter',
                    policy_expression: 'region = current_user_region()',
                    policy_description: 'Users can only see data from their assigned region',
                    is_active: true,
                    principals: ['role:data_analyst', 'user:john.doe@company.com'],
                    estimated_percentage_visible: 25.5,
                    created_by: 'admin@company.com'
                },
                {
                    policy_name: 'department_access',
                    policy_expression: 'department IN (SELECT dept FROM user_departments WHERE user_id = current_user())',
                    policy_description: 'Restrict access to department-specific data',
                    is_active: true,
                    principals: ['group:finance_team'],
                    estimated_percentage_visible: 60.0,
                    created_by: 'admin@company.com'
                },
                {
                    policy_name: 'sensitive_data_filter',
                    policy_expression: 'sensitivity_level <= current_user_clearance()',
                    policy_description: 'Filter sensitive data based on user clearance level',
                    is_active: false,
                    principals: ['role:admin'],
                    estimated_percentage_visible: 95.0,
                    created_by: 'security@company.com'
                }
            ];
            
            this.renderRowPolicies();
        } catch (error) {
            console.error('Failed to load row policies:', error);
        }
    }

    renderRowPolicies() {
        const list = document.getElementById('policy-list');
        list.innerHTML = '';
        
        if (this.policies.length === 0) {
            list.innerHTML = `
                <div class="fgac-empty">
                    <p>No row policies configured for this table.</p>
                    <button class="fgac-btn fgac-btn-primary" onclick="createRowPolicy()">
                        Create First Policy
                    </button>
                </div>
            `;
            return;
        }
        
        this.policies.forEach(policy => {
            const item = document.createElement('div');
            item.className = 'fgac-policy-item';
            
            const statusClass = policy.is_active ? 'fgac-status-active' : 'fgac-status-inactive';
            const statusText = policy.is_active ? 'Active' : 'Inactive';
            
            item.innerHTML = `
                <div class="fgac-policy-name">
                    ${policy.policy_name}
                    <span class="${statusClass}">● ${statusText}</span>
                </div>
                <div class="fgac-policy-expression">${policy.policy_expression}</div>
                <div style="margin-bottom: 8px;">
                    <small style="color: #6c757d;">${policy.policy_description || 'No description'}</small>
                </div>
                <div class="fgac-policy-meta">
                    <div>
                        <strong>Principals:</strong>
                        <div class="fgac-policy-principals">
                            ${policy.principals.map(p => `<span class="fgac-principal-badge">${p}</span>`).join('')}
                        </div>
                    </div>
                    <div><strong>Est. Coverage:</strong> ${policy.estimated_percentage_visible || 'Unknown'}%</div>
                    <div><strong>Created by:</strong> ${policy.created_by}</div>
                </div>
            `;
            
            // Add click handler for editing
            item.style.cursor = 'pointer';
            item.onclick = () => this.editRowPolicy(policy);
            
            list.appendChild(item);
        });
    }

    showTab(tabName) {
        // Update tab buttons
        document.querySelectorAll('.fgac-tab').forEach(tab => {
            tab.classList.remove('active');
        });
        document.querySelector(`[onclick="showTab('${tabName}')"]`).classList.add('active');
        
        // Update tab content
        document.querySelectorAll('.fgac-tab-content').forEach(content => {
            content.classList.remove('active');
        });
        document.getElementById(`${tabName}-tab`).classList.add('active');
        
        this.currentTab = tabName;
        
        // Load content if needed
        if (tabName === 'audit' && this.auditLog.length === 0) {
            this.loadAuditLog();
        }
    }

    async loadAuditLog() {
        const list = document.getElementById('audit-list');
        
        // Simulate loading audit log
        setTimeout(() => {
            this.auditLog = [
                {
                    timestamp: new Date().toISOString(),
                    action_type: 'create',
                    resource_type: 'column_permission',
                    performed_by: 'admin@company.com',
                    details: 'Created masking permission for email column'
                },
                {
                    timestamp: new Date(Date.now() - 3600000).toISOString(),
                    action_type: 'update',
                    resource_type: 'row_policy',
                    performed_by: 'john.doe@company.com',
                    details: 'Modified region_filter policy expression'
                },
                {
                    timestamp: new Date(Date.now() - 7200000).toISOString(),
                    action_type: 'delete',
                    resource_type: 'column_permission',
                    performed_by: 'admin@company.com',
                    details: 'Removed access permission for ssn column'
                }
            ];
            
            this.renderAuditLog();
        }, 1000);
    }

    renderAuditLog() {
        const list = document.getElementById('audit-list');
        list.innerHTML = '';
        
        this.auditLog.forEach(entry => {
            const item = document.createElement('div');
            item.className = 'fgac-policy-item';
            
            const timestamp = new Date(entry.timestamp).toLocaleString();
            
            item.innerHTML = `
                <div class="fgac-policy-name">
                    ${entry.action_type.toUpperCase()} ${entry.resource_type.replace('_', ' ')}
                </div>
                <div style="margin-bottom: 8px;">
                    <small>${entry.details}</small>
                </div>
                <div class="fgac-policy-meta">
                    <div><strong>User:</strong> ${entry.performed_by}</div>
                    <div><strong>Time:</strong> ${timestamp}</div>
                </div>
            `;
            
            list.appendChild(item);
        });
    }

    editPermission(columnName, principal, currentPermission) {
        const permissionTypes = ['allow', 'block', 'mask', 'custom'];
        const maskingMethods = ['null', 'hash', 'partial', 'encrypt', 'custom'];
        
        // Simple modal dialog for editing (in production, you'd use a proper modal library)
        const permission = currentPermission || { permission_type: 'allow', masking_enabled: false };
        
        const newType = prompt(
            `Edit permission for ${principal.display_name} on column "${columnName}":\n\n` +
            `Current: ${permission.permission_type}\n` +
            `Available: ${permissionTypes.join(', ')}\n\n` +
            `Enter new permission type:`,
            permission.permission_type
        );
        
        if (newType && permissionTypes.includes(newType)) {
            // Update permission (in production, this would make an API call)
            console.log('Updating permission:', {
                column: columnName,
                principal: principal,
                permission: newType
            });
            
            // Simulate update
            if (!this.matrixData.permissions[columnName]) {
                this.matrixData.permissions[columnName] = {};
            }
            
            const principalKey = `${principal.principal_type}:${principal.principal_id}`;
            this.matrixData.permissions[columnName][principalKey] = {
                permission_type: newType,
                masking_enabled: newType === 'mask',
                masking_method: newType === 'mask' ? 'partial' : null,
                granted_by: 'current_user@company.com'
            };
            
            // Re-render matrix
            this.renderMatrix();
        }
    }

    editRowPolicy(policy) {
        // Simple editing interface (in production, you'd use a proper form)
        const newExpression = prompt(
            `Edit policy "${policy.policy_name}":\n\n` +
            `Current expression:\n${policy.policy_expression}\n\n` +
            `Enter new expression:`,
            policy.policy_expression
        );
        
        if (newExpression && newExpression.trim()) {
            policy.policy_expression = newExpression.trim();
            console.log('Updated policy:', policy);
            this.renderRowPolicies();
        }
    }

    showError(message) {
        const container = document.querySelector('.fgac-container');
        const errorDiv = document.createElement('div');
        errorDiv.style.cssText = `
            background: #f8d7da;
            color: #721c24;
            padding: 15px;
            border-radius: 6px;
            margin: 20px 0;
            border: 1px solid #f5c6cb;
        `;
        errorDiv.innerHTML = `<strong>Error:</strong> ${message}`;
        container.insertBefore(errorDiv, container.firstChild);
    }
}

// Global functions for UI interactions
function showTab(tabName) {
    window.fgacMatrix.showTab(tabName);
}

function showTemplateModal() {
    alert('Template functionality will open a modal to select and apply FGAC policy templates.');
}

function bulkEdit() {
    alert('Bulk edit functionality will open an interface for making multiple permission changes at once.');
}

function exportConfig() {
    const config = {
        matrix: window.fgacMatrix.matrixData,
        policies: window.fgacMatrix.policies
    };
    
    const blob = new Blob([JSON.stringify(config, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `fgac-config-${window.fgacMatrix.tableName}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
}

function createRowPolicy() {
    const policyName = prompt('Enter policy name:');
    if (!policyName) return;
    
    const policyExpression = prompt('Enter SQL WHERE expression:');
    if (!policyExpression) return;
    
    const policy = {
        policy_name: policyName,
        policy_expression: policyExpression,
        policy_description: '',
        is_active: true,
        principals: [],
        estimated_percentage_visible: null,
        created_by: 'current_user@company.com'
    };
    
    window.fgacMatrix.policies.push(policy);
    window.fgacMatrix.renderRowPolicies();
}

function refreshAuditLog() {
    window.fgacMatrix.loadAuditLog();
}

// Initialize the FGAC Matrix when the page loads
document.addEventListener('DOMContentLoaded', function() {
    window.fgacMatrix = new FgacMatrix();
});