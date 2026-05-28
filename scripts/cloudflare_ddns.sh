#!/usr/bin/env bash
set -euo pipefail

: "${CF_API_TOKEN:?CF_API_TOKEN is required}"
: "${CF_ZONE_NAME:=ambrois.uk}"
: "${CF_RECORD_NAME:=stockdb.ambrois.uk}"
: "${CF_RECORD_TYPE:=A}"
: "${CF_PROXIED:=false}"
: "${CF_TTL:=120}"
: "${CF_IP_URL:=https://api.ipify.org}"

api="https://api.cloudflare.com/client/v4"
auth_header="Authorization: Bearer ${CF_API_TOKEN}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

cf_get() {
  curl -fsS \
    -H "${auth_header}" \
    -H "Content-Type: application/json" \
    "$1"
}

cf_send() {
  local method="$1"
  local url="$2"
  local data="$3"

  curl -fsS \
    -X "${method}" \
    -H "${auth_header}" \
    -H "Content-Type: application/json" \
    --data "${data}" \
    "${url}"
}

require_cmd curl
require_cmd jq

current_ip="$(curl -fsS "${CF_IP_URL}")"
if [[ ! "${current_ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "Could not determine a valid IPv4 address: ${current_ip}" >&2
  exit 1
fi

zone_response="$(cf_get "${api}/zones?name=${CF_ZONE_NAME}&status=active")"
zone_id="$(jq -r '.result[0].id // empty' <<<"${zone_response}")"
if [[ -z "${zone_id}" ]]; then
  echo "Could not find active Cloudflare zone: ${CF_ZONE_NAME}" >&2
  exit 1
fi

record_response="$(cf_get "${api}/zones/${zone_id}/dns_records?type=${CF_RECORD_TYPE}&name=${CF_RECORD_NAME}")"
record_id="$(jq -r '.result[0].id // empty' <<<"${record_response}")"
record_ip="$(jq -r '.result[0].content // empty' <<<"${record_response}")"

payload="$(
  jq -n \
    --arg type "${CF_RECORD_TYPE}" \
    --arg name "${CF_RECORD_NAME}" \
    --arg content "${current_ip}" \
    --argjson ttl "${CF_TTL}" \
    --argjson proxied "${CF_PROXIED}" \
    '{type: $type, name: $name, content: $content, ttl: $ttl, proxied: $proxied}'
)"

if [[ -z "${record_id}" ]]; then
  response="$(cf_send POST "${api}/zones/${zone_id}/dns_records" "${payload}")"
  success="$(jq -r '.success' <<<"${response}")"
  if [[ "${success}" != "true" ]]; then
    echo "Cloudflare record creation failed:" >&2
    jq '.' <<<"${response}" >&2
    exit 1
  fi
  echo "Created ${CF_RECORD_TYPE} ${CF_RECORD_NAME} -> ${current_ip}"
  exit 0
fi

if [[ "${record_ip}" == "${current_ip}" ]]; then
  echo "No change: ${CF_RECORD_NAME} already points to ${current_ip}"
  exit 0
fi

response="$(cf_send PATCH "${api}/zones/${zone_id}/dns_records/${record_id}" "${payload}")"
success="$(jq -r '.success' <<<"${response}")"
if [[ "${success}" != "true" ]]; then
  echo "Cloudflare record update failed:" >&2
  jq '.' <<<"${response}" >&2
  exit 1
fi

echo "Updated ${CF_RECORD_NAME}: ${record_ip} -> ${current_ip}"
