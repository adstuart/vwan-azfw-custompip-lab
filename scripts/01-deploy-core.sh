#!/usr/bin/env bash
# Phase 1: RG, vWAN, hub, AzFW (Standard, secured hub), routing intent (Private + Internet).
source "$(dirname "$0")/00-vars.sh"

echo "== [01] Creating RG + vWAN =="
az group create -n "$RG" -l "$LOC" -o none
az network vwan create -g "$RG" -n "$VWAN" -l "$LOC" --type Standard -o none

echo "== [01] Creating virtual hub $HUB ($HUB_ADDR) — 10-15 min =="
az network vhub create -g "$RG" --vwan "$VWAN" -n "$HUB" -l "$LOC" \
  --address-prefix "$HUB_ADDR" --sku Standard -o none

echo "== [01] Creating Firewall Policy (Standard) with explicit egress allow rule =="
az network firewall policy create -g "$RG" -n "$FWPOL" -l "$LOC" --sku Standard -o none
az network firewall policy rule-collection-group create \
  -g "$RG" --policy-name "$FWPOL" -n DefaultNetworkRuleCollectionGroup \
  --priority 200 -o none
az network firewall policy rule-collection-group collection add-filter-collection \
  -g "$RG" --policy-name "$FWPOL" \
  --rule-collection-group-name DefaultNetworkRuleCollectionGroup \
  --name AllowEgress --collection-priority 1000 --action Allow \
  --rule-name allow-web --rule-type NetworkRule \
  --source-addresses "10.200.0.0/24" --destination-addresses "*" \
  --destination-ports 80 443 53 --ip-protocols TCP UDP -o none

echo "== [01] Deploying AzFW into hub (Standard, 1 Azure-managed PIP) — 15-25 min =="
az network firewall create -g "$RG" -n "$FWNAME" -l "$LOC" \
  --sku AZFW_Hub --tier Standard \
  --virtual-hub "$HUB" --public-ip-count 1 \
  --firewall-policy "$FWPOL" -o none

FW_ID=$(az network firewall show -g "$RG" -n "$FWNAME" --query id -o tsv)

echo "== [01] Enabling routing intent (Private + Internet → AzFW) =="
az network vhub routing-intent create -g "$RG" --vhub "$HUB" -n routing-intent \
  --routing-policies "[{name:InternetTraffic,destinations:[Internet],next-hop:$FW_ID},{name:PrivateTrafficPolicy,destinations:[PrivateTraffic],next-hop:$FW_ID}]" -o none

echo "== [01] Core deploy complete =="
az network firewall show -g "$RG" -n "$FWNAME" \
  --query "{fw:name, state:provisioningState, pipCount:length(hubIPAddresses.publicIPs.addresses), privateIp:hubIPAddresses.privateIPAddress}" -o json
