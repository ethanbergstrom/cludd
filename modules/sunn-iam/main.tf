# Sunn access module - requires Fn
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
    "Allow group id ${oci_identity_group.enviroStoreSvcGroup.id} to use fn-invocation in compartment id ${var.compartment_ocid} where target.function.id = '${var.put_function_id}'"
  ]
}

