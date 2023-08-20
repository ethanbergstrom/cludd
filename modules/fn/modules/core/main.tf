resource oci_core_vcn base {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr_block]
}

resource oci_core_network_security_group base {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.base.id
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

resource oci_core_security_list https {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.base.id

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "6"
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"

    tcp_options {
      max = "443"
      min = "443"
    }
  }
}

resource oci_core_subnet base {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.base.id
  # Use the entire VCN
  cidr_block        = var.vcn_cidr_block
  security_list_ids = [
    oci_core_security_list.https.id
  ]
}

output subnet_id {
  value = oci_core_subnet.base.id
}
