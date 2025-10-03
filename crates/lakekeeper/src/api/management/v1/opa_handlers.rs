use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
    routing::{get, post},
    Router,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::{
    api::{
        iceberg::v1::{ApiContext, Result},
        management::v1::ErrorModel,
    },
    service::{
        opa_integration_service::{
            DeploymentStatus, OpaIntegrationService, PolicyStatus, PolicyValidationResult,
        },
        WarehouseId,
    },
};

/// REST API handlers for OPA integration
pub struct OpaIntegrationHandlers;

#[derive(Debug, Deserialize)]
pub struct GeneratePoliciesQuery {
    pub base_path: Option<String>,
    pub deploy: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct PolicyGenerationResponse {
    pub table_identifier: String,
    pub policies_generated: usize,
    pub deployed: bool,
    pub generation_time_ms: u64,
}

#[derive(Debug, Serialize)]
pub struct AllPoliciesResponse {
    pub total_tables: usize,
    pub total_policies: usize,
    pub deployed: bool,
    pub generation_time_ms: u64,
}

impl OpaIntegrationHandlers {
    /// Create router for OPA integration endpoints
    pub fn create_router() -> Router<Arc<ApiContext>> {
        Router::new()
            .route(
                "/opa/policies/table/:warehouse_id/:namespace/:table/generate",
                post(Self::generate_table_policies),
            )
            .route(
                "/opa/policies/table/:warehouse_id/:namespace/:table/status",
                get(Self::get_policy_status),
            )
            .route(
                "/opa/policies/table/:warehouse_id/:namespace/:table/validate",
                get(Self::validate_policies),
            )
            .route("/opa/policies/generate-all", post(Self::generate_all_policies))
            .route("/opa/policies/deploy-all", post(Self::deploy_all_policies))
            .route("/opa/deployment/status", get(Self::get_deployment_status))
            .route("/opa/policies/refresh", post(Self::refresh_policies))
    }

    /// Generate OPA policies for a specific table
    pub async fn generate_table_policies(
        State(context): State<Arc<ApiContext>>,
        Path((warehouse_id, namespace, table)): Path<(WarehouseId, String, String)>,
        Query(params): Query<GeneratePoliciesQuery>,
    ) -> Result<Json<PolicyGenerationResponse>> {
        let start_time = std::time::Instant::now();

        let opa_service = OpaIntegrationService::new(context.v1_state.catalog.clone());

        let policies = opa_service
            .generate_table_policies(warehouse_id, &namespace, &table)
            .await?;

        let deployed = if params.deploy.unwrap_or(false) {
            let base_path = params.base_path.as_deref().unwrap_or("./");
            opa_service
                .deploy_table_policies(warehouse_id, &namespace, &table, base_path)
                .await?;
            true
        } else {
            false
        };

        let generation_time = start_time.elapsed().as_millis() as u64;

        Ok(Json(PolicyGenerationResponse {
            table_identifier: format!("{}.{}.{}", warehouse_id, namespace, table),
            policies_generated: policies.len(),
            deployed,
            generation_time_ms: generation_time,
        }))
    }

    /// Get policy status for a table
    pub async fn get_policy_status(
        State(context): State<Arc<ApiContext>>,
        Path((warehouse_id, namespace, table)): Path<(WarehouseId, String, String)>,
    ) -> Result<Json<PolicyStatus>> {
        let opa_service = OpaIntegrationService::new(context.v1_state.catalog.clone());

        let status = opa_service
            .get_policy_status(warehouse_id, &namespace, &table)
            .await?;

        Ok(Json(status))
    }

    /// Validate policies for a table
    pub async fn validate_policies(
        State(context): State<Arc<ApiContext>>,
        Path((warehouse_id, namespace, table)): Path<(WarehouseId, String, String)>,
    ) -> Result<Json<PolicyValidationResult>> {
        let opa_service = OpaIntegrationService::new(context.v1_state.catalog.clone());

        let validation = opa_service
            .validate_policies(warehouse_id, &namespace, &table)
            .await?;

        Ok(Json(validation))
    }

    /// Generate policies for all tables
    pub async fn generate_all_policies(
        State(context): State<Arc<ApiContext>>,
        Query(params): Query<GeneratePoliciesQuery>,
    ) -> Result<Json<AllPoliciesResponse>> {
        let start_time = std::time::Instant::now();

        let opa_service = OpaIntegrationService::new(context.v1_state.catalog.clone());

        let policies = opa_service.generate_all_table_policies().await?;

        // Count unique tables
        let unique_tables: std::collections::HashSet<String> = policies
            .iter()
            .map(|p| p.applies_to.clone())
            .collect();

        let deployed = if params.deploy.unwrap_or(false) {
            let base_path = params.base_path.as_deref().unwrap_or("./");
            opa_service.deploy_all_policies(base_path).await?;
            true
        } else {
            false
        };

        let generation_time = start_time.elapsed().as_millis() as u64;

        Ok(Json(AllPoliciesResponse {
            total_tables: unique_tables.len(),
            total_policies: policies.len(),
            deployed,
            generation_time_ms: generation_time,
        }))
    }

    /// Deploy all policies to OPA
    pub async fn deploy_all_policies(
        State(context): State<Arc<ApiContext>>,
        Query(params): Query<GeneratePoliciesQuery>,
    ) -> Result<Json<AllPoliciesResponse>> {
        let start_time = std::time::Instant::now();

        let opa_service = OpaIntegrationService::new(context.v1_state.catalog.clone());

        let base_path = params.base_path.as_deref().unwrap_or("./");
        opa_service.deploy_all_policies(base_path).await?;

        // Get stats for response
        let policies = opa_service.generate_all_table_policies().await?;
        let unique_tables: std::collections::HashSet<String> = policies
            .iter()
            .map(|p| p.applies_to.clone())
            .collect();

        let generation_time = start_time.elapsed().as_millis() as u64;

        Ok(Json(AllPoliciesResponse {
            total_tables: unique_tables.len(),
            total_policies: policies.len(),
            deployed: true,
            generation_time_ms: generation_time,
        }))
    }

    /// Get OPA deployment status
    pub async fn get_deployment_status(
        State(context): State<Arc<ApiContext>>,
    ) -> Result<Json<DeploymentStatus>> {
        let opa_service = OpaIntegrationService::new(context.v1_state.catalog.clone());

        let status = opa_service.get_deployment_status().await?;

        Ok(Json(status))
    }

    /// Refresh policies from database
    pub async fn refresh_policies(
        State(context): State<Arc<ApiContext>>,
    ) -> Result<Json<AllPoliciesResponse>> {
        let start_time = std::time::Instant::now();

        let opa_service = OpaIntegrationService::new(context.v1_state.catalog.clone());

        opa_service.refresh_policies().await?;

        // Get stats for response
        let policies = opa_service.generate_all_table_policies().await?;
        let unique_tables: std::collections::HashSet<String> = policies
            .iter()
            .map(|p| p.applies_to.clone())
            .collect();

        let generation_time = start_time.elapsed().as_millis() as u64;

        Ok(Json(AllPoliciesResponse {
            total_tables: unique_tables.len(),
            total_policies: policies.len(),
            deployed: true,
            generation_time_ms: generation_time,
        }))
    }
}

/// Webhook handlers for OPA policy updates
pub struct OpaWebhookHandlers;

#[derive(Debug, Deserialize)]
pub struct PolicyChangeNotification {
    pub table_identifier: String,
    pub change_type: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

impl OpaWebhookHandlers {
    /// Create router for OPA webhook endpoints
    pub fn create_router() -> Router<Arc<ApiContext>> {
        Router::new()
            .route("/opa/webhooks/policy-changed", post(Self::handle_policy_change))
            .route("/opa/webhooks/deployment-status", post(Self::handle_deployment_status))
    }

    /// Handle policy change notifications
    pub async fn handle_policy_change(
        State(context): State<Arc<ApiContext>>,
        Json(notification): Json<PolicyChangeNotification>,
    ) -> Result<StatusCode> {
        tracing::info!(
            "Received policy change notification for table: {} (type: {})",
            notification.table_identifier,
            notification.change_type
        );

        let opa_service = OpaIntegrationService::new(context.v1_state.catalog.clone());

        opa_service
            .notify_policy_change(&notification.table_identifier)
            .await?;

        Ok(StatusCode::OK)
    }

    /// Handle deployment status updates
    pub async fn handle_deployment_status(
        State(context): State<Arc<ApiContext>>,
        Json(status): Json<DeploymentStatus>,
    ) -> Result<StatusCode> {
        tracing::info!(
            "Received deployment status update: deployed={}, active_policies={}",
            status.is_deployed,
            status.active_policies
        );

        // Store deployment status or take appropriate action
        // This would typically update a status table or trigger notifications

        Ok(StatusCode::OK)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::StatusCode;
    use serde_json::json;

    #[tokio::test]
    async fn test_policy_generation_response_serialization() {
        let response = PolicyGenerationResponse {
            table_identifier: "warehouse.namespace.table".to_string(),
            policies_generated: 3,
            deployed: true,
            generation_time_ms: 150,
        };

        let json = serde_json::to_value(&response).unwrap();
        assert_eq!(json["policies_generated"], 3);
        assert_eq!(json["deployed"], true);
    }

    #[tokio::test]
    async fn test_policy_validation_response() {
        let validation = PolicyValidationResult {
            table_identifier: "warehouse.namespace.table".to_string(),
            is_valid: false,
            issues: vec!["Column has too many permissions".to_string()],
            recommendations: vec!["Consider using role-based permissions".to_string()],
        };

        let json = serde_json::to_value(&validation).unwrap();
        assert_eq!(json["is_valid"], false);
        assert_eq!(json["issues"].as_array().unwrap().len(), 1);
    }
}