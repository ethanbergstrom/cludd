resource random_string base {
  length  = 5
  numeric  = false
  special = false
  upper = false
}

resource oci_identity_compartment base {
  compartment_id = var.compartment_ocid
  name = random_string.base.result
  description = var.stack_compartment_description
}

resource oci_ons_notification_topic base {
  compartment_id = var.compartment_ocid
  name = random_string.base.result
}

resource oci_devops_project base {
  compartment_id = var.compartment_ocid
  name = random_string.base.result

  notification_config {
    topic_id = oci_ons_notification_topic.base.id
  }
}

resource oci_kms_vault base {
  compartment_id = var.compartment_ocid
  display_name = random_string.base.result
  vault_type = "DEFAULT"
}

resource oci_kms_key base {
  compartment_id      = var.compartment_ocid
  display_name = random_string.base.result
  management_endpoint = oci_kms_vault.base.management_endpoint

  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

resource oci_vault_secret base {
  compartment_id = var.compartment_ocid
  key_id = oci_kms_key.base.id
  secret_name    = random_string.base.result
  vault_id       = oci_kms_vault.base.id
  secret_content {
    # Base64 is the only option
    content_type = "BASE64"
    content = base64encode(var.github_token)
  }
}

resource random_string put_repo {
  length  = 5
  numeric  = false
  special = false
  upper = false
}

resource random_string get_repo {
  length  = 5
  numeric  = false
  special = false
  upper = false
}

resource oci_artifacts_container_repository base {
  for_each = {
    put = random_string.put_repo
    get = random_string.get_repo
  }

  compartment_id = var.compartment_ocid
  display_name   = each.value.result
}

data oci_objectstorage_namespace ns {}

resource oci_devops_deploy_artifact base {
  for_each = oci_artifacts_container_repository.base

  argument_substitution_mode = "SUBSTITUTE_PLACEHOLDERS"
  deploy_artifact_type = "DOCKER_IMAGE"
  display_name         = each.key
  project_id = oci_devops_project.base.id

  deploy_artifact_source {
    deploy_artifact_source_type = "OCIR"
    image_digest = ""
    ## The $$ in Terraform will let us use ${imageVersion} as a literal string and wont try to interpolte it into a Terraform variable, so that OCI can use it as a variable
    image_uri    = "${var.region}.ocir.io/${data.oci_objectstorage_namespace.ns.namespace}/${each.value.display_name}:$${imageVersion}"
  }
}

resource oci_devops_build_pipeline base {
  project_id = oci_devops_project.base.id
}

resource oci_devops_connection base {
  access_token = oci_vault_secret.base.id
  connection_type = "GITHUB_ACCESS_TOKEN"
  display_name = "GitHub"
  project_id = oci_devops_project.base.id
}

resource oci_devops_build_pipeline_stage build {
  build_pipeline_id = oci_devops_build_pipeline.base.id
  build_pipeline_stage_type = "BUILD"
  image = "OL7_X86_64_STANDARD_10"
  primary_build_source = "SourceRepo"

  build_pipeline_stage_predecessor_collection {
    items {
      id = oci_devops_build_pipeline.base.id
    }
  }

  build_runner_shape_config {
    build_runner_type = "DEFAULT"
  }

  build_source_collection {
    items {
      branch          = "oci"
      connection_id   = oci_devops_connection.base.id
      connection_type = "GITHUB"
      name            = "SourceRepo"
      repository_url = var.github_url
    }
  }
}

resource oci_devops_build_pipeline_stage deliver {
  build_pipeline_id = oci_devops_build_pipeline.base.id
  build_pipeline_stage_type = "DELIVER_ARTIFACT"

  build_pipeline_stage_predecessor_collection {
    items {
      id = oci_devops_build_pipeline_stage.build.id
    }
  }

  deliver_artifact_collection {
    items {
      artifact_id   = oci_devops_deploy_artifact.base["put"].id
      artifact_name = "munn-put-image"
    }
    items {
      artifact_id   = oci_devops_deploy_artifact.base["get"].id
      artifact_name = "munn-get-image"
    }
  }
}

resource oci_logging_log_group devops {
  compartment_id = var.compartment_ocid
  display_name = "DevOps"
}

resource oci_logging_log devops {
  display_name = "Operations"
  is_enabled         = "true"
  log_group_id       = oci_logging_log_group.devops.id
  log_type           = "SERVICE"
  retention_duration = "30"

  configuration {
    source {
      category    = "all"
      resource    = oci_devops_project.base.id
      service     = "devops"
      source_type = "OCISERVICE"
    }
  }
}

resource random_string devops {
  length  = 5
  numeric  = false
  special = false
  upper = false
}

resource oci_identity_dynamic_group devops {
  compartment_id = var.tenancy_ocid
  name           = random_string.devops.result
  description    = "DevOps resource identities"
  matching_rule = "All {resource.compartment.id = '${var.compartment_ocid}', Any {resource.type = 'devopsdeploypipeline', resource.type = 'devopsbuildpipeline', resource.type = 'devopsrepository', resource.type = 'devopsconnection', resource.type = 'devopstrigger'}}"
}

resource oci_identity_policy devops {
  compartment_id = var.compartment_ocid
  name           = random_string.devops.result
  description    = "DevOps to complete its pipeline steps"

  statements = [
    "Allow dynamic-group id ${oci_identity_dynamic_group.devops.id} to manage devops-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.devops.id} to manage functions-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.devops.id} to manage generic-artifacts in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.devops.id} to manage repos in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.devops.id} to use ons-topics in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.devops.id} to read secret-family in compartment id ${var.compartment_ocid}",
  ]
}

# Do initial run to populate the repository with images
resource oci_devops_build_run base {
  build_pipeline_id = oci_devops_build_pipeline.base.id
  # Ensure it runs after DeliverArtifact stage is in place, Logging is enabled, and necessarily permissions are granted
  depends_on = [oci_logging_log.devops,oci_devops_build_pipeline_stage.deliver,oci_identity_policy.devops]
}

module munn-fn {
  source = "./modules/munn-fn"
  tenancy_ocid = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  image_uris = oci_devops_build_run.base.build_outputs[0].delivered_artifacts[0]
}

resource oci_devops_deploy_environment base {
  for_each = module.munn-fn.function_ids

  deploy_environment_type = "FUNCTION"
  display_name            = each.key
  function_id = each.value
  project_id = oci_devops_project.base.id
}

resource oci_devops_deploy_pipeline base {
  project_id = oci_devops_project.base.id
}

resource oci_devops_deploy_stage base {
  for_each = oci_devops_deploy_environment.base

  deploy_pipeline_id = oci_devops_deploy_pipeline.base.id
  function_deploy_environment_id = each.value.id
  deploy_stage_type = "DEPLOY_FUNCTION"
  display_name                    = each.key
  docker_image_deploy_artifact_id = oci_devops_deploy_artifact.base[each.key].id
  
  deploy_stage_predecessor_collection {
    items {
      id = oci_devops_deploy_pipeline.base.id
    }
  }
}

# Append the Triger Deploy build step to the Build pipeline
resource oci_devops_build_pipeline_stage trigger {
  build_pipeline_id = oci_devops_build_pipeline.base.id
  build_pipeline_stage_predecessor_collection {
    items {
      id = oci_devops_build_pipeline_stage.deliver.id
    }
  }
  build_pipeline_stage_type = "TRIGGER_DEPLOYMENT_PIPELINE"
  deploy_pipeline_id = oci_devops_deploy_pipeline.base.id
  display_name       = "Trigger Deployment"
  is_pass_all_parameters_enabled = "true"
}
