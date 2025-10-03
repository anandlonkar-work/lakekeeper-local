// Fine-Grained Access Control (FGAC) Widget for lakekeeper console
// This module provides functions to load and manage FGAC settings for a specific table

class FGACWidget {
    constructor(containerId, warehouseId, tableId) {
        this.containerId = containerId;
        this.warehouseId = warehouseId;
        this.tableId = tableId;
        this.container = document.getElementById(containerId);
        this.currentFgacData = null;
        
        if (!this.container) {
            console.error(`Container with id ${containerId} not found`);
            return;
        }
        
        this.init();
    }

    // Helper function to get authentication headers
    async getAuthHeaders() {
        const headers = {
            'Accept': 'application/json',
            'Content-Type': 'application/json'
        };

        // Try to get access token from various storage locations
        let accessToken = null;
        
        // Check localStorage
        const tokenFromStorage = localStorage.getItem('access_token') || 
                                localStorage.getItem('lakekeeper_token') ||
                                localStorage.getItem('oidc_token');
        
        if (tokenFromStorage) {
            accessToken = tokenFromStorage;
        }
        
        // Check sessionStorage
        if (!accessToken) {
            const sessionToken = sessionStorage.getItem('access_token') || 
                                sessionStorage.getItem('lakekeeper_token') ||
                                sessionStorage.getItem('oidc_token');
            if (sessionToken) {
                accessToken = sessionToken;
            }
        }
        
        // If we have a token, add it to headers
        if (accessToken) {
            // Remove quotes if present
            accessToken = accessToken.replace(/^"(.*)"$/, '$1');
            headers['Authorization'] = `Bearer ${accessToken}`;
        }
        
        return headers;
    }
    
    async init() {
        this.container.innerHTML = this.getLoadingHTML();
        try {
            await this.loadFgacData();
        } catch (error) {
            this.showError(`Failed to initialize FGAC widget: ${error.message}`);
        }
    }
    
    getLoadingHTML() {
        return `
            <div class="fgac-widget">
                <div class="fgac-loading">
                    <div class="spinner"></div>
                    Loading FGAC settings...
                </div>
            </div>
        `;
    }
    
    async loadFgacData() {
        try {            
            // Use the UI proxy endpoint instead of direct management API call
            const response = await fetch(`/ui/api/fgac/${this.warehouseId}/${this.tableId}`, {
                method: 'GET',
                credentials: 'include', // Include cookies/session
                headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json'
                }
            });
            if (!response.ok) {
                throw new Error(`Failed to load FGAC data: ${response.statusText}`);
            }
            
            const data = await response.json();
            this.currentFgacData = data;
            this.render();
            
        } catch (error) {
            console.error('Error loading FGAC data:', error);
            this.showError(`Error loading FGAC data: ${error.message}`);
        }
    }

    loadDemoFgacData() {
        // Demo data that matches the expected API response format
        this.currentFgacData = {
            table_info: {
                warehouse_id: this.warehouseId,
                table_id: this.tableId,
                warehouse_name: "demo_warehouse",
                namespace_name: "sales",
                table_name: this.tableId
            },
            available_columns: [
                "customer_id", "name", "email", "phone", "address", "credit_rating", "ssn", "salary", "department"
            ],
            column_permissions: [
                {
                    column_name: "ssn",
                    principal_type: "role",
                    principal_id: "data_analyst",
                    permission_type: "mask",
                    masking_method: "hash"
                },
                {
                    column_name: "salary",
                    principal_type: "role",
                    principal_id: "hr_manager",
                    permission_type: "allow",
                    masking_method: null
                },
                {
                    column_name: "credit_rating",
                    principal_type: "role",
                    principal_id: "sales_rep",  
                    permission_type: "deny",
                    masking_method: null
                }
            ],
            row_policies: [
                {
                    policy_name: "regional_filter",
                    principal_type: "role",
                    principal_id: "sales_rep",
                    policy_expression: "region = 'WEST'",
                    is_active: true
                },
                {
                    policy_name: "department_filter",
                    principal_type: "user",
                    principal_id: "alice",
                    policy_expression: "department = 'Engineering'",
                    is_active: false
                }
            ],
            available_principals: [
                "user:alice", "user:bob", "user:charlie",
                "role:admin", "role:data_analyst", "role:sales_rep", "role:hr_manager"
            ]
        };
        
        this.render();
        this.showMessage('Demo FGAC data loaded (authentication required for real data)', 'info');
    }
    
    render() {
        if (!this.currentFgacData) {
            this.showError('No FGAC data available');
            return;
        }
        
        const html = `
            <div class="fgac-widget">
                <div class="fgac-section">
                    <h3>Column Permissions</h3>
                    <div class="fgac-permissions-grid" id="column-permissions-${this.containerId}">
                        ${this.renderColumnPermissions()}
                    </div>
                    <button class="fgac-add-btn" onclick="window.fgacWidget_${this.containerId}.addColumnPermission()">
                        + Add Column Permission
                    </button>
                </div>
                
                <div class="fgac-section">
                    <h3>Row Policies</h3>
                    <div class="fgac-permissions-grid" id="row-policies-${this.containerId}">
                        ${this.renderRowPolicies()}
                    </div>
                    <button class="fgac-add-btn" onclick="window.fgacWidget_${this.containerId}.addRowPolicy()">
                        + Add Row Policy
                    </button>
                </div>
                
                <div class="fgac-actions">
                    <button class="fgac-save-btn" onclick="window.fgacWidget_${this.containerId}.saveFgacData()">
                        Save Changes
                    </button>
                </div>
                
                <div id="fgac-message-${this.containerId}" class="fgac-message" style="display: none;"></div>
            </div>
        `;
        
        this.container.innerHTML = html;
        
        // Store reference to this widget for onclick handlers
        window[`fgacWidget_${this.containerId}`] = this;
    }
    
    renderColumnPermissions() {
        if (!this.currentFgacData.column_permissions || this.currentFgacData.column_permissions.length === 0) {
            return '<div class="fgac-empty">No column permissions defined</div>';
        }
        
        return this.currentFgacData.column_permissions.map((perm, index) => `
            <div class="fgac-permission-card">
                <div class="fgac-permission-header">
                    <span class="fgac-column-name">${this.escapeHtml(perm.column_name)}</span>
                    <div class="fgac-permission-actions">
                        <button class="fgac-edit-btn" onclick="window.fgacWidget_${this.containerId}.editColumnPermission(${index})">Edit</button>
                        <button class="fgac-remove-btn" onclick="window.fgacWidget_${this.containerId}.removeColumnPermission(${index})">Remove</button>
                    </div>
                </div>
                <div class="fgac-permission-details">
                    <span><strong>Principal:</strong> ${this.escapeHtml(perm.principal_type)}:${this.escapeHtml(perm.principal_name)}</span>
                    <span><strong>Permission:</strong> ${this.escapeHtml(perm.permission)}</span>
                </div>
            </div>
        `).join('');
    }
    
    renderRowPolicies() {
        if (!this.currentFgacData.row_policies || this.currentFgacData.row_policies.length === 0) {
            return '<div class="fgac-empty">No row policies defined</div>';
        }
        
        return this.currentFgacData.row_policies.map((policy, index) => `
            <div class="fgac-permission-card">
                <div class="fgac-permission-header">
                    <span class="fgac-policy-name">${this.escapeHtml(policy.policy_name)}</span>
                    <div class="fgac-permission-actions">
                        <button class="fgac-edit-btn" onclick="window.fgacWidget_${this.containerId}.editRowPolicy(${index})">Edit</button>
                        <button class="fgac-remove-btn" onclick="window.fgacWidget_${this.containerId}.removeRowPolicy(${index})">Remove</button>
                    </div>
                </div>
                <div class="fgac-permission-details">
                    <span><strong>Principal:</strong> ${this.escapeHtml(policy.principal_type)}:${this.escapeHtml(policy.principal_name)}</span>
                    <span><strong>Filter:</strong> ${this.escapeHtml(policy.filter_expression)}</span>
                </div>
            </div>
        `).join('');
    }
    
    async saveFgacData() {
        try {
            this.showMessage('Saving...', 'info');
            
            // For now, just simulate a successful save since we're using mock data
            // This would use a POST/PUT endpoint to the proxy when real data is implemented
            setTimeout(() => {
                this.showMessage('FGAC settings saved successfully (simulated)', 'success');
            }, 1000);
            
        } catch (error) {
            console.error('Error saving FGAC data:', error);
            this.showMessage(`Error saving FGAC data: ${error.message}`, 'error');
        }
    }
    
    addColumnPermission() {
        const columnName = prompt('Enter column name:');
        const principalType = prompt('Enter principal type (user/role):');
        const principalName = prompt('Enter principal name:');
        const permission = prompt('Enter permission (read/write):');
        
        if (columnName && principalType && principalName && permission) {
            if (!this.currentFgacData.column_permissions) {
                this.currentFgacData.column_permissions = [];
            }
            
            this.currentFgacData.column_permissions.push({
                column_name: columnName,
                principal_type: principalType,
                principal_name: principalName,
                permission: permission
            });
            
            this.render();
        }
    }
    
    addRowPolicy() {
        const policyName = prompt('Enter policy name:');
        const principalType = prompt('Enter principal type (user/role):');
        const principalName = prompt('Enter principal name:');
        const filterExpression = prompt('Enter filter expression:');
        
        if (policyName && principalType && principalName && filterExpression) {
            if (!this.currentFgacData.row_policies) {
                this.currentFgacData.row_policies = [];
            }
            
            this.currentFgacData.row_policies.push({
                policy_name: policyName,
                principal_type: principalType,
                principal_name: principalName,
                filter_expression: filterExpression
            });
            
            this.render();
        }
    }
    
    editColumnPermission(index) {
        const perm = this.currentFgacData.column_permissions[index];
        
        const columnName = prompt('Enter column name:', perm.column_name);
        const principalType = prompt('Enter principal type (user/role):', perm.principal_type);
        const principalName = prompt('Enter principal name:', perm.principal_name);
        const permission = prompt('Enter permission (read/write):', perm.permission);
        
        if (columnName && principalType && principalName && permission) {
            this.currentFgacData.column_permissions[index] = {
                column_name: columnName,
                principal_type: principalType,
                principal_name: principalName,
                permission: permission
            };
            
            this.render();
        }
    }
    
    editRowPolicy(index) {
        const policy = this.currentFgacData.row_policies[index];
        
        const policyName = prompt('Enter policy name:', policy.policy_name);
        const principalType = prompt('Enter principal type (user/role):', policy.principal_type);
        const principalName = prompt('Enter principal name:', policy.principal_name);
        const filterExpression = prompt('Enter filter expression:', policy.filter_expression);
        
        if (policyName && principalType && principalName && filterExpression) {
            this.currentFgacData.row_policies[index] = {
                policy_name: policyName,
                principal_type: principalType,
                principal_name: principalName,
                filter_expression: filterExpression
            };
            
            this.render();
        }
    }
    
    removeColumnPermission(index) {
        if (confirm('Are you sure you want to remove this column permission?')) {
            this.currentFgacData.column_permissions.splice(index, 1);
            this.render();
        }
    }
    
    removeRowPolicy(index) {
        if (confirm('Are you sure you want to remove this row policy?')) {
            this.currentFgacData.row_policies.splice(index, 1);
            this.render();
        }
    }
    
    showMessage(message, type) {
        const messageDiv = document.getElementById(`fgac-message-${this.containerId}`);
        if (messageDiv) {
            messageDiv.textContent = message;
            messageDiv.className = `fgac-message fgac-message-${type}`;
            messageDiv.style.display = 'block';
            
            // Hide message after 3 seconds for success/info messages
            if (type === 'success' || type === 'info') {
                setTimeout(() => {
                    messageDiv.style.display = 'none';
                }, 3000);
            }
        }
    }
    
    showError(message) {
        this.container.innerHTML = `
            <div class="fgac-widget">
                <div class="fgac-error">
                    <strong>Error:</strong> ${this.escapeHtml(message)}
                </div>
            </div>
        `;
    }
    
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
}

// Global function to create FGAC widget
window.createFGACWidget = function(warehouseId, tableId, containerId) {
    return new FGACWidget(warehouseId, tableId, containerId);
};

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = FGACWidget;
}