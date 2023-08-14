# Munn Deploy - Requires Fn
resource oci_devops_deploy_environment enviroStoreDeployEnv {
  deploy_environment_type = "FUNCTION"
  display_name            = "enviroStore"
  function_id = var.put_function_id
  project_id = var.project_id
}

resource oci_devops_deploy_environment enviroRetrieveDeployEnv {
  deploy_environment_type = "FUNCTION"
  display_name            = "enviroRetrieve"
  function_id = var.get_function_id
  project_id = var.project_id
}

resource oci_devops_deploy_pipeline deployPipeline {
  project_id = var.project_id
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
  docker_image_deploy_artifact_id = var.put_devops_artifact_id
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
  docker_image_deploy_artifact_id = var.get_devops_artifact_id
  function_deploy_environment_id = oci_devops_deploy_environment.enviroRetrieveDeployEnv.id
}

# Append the Triger Deploy build step to the Build pipeline
resource oci_devops_build_pipeline_stage buildTriggerDeployStage {
  build_pipeline_id = var.build_pipeline_id
  build_pipeline_stage_predecessor_collection {
    items {
      id = var.build_pipeline_deliver_stage_id
    }
  }
  build_pipeline_stage_type = "TRIGGER_DEPLOYMENT_PIPELINE"
  deploy_pipeline_id = oci_devops_deploy_pipeline.deployPipeline.id
  display_name       = "Trigger Deployment"
  is_pass_all_parameters_enabled = "true"
}
