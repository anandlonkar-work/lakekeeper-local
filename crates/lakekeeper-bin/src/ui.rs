use std::{default::Default, env::VarError, sync::LazyLock};

use lakekeeper::{
    axum,
    axum::{
        body::Body,
        http::{header, HeaderMap, HeaderValue, StatusCode, Uri},
        response::{IntoResponse, Response},
        routing::get,
        Router,
    },
    determine_base_uri,
    request_tracing::{MakeRequestUuid7, RestMakeSpan},
    tower,
    tower_http::{
        catch_panic::CatchPanicLayer,
        compression::CompressionLayer,
        sensitive_headers::SetSensitiveHeadersLayer,
        timeout::TimeoutLayer,
        trace::{self, TraceLayer},
        ServiceBuilderExt,
    },
    tracing, AuthZBackend, CONFIG, X_FORWARDED_PREFIX_HEADER,
};
use lakekeeper_console::{CacheItem, FileCache, LakekeeperConsoleConfig};

// Static configuration for UI
static UI_CONFIG: LazyLock<LakekeeperConsoleConfig> = LazyLock::new(|| {
    let default_config = LakekeeperConsoleConfig::default();
    let config = LakekeeperConsoleConfig {
        idp_authority: std::env::var("LAKEKEEPER__UI__OPENID_PROVIDER_URI")
            .ok()
            .or(CONFIG
                .openid_provider_uri
                .clone()
                .map(|uri| uri.to_string()))
            .unwrap_or(default_config.idp_authority),
        idp_client_id: std::env::var("LAKEKEEPER__UI__OPENID_CLIENT_ID")
            .unwrap_or(default_config.idp_client_id),
        idp_redirect_path: std::env::var("LAKEKEEPER__UI__OPENID_REDIRECT_PATH")
            .unwrap_or(default_config.idp_redirect_path),
        idp_scope: std::env::var("LAKEKEEPER__UI__OPENID_SCOPE")
            .unwrap_or(default_config.idp_scope),
        idp_resource: std::env::var("LAKEKEEPER__UI__OPENID_RESOURCE")
            .unwrap_or(default_config.idp_resource),
        idp_post_logout_redirect_path: std::env::var(
            "LAKEKEEPER__UI__OPENID_POST_LOGOUT_REDIRECT_PATH",
        )
        .unwrap_or(default_config.idp_post_logout_redirect_path),
        idp_token_type: match std::env::var("LAKEKEEPER__UI__OPENID_TOKEN_TYPE").as_deref() {
            Ok("id_token") => lakekeeper_console::IdpTokenType::IdToken,
            Ok("access_token") | Err(VarError::NotPresent) => {
                lakekeeper_console::IdpTokenType::AccessToken
            }
            Ok(v) => {
                tracing::warn!(
                    "Unknown value `{v}` for LAKEKEEPER__UI__OPENID_TOKEN_TYPE, defaulting to AccessToken. Expected values are 'id_token' or 'access_token'.", 
                );
                lakekeeper_console::IdpTokenType::AccessToken
            }
            Err(VarError::NotUnicode(_)) => {
                tracing::warn!(
                    "Non-Unicode value for LAKEKEEPER__UI__OPENID_TOKEN_TYPE, defaulting to AccessToken."
                );
                default_config.idp_token_type
            }
        },
        enable_authentication: CONFIG.openid_provider_uri.is_some(),
        enable_permissions: CONFIG.authz_backend == AuthZBackend::OpenFGA,
        app_lakekeeper_url: std::env::var("LAKEKEEPER__UI__LAKEKEEPER_URL")
            .ok()
            .or(CONFIG.base_uri.as_ref().map(ToString::to_string)),
        base_url_prefix: CONFIG.base_uri.as_ref().and_then(|uri| {
            let path_stripped = uri.path().trim_matches('/');
            if path_stripped.is_empty() {
                None
            } else {
                Some(format!("/{path_stripped}"))
            }
        }),
    };
    tracing::debug!("UI config: {:?}", config);
    config
});

// Create a global file cache initialized with the UI config
static FILE_CACHE: LazyLock<FileCache> = LazyLock::new(|| FileCache::new(UI_CONFIG.clone()));

// We use static route matchers ("/" and "/index.html") to serve our home page
pub(crate) async fn index_handler(headers: HeaderMap) -> impl IntoResponse {
    static_handler("/index.html".parse::<Uri>().unwrap(), headers).await
}

pub(crate) async fn favicon_handler(headers: HeaderMap) -> impl IntoResponse {
    static_handler("/favicon.ico".parse::<Uri>().unwrap(), headers).await
}

// Handler for static assets
pub(crate) async fn static_handler(uri: Uri, headers: HeaderMap) -> impl IntoResponse {
    let mut path = uri.path().trim_start_matches('/').to_string();

    if path.starts_with("ui/") {
        path = path.replace("ui/", "");
    }

    let forwarded_prefix = forwarded_prefix(&headers);
    let lakekeeper_base_uri = determine_base_uri(&headers);

    tracing::trace!(
        "Serving static file: path={}, forwarded_prefix={:?}, lakekeeper_base_uri={:?}",
        path,
        forwarded_prefix,
        lakekeeper_base_uri
    );
    cache_item_to_response(FILE_CACHE.get_file(
        &path,
        forwarded_prefix,
        lakekeeper_base_uri.as_deref(),
    ))
}

fn forwarded_prefix(headers: &HeaderMap) -> Option<&str> {
    headers
        .get(X_FORWARDED_PREFIX_HEADER)
        .and_then(|hv| hv.to_str().ok())
}

fn cache_item_to_response(item: CacheItem) -> Response {
    match item {
        CacheItem::NotFound => (StatusCode::NOT_FOUND, "404 Not Found").into_response(),
        CacheItem::Found { mime, data } => {
            ([(header::CONTENT_TYPE, mime.as_ref())], data).into_response()
        }
    }
}

// FGAC API proxy handler that forwards requests to the real backend API
pub(crate) async fn fgac_proxy_handler(
    axum::extract::Path((warehouse_id, namespace_table)): axum::extract::Path<(String, String)>,
    headers: HeaderMap,
) -> impl IntoResponse {
    use reqwest::Client;

    // Extract namespace and table from the combined path parameter
    // Expected format: "namespace.table" or "namespace₁ftable" (unicode separator)
    let (namespace, table) = if let Some(dot_pos) = namespace_table.rfind('.') {
        (&namespace_table[..dot_pos], &namespace_table[dot_pos + 1..])
    } else if let Some(sep_pos) = namespace_table.find('\u{1f}') {
        (&namespace_table[..sep_pos], &namespace_table[sep_pos + 1..])
    } else {
        // If no separator found, treat the whole thing as table name in default namespace
        ("default", namespace_table.as_str())
    };

    // Build the backend API URL
    // The real FGAC API is at: /management/v1/warehouse/{warehouse_id}/namespace/{namespace}/table/{table}/fgac/summary
    let backend_url = format!(
        "http://localhost:8181/management/v1/warehouse/{}/namespace/{}/table/{}/fgac/configuration",
        warehouse_id, namespace, table
    );

    // Forward the request to the backend API with authentication headers
    let client = Client::new();
    let mut request_builder = client.get(&backend_url);

    // Log all incoming headers for debugging
    tracing::info!("FGAC proxy - Request received for: {}", backend_url);
    tracing::info!("FGAC proxy - Incoming headers:");
    for (name, value) in headers.iter() {
        tracing::info!("  {}: {:?}", name, value);
    }

    // Forward ALL headers to backend (the backend will filter what it needs)
    for (name, value) in headers.iter() {
        // Skip host and connection headers as they're specific to the proxy connection
        if name != header::HOST && name != header::CONNECTION {
            request_builder = request_builder.header(name, value);
        }
    }

    match request_builder.send().await {
        Ok(response) => {
            let status = response.status();

            let mut headers_to_forward = HeaderMap::new();
            if let Some(content_type) = response.headers().get(header::CONTENT_TYPE) {
                headers_to_forward.insert(header::CONTENT_TYPE, content_type.clone());
            }
            if let Some(content_encoding) = response.headers().get(header::CONTENT_ENCODING) {
                headers_to_forward.insert(header::CONTENT_ENCODING, content_encoding.clone());
            }
            if let Some(cache_control) = response.headers().get(header::CACHE_CONTROL) {
                headers_to_forward.insert(header::CACHE_CONTROL, cache_control.clone());
            }
            if let Some(pragma) = response.headers().get(header::PRAGMA) {
                headers_to_forward.insert(header::PRAGMA, pragma.clone());
            }

            match response.bytes().await {
                Ok(body_bytes) => {
                    let preview_len = body_bytes.len().min(128);
                    let preview = String::from_utf8_lossy(&body_bytes[..preview_len]);
                    tracing::info!(
                        "FGAC proxy - Upstream status: {}, body preview: {}",
                        status,
                        preview
                    );

                    let mut proxy_response = Response::new(Body::from(body_bytes));
                    *proxy_response.status_mut() = status;

                    let headers_mut = proxy_response.headers_mut();
                    for (key, value) in headers_to_forward.iter() {
                        headers_mut.insert(key.clone(), value.clone());
                    }
                    if !headers_mut.contains_key(header::CONTENT_TYPE) {
                        headers_mut.insert(
                            header::CONTENT_TYPE,
                            HeaderValue::from_static("application/json"),
                        );
                    }

                    proxy_response
                }
                Err(e) => {
                    tracing::error!("Failed to read FGAC API response: {}", e);
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        [(header::CONTENT_TYPE, "application/json")],
                        r#"{"error": "Failed to read API response"}"#.to_string(),
                    )
                        .into_response()
                }
            }
        }
        Err(e) => {
            tracing::error!("Failed to call FGAC API: {}", e);
            (
                StatusCode::BAD_GATEWAY,
                [(header::CONTENT_TYPE, "application/json")],
                format!(r#"{{"error": "Failed to connect to FGAC API: {}"}}"#, e),
            )
                .into_response()
        }
    }
}

// Warehouses API proxy handler
pub(crate) async fn warehouses_proxy_handler(headers: HeaderMap) -> impl IntoResponse {
    let mock_response = r#"{{
        "warehouses": [
            {{
                "warehouse_id": "demo",
                "warehouse_name": "demo (created via notebooks)",
                "status": "active"
            }},
            {{
                "warehouse_id": "example",
                "warehouse_name": "example (demo data)",
                "status": "active"
            }}
        ]
    }}"#;

    ([(header::CONTENT_TYPE, "application/json")], mock_response)
}

// Schemas API proxy handler
pub(crate) async fn schemas_proxy_handler(
    axum::extract::Path(warehouse_id): axum::extract::Path<String>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let mock_response = r#"{{
        "namespaces": [
            "sales", 
            "marketing", 
            "finance", 
            "hr",
            "inventory",
            "crm"
        ]
    }}"#;

    ([(header::CONTENT_TYPE, "application/json")], mock_response)
}

// Tables API proxy handler
pub(crate) async fn tables_proxy_handler(
    axum::extract::Path((warehouse_id, schema_name)): axum::extract::Path<(String, String)>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let mock_response = format!(
        r#"{{
        "identifiers": [
            {{ "namespace": "{}", "name": "customers" }},
            {{ "namespace": "{}", "name": "orders" }},
            {{ "namespace": "{}", "name": "products" }},
            {{ "namespace": "{}", "name": "employees" }}
        ]
    }}"#,
        schema_name, schema_name, schema_name, schema_name
    );

    ([(header::CONTENT_TYPE, "application/json")], mock_response)
}

// Note: FGAC tab is integrated into the Vue.js SPA (not a separate server-rendered page)
// The Vue.js application uses the API endpoints below to fetch FGAC data

pub(crate) fn get_ui_router() -> Router {
    Router::new()
        .route("/ui", get(redirect_to_ui))
        .route("/", get(redirect_to_ui))
        .route("/ui/index.html", get(redirect_to_ui))
        .route("/ui/", get(index_handler))
        .route("/ui/favicon.ico", get(favicon_handler))
        .route("/ui/assets/{*file}", get(static_handler))
        // FGAC API endpoints (used by Vue.js SPA)
        // Format: /ui/api/fgac/{warehouse_id}/{namespace.table}
        .route(
            "/ui/api/fgac/{warehouse_id}/{namespace_table}",
            get(fgac_proxy_handler),
        )
        .route("/ui/api/warehouses", get(warehouses_proxy_handler))
        .route("/ui/api/schemas/{warehouse_id}", get(schemas_proxy_handler))
        .route(
            "/ui/api/tables/{warehouse_id}/{schema_name}",
            get(tables_proxy_handler),
        )
        // Catch-all route must be last
        .route("/ui/{*file}", get(index_handler))
        .layer(
            tower::ServiceBuilder::new()
                .set_x_request_id(MakeRequestUuid7)
                .layer(SetSensitiveHeadersLayer::new([
                    axum::http::header::AUTHORIZATION,
                ]))
                .layer(CompressionLayer::new())
                .layer(
                    TraceLayer::new_for_http()
                        .on_failure(())
                        .make_span_with(RestMakeSpan::new(tracing::Level::INFO))
                        .on_response(trace::DefaultOnResponse::new().level(tracing::Level::DEBUG)),
                )
                .layer(TimeoutLayer::new(std::time::Duration::from_secs(30)))
                .layer(CatchPanicLayer::new())
                .propagate_x_request_id(),
        )
}

async fn redirect_to_ui(headers: axum::http::HeaderMap) -> axum::response::Redirect {
    if let Some(prefix) = lakekeeper::determine_forwarded_prefix(&headers) {
        axum::response::Redirect::permanent(format!("/{prefix}/ui/").as_str())
    } else {
        axum::response::Redirect::permanent("/ui/")
    }
}

#[cfg(test)]
mod test {
    use lakekeeper::tokio;

    use super::*;

    #[tokio::test]
    async fn test_index_found() {
        let headers = HeaderMap::new();
        let response = index_handler(headers).await.into_response();
        assert_eq!(response.status(), 200);
        let body = response.into_body();
        let body_str = String::from_utf8(
            axum::body::to_bytes(body, 10000)
                .await
                .expect("Failed to read response body")
                .to_vec(),
        )
        .unwrap();
        assert!(body_str.contains("\"/ui/assets/"));
    }

    #[tokio::test]
    async fn test_index_prefix() {
        let mut headers = HeaderMap::new();
        headers.append(X_FORWARDED_PREFIX_HEADER, "/lakekeeper".parse().unwrap());
        let response = index_handler(headers).await.into_response();
        assert_eq!(response.status(), 200);
        let body = response.into_body();
        let body_str = String::from_utf8(
            axum::body::to_bytes(body, 10000)
                .await
                .expect("Failed to read response body")
                .to_vec(),
        )
        .unwrap();
        assert!(body_str.contains("\"/lakekeeper/ui/assets/"));
    }
}
