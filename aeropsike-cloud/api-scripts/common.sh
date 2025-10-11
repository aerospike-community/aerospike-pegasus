#!/bin/bash

function acs_get_all_clusters_json() {
#  local cluster_json=$(curl 'https://api.aerospike.cloud/v2/databases' -sX GET -H "@${ACS_AUTH_HEADER}" | jq -r '.databases[]')
  local cluster_json=$(curl "$REST_API_URI" -sX GET -H "@${ACS_AUTH_HEADER}" | jq -r '.databases[]')
  echo "${cluster_json}"
}

function acs_get_cluster_json() {
  local cluster_id=$1
  local cluster_json=$(
    acs_get_all_clusters_json | jq --arg database "${cluster_id}"  'select(.id == $database)'
  )
  echo "${cluster_json}"
}

function acs_get_active_clusters_json() {
  local cluster_json=$(
    acs_get_all_clusters_json | \
      jq  'select(.health.status != "decommissioning") | select(.health.status != "decommissioned")'
  )
  echo "${cluster_json}"
}

function acs_get_cluster_id() {
  local cluster_name=$1
  local get_all_clusters=$2

  if [[ "${get_all_clusters}" == "true" ]]; then
    local cluster_json=$(acs_get_all_clusters_json)
  else
    local cluster_json=$(acs_get_active_clusters_json)
  fi

  local cluster_id=$(echo "${cluster_json}" | jq -r --arg cluster_name "${cluster_name}" 'select(.name == $cluster_name) | .id')

  echo "${cluster_id}"
}

function acs_list_clusters() {
  acs_get_active_clusters_json | jq '[{name: .name, id: .id}]'
}

function acs_get_cluster_hostname() {
  local cluster_id=$1
  local cluster_hostname=$(acs_get_cluster_json "${cluster_id}" | jq -r '.connectionDetails.host')
  echo "${cluster_hostname}"
}

function acs_get_cluster_tls_cert() {
  local cluster_id=$1
  local cluster_tls_cert=$(acs_get_cluster_json "${cluster_id}" | jq -r '.connectionDetails.tlsCertificate')
  echo "${cluster_tls_cert}"
}

function acs_get_cluster_tls_name() {
  local cluster_id=$1
  local cluster_tls_name=$(acs_get_cluster_json "${cluster_id}" | jq -r '.connectionDetails.host')
  echo "${cluster_tls_name}"
}

function acs_get_cluster_tls_key() {
  local cluster_id=$1
  local cluster_tls_key=$(acs_get_cluster_json "${cluster_id}" | jq -r '.connectionDetails.tlsKey')
  echo "${cluster_tls_key}"
}

function acs_get_cluster_status() {
  local cluster_id=$1
  local cluster_status=$(acs_get_cluster_json "${cluster_id}" | jq -r '.health.status')
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

