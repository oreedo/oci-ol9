#!/bin/bash
# oci-portainer-check.sh
# Usage: ./oci-portainer-check.sh <instance-ocid> [output-md-path]
# Produces a Markdown report with VCN, subnet, security-lists, NSGs, route-tables, IGW and vNIC details
# Robustly resolves current public IPs using OCI CLI:
#  - prefer the "public-ip" field returned by list-vnics
#  - fallback to `oci network public-ip list --vnic-id <vnic-id>` to find reserved/public-ip resources

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <instance-ocid> [output-md-path]" >&2
  exit 2
fi

INSTANCE_OCID="$1"
OUT_PATH="${2:-./portainer-$(echo "$INSTANCE_OCID" | sed 's/[^a-z0-9]/-/g' | cut -c1-38).md}"

command -v oci >/dev/null 2>&1 || { echo "oci CLI not found in PATH" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "jq not found in PATH" >&2; exit 3; }

if ! echo "$INSTANCE_OCID" | grep -qE '^ocid1\.instance\.'; then
  echo "ERROR: Provided instance OCID does not look like an instance OCID: '$INSTANCE_OCID'" >&2
  exit 4
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Wrapper for oci calls -> writes JSON to file (returns non-zero on failure)
oci_get() {
  local cmd="$1" out="$2"
  if ! oci $cmd --output json > "$out" 2> "$TMPDIR/oci_err.log"; then
    echo "WARN: oci $cmd failed (see $TMPDIR/oci_err.log)" >&2
    return 1
  fi
  return 0
}

# Resolve public IP for a vnic JSON blob (string containing JSON)
# 1) use .["public-ip"] if present
# 2) fallback to `oci network public-ip list --vnic-id <vnic-id>`
# Returns empty string on failure.
resolve_vnic_public_ip() {
  local vnic_json="$1"
  local vnic_id ip

  vnic_id=$(jq -r '.id' <<<"$vnic_json")
  ip=$(jq -r '."public-ip" // empty' <<<"$vnic_json")
  if [ -n "$ip" ]; then
    printf '%s' "$ip"
    return 0
  fi

  # fallback: check public-ip resources tied to the vnic
  if oci network public-ip list --vnic-id "$vnic_id" --all --output json > "$TMPDIR/pubip_${vnic_id}.json" 2>/dev/null; then
    ip=$(jq -r '.data[0]."ip-address" // empty' "$TMPDIR/pubip_${vnic_id}.json")
    if [ -n "$ip" ]; then
      printf '%s' "$ip"
      return 0
    fi
  fi

  # nothing found
  printf ''
  return 1
}

# Fetch instance
INSTANCE_JSON="$TMPDIR/instance.json"
if ! oci_get "compute instance get --instance-id $INSTANCE_OCID" "$INSTANCE_JSON"; then
  echo "ERROR: cannot fetch instance. Check OCID/region/permissions." >&2
  exit 5
fi

INST_DISPLAY_NAME=$(jq -r '.data["display-name"] // "n/a"' "$INSTANCE_JSON")
INST_STATE=$(jq -r '.data["lifecycle-state"] // "n/a"' "$INSTANCE_JSON")
INST_COMP=$(jq -r '.data["compartment-id"] // "n/a"' "$INSTANCE_JSON")
INST_AD=$(jq -r '.data["availability-domain"] // "n/a"' "$INSTANCE_JSON")

# Fetch vNICs (this output often includes public-ip)
VNICS_JSON="$TMPDIR/vnics.json"
if ! oci_get "compute instance list-vnics --instance-id $INSTANCE_OCID --all" "$VNICS_JSON"; then
  echo "ERROR: failed to list vNICs" >&2
  exit 6
fi

VNICS_COUNT=$(jq '.data | length' "$VNICS_JSON")
if [ "$VNICS_COUNT" -eq 0 ]; then
  echo "ERROR: no vNICs found for instance $INSTANCE_OCID" >&2
  exit 7
fi

# Build markdown report
{
  echo "# OCI Network Report for instance: ${INST_DISPLAY_NAME}"
  echo
  echo "- Instance OCID: ${INSTANCE_OCID}"
  echo "- Display name: ${INST_DISPLAY_NAME}"
  echo "- Lifecycle state: ${INST_STATE}"
  echo "- Availability Domain: ${INST_AD}"
  echo "- Compartment OCID: ${INST_COMP}"
  echo
  echo "## vNICs"
  echo

  # iterate vNICs and resolve public IPs using OCI CLI (prefer field, fallback to public-ip resource)
  jq -c '.data[]' "$VNICS_JSON" | while read -r vnic; do
    vnic_id=$(jq -r '.id' <<<"$vnic")
    vnic_name=$(jq -r '."display-name" // "(none)"' <<<"$vnic")
    priv_ip=$(jq -r '."private-ip" // "(none)"' <<<"$vnic")
    pub_ip=$(resolve_vnic_public_ip "$vnic" || true)
    [ -z "$pub_ip" ] && pub_ip="(none)"
    subnet_id=$(jq -r '."subnet-id" // "(none)"' <<<"$vnic")
    nsgs=$(jq -r '."nsg-ids" // [] | join(", ")' <<<"$vnic")
    [ -z "$nsgs" ] && nsgs="(none)"
    cat <<-EOF
- vNIC OCID: ${vnic_id}
  - VNIC display-name: ${vnic_name}
  - Private IP: ${priv_ip}
  - Public IP: ${pub_ip}
  - Subnet OCID: ${subnet_id}
  - NSG IDs: ${nsgs}

EOF
  done

  # collect unique subnet / nsg ids
  mapfile -t SUBNET_IDS < <(jq -r '.data[] | ."subnet-id"' "$VNICS_JSON" | sort -u)
  mapfile -t NSG_IDS < <(jq -r '.data[] | ."nsg-ids"[]?' "$VNICS_JSON" 2>/dev/null | sort -u || true)

  for SUBNET_ID in "${SUBNET_IDS[@]}"; do
    SUB_JSON="$TMPDIR/subnet_$(echo "$SUBNET_ID" | sed 's/[^a-zA-Z0-9]/_/g').json"
    if oci_get "network subnet get --subnet-id $SUBNET_ID" "$SUB_JSON"; then
      SUB_NAME=$(jq -r '.data["display-name"] // "(none)"' "$SUB_JSON")
      SUB_CIDR=$(jq -r '.data["cidr-block"] // "(none)"' "$SUB_JSON")
      SUB_AD=$(jq -r '.data["availability-domain"] // "(none)"' "$SUB_JSON")
      VCN_ID=$(jq -r '.data["vcn-id"] // "null"' "$SUB_JSON")
      RT_ID=$(jq -r '.data["route-table-id"] // "null"' "$SUB_JSON")
      DHCP_ID=$(jq -r '.data["dhcp-options-id"] // "null"' "$SUB_JSON")
      SEC_LIST_IDS=$(jq -r '.data["security-list-ids"][]?' "$SUB_JSON" 2>/dev/null | tr '\n' ' ')

      echo "## Subnet: ${SUBNET_ID}"
      echo
      echo "- Name: ${SUB_NAME}"
      echo "- CIDR: ${SUB_CIDR}"
      echo "- Availability Domain: ${SUB_AD}"
      echo "- VCN OCID: ${VCN_ID}"
      echo "- Route Table OCID: ${RT_ID}"
      echo "- DHCP Options OCID: ${DHCP_ID}"
      echo "- Security List IDs: ${SEC_LIST_IDS:-(none)}"
      echo

      # VCN summary
      if [ -n "$VCN_ID" ] && [ "$VCN_ID" != "null" ]; then
        VCN_JSON="$TMPDIR/vcn_$(echo "$VCN_ID" | sed 's/[^a-zA-Z0-9]/_/g').json"
        if oci_get "network vcn get --vcn-id $VCN_ID" "$VCN_JSON"; then
          VCN_NAME=$(jq -r '.data["display-name"] // "(none)"' "$VCN_JSON")
          VCN_CIDR=$(jq -r '.data["cidr-block"] // "(none)"' "$VCN_JSON")
          echo "### VCN: ${VCN_ID}"
          echo
          echo "- Name: ${VCN_NAME}"
          echo "- CIDR: ${VCN_CIDR}"
          echo

          # Internet Gateways (may fail if no permission)
          IG_JSON="$TMPDIR/igs_$(echo "$VCN_ID" | sed 's/[^a-zA-Z0-9]/_/g').json"
          if oci_get "network internet-gateway list --vcn-id $VCN_ID --all" "$IG_JSON"; then
            IGS=$(jq -r '.data[]? | "- " + .id + " (display-name: " + (.["display-name"]//"") + ", isEnabled: " + (.["is-enabled"]|tostring) + ")"' "$IG_JSON" || true)
            echo "#### Internet Gateways"
            if [ -z "$IGS" ]; then
              echo "- (none)"
            else
              echo "$IGS"
            fi
            echo
          fi

          # Route table
          if [ -n "$RT_ID" ] && [ "$RT_ID" != "null" ]; then
            RT_JSON="$TMPDIR/rt_$(echo "$RT_ID" | sed 's/[^a-zA-Z0-9]/_/g').json"
            if oci_get "network route-table get --rt-id $RT_ID" "$RT_JSON"; then
              echo "#### Route Table: ${RT_ID}"
              jq -r '.data["route-rules"][]? | "- destination: " + (.destination // "n/a") + ", network_entity_id: " + (.network_entity_id // "n/a")' "$RT_JSON" || echo "- (no route rules)"
              echo
            fi
          fi
        fi
      fi

      # Security lists
      echo "### Security Lists for subnet ${SUBNET_ID}"
      if [ -n "$SEC_LIST_IDS" ]; then
        for SL in $SEC_LIST_IDS; do
          SL_JSON="$TMPDIR/sl_$(echo "$SL" | sed 's/[^a-zA-Z0-9]/_/g').json"
          if oci_get "network security-list get --security-list-id $SL" "$SL_JSON"; then
            SL_NAME=$(jq -r '.data["display-name"] // "(none)"' "$SL_JSON")
            echo "- Security List: ${SL} (${SL_NAME})"
            echo "  - Ingress rules:"
            jq -r '.data["ingress-security-rules"][]? |
              "    - protocol: " + (.protocol // "n/a") + ", source: " + (.source // "n/a") +
              (if .tcpOptions then (", ports: " + (.tcpOptions.destinationPortRange.min|tostring) + "-" + (.tcpOptions.destinationPortRange.max|tostring)) else "" end)' "$SL_JSON" || echo "    - (none)"
            echo "  - Egress rules:"
            jq -r '.data["egress-security-rules"][]? |
              "    - protocol: " + (.protocol // "n/a") +
              (if .tcpOptions then (", ports: " + (.tcpOptions.destinationPortRange.min|tostring) + "-" + (.tcpOptions.destinationPortRange.max|tostring)) else "" end)' "$SL_JSON" || echo "    - (none)"
            echo
          fi
        done
      else
        echo "- (none)"
        echo
      fi
    else
      echo "WARN: failed to fetch subnet ${SUBNET_ID}" >&2
    fi
  done

  # NSGs
  echo "## Network Security Groups (NSGs) attached to instance vNICs"
  if [ "${#NSG_IDS[@]}" -gt 0 ] && [ -n "${NSG_IDS[0]}" ]; then
    for NSG in "${NSG_IDS[@]}"; do
      NSG_JSON="$TMPDIR/nsg_$(echo "$NSG" | sed 's/[^a-zA-Z0-9]/_/g').json"
      if oci_get "network network-security-group get --network-security-group-id $NSG" "$NSG_JSON"; then
        NSG_NAME=$(jq -r '.data["display-name"] // "(none)"' "$NSG_JSON")
        echo "- NSG: ${NSG} (${NSG_NAME})"
        echo "  - Security rules:"
        jq -r '.data["security-rules"][]? |
          "    - direction: " + (.direction // "n/a") + ", protocol: " + (.protocol // "n/a") +
          (if .tcpOptions then (", ports: " + (.tcpOptions.destinationPortRange.min|tostring) + "-" + (.tcpOptions.destinationPortRange.max|tostring)) else "" end) +
          ", source/destination: " + ((.source // .destination) // "n/a")' "$NSG_JSON" || echo "    - (none)"
        echo
      fi
    done
  else
    echo "- (none)"
    echo
  fi

  # Reachability summary
  echo "## Reachability / next steps"
  echo
  jq -r '.data[] | "- vNIC: " + .id + " - Private IP: " + (.["private-ip"] // "(none)") + " - Public IP: " + (.["public-ip"] // "(none)")' "$VNICS_JSON"
  echo
  echo "- Confirm the subnet's Security List or NSG allows inbound TCP to ports: 9000, 9443, 8000 from the sources you intend to allow."
  echo "- Ensure host firewall (firewalld/iptables) on the instance permits those ports."
  echo "- If the instance is in a private subnet, deploy a public Load Balancer or assign a public IP for external access."
  echo
} > "$OUT_PATH"

echo "Report written to $OUT_PATH"
exit 0
```// filepath: /mnt/data/projects/portainer/scripts/oci-portainer-check.sh
#!/bin/bash
# oci-portainer-check.sh
# Usage: ./oci-portainer-check.sh <instance-ocid> [output-md-path]
# Produces a Markdown report with VCN, subnet, security-lists, NSGs, route-tables, IGW and vNIC details
# Robustly resolves current public IPs using OCI CLI:
#  - prefer the "public-ip" field returned by list-vnics
#  - fallback to `oci network public-ip list --vnic-id <vnic-id>` to find reserved/public-ip resources

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <instance-ocid> [output-md-path]" >&2
  exit 2
fi

INSTANCE_OCID="$1"
OUT_PATH="${2:-./portainer-$(echo "$INSTANCE_OCID" | sed 's/[^a-z0-9]/-/g' | cut -c1-38).md}"

command -v oci >/dev/null 2>&1 || { echo "oci CLI not found in PATH" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "jq not found in PATH" >&2; exit 3; }

if ! echo "$INSTANCE_OCID" | grep -qE '^ocid1\.instance\.'; then
  echo "ERROR: Provided instance OCID does not look like an instance OCID: '$INSTANCE_OCID'" >&2
  exit 4
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Wrapper for oci calls -> writes JSON to file (returns non-zero on failure)
oci_get() {
  local cmd="$1" out="$2"
  if ! oci $cmd --output json > "$out" 2> "$TMPDIR/oci_err.log"; then
    echo "WARN: oci $cmd failed (see $TMPDIR/oci_err.log)" >&2
    return 1
  fi
  return 0
}

# Resolve public IP for a vnic JSON blob (string containing JSON)
# 1) use .["public-ip"] if present
# 2) fallback to `oci network public-ip list --vnic-id <vnic-id>`
# Returns empty string on failure.
resolve_vnic_public_ip() {
  local vnic_json="$1"
  local vnic_id ip

  vnic_id=$(jq -r '.id' <<<"$vnic_json")
  ip=$(jq -r '."public-ip" // empty' <<<"$vnic_json")
  if [ -n "$ip" ]; then
    printf '%s' "$ip"
    return 0
  fi

  # fallback: check public-ip resources tied to the vnic
  if oci network public-ip list --vnic-id "$vnic_id" --all --output json > "$TMPDIR/pubip_${vnic_id}.json" 2>/dev/null; then
    ip=$(jq -r '.data[0]."ip-address" // empty' "$TMPDIR/pubip_${vnic_id}.json")
    if [ -n "$ip" ]; then
      printf '%s' "$ip"
      return 0
    fi
  fi

  # nothing found
  printf ''
  return 1
}

# Fetch instance
INSTANCE_JSON="$TMPDIR/instance.json"
if ! oci_get "compute instance get --instance-id $INSTANCE_OCID" "$INSTANCE_JSON"; then
  echo "ERROR: cannot fetch instance. Check OCID/region/permissions." >&2
  exit 5
fi

INST_DISPLAY_NAME=$(jq -r '.data["display-name"] // "n/a"' "$INSTANCE_JSON")
INST_STATE=$(jq -r '.data["lifecycle-state"] // "n/a"' "$INSTANCE_JSON")
INST_COMP=$(jq -r '.data["compartment-id"] // "n/a"' "$INSTANCE_JSON")
INST_AD=$(jq -r '.data["availability-domain"] // "n/a"' "$INSTANCE_JSON")

# Fetch vNICs (this output often includes public-ip)
VNICS_JSON="$TMPDIR/vnics.json"
if ! oci_get "compute instance list-vnics --instance-id $INSTANCE_OCID --all" "$VNICS_JSON"; then
  echo "ERROR: failed to list vNICs" >&2
  exit 6
fi

VNICS_COUNT=$(jq '.data | length' "$VNICS_JSON")
if [ "$VNICS_COUNT" -eq 0 ]; then
  echo "ERROR: no vNICs found for instance $INSTANCE_OCID" >&2
  exit 7
fi

# Build markdown report
{
  echo "# OCI Network Report for instance: ${INST_DISPLAY_NAME}"
  echo
  echo "- Instance OCID: ${INSTANCE_OCID}"
  echo "- Display name: ${INST_DISPLAY_NAME}"
  echo "- Lifecycle state: ${INST_STATE}"
  echo "- Availability Domain: ${INST_AD}"
  echo "- Compartment OCID: ${INST_COMP}"
  echo
  echo "## vNICs"
  echo

  # iterate vNICs and resolve public IPs using OCI CLI (prefer field, fallback to public-ip resource)
  jq -c '.data[]' "$VNICS_JSON" | while read -r vnic; do
    vnic_id=$(jq -r '.id' <<<"$vnic")
    vnic_name=$(jq -r '."display-name" // "(none)"' <<<"$vnic")
    priv_ip=$(jq -r '."private-ip" // "(none)"' <<<"$vnic")
    pub_ip=$(resolve_vnic_public_ip "$vnic" || true)
    [ -z "$pub_ip" ] && pub_ip="(none)"
    subnet_id=$(jq -r '."subnet-id" // "(none)"' <<<"$vnic")
    nsgs=$(jq -r '."nsg-ids" // [] | join(", ")' <<<"$vnic")
    [ -z "$nsgs" ] && nsgs="(none)"
    cat <<-EOF
- vNIC OCID: ${vnic_id}
  - VNIC display-name: ${vnic_name}
  - Private IP: ${priv_ip}
  - Public IP: ${pub_ip}
  - Subnet OCID: ${subnet_id}
  - NSG IDs: ${nsgs}

EOF
  done

  # collect unique subnet / nsg ids
  mapfile -t SUBNET_IDS < <(jq -r '.data[] | ."subnet-id"' "$VNICS_JSON" | sort -u)
  mapfile -t NSG_IDS < <(jq -r '.data[] | ."nsg-ids"[]?' "$VNICS_JSON" 2>/dev/null | sort -u || true)

  for SUBNET_ID in "${SUBNET_IDS[@]}"; do
    SUB_JSON="$TMPDIR/subnet_$(echo "$SUBNET_ID" | sed 's/[^a-zA-Z0-9]/_/g').json"
    if oci_get "network subnet get --subnet-id $SUBNET_ID" "$SUB_JSON"; then
      SUB_NAME=$(jq -r '.data["display-name"] // "(none)"' "$SUB_JSON")
      SUB_CIDR=$(jq -r '.data["cidr-block"] // "(none)"' "$SUB_JSON")
      SUB_AD=$(jq -r '.data["availability-domain"] // "(none)"' "$SUB_JSON")
      VCN_ID=$(jq -r '.data["vcn-id"] // "null"' "$SUB_JSON")
      RT_ID=$(jq -r '.data["route-table-id"] // "null"' "$SUB_JSON")
      DHCP_ID=$(jq -r '.data["dhcp-options-id"] // "null"' "$SUB_JSON")
      SEC_LIST_IDS=$(jq -r '.data["security-list-ids"][]?' "$SUB_JSON" 2>/dev/null | tr '\n' ' ')

      echo "## Subnet: ${SUBNET_ID}"
      echo
      echo "- Name: ${SUB_NAME}"
      echo "- CIDR: ${SUB_CIDR}"
      echo "- Availability Domain: ${SUB_AD}"
      echo "- VCN OCID: ${VCN_ID}"
      echo "- Route Table OCID: ${RT_ID}"
      echo "- DHCP Options OCID: ${DHCP_ID}"
      echo "- Security List IDs: ${SEC_LIST_IDS:-(none)}"
      echo

      # VCN summary
      if [ -n "$VCN_ID" ] && [ "$VCN_ID" != "null" ]; then
        VCN_JSON="$TMPDIR/vcn_$(echo "$VCN_ID" | sed 's/[^a-zA-Z0-9]/_/g').json"
        if oci_get "network vcn get --vcn-id $VCN_ID" "$VCN_JSON"; then
          VCN_NAME=$(jq -r '.data["display-name"] // "(none)"' "$VCN_JSON")
          VCN_CIDR=$(jq -r '.data["cidr-block"] // "(none)"' "$VCN_JSON")
          echo "### VCN: ${VCN_ID}"
          echo
          echo "- Name: ${VCN_NAME}"
          echo "- CIDR: ${VCN_CIDR}"
          echo

          # Internet Gateways (may fail if no permission)
          IG_JSON="$TMPDIR/igs_$(echo "$VCN_ID" | sed 's/[^a-zA-Z0-9]/_/g').json"
          if oci_get "network internet-gateway list --vcn-id $VCN_ID --all" "$IG_JSON"; then
            IGS=$(jq -r '.data[]? | "- " + .id + " (display-name: " + (.["display-name"]//"") + ", isEnabled: " + (.["is-enabled"]|tostring) + ")"' "$IG_JSON" || true)
            echo "#### Internet Gateways"
            if [ -z "$IGS" ]; then
              echo "- (none)"
            else
              echo "$IGS"
            fi
            echo
          fi

          # Route table
          if [ -n "$RT_ID" ] && [ "$RT_ID" != "null" ]; then
            RT_JSON="$TMPDIR/rt_$(echo "$RT_ID" | sed 's/[^a-zA-Z0-9]/_/g').json"
            if oci_get "network route-table get --rt-id $RT_ID" "$RT_JSON"; then
              echo "#### Route Table: ${RT_ID}"
              jq -r '.data["route-rules"][]? | "- destination: " + (.destination // "n/a") + ", network_entity_id: " + (.network_entity_id // "n/a")' "$RT_JSON" || echo "- (no route rules)"
              echo
            fi
          fi
        fi
      fi

      # Security lists
      echo "### Security Lists for subnet ${SUBNET_ID}"
      if [ -n "$SEC_LIST_IDS" ]; then
        for SL in $SEC_LIST_IDS; do
          SL_JSON="$TMPDIR/sl_$(echo "$SL" | sed 's/[^a-zA-Z0-9]/_/g').json"
          if oci_get "network security-list get --security-list-id $SL" "$SL_JSON"; then
            SL_NAME=$(jq -r '.data["display-name"] // "(none)"' "$SL_JSON")
            echo "- Security List: ${SL} (${SL_NAME})"
            echo "  - Ingress rules:"
            jq -r '.data["ingress-security-rules"][]? |
              "    - protocol: " + (.protocol // "n/a") + ", source: " + (.source // "n/a") +
              (if .tcpOptions then (", ports: " + (.tcpOptions.destinationPortRange.min|tostring) + "-" + (.tcpOptions.destinationPortRange.max|tostring)) else "" end)' "$SL_JSON" || echo "    - (none)"
            echo "  - Egress rules:"
            jq -r '.data["egress-security-rules"][]? |
              "    - protocol: " + (.protocol // "n/a") +
              (if .tcpOptions then (", ports: " + (.tcpOptions.destinationPortRange.min|tostring) + "-" + (.tcpOptions.destinationPortRange.max|tostring)) else "" end)' "$SL_JSON" || echo "    - (none)"
            echo
          fi
        done
      else
        echo "- (none)"
        echo
      fi
    else
      echo "WARN: failed to fetch subnet ${SUBNET_ID}" >&2
    fi
  done

  # NSGs
  echo "## Network Security Groups (NSGs) attached to instance vNICs"
  if [ "${#NSG_IDS[@]}" -gt 0 ] && [ -n "${NSG_IDS[0]}" ]; then
    for NSG in "${NSG_IDS[@]}"; do
      NSG_JSON="$TMPDIR/nsg_$(echo "$NSG" | sed 's/[^a-zA-Z0-9]/_/g').json"
      if oci_get "network network-security-group get --network-security-group-id $NSG" "$NSG_JSON"; then
        NSG_NAME=$(jq -r '.data["display-name"] // "(none)"' "$NSG_JSON")
        echo "- NSG: ${NSG} (${NSG_NAME})"
        echo "  - Security rules:"
        jq -r '.data["security-rules"][]? |
          "    - direction: " + (.direction // "n/a") + ", protocol: " + (.protocol // "n/a") +
          (if .tcpOptions then (", ports: " + (.tcpOptions.destinationPortRange.min|tostring) + "-" + (.tcpOptions.destinationPortRange.max|tostring)) else "" end) +
          ", source/destination: " + ((.source // .destination) // "n/a")' "$NSG_JSON" || echo "    - (none)"
        echo
      fi
    done
  else
    echo "- (none)"
    echo
  fi

  # Reachability summary
  echo "## Reachability / next steps"
  echo
  jq -r '.data[] | "- vNIC: " + .id + " - Private IP: " + (.["private-ip"] // "(none)") + " - Public IP: " + (.["public-ip"] // "(none)")' "$VNICS_JSON"
  echo
  echo "- Confirm the subnet's Security List or NSG allows inbound TCP to ports: 9000, 9443, 8000 from the sources you intend to allow."
  echo "- Ensure host firewall (firewalld/iptables) on the instance permits those ports."
  echo "- If the instance is in a private subnet, deploy a public Load Balancer or assign a public IP for external access."
  echo
} > "$OUT_PATH"

echo "Report written to $OUT_PATH"
exit 0