use super::dbutils::DBErrorHandler;
use crate::service::{Result, TableId};

/// Raw column permission data from the database for FGAC UI
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct FgacColumnPermissionRow {
    pub column_permission_id: sqlx::types::Uuid,
    pub column_name: String,
    pub principal_type: String,
    pub principal_id: String,
    pub permission_type: String,
    pub granted_by: String,
    pub granted_at: chrono::DateTime<chrono::Utc>,
    pub expires_at: Option<chrono::DateTime<chrono::Utc>>,
}

/// Raw row policy data from the database for FGAC UI
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct FgacRowPolicyRow {
    pub row_policy_id: sqlx::types::Uuid,
    pub policy_name: String,
    pub principal_type: String,
    pub principal_id: String,
    pub policy_expression: String,
    pub policy_type: String,
    pub is_active: bool,
    pub priority: i32,
    pub granted_by: String,
    pub granted_at: chrono::DateTime<chrono::Utc>,
    pub expires_at: Option<chrono::DateTime<chrono::Utc>>,
}

/// Query column permissions for FGAC UI display
pub(crate) async fn list_fgac_column_permissions<
    'e,
    'c: 'e,
    E: sqlx::Executor<'c, Database = sqlx::Postgres>,
>(
    table_id: TableId,
    connection: E,
) -> Result<Vec<FgacColumnPermissionRow>> {
    let rows = sqlx::query_as::<_, FgacColumnPermissionRow>(
        r#"
        SELECT 
            cp.column_permission_id,
            cp.column_name,
            cp.principal_type,
            cp.principal_id,
            cp.permission_type,
            cp.granted_by,
            cp.granted_at,
            cp.expires_at
        FROM column_permissions cp
        JOIN tabular t ON cp.warehouse_id = t.warehouse_id 
            AND cp.namespace_name = array_to_string(t.tabular_namespace_name, '.') 
            AND cp.table_name = t.name
        WHERE t.tabular_id = $1
            AND t.typ = 'table'
            AND (cp.expires_at IS NULL OR cp.expires_at > now())
        ORDER BY cp.column_name, cp.principal_type, cp.principal_id
        "#,
    )
    .bind(<TableId as Into<sqlx::types::Uuid>>::into(table_id))
    .fetch_all(connection)
    .await
    .map_err(|e| e.into_error_model("Error fetching column permissions".to_string()))?;

    Ok(rows)
}

/// Query row policies for FGAC UI display
pub(crate) async fn list_fgac_row_policies<
    'e,
    'c: 'e,
    E: sqlx::Executor<'c, Database = sqlx::Postgres>,
>(
    table_id: TableId,
    connection: E,
) -> Result<Vec<FgacRowPolicyRow>> {
    let rows = sqlx::query_as::<_, FgacRowPolicyRow>(
        r#"
        SELECT 
            rp.row_policy_id,
            rp.policy_name,
            rp.principal_type,
            rp.principal_id,
            rp.policy_expression,
            rp.policy_type,
            rp.is_active,
            rp.priority,
            rp.granted_by,
            rp.granted_at,
            rp.expires_at
        FROM row_policies rp
        JOIN tabular t ON rp.warehouse_id = t.warehouse_id 
            AND rp.namespace_name = array_to_string(t.tabular_namespace_name, '.') 
            AND rp.table_name = t.name
        WHERE t.tabular_id = $1
            AND t.typ = 'table'
            AND rp.is_active = true
            AND (rp.expires_at IS NULL OR rp.expires_at > now())
        ORDER BY rp.priority DESC, rp.policy_name
        "#,
    )
    .bind(<TableId as Into<sqlx::types::Uuid>>::into(table_id))
    .fetch_all(connection)
    .await
    .map_err(|e| e.into_error_model("Error fetching row policies".to_string()))?;

    Ok(rows)
}
