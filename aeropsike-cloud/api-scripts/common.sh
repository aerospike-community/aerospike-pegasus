#!/bin/bash

function acs_get_all_clusters_json() {
  # Return the full API response (not individual databases)
  curl "${REST_API_URI}?status_ne=decommissioned,decommissioning" -sX GET -H "@${ACS_AUTH_HEADER}" 2>/dev/null
}

function acs_get_cluster_json() {
  local cluster_id=$1
  local cluster_json=$(
    curl -s "${REST_API_URI}?status_ne=decommissioned,decommissioning" -H "@${ACS_AUTH_HEADER}" | \
      jq --arg database "${cluster_id}" '.databases[] | select(.id == $database)' 2>/dev/null
  )
  echo "${cluster_json}"
}

function acs_get_active_clusters_json() {
  # Now using API query parameter, so just return all from the filtered query
  acs_get_all_clusters_json
}

function acs_get_cluster_id() {
  local cluster_name=$1
  local get_all_clusters=${2:-false}

  # Query the API directly and filter with jq in one pass
  local cluster_id=$(curl -s "${REST_API_URI}?status_ne=decommissioned,decommissioning" -H "@${ACS_AUTH_HEADER}" | \
    jq -r --arg cluster_name "${cluster_name}" '.databases[] | select(.name == $cluster_name) | .id' 2>/dev/null | head -1)

  echo "${cluster_id}"
}

function acs_list_clusters() {
  acs_get_active_clusters_json | jq '[{name: .name, id: .id}]'
}

function acs_get_cluster_hostname() {
  local cluster_id=$1
  local cluster_hostname=$(curl -s "${REST_API_URI}?status_ne=decommissioned,decommissioning" -H "@${ACS_AUTH_HEADER}" | \
    jq -r --arg id "${cluster_id}" '.databases[] | select(.id == $id) | .connectionDetails.host' 2>/dev/null)
  echo "${cluster_hostname}"
}

function acs_get_cluster_tls_cert() {
  local cluster_id=$1
  # Fetch certificate directly via API to avoid jq parsing issues with newlines in certificates
  local cluster_tls_cert=$(curl -s "${REST_API_URI}/${cluster_id}" -H "@${ACS_AUTH_HEADER}" | jq -r '.connectionDetails.tlsCertificate')
  echo "${cluster_tls_cert}"
}

function acs_get_cluster_tls_name() {
  local cluster_id=$1
  local cluster_tls_name=$(curl -s "${REST_API_URI}?status_ne=decommissioned,decommissioning" -H "@${ACS_AUTH_HEADER}" | \
    jq -r --arg id "${cluster_id}" '.databases[] | select(.id == $id) | .connectionDetails.host' 2>/dev/null)
  echo "${cluster_tls_name}"
}

function acs_get_cluster_tls_key() {
  local cluster_id=$1
  local cluster_tls_key=$(acs_get_cluster_json "${cluster_id}" | jq -r '.connectionDetails.tlsKey')
  echo "${cluster_tls_key}"
}

function acs_get_cluster_status() {
  local cluster_id=$1
  local cluster_status=$(curl -s "${REST_API_URI}?status_ne=decommissioned,decommissioning" -H "@${ACS_AUTH_HEADER}" | \
    jq -r --arg id "${cluster_id}" '.databases[] | select(.id == $id) | .health.status' 2>/dev/null)
  echo "${cluster_status}"
}

function acs_destroy_cluster() {
  local cluster_id=$1
  curl "$REST_API_URI/${cluster_id}" -sX DELETE -H "@${ACS_AUTH_HEADER}"
}

function acs_get_vpc_peering_json() {
  local cluster_id=$1
  curl -sX GET  "$REST_API_URI/${cluster_id}/vpc-peerings" -H "@${ACS_AUTH_HEADER}"
}

function acs_get_zone_ids() {
  local cluster_id=$1
  local acs_zone_id=$(acs_get_cluster_json "${cluster_id}" | jq -r '.infrastructure.zoneIds[]')
  echo "${acs_zone_id}"
}

# Tailscale and proxy management functions

function tailscale_on() {
  # Just in case Tailscale is already running
  tailscale down 2>/dev/null || true
  pkill tailscaled

  echo -e "\n===== Turning Tailscale on ====="
  tailscaled --tun=userspace-networking --socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1055 > /dev/null 2>&1 &
  tailscale up --reset --exit-node 100.102.201.52
}

function tailscale_off() {
  echo -e "\n===== Turning Tailscale off =====\n"
  tailscale down
  systemctl stop tailscaled
  pkill tailscaled
}

function set_proxy() {
  # Set proxy variables for Tailscale
  export HTTPS_PROXY=http://localhost:1055/
  export https_proxy=http://localhost:1055/
}

function unset_proxy() {
  # Unset proxy variables
  unset HTTPS_PROXY
  unset https_proxy
}

