resource "random_uuid" "stack_compartment_name" {
}

resource "oci_identity_compartment" "stack_compartment" {
    compartment_id = var.compartment_ocid
    name = random_uuid.stack_compartment_name.result
    description = var.stack_compartment_description
}

resource "random_string" "topic_name" {
  length  = 10
  special = false
}

resource "random_string" "project_name" {
  length  = 10
  special = false
}

resource "oci_ons_notification_topic" "notification_topic" {
  compartment_id = var.compartment_ocid
  name = random_string.topic_name.result
}

resource "oci_devops_project" "project" {
  compartment_id = var.compartment_ocid
  name = random_string.project_name.result
  notification_config {
    topic_id = oci_ons_notification_topic.notification_topic.id
  }
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
    content = var.github_token
  }
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
      repository_url = var.github_url
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

module "munn-fn" {
  source = "./modules/munn-fn"
  tenancy_ocid = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  image_uris = oci_devops_build_run.initial_build_run.build_outputs[0].delivered_artifacts[0]
}

resource oci_devops_deploy_environment enviroStoreDeployEnv {
  deploy_environment_type = "FUNCTION"
  display_name            = "enviroStore"
  function_id = module.munn-fn.put_function_id
  project_id = oci_devops_project.project.id
}

resource oci_devops_deploy_environment enviroRetrieveDeployEnv {
  deploy_environment_type = "FUNCTION"
  display_name            = "enviroRetrieve"
  function_id = module.munn-fn.get_function_id
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
