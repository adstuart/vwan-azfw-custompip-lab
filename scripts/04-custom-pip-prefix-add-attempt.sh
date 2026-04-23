#!/usr/bin/env bash
# Phase 4: Attempt to ADD prefix-allocated PIPs to the running FW *without* deallocate.
# Expected per MS doc: not supported on existing hubs — you must deallocate then reallocate.
source "$(dirname "$0")/00-vars.sh"

echo "== [04] Creating Public IP Prefix /$PIP_PREFIX_LEN in $LOC =="
az network public-ip prefix create -g "$RG" -n "$PIP_PREFIX_NAME" -l "$LOC" \
  --length "$PIP_PREFIX_LEN" --version IPv4 --tier Regional -o none
PREFIX_ID=$(az network public-ip prefix show -g "$RG" -n "$PIP_PREFIX_NAME" --query id -o tsv)
PREFIX=$(az network public-ip prefix show -g "$RG" -n "$PIP_PREFIX_NAME" --query ipPrefix -o tsv)
echo "Prefix: $PREFIX   (id: $PREFIX_ID)"

echo "== [04] Pre-allocating 2 static Standard PIPs from the prefix =="
for i in 1 2; do
  az network public-ip create -g "$RG" -n "pip-fw-prefix-$i" -l "$LOC" \
    --sku Standard --allocation-method Static \
    --version IPv4 --public-ip-prefix "$PREFIX_ID" -o none
done
az network public-ip list -g "$RG" --query "[?publicIPPrefix.id=='$PREFIX_ID'].{name:name, ip:ipAddress}" -o table

echo "== [04] Attempting to add prefix PIPs to AzFW *without* deallocate =="
ORIG_IP=$(az network firewall show -g "$RG" -n "$FWNAME" --query 'hubIPAddresses.publicIPs.addresses[0].address' -o tsv)
NEW1=$(az network public-ip show -g "$RG" -n pip-fw-prefix-1 --query ipAddress -o tsv)
NEW2=$(az network public-ip show -g "$RG" -n pip-fw-prefix-2 --query ipAddress -o tsv)

cat > /tmp/azfw-coexist-patch.json <<EOF
{
  "properties": {
    "hubIPAddresses": {
      "publicIPs": {
        "count": 3,
        "addresses": [
          {"address": "$ORIG_IP"},
          {"address": "$NEW1"},
          {"address": "$NEW2"}
        ]
      }
    }
  }
}
EOF
echo "--- PATCH body:"; cat /tmp/azfw-coexist-patch.json

FW_ID=$(az network firewall show -g "$RG" -n "$FWNAME" --query id -o tsv)
set +e
az rest --method patch --url "https://management.azure.com${FW_ID}?api-version=2023-09-01" \
  --body @/tmp/azfw-coexist-patch.json 2>&1 | tee /tmp/coexist-attempt.out
RC=$?
set -e
echo "Return code: $RC"

sleep 10
az network firewall show -g "$RG" -n "$FWNAME" \
  --query "{state:provisioningState, pipCount:length(hubIPAddresses.publicIPs.addresses), pips:hubIPAddresses.publicIPs.addresses[].address}" -o json

{
  echo
  echo "## Coexistence test — $(date -Iseconds)"
  echo
  echo "Attempted online PATCH of AzFW \`hubIPAddresses.publicIPs\` to hold 3 addresses (1 Azure-managed + 2 prefix-allocated) without deallocating the firewall."
  echo
  echo '```'; cat /tmp/coexist-attempt.out; echo '```'
  echo
  echo "**Conclusion:** Per MS docs the supported swap path requires setting \`count=0\`, calling \`Deallocate\`, then \`Allocate\` with the new PIP array. Online coexistence of Azure-managed and customer-provided PIPs is not a supported configuration on an existing secured hub. See [Secured hub customer public IP](https://learn.microsoft.com/en-us/azure/firewall/secured-hub-customer-public-ip?tabs=portal#reconfigure-an-existing-secure-hub-azure-firewall-with-customer-tenant-public-ip)."
} >> "$REPORT"
