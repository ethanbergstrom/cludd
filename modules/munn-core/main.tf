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

output "subnet_id" {
  value = oci_core_subnet.function_subnet.id
}
