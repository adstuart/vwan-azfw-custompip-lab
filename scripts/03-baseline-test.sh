#!/usr/bin/env bash
# Phase 3: baseline egress test. VM curls ifconfig.co; captured IP should == AzFW PIP.
source "$(dirname "$0")/00-vars.sh"

echo "== [03] Listing AzFW public IPs =="
az network firewall show -g "$RG" -n "$FWNAME" \
  --query "hubIPAddresses.publicIPs.addresses[].address" -o tsv | tee /tmp/fw-pips-before.txt

echo "== [03] Running curl from spoke VM — using ipify + ifconfig.me (ifconfig.co serves Cloudflare challenge HTML from Azure IPs, adds noise) =="
OUT=$(az vm run-command invoke -g "$RG" -n "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "echo IPIFY=\$(curl -s --max-time 15 https://api.ipify.org); echo IFCONFIGME=\$(curl -s --max-time 15 https://ifconfig.me); echo ICANHAZIP=\$(curl -s --max-time 15 https://icanhazip.com)" \
  --query "value[0].message" -o tsv)
echo "$OUT"

# Extract IPs from KEY=IP lines only; require at least 2 of 3 echo services to agree
VM_IP=$(echo "$OUT" | grep -oE '^(IPIFY|IFCONFIGME|ICANHAZIP)=[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | cut -d= -f2 | sort | uniq -c | sort -rn | awk 'NR==1 && $1>=2 {print $2}')
echo "VM-seen egress IP (consensus): $VM_IP"
echo "AzFW PIPs         :"; cat /tmp/fw-pips-before.txt
grep -q "^$VM_IP$" /tmp/fw-pips-before.txt \
  && echo "[PASS] egress uses AzFW PIP" \
  || { echo "[FAIL] egress IP not in AzFW PIP set"; exit 1; }

mkdir -p "$(dirname "$REPORT")"
{
  echo
  echo "## Baseline egress test — $(date -Iseconds)"
  echo
  echo "- AzFW PIPs: $(paste -sd, /tmp/fw-pips-before.txt)"
  echo "- VM-observed egress IP (ifconfig.co/ipify/ifconfig.me): \`$VM_IP\`"
  echo "- Result: **PASS** — egress IP matches AzFW PIP, confirming spoke traffic is SNATed by AzFW."
} >> "$REPORT"
