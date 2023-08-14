resource "random_string" "topic_name" {
  length  = 10
  special = false
}

resource "random_string" "project_name" {
  length  = 10
  special = false
}

resource "oci_kms_vault" "vault" {
    #Required
    compartment_id = var.compartment_ocid
    display_name = "Test Vault"
    vault_type = "DEFAULT"
}

resource "oci_kms_key" "master_key" {
  #Required
  compartment_id      = var.compartment_ocid
  display_name        = "Master Key"
  management_endpoint = oci_kms_vault.vault.management_endpoint

  key_shape {
    #Required
    algorithm = "AES"
    length    = 32
  }
}

resource oci_vault_secret githubSecret {
  compartment_id = var.compartment_ocid
  key_id = oci_kms_key.master_key.id
  secret_name    = "githubToken"
  vault_id       = oci_kms_vault.vault.id
  secret_content {
    #Required
    content_type = "BASE64"

    #Optional
    content = "PHZhcj4mbHQ7YmFzZTY0X2VuY29kZWRfc2VjcmV0X2NvbnRlbnRzJmd0OzwvdmFyPg=="
  }
}

resource "oci_ons_notification_topic" "notification_topic" {
  compartment_id = var.compartment_ocid
  name = random_string.topic_name.result
}

resource "random_string" "enviroStoreRepoName" {
  length  = 5
  numeric  = false
  special = false
  upper = false
}

resource "random_string" "enviroRetrieveRepoName" {
  length  = 5
  numeric  = false
  special = false
  upper = false
}

resource oci_artifacts_container_repository EnviroStoreRepo {
  compartment_id = var.compartment_ocid
  display_name   = random_string.enviroStoreRepoName.result
}

resource oci_artifacts_container_repository EnviroRetrieveRepo {
  compartment_id = var.compartment_ocid
  display_name   = random_string.enviroRetrieveRepoName.result
}

resource "oci_devops_project" "project" {
  compartment_id = var.compartment_ocid
  name = random_string.project_name.result
  notification_config {
    topic_id = oci_ons_notification_topic.notification_topic.id
  }
}

data "oci_objectstorage_namespace" "ns" {}

resource oci_devops_deploy_artifact EnviroStoreArtifact {
  argument_substitution_mode = "SUBSTITUTE_PLACEHOLDERS"
  deploy_artifact_source {
    deploy_artifact_source_type = "OCIR"
    image_digest = ""
    ## The $$ in Terraform will let us use ${imageVersion} as a literal string and wont try to interpolte it into a Terraform variable, so that OCI can use it as a variable
    image_uri    = "${var.region}.ocir.io/${data.oci_objectstorage_namespace.ns.namespace}/${random_string.enviroStoreRepoName.result}:$${imageVersion}"
  }
  deploy_artifact_type = "DOCKER_IMAGE"
  display_name         = "EnviroStoreRepo"
  project_id = oci_devops_project.project.id
}

resource oci_devops_deploy_artifact EnviroRetrieveArtifact {
  argument_substitution_mode = "SUBSTITUTE_PLACEHOLDERS"
  deploy_artifact_source {
    deploy_artifact_source_type = "OCIR"
    image_digest = ""
    ## The $$ in Terraform will let us use ${imageVersion} as a literal string and wont try to interpolte it into a Terraform variable, so that OCI can use it as a variable
    image_uri    = "${var.region}.ocir.io/${data.oci_objectstorage_namespace.ns.namespace}/${random_string.enviroRetrieveRepoName.result}:$${imageVersion}"
  }
  deploy_artifact_type = "DOCKER_IMAGE"
  display_name         = "EnviroRetrieveRepo"
  project_id = oci_devops_project.project.id
}

resource oci_devops_build_pipeline buildPipeline {
#   build_pipeline_parameters {
#   }
  project_id = oci_devops_project.project.id
}

resource oci_devops_connection githubConnection {
  access_token = oci_vault_secret.githubSecret.id
  connection_type = "GITHUB_ACCESS_TOKEN"
  display_name = "GitHub"
  project_id = oci_devops_project.project.id
}

resource oci_devops_build_pipeline_stage buildImageStage {
  build_pipeline_id = oci_devops_build_pipeline.buildPipeline.id
  build_pipeline_stage_predecessor_collection {
    items {
      id = oci_devops_build_pipeline.buildPipeline.id
    }
  }
  build_pipeline_stage_type = "BUILD"
  build_runner_shape_config {
    build_runner_type = "DEFAULT"
  }
  build_source_collection {
    items {
      branch          = "oci"
      connection_id   = oci_devops_connection.githubConnection.id
      connection_type = "GITHUB"
      name            = "SourceRepo"
      repository_url = "https://github.com/ethanbergstrom/enviro.git"
    }
  }
  display_name = "BuildStage"
  image = "OL7_X86_64_STANDARD_10"
  primary_build_source = "SourceRepo"
}

resource oci_devops_build_pipeline_stage deliverArtifactStage {
  build_pipeline_id = oci_devops_build_pipeline.buildPipeline.id
  build_pipeline_stage_predecessor_collection {
    items {
      id = oci_devops_build_pipeline_stage.buildImageStage.id
    }
  }
  build_pipeline_stage_type = "DELIVER_ARTIFACT"
  deliver_artifact_collection {
    items {
      artifact_id   = oci_devops_deploy_artifact.EnviroStoreArtifact.id
      artifact_name = "munn-put-image"
    }
    items {
      artifact_id   = oci_devops_deploy_artifact.EnviroRetrieveArtifact.id
      artifact_name = "munn-get-image"
    }
  }
  display_name = "DeliverArtifact"
}

resource oci_logging_log_group devopsLogGroup {
  compartment_id = var.compartment_ocid
  display_name = "DevOpsLogGroup"
}

resource oci_logging_log devopsLog {
  configuration {
    source {
      category    = "all"
      resource    = oci_devops_project.project.id
      service     = "devops"
      source_type = "OCISERVICE"
    }
  }
  display_name = "DevOpsLog"
  is_enabled         = "true"
  log_group_id       = oci_logging_log_group.devopsLogGroup.id
  log_type           = "SERVICE"
  retention_duration = "30"
}

resource "oci_identity_dynamic_group" "devopsDynGroup" {
  compartment_id = var.tenancy_ocid
  name           = "devopsDynGroup"
  # Dynamic groups require a description
  description    = "Dynamic group to define the scope of Enviro DevOps Project resources"
  matching_rule = "All {resource.compartment.id = '${var.compartment_ocid}', Any {resource.type = 'devopsdeploypipeline', resource.type = 'devopsbuildpipeline', resource.type = 'devopsrepository', resource.type = 'devopsconnection', resource.type = 'devopstrigger'}}"
}

resource "oci_identity_policy" "devopsPolicy" {
  name           = "devopsPolicy"
  # Policies require a description
  description    = "Provide the necessary permissions for the Enviro DevOps Project to complete its pipeline steps"
  compartment_id = var.compartment_ocid

  statements = [
    "Allow dynamic-group id ${oci_identity_dynamic_group.devopsDynGroup.id} to manage devops-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.devopsDynGroup.id} to manage functions-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.devopsDynGroup.id} to manage generic-artifacts in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.devopsDynGroup.id} to manage repos in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.devopsDynGroup.id} to use ons-topics in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.devopsDynGroup.id} to read secret-family in compartment id ${var.compartment_ocid}",
  ]
}

# Do initial run to populate the repository with images
resource "oci_devops_build_run" "initial_build_run" {
  #Required
  build_pipeline_id = oci_devops_build_pipeline.buildPipeline.id
  # Ensure it runs after DeliverArtifact stage is in place, Logging is enabled, and necessarily permissions are granted
  depends_on = [oci_logging_log.devopsLog,oci_devops_build_pipeline_stage.deliverArtifactStage,oci_identity_policy.devopsPolicy]
}

resource "random_string" "database_name" {
  length  = 5
  numeric  = false
  special = false
  upper = false
}

resource "oci_nosql_table" "database" {
    compartment_id = var.compartment_ocid
    name = random_string.database_name.result
    # Examples: https://docs.oracle.com/en/database/other-databases/nosql-database/22.3/java-driver-table/create-table.html
    # Key design: https://docs.oracle.com/en/database/other-databases/nosql-database/22.3/java-driver-table/primary-keys.html
    # Index design: https://docs.oracle.com/en/database/other-databases/nosql-database/22.3/java-driver-table/creating-indexes.html
    ddl_statement = "CREATE TABLE IF NOT EXISTS ${random_string.database_name.result} (id STRING AS UUID GENERATED BY DEFAULT, createdAt TIMESTAMP(0), collectedAt TIMESTAMP(0), temperature FLOAT, pressure FLOAT, lux FLOAT, PRIMARY KEY (id))"
    table_limits {
        max_read_units = "25"
        max_write_units = "25"
        max_storage_in_gbs = "5"
    }
}

resource "random_uuid" "application_name" {
}

resource "oci_core_vcn" "function_vcn" {
  compartment_id = var.compartment_ocid
  cidr_blocks = [var.vcn_cidr_block]
}

resource "oci_core_network_security_group" "function_security_group" {
  compartment_id = var.compartment_ocid
  vcn_id = oci_core_vcn.function_vcn.id
}

resource "oci_core_internet_gateway" "function_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id = oci_core_vcn.function_vcn.id
}

resource "oci_core_default_route_table" "function_default_route" {
  manage_default_resource_id = oci_core_vcn.function_vcn.default_route_table_id

  route_rules {
    description = "Default Route"
	  destination = "0.0.0.0/0"
	  network_entity_id = oci_core_internet_gateway.function_gateway.id
  }
}

resource oci_core_security_list apiSecurityList {
  compartment_id = var.compartment_ocid
  display_name = "apiSecurityList"
  egress_security_rules {
    destination      = "0.0.0.0/0"
    protocol  = "6"
  }
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    tcp_options {
      max = "443"
      min = "443"
    }
  }
  vcn_id = oci_core_vcn.function_vcn.id
}

resource "oci_core_subnet" "function_subnet" {
  compartment_id = var.compartment_ocid
  vcn_id = oci_core_vcn.function_vcn.id
  # Use the entire VCN
  cidr_block = var.vcn_cidr_block
  security_list_ids = [
    oci_core_security_list.apiSecurityList.id
  ]
}

resource "oci_functions_application" "function_application" {
  compartment_id = var.compartment_ocid
  display_name = random_uuid.application_name.result
  subnet_ids = [oci_core_subnet.function_subnet.id]
  # Set env vars for all functions
  config = {
    "TABLE_NAME" = random_string.database_name.result
    "COMPARTMENT_OCID" = var.compartment_ocid
  }
}

resource oci_logging_log_group fnAppLogGroup {
  compartment_id = var.compartment_ocid
  display_name = "FnAppLogGroup"
}

resource oci_logging_log fnAppLog {
  configuration {
    source {
      category    = "invoke"
      resource    = oci_functions_application.function_application.id
      service     = "functions"
      source_type = "OCISERVICE"
    }
  }
  display_name = "FnAppLog"
  is_enabled         = "true"
  log_group_id       = oci_logging_log_group.fnAppLogGroup.id
  log_type           = "SERVICE"
  retention_duration = "30"
}

resource "oci_functions_function" "enviroStore" {
  application_id = oci_functions_application.function_application.id
  display_name   = "enviroStore"
  memory_in_mbs  = "128"
  image = "${oci_devops_build_run.initial_build_run.build_outputs[0].delivered_artifacts[0].items[0].image_uri}"
  
  lifecycle {
    ignore_changes = [image,image_digest]
  }
}

resource "oci_functions_function" "enviroRetrieve" {
  application_id = oci_functions_application.function_application.id
  display_name   = "enviroRetrieve"
  memory_in_mbs  = "128"
  image = "${oci_devops_build_run.initial_build_run.build_outputs[0].delivered_artifacts[0].items[1].image_uri}"
  
  lifecycle {
    ignore_changes = [image,image_digest]
  }
}

resource oci_devops_deploy_environment enviroStoreDeployEnv {
  deploy_environment_type = "FUNCTION"
  display_name            = "enviroStore"
  function_id = oci_functions_function.enviroStore.id
  project_id = oci_devops_project.project.id
}

resource oci_devops_deploy_environment enviroRetrieveDeployEnv {
  deploy_environment_type = "FUNCTION"
  display_name            = "enviroRetrieve"
  function_id = oci_functions_function.enviroRetrieve.id
  project_id = oci_devops_project.project.id
}

resource oci_devops_deploy_pipeline deployPipeline {
  project_id = oci_devops_project.project.id
}

resource oci_devops_deploy_stage enviroStoreDeployStage {
  deploy_pipeline_id = oci_devops_deploy_pipeline.deployPipeline.id
  deploy_stage_predecessor_collection {
    items {
      id = oci_devops_deploy_pipeline.deployPipeline.id
    }
  }
  deploy_stage_type = "DEPLOY_FUNCTION"
  display_name                    = "enviroStore"
  docker_image_deploy_artifact_id = oci_devops_deploy_artifact.EnviroStoreArtifact.id
  function_deploy_environment_id = oci_devops_deploy_environment.enviroStoreDeployEnv.id
}

resource oci_devops_deploy_stage enviroRetrieveDeployStage {
  deploy_pipeline_id = oci_devops_deploy_pipeline.deployPipeline.id
  deploy_stage_predecessor_collection {
    items {
      id = oci_devops_deploy_pipeline.deployPipeline.id
    }
  }
  deploy_stage_type = "DEPLOY_FUNCTION"
  display_name                    = "enviroRetrieve"
  docker_image_deploy_artifact_id = oci_devops_deploy_artifact.EnviroRetrieveArtifact.id
  function_deploy_environment_id = oci_devops_deploy_environment.enviroRetrieveDeployEnv.id
}

# Append the Triger Deploy build step to the Build pipeline
resource oci_devops_build_pipeline_stage buildTriggerDeployStage {
  build_pipeline_id = oci_devops_build_pipeline.buildPipeline.id
  build_pipeline_stage_predecessor_collection {
    items {
      id = oci_devops_build_pipeline_stage.deliverArtifactStage.id
    }
  }
  build_pipeline_stage_type = "TRIGGER_DEPLOYMENT_PIPELINE"
  deploy_pipeline_id = oci_devops_deploy_pipeline.deployPipeline.id
  display_name       = "Trigger Deployment"
  is_pass_all_parameters_enabled = "true"
}

resource "oci_identity_dynamic_group" enviroFnAppDynGroup {
  compartment_id = var.tenancy_ocid
  name           = "enviroFnAppDynGroup"
  # Dynamic groups require a description
  description    = "Dynamic group to define the scope of Enviro Fn resource identities"
  matching_rule = "All {resource.compartment.id = '${var.compartment_ocid}', resource.type = 'fnfunc'}}"
}

resource "oci_identity_policy" environFnAppPolicy {
  name           = "environFnAppPolicy"
  # Policies require a description
  description    = "Provide the necessary permissions for the Enviro DevOps Project to complete its pipeline steps"
  compartment_id = var.compartment_ocid

  statements = [
    "Allow dynamic-group id ${oci_identity_dynamic_group.enviroFnAppDynGroup.id} to use nosql-rows in compartment id ${var.compartment_ocid}"
  ]
}

resource "oci_identity_user" enviroStoreSvcUser {
  name           = "enviroStoreSvcUser"
  # Policies require a description
  description    = "Simple user with permission to invoke the enviroStore function"
  compartment_id = var.tenancy_ocid
}

resource "oci_identity_group" enviroStoreSvcGroup {
  compartment_id = var.tenancy_ocid
  name           = "enviroStoreSvcGroup"
  # Dynamic groups require a description
  description    = "Simple group with permission to invoke the enviroStore function"
}

resource "oci_identity_user_group_membership" "enviroStoreSvcGroupMember" {
    #Required
    group_id = oci_identity_group.enviroStoreSvcGroup.id
    user_id = oci_identity_user.enviroStoreSvcUser.id
}

resource "oci_identity_policy" enviroStoreSvcPolicy {
  name           = "enviroStoreSvcPolicy"
  # Policies require a description
  description    = "Only allow enviroStore service account access to invoke corresponding function"
  compartment_id = var.compartment_ocid

  statements = [
    "Allow group id ${oci_identity_group.enviroStoreSvcGroup.id} to use fn-invocation in compartment id ${var.compartment_ocid} where target.function.id = '${oci_functions_function.enviroStore.id}'"
  ]
}

resource oci_apigateway_gateway enviroGateway {
  compartment_id = var.compartment_ocid
  display_name  = "enviroGateway"
  endpoint_type = "PUBLIC"
  subnet_id = oci_core_subnet.function_subnet.id
}

resource oci_apigateway_deployment envrioAPIDeploy {
  compartment_id = var.compartment_ocid
  display_name = "envrioAPIDeploy"
  gateway_id  = oci_apigateway_gateway.enviroGateway.id
  path_prefix = "/"
  specification {
    routes {
      backend {
        function_id = oci_functions_function.enviroRetrieve.id
        type = "ORACLE_FUNCTIONS_BACKEND"
      }
      methods = [
        "POST",
      ]
      path = "/enviroRetrieve"
      request_policies {
        cors {
          allowed_headers = [
            "*",
          ]
          allowed_methods = [
            "*",
          ]
          allowed_origins = [
            "*",
          ]
          exposed_headers = [
            "*",
          ]
          is_allow_credentials_enabled = "false"
          max_age_in_seconds           = "0"
        }
      }
    }
  }
}

resource oci_logging_log_group apiGatewayLogGroup {
  compartment_id = var.compartment_ocid
  display_name = "apiGatewayLogGroup"
}

resource oci_logging_log envrioAPIDeploy_execution {
  configuration {
    compartment_id = var.compartment_ocid
    source {
      category    = "execution"
      resource    = oci_apigateway_deployment.envrioAPIDeploy.id
      service     = "apigateway"
      source_type = "OCISERVICE"
    }
  }
  display_name = "envrioAPIDeploy_execution"
  is_enabled         = "true"
  log_group_id       = oci_logging_log_group.apiGatewayLogGroup.id
  log_type           = "SERVICE"
  retention_duration = "30"
}

resource oci_logging_log envrioAPIDeploy_access {
  configuration {
    compartment_id = var.compartment_ocid
    source {
      category    = "access"
      resource    = oci_apigateway_deployment.envrioAPIDeploy.id
      service     = "apigateway"
      source_type = "OCISERVICE"
    }
  }
  display_name = "envrioAPIDeploy_access"
  is_enabled         = "true"
  log_group_id       = oci_logging_log_group.apiGatewayLogGroup.id
  log_type           = "SERVICE"
  retention_duration = "30"
}

resource "oci_identity_dynamic_group" "apiGatewayDynGroup" {
  compartment_id = var.tenancy_ocid
  name           = "apiGatewayDynGroup"
  # Dynamic groups require a description
  description    = "Dynamic group to define the scope of API GateWay that can invoke EnviroRetrieve"
  matching_rule = "All {resource.compartment.id = '${var.compartment_ocid}', resource.type = 'apigateway'}"
}

resource "oci_identity_policy" "apiGatewayPolicy" {
  name           = "apiGatewayPolicy"
  # Policies require a description
  description    = "Provide the necessary permissions for the API Gateway to invoke the EnviroRetrieve function"
  compartment_id = var.compartment_ocid

  statements = [
    "Allow dynamic-group id ${oci_identity_dynamic_group.apiGatewayDynGroup.id} to use fn-invocation in compartment id ${var.compartment_ocid} where target.function.id = '${oci_functions_function.enviroRetrieve.id}'"
  ]
}