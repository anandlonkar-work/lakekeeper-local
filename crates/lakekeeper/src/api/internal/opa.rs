use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

use crate::api::ApiContext;
use crate::service::{Catalog, State as ServiceState};

/// Internal API for OPA to query FGAC policies from PostgreSQL
/// This module provides endpoints that OPA calls via http.send() to fetch
/// column masks and row filters stored in the database.
///
/// Note: These endpoints do NOT use authentication or authorization.
/// They are meant to be called only by OPA running in the same network.
/// In production, use network policies to restrict access.

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct ColumnMasksQuery {
    pub user_id: Uuid,
    pub warehouse: String,
    pub namespace: String,
    pub table: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct ColumnMaskResponse {
    pub column_masks: HashMap<String, ColumnMask>,
}

#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "snake_case")]
pub struct ColumnMask {
    pub expression: String,
    pub method: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct RowFiltersQuery {
    pub user_id: Uuid,
    pub warehouse: String,
    pub namespace: String,
    pub table: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct RowFiltersResponse {
    pub row_filters: Vec<RowFilter>,
}

#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "snake_case")]
pub struct RowFilter {
    pub expression: String,
    pub priority: i32,
    pub policy_name: String,
}

/// Get column masks for a user and table
/// Called by OPA during query evaluation
pub(crate) async fn get_column_masks<A, C, S>(
    State(api_context): State<ApiContext<ServiceState<A, C, S>>>,
    Query(params): Query<ColumnMasksQuery>,
) -> Result<impl IntoResponse, (StatusCode, String)>
where
    A: crate::service::authz::Authorizer + Clone,
    C: Catalog,
    S: crate::service::SecretStore,
{
    tracing::info!(
        "Query column masks for user={}, warehouse={}, namespace={}, table={}",
        params.user_id,
        params.warehouse,
        params.namespace,
        params.table
    );

    // TODO: Query database when type system allows accessing read_pool()
    // See FGAC_STATUS.md for implementation options
    let masks: HashMap<String, ColumnMask> = HashMap::new();

    Ok(Json(ColumnMaskResponse {
        column_masks: masks,
    }))
}

/// Get row filters for a user and table
/// Called by OPA during query evaluation
pub(crate) async fn get_row_filters<A, C, S>(
    State(api_context): State<ApiContext<ServiceState<A, C, S>>>,
    Query(params): Query<RowFiltersQuery>,
) -> Result<impl IntoResponse, (StatusCode, String)>
where
    A: crate::service::authz::Authorizer + Clone,
    C: Catalog,
    S: crate::service::SecretStore,
{
    tracing::info!(
        "Query row filters for user={}, warehouse={}, namespace={}, table={}",
        params.user_id,
        params.warehouse,
        params.namespace,
        params.table
    );

    // TODO: Query database when type system allows accessing read_pool()
    // See FGAC_STATUS.md for implementation options
    let filters: Vec<RowFilter> = Vec::new();

    Ok(Json(RowFiltersResponse { row_filters: filters }))
}

pub fn new_router<A, C, S>() -> Router<ApiContext<ServiceState<A, C, S>>>
where
    A: crate::service::authz::Authorizer + Clone,
    C: Catalog,
    S: crate::service::SecretStore + Clone,
{
    let path1 = "/v1/column-masks";
    let path2 = "/v1/row-filters";
    Router::new()
        .route(path1, axum::routing::get(get_column_masks::<A, C, S>))
        .route(path2, axum::routing::get(get_row_filters::<A, C, S>))
}

