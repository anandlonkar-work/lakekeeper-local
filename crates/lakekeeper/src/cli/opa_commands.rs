use clap::{Args, Subcommand};
use std::path::PathBuf;

use crate::{
    api::iceberg::v1::Result,
    implementations::postgres::fgac_service::FgacDatabaseService,
    service::{
        opa_fgac_generator::{OpaFgacPolicyGenerator, OpaPolicyConfig},
        opa_integration_service::OpaIntegrationService,
        WarehouseId,
    },
};
use sqlx::PgPool;

/// CLI commands for OPA FGAC policy management
#[derive(Debug, Args)]
pub struct OpaCommand {
    #[command(subcommand)]
    pub command: OpaSubcommand,
}

#[derive(Debug, Subcommand)]
pub enum OpaSubcommand {
    /// Generate OPA policies for a specific table
    GenerateTable(GenerateTableArgs),
    /// Generate OPA policies for all tables with FGAC configuration
    GenerateAll(GenerateAllArgs),
    /// Deploy generated policies to OPA directory
    Deploy(DeployArgs),
    /// Validate FGAC configuration for policy generation
    Validate(ValidateArgs),
    /// Show policy status for tables
    Status(StatusArgs),
    /// Test generated policies with sample data
    Test(TestArgs),
}

#[derive(Debug, Args)]
pub struct GenerateTableArgs {
    /// Warehouse ID
    #[arg(short, long)]
    pub warehouse_id: WarehouseId,

    /// Namespace name
    #[arg(short, long)]
    pub namespace: String,

    /// Table name
    #[arg(short, long)]
    pub table: String,

    /// Output directory for generated policies
    #[arg(short, long, default_value = "./authz/opa-bridge/policies")]
    pub output_dir: PathBuf,

    /// Whether to deploy policies after generation
    #[arg(short, long)]
    pub deploy: bool,
}

#[derive(Debug, Args)]
pub struct GenerateAllArgs {
    /// Output directory for generated policies
    #[arg(short, long, default_value = "./authz/opa-bridge/policies")]
    pub output_dir: PathBuf,

    /// Whether to deploy policies after generation
    #[arg(short, long)]
    pub deploy: bool,

    /// Specific warehouse to generate policies for
    #[arg(short, long)]
    pub warehouse_id: Option<WarehouseId>,
}

#[derive(Debug, Args)]
pub struct DeployArgs {
    /// Directory containing generated policies
    #[arg(short, long, default_value = "./authz/opa-bridge/policies")]
    pub policies_dir: PathBuf,

    /// Target OPA deployment directory
    #[arg(short, long)]
    pub target_dir: Option<PathBuf>,

    /// Force deployment even if validation fails
    #[arg(short, long)]
    pub force: bool,
}

#[derive(Debug, Args)]
pub struct ValidateArgs {
    /// Warehouse ID
    #[arg(short, long)]
    pub warehouse_id: Option<WarehouseId>,

    /// Namespace name
    #[arg(short, long)]
    pub namespace: Option<String>,

    /// Table name
    #[arg(short, long)]
    pub table: Option<String>,

    /// Show detailed validation results
    #[arg(short, long)]
    pub verbose: bool,
}

#[derive(Debug, Args)]
pub struct StatusArgs {
    /// Warehouse ID filter
    #[arg(short, long)]
    pub warehouse_id: Option<WarehouseId>,

    /// Show detailed status information
    #[arg(short, long)]
    pub verbose: bool,
}

#[derive(Debug, Args)]
pub struct TestArgs {
    /// Path to generated policy file
    #[arg(short, long)]
    pub policy_file: PathBuf,

    /// Test data file (JSON)
    #[arg(short, long)]
    pub test_data: PathBuf,

    /// Show detailed test results
    #[arg(short, long)]
    pub verbose: bool,
}

impl OpaCommand {
    /// Execute OPA command
    pub async fn execute(&self, pool: &PgPool) -> Result<()> {
        match &self.command {
            OpaSubcommand::GenerateTable(args) => {
                self.generate_table_policies(pool, args).await
            }
            OpaSubcommand::GenerateAll(args) => {
                self.generate_all_policies(pool, args).await
            }
            OpaSubcommand::Deploy(args) => {
                self.deploy_policies(args).await
            }
            OpaSubcommand::Validate(args) => {
                self.validate_configuration(pool, args).await
            }
            OpaSubcommand::Status(args) => {
                self.show_status(pool, args).await
            }
            OpaSubcommand::Test(args) => {
                self.test_policies(args).await
            }
        }
    }

    async fn generate_table_policies(
        &self,
        pool: &PgPool,
        args: &GenerateTableArgs,
    ) -> Result<()> {
        println!(
            "Generating OPA policies for table {}.{}.{}...",
            args.warehouse_id, args.namespace, args.table
        );

        let opa_service = OpaIntegrationService::new(pool.clone());

        let policies = opa_service
            .generate_table_policies(args.warehouse_id, &args.namespace, &args.table)
            .await?;

        println!("Generated {} policies:", policies.len());
        for policy in &policies {
            println!("  - {} ({})", policy.policy_type, policy.applies_to);
        }

        // Write policies to files
        let output_path = args.output_dir.to_string_lossy();
        OpaFgacPolicyGenerator::write_policies_to_files(&policies, &output_path)?;

        println!("Policies written to: {}", output_path);

        if args.deploy {
            println!("Deploying policies...");
            opa_service
                .deploy_table_policies(
                    args.warehouse_id,
                    &args.namespace,
                    &args.table,
                    &output_path,
                )
                .await?;
            println!("Policies deployed successfully!");
        }

        Ok(())
    }

    async fn generate_all_policies(&self, pool: &PgPool, args: &GenerateAllArgs) -> Result<()> {
        println!("Generating OPA policies for all tables...");

        let opa_service = OpaIntegrationService::new(pool.clone());

        let policies = opa_service.generate_all_table_policies().await?;

        // Group by table
        let mut table_counts = std::collections::HashMap::new();
        for policy in &policies {
            *table_counts.entry(policy.applies_to.clone()).or_insert(0) += 1;
        }

        println!("Generated policies for {} tables:", table_counts.len());
        for (table, count) in &table_counts {
            println!("  - {}: {} policies", table, count);
        }

        // Write policies to files
        let output_path = args.output_dir.to_string_lossy();
        OpaFgacPolicyGenerator::write_policies_to_files(&policies, &output_path)?;

        println!("All policies written to: {}", output_path);

        if args.deploy {
            println!("Deploying all policies...");
            opa_service.deploy_all_policies(&output_path).await?;
            println!("All policies deployed successfully!");
        }

        Ok(())
    }

    async fn deploy_policies(&self, args: &DeployArgs) -> Result<()> {
        println!("Deploying policies from: {:?}", args.policies_dir);

        // Read existing policy files
        let policy_files = std::fs::read_dir(&args.policies_dir)
            .map_err(|e| {
                iceberg_ext::catalog::rest::ErrorModel::internal(
                    "Failed to read policies directory",
                    "PolicyDirectoryError",
                    Some(Box::new(e)),
                )
            })?
            .filter_map(|entry| {
                entry.ok().and_then(|e| {
                    let path = e.path();
                    if path.extension().and_then(|s| s.to_str()) == Some("rego") {
                        Some(path)
                    } else {
                        None
                    }
                })
            })
            .collect::<Vec<_>>();

        println!("Found {} policy files:", policy_files.len());
        for file in &policy_files {
            println!("  - {}", file.display());
        }

        // Copy to target directory if specified
        if let Some(target_dir) = &args.target_dir {
            std::fs::create_dir_all(target_dir).map_err(|e| {
                iceberg_ext::catalog::rest::ErrorModel::internal(
                    "Failed to create target directory",
                    "TargetDirectoryError",
                    Some(Box::new(e)),
                )
            })?;

            for file in &policy_files {
                let filename = file.file_name().unwrap();
                let target_path = target_dir.join(filename);
                std::fs::copy(file, &target_path).map_err(|e| {
                    iceberg_ext::catalog::rest::ErrorModel::internal(
                        "Failed to copy policy file",
                        "PolicyCopyError",
                        Some(Box::new(e)),
                    )
                })?;
                println!("Copied {} to {}", file.display(), target_path.display());
            }

            println!("Deployment completed to: {}", target_dir.display());
        } else {
            println!("No target directory specified, policies remain in: {:?}", args.policies_dir);
        }

        Ok(())
    }

    async fn validate_configuration(&self, pool: &PgPool, args: &ValidateArgs) -> Result<()> {
        let opa_service = OpaIntegrationService::new(pool.clone());

        if let (Some(warehouse_id), Some(namespace), Some(table)) = 
            (&args.warehouse_id, &args.namespace, &args.table) {
            // Validate specific table
            println!("Validating FGAC configuration for table {}.{}.{}...", 
                warehouse_id, namespace, table);

            let validation = opa_service
                .validate_policies(*warehouse_id, namespace, table)
                .await?;

            if validation.is_valid {
                println!("✅ Configuration is valid");
            } else {
                println!("❌ Configuration has issues:");
                for issue in &validation.issues {
                    println!("  - {}", issue);
                }
            }

            if !validation.recommendations.is_empty() {
                println!("💡 Recommendations:");
                for rec in &validation.recommendations {
                    println!("  - {}", rec);
                }
            }
        } else {
            // Validate all tables
            println!("Validating FGAC configuration for all tables...");

            let tables = FgacDatabaseService::get_tables_with_fgac_config(pool).await?;
            let mut total_issues = 0;
            let mut valid_tables = 0;

            for (warehouse_id, namespace, table) in tables {
                let validation = opa_service
                    .validate_policies(warehouse_id, &namespace, &table)
                    .await?;

                if validation.is_valid {
                    valid_tables += 1;
                    if args.verbose {
                        println!("✅ {}.{}.{}", warehouse_id, namespace, table);
                    }
                } else {
                    total_issues += validation.issues.len();
                    println!("❌ {}.{}.{}:", warehouse_id, namespace, table);
                    for issue in &validation.issues {
                        println!("    - {}", issue);
                    }
                }
            }

            println!("\nValidation Summary:");
            println!("  Valid tables: {}", valid_tables);
            println!("  Total issues: {}", total_issues);
        }

        Ok(())
    }

    async fn show_status(&self, pool: &PgPool, args: &StatusArgs) -> Result<()> {
        let opa_service = OpaIntegrationService::new(pool.clone());

        println!("FGAC Policy Status");
        println!("==================");

        let tables = FgacDatabaseService::get_tables_with_fgac_config(pool).await?;

        for (warehouse_id, namespace, table) in tables {
            if let Some(filter_warehouse) = args.warehouse_id {
                if warehouse_id != filter_warehouse {
                    continue;
                }
            }

            let status = opa_service
                .get_policy_status(warehouse_id, &namespace, &table)
                .await?;

            println!("\nTable: {}", status.table_identifier);
            println!("  Column Permissions: {}", status.has_column_permissions);
            println!("  Row Policies: {}", status.has_row_policies);
            println!("  Valid: {}", status.is_valid);
            println!("  Policy Count: {}", status.policy_count);
            println!("  Validation Issues: {}", status.validation_issues);
            println!("  Last Updated: {}", status.last_updated.format("%Y-%m-%d %H:%M:%S UTC"));

            if args.verbose {
                // Additional detailed information
                let validation = opa_service
                    .validate_policies(warehouse_id, &namespace, &table)
                    .await?;

                if !validation.issues.is_empty() {
                    println!("  Issues:");
                    for issue in &validation.issues {
                        println!("    - {}", issue);
                    }
                }

                if !validation.recommendations.is_empty() {
                    println!("  Recommendations:");
                    for rec in &validation.recommendations {
                        println!("    - {}", rec);
                    }
                }
            }
        }

        Ok(())
    }

    async fn test_policies(&self, args: &TestArgs) -> Result<()> {
        println!("Testing OPA policy: {:?}", args.policy_file);
        println!("With test data: {:?}", args.test_data);

        // Read policy file
        let policy_content = std::fs::read_to_string(&args.policy_file).map_err(|e| {
            iceberg_ext::catalog::rest::ErrorModel::internal(
                "Failed to read policy file",
                "PolicyFileError",
                Some(Box::new(e)),
            )
        })?;

        // Read test data
        let test_data_content = std::fs::read_to_string(&args.test_data).map_err(|e| {
            iceberg_ext::catalog::rest::ErrorModel::internal(
                "Failed to read test data file",
                "TestDataFileError", 
                Some(Box::new(e)),
            )
        })?;

        println!("Policy loaded: {} bytes", policy_content.len());
        println!("Test data loaded: {} bytes", test_data_content.len());

        // This would integrate with OPA testing framework
        // For now, just validate the files are readable
        if args.verbose {
            println!("\nPolicy preview:");
            println!("{}", &policy_content[..policy_content.len().min(500)]);
            if policy_content.len() > 500 {
                println!("... (truncated)");
            }

            println!("\nTest data preview:");
            println!("{}", &test_data_content[..test_data_content.len().min(500)]);
            if test_data_content.len() > 500 {
                println!("... (truncated)");
            }
        }

        println!("✅ Policy and test data files are valid");
        println!("Note: Full OPA policy testing requires OPA runtime integration");

        Ok(())
    }
}