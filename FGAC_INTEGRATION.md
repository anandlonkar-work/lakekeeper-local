# FGAC Integration Guide

This guide explains how the Fine-Grained Access Control (FGAC) UI components are integrated into the lakekeeper console.

## Overview

The FGAC system provides table-level column permissions and row policies that can be managed through a web interface. Instead of having a standalone FGAC page, the UI is designed as embeddable components that can be integrated into the console's table permissions tab.

## Architecture

### Backend Components

1. **FGAC API Endpoints** (`/management/v1/warehouse/{warehouse_id}/table/{table_id}/fgac`)
   - `GET` - Retrieve current FGAC settings for a table
   - `PUT` - Update FGAC settings for a table

2. **Database Schema**
   - `column_permissions` table for column-level access control
   - `row_policies` table for row-level filtering policies

3. **OpenFGA Integration**
   - Authorization checks using OpenFGA policies
   - Integration with existing warehouse and table permissions

### Frontend Components

1. **FGAC Widget JavaScript** (`/ui/fgac-widget.js`)
   - Reusable `FGACWidget` class that can be embedded in any container
   - Handles API communication and UI updates
   - Supports multiple instances on the same page

2. **FGAC Widget CSS** (`/ui/fgac-widget.css`)
   - Styled to match the console's design system
   - Responsive design with mobile support
   - Dark mode compatibility

3. **Integration Example** (`/ui/fgac-integration`)
   - Demonstrates how to integrate FGAC into a table permissions interface
   - Shows the proper tab structure and initialization

## Integration Steps

### 1. Console Integration

The lakekeeper console (https://github.com/lakekeeper/console) needs to be updated to include FGAC functionality in the table permissions tab:

```javascript
// In the table details view, add FGAC tab
if (enable_permissions && authz_backend === 'OpenFGA') {
    // Load FGAC widget resources
    const fgacCSS = document.createElement('link');
    fgacCSS.rel = 'stylesheet';
    fgacCSS.href = '/ui/fgac-widget.css';
    document.head.appendChild(fgacCSS);
    
    const fgacJS = document.createElement('script');
    fgacJS.src = '/ui/fgac-widget.js';
    fgacJS.onload = () => {
        // Initialize FGAC widget in permissions tab
        const fgacWidget = window.createFGACWidget(
            warehouseId, 
            tableId, 
            'fgac-container'
        );
    };
    document.head.appendChild(fgacJS);
}
```

### 2. UI Configuration

The UI configuration already includes the `enable_permissions` flag:

```rust
enable_permissions: CONFIG.authz_backend == AuthZBackend::OpenFGA,
```

This flag should be used by the console to show/hide the FGAC functionality.

### 3. Authentication

All FGAC API endpoints require proper authentication. The console should handle authentication tokens and pass them with API requests.

## Current Status

### ✅ Completed
- FGAC REST API endpoints are functional
- Database schema is in place
- OpenFGA integration works
- FGAC widget components are created
- UI routing for widget resources is implemented
- Integration example is available

### 🔄 In Progress
- Console integration (requires updates to lakekeeper/console repository)
- Docker image rebuild with new components

### 📋 Next Steps
1. Update the lakekeeper/console repository to include FGAC integration
2. Rebuild and deploy updated Docker images
3. Test full integration in the running environment

## Testing

### Current Testing Approach

Since the Docker build is experiencing SSL issues, you can test the integration by:

1. **Access the integration example:**
   ```
   http://localhost:8181/ui/fgac-integration
   ```

2. **Enter your warehouse and table IDs** in the form

3. **Click "Load FGAC Widget"** to see the integration in action

4. **Switch to the "Fine-Grained Access Control" tab** to see how it would appear in the console

### API Testing

Test the FGAC API endpoints directly:

```bash
# Get FGAC settings for a table
curl -X GET "http://localhost:8181/management/v1/warehouse/{warehouse_id}/table/{table_id}/fgac" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Update FGAC settings
curl -X PUT "http://localhost:8181/management/v1/warehouse/{warehouse_id}/table/{table_id}/fgac" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "table_name": "example_table",
    "warehouse_name": "main_warehouse", 
    "column_permissions": [
      {
        "column_name": "sensitive_column",
        "principal_type": "user",
        "principal_name": "john.doe",
        "permission": "read"
      }
    ],
    "row_policies": [
      {
        "policy_name": "department_filter",
        "principal_type": "role", 
        "principal_name": "analyst",
        "filter_expression": "department = 'sales'"
      }
    ]
  }'
```

## Widget Usage

### Basic Usage

```javascript
// Create FGAC widget
const widget = window.createFGACWidget(warehouseId, tableId, containerId);
```

### Parameters

- `warehouseId` - UUID of the warehouse containing the table
- `tableId` - UUID of the table to manage FGAC settings for  
- `containerId` - ID of the DOM element to render the widget in

### Features

- **Column Permissions**: Manage read/write access to specific columns
- **Row Policies**: Define filtering expressions for row-level access
- **Real-time Updates**: Changes are saved immediately via API
- **Error Handling**: User-friendly error messages and validation
- **Responsive Design**: Works on desktop and mobile devices

## File Structure

```
crates/lakekeeper/src/api/management/v1/
├── fgac_api.rs                    # REST API endpoints
├── fgac_widget.js                 # JavaScript widget component  
├── fgac_widget.css                # Widget styles
├── fgac_integration_example.html  # Integration example
├── table_fgac.html               # Original standalone UI
└── fgac_ui.html                  # Legacy UI file

crates/lakekeeper-bin/src/ui.rs    # UI routing and handlers
```

## Security Considerations

1. **Authentication Required**: All FGAC endpoints require valid authentication
2. **Authorization Checks**: OpenFGA policies control access to FGAC management
3. **Input Validation**: All user inputs are validated on the backend
4. **SQL Injection Prevention**: Row policy expressions are validated and sanitized
5. **CSRF Protection**: Proper request headers and tokens required

## Troubleshooting

### Widget Not Loading
- Check browser console for JavaScript errors
- Verify `/ui/fgac-widget.js` and `/ui/fgac-widget.css` are accessible
- Ensure container element exists in DOM

### API Errors
- Verify authentication token is valid
- Check warehouse and table IDs are correct
- Confirm OpenFGA is properly configured

### Permission Issues
- Ensure user has table management permissions
- Verify OpenFGA policies allow FGAC operations
- Check that `enable_permissions` is true in UI config

## Future Enhancements

1. **Advanced Policy Editor**: Rich text editor for complex row policies
2. **Column Detection**: Auto-discover available columns from table schema
3. **Policy Testing**: Preview how policies affect data access
4. **Audit Logging**: Track who changes FGAC settings
5. **Bulk Operations**: Apply policies to multiple tables at once