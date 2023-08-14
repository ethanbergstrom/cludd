# Fn - Requires NoSQL, Build pipeline
resource "random_uuid" "application_name" {
}

resource "oci_functions_application" "function_application" {
  compartment_id = var.compartment_ocid
  display_name = random_uuid.application_name.result
  subnet_ids = [var.subnet_id]
  # Set env vars for all functions
  config = {
    "TABLE_NAME" = var.database_name
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
  image = var.image_uris.items[0].image_uri
  
  lifecycle {
    ignore_changes = [image,image_digest]
  }
}

resource "oci_functions_function" "enviroRetrieve" {
  application_id = oci_functions_application.function_application.id
  display_name   = "enviroRetrieve"
  memory_in_mbs  = "128"
  image = var.image_uris.items[1].image_uri
  
  lifecycle {
    ignore_changes = [image,image_digest]
  }
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

output "put_function_id" {
  value = oci_functions_function.enviroStore.id
}

output "get_function_id" {
  value = oci_functions_function.enviroRetrieve.id
}
