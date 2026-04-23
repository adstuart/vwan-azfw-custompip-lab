#!/usr/bin/env bash
# Phase 2: spoke VNet + Ubuntu VM + vWAN hub connection. VM has no public IP; egress MUST go via FW.
source "$(dirname "$0")/00-vars.sh"

echo "== [02] Creating spoke VNet + subnet + NSG =="
az network nsg create -g "$RG" -n "$SPOKE_NSG" -l "$LOC" -o none
az network vnet create -g "$RG" -n "$SPOKE_VNET" -l "$LOC" \
  --address-prefixes "$SPOKE_ADDR" \
  --subnet-name "$SPOKE_SUBNET" --subnet-prefixes "$SPOKE_SUBNET_ADDR" \
  --nsg "$SPOKE_NSG" -o none

echo "== [02] Creating VM (no public IP) =="
az vm create -g "$RG" -n "$VM_NAME" -l "$LOC" \
  --image "$VM_IMAGE" --size "$VM_SIZE" \
  --vnet-name "$SPOKE_VNET" --subnet "$SPOKE_SUBNET" \
  --admin-username "$VM_USER" --generate-ssh-keys \
  --public-ip-address "" --nsg "" -o none

echo "== [02] Connecting spoke VNet to vWAN hub (secure internet egress enabled) =="
VNET_ID=$(az network vnet show -g "$RG" -n "$SPOKE_VNET" --query id -o tsv)
az network vhub connection create -g "$RG" --vhub-name "$HUB" \
  -n conn-spoke1 --remote-vnet "$VNET_ID" \
  --internet-security true -o none

az network vhub connection show -g "$RG" --vhub-name "$HUB" -n conn-spoke1 \
  --query "{name:name, state:provisioningState, secureInternet:enableInternetSecurity}" -o json
