resource "random_uuid" "stack_compartment_name" {
}

resource "oci_identity_compartment" "stack_compartment" {
    compartment_id = var.compartment_ocid
    name = random_uuid.stack_compartment_name.result
    description = var.stack_compartment_description
}

module "oci-devops-functions" {
  source = "./modules/oci-devops-functions"
  region = var.region
  compartment_ocid = oci_identity_compartment.stack_compartment.id
  tenancy_ocid = var.tenancy_ocid
}
