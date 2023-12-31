resource oci_core_vcn base {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr_block]
}

resource oci_core_network_security_group base {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.base.id
}

resource oci_core_network_security_group_security_rule base {
  network_security_group_id = oci_core_network_security_group.base.id
  direction                 = "INGRESS"
  protocol                  = 6
  source_type               = "CIDR_BLOCK"
  source                    = "0.0.0.0/0"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource oci_core_internet_gateway base {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.base.id
}

resource oci_core_default_route_table base {
  manage_default_resource_id = oci_core_vcn.base.default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.base.id
  }
}

resource oci_core_subnet base {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.base.id
  # Use the entire VCN
  cidr_block        = var.vcn_cidr_block
}

output subnet_id {
  value = oci_core_subnet.base.id
}

output nsg_id {
  value = oci_core_network_security_group.base.id
}
