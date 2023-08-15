module core {
  source = "./modules/munn-core"
  compartment_ocid = var.compartment_ocid
}

resource oci_nosql_table base {
    compartment_id = var.compartment_ocid
    name = var.app_name
    # Examples: https://docs.oracle.com/en/database/other-databases/nosql-database/22.3/java-driver-table/create-table.html
    # Key design: https://docs.oracle.com/en/database/other-databases/nosql-database/22.3/java-driver-table/primary-keys.html
    # Index design: https://docs.oracle.com/en/database/other-databases/nosql-database/22.3/java-driver-table/creating-indexes.html
    ddl_statement = "CREATE TABLE IF NOT EXISTS ${var.app_name} (id STRING AS UUID GENERATED BY DEFAULT, createdAt TIMESTAMP(0), collectedAt TIMESTAMP(0), temperature FLOAT, pressure FLOAT, lux FLOAT, PRIMARY KEY (id))"
    table_limits {
        max_read_units = "25"
        max_write_units = "25"
        max_storage_in_gbs = "5"
    }
}

resource oci_functions_application base {
  compartment_id = var.compartment_ocid
  display_name = var.app_name
  subnet_ids = [module.core.subnet_id]
  # Set env vars for all functions
  config = {
    "TABLE_NAME" = var.app_name
    "COMPARTMENT_OCID" = var.compartment_ocid
  }
}

resource oci_logging_log_group fn {
  compartment_id = var.compartment_ocid
  display_name = "Functions"
}

resource oci_logging_log fn {
  configuration {
    source {
      category    = "invoke"
      resource    = oci_functions_application.base.id
      service     = "functions"
      source_type = "OCISERVICE"
    }
  }
  is_enabled         = "true"
  log_group_id       = oci_logging_log_group.fn.id
  log_type           = "SERVICE"
  retention_duration = "30"
  display_name = "Invocations"
}


resource oci_functions_function base {
  for_each = {
    # I dont love this, and want to come back to it later
    put = 0
    get = 1
  }
  application_id = oci_functions_application.base.id
  display_name   = each.key
  memory_in_mbs  = "128"
  image = var.image_uris.items[each.value].image_uri
  
  lifecycle {
    ignore_changes = [image,image_digest]
  }
}

resource random_string fn_nosql {
  length  = 5
  numeric  = false
  special = false
  upper = false
}

resource oci_identity_dynamic_group fn_nosql {
  compartment_id = var.tenancy_ocid
  # Group namespace is tenancy-scoped and need to be dynamic
  name           = random_string.fn_nosql.result
  # Dynamic groups require a description
  description    = "Function resource identities"
  matching_rule = "All {resource.compartment.id = '${var.compartment_ocid}', resource.type = 'fnfunc'}}"
}

resource oci_identity_policy fn_nosql {
  compartment_id = var.compartment_ocid
  name           = random_string.fn_nosql.result
  # Policies namespace is tenancy-scoped and need to be dynamic
  description    = "Functions to insert NoSQL database rows"

  statements = [
    "Allow dynamic-group id ${oci_identity_dynamic_group.fn_nosql.id} to use nosql-rows in compartment id ${var.compartment_ocid}"
  ]
}

resource random_string put {
  length  = 5
  numeric  = false
  special = false
  upper = false
}

# Sunn access module - requires Fn
resource oci_identity_user put {
  compartment_id = var.tenancy_ocid
  name           = random_string.put.result
  description    = "Invoke a 'put' Function"
}

resource oci_identity_group put {
  compartment_id = var.tenancy_ocid
  name           = random_string.put.result
  description    = "Invoke a 'put' Function"
}

resource oci_identity_user_group_membership put {
    group_id = oci_identity_group.put.id
    user_id = oci_identity_user.put.id
}

resource oci_identity_policy put {
  name           = random_string.put.result
  description    = "Invoke a 'put' Function"
  compartment_id = var.compartment_ocid

  statements = [
    "Allow group id ${oci_identity_group.put.id} to use fn-invocation in compartment id ${var.compartment_ocid} where target.function.id = '${oci_functions_function.base["put"].id}'"
  ]
}

resource oci_apigateway_gateway base {
  compartment_id = var.compartment_ocid
  endpoint_type = "PUBLIC"
  subnet_id = module.core.subnet_id
}

resource oci_apigateway_deployment base {
  compartment_id = var.compartment_ocid
  gateway_id  = oci_apigateway_gateway.base.id
  path_prefix = "/"
  specification {
    routes {
      backend {
        function_id = oci_functions_function.base["get"].id
        type = "ORACLE_FUNCTIONS_BACKEND"
      }
      methods = [
        "POST",
      ]
      path = "/get"
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
        }
      }
    }
  }
}

resource oci_logging_log_group api {
  compartment_id = var.compartment_ocid
  display_name = "APIGateway"
}

resource oci_logging_log api {
  for_each = toset(["execution", "access"])
  
  configuration {
    compartment_id = var.compartment_ocid
    source {
      category    = each.key
      resource    = oci_apigateway_deployment.base.id
      service     = "apigateway"
      source_type = "OCISERVICE"
    }
  }
  display_name = each.key
  is_enabled         = "true"
  log_group_id       = oci_logging_log_group.api.id
  log_type           = "SERVICE"
  retention_duration = "30"
}

resource random_string api_fn {
  length  = 5
  numeric  = false
  special = false
  upper = false
}

resource oci_identity_dynamic_group api_fn {
  compartment_id = var.tenancy_ocid
  name           = random_string.api_fn.result
  description    = "API Gateway resource identities"
  matching_rule = "All {resource.compartment.id = '${var.compartment_ocid}', resource.type = 'apigateway'}"
}

resource oci_identity_policy api_fn {
  compartment_id = var.compartment_ocid
  name           = random_string.api_fn.result
  description    = "Provide the necessary permissions for API Gateways to invoke a Function"

  statements = [
    "Allow dynamic-group id ${oci_identity_dynamic_group.api_fn.id} to use fn-invocation in compartment id ${var.compartment_ocid} where target.function.id = '${oci_functions_function.base["get"].id}'"
  ]
}

output "function_ids" {
  value = {
    for k, v in oci_functions_function.base : k => v.id
  }
}