resource oci_apigateway_gateway enviroGateway {
  compartment_id = var.compartment_ocid
  display_name  = "enviroGateway"
  endpoint_type = "PUBLIC"
  subnet_id = var.subnet_id
}

resource oci_apigateway_deployment envrioAPIDeploy {
  compartment_id = var.compartment_ocid
  display_name = "envrioAPIDeploy"
  gateway_id  = oci_apigateway_gateway.enviroGateway.id
  path_prefix = "/"
  specification {
    routes {
      backend {
        function_id = var.get_function_id
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
    "Allow dynamic-group id ${oci_identity_dynamic_group.apiGatewayDynGroup.id} to use fn-invocation in compartment id ${var.compartment_ocid} where target.function.id = '${var.get_function_id}'"
  ]
}