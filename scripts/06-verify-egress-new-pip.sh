#!/usr/bin/env bash
# Phase 6: re-run egress test; expect VM-observed IP now comes from the prefix.
source "$(dirname "$0")/00-vars.sh"

PREFIX=$(az network public-ip prefix show -g "$RG" -n "$PIP_PREFIX_NAME" --query ipPrefix -o tsv)
echo "Prefix: $PREFIX"

OUT=$(az vm run-command invoke -g "$RG" -n "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "for i in 1 2 3; do echo IPIFY=\$(curl -s --max-time 10 https://api.ipify.org); sleep 1; done" \
  --query "value[0].message" -o tsv)
echo "$OUT"

VM_IP=$(echo "$OUT" | grep -oE '^IPIFY=[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | cut -d= -f2 | sort -u | head -1)
echo "VM-observed IP: $VM_IP"

RC=0
python3 - <<PY || RC=$?
import ipaddress, sys
ip = ipaddress.ip_address("$VM_IP")
net = ipaddress.ip_network("$PREFIX", strict=False)
print(f"In prefix $PREFIX ? {ip in net}")
sys.exit(0 if ip in net else 2)
PY

{
  echo
  echo "## Post-swap egress test — $(date -Iseconds)"
  echo
  echo "- Prefix: \`$PREFIX\`"
  echo "- VM-observed egress IP: \`$VM_IP\`"
  echo "- Result: $([ $RC -eq 0 ] && echo "**PASS** — egress now uses a prefix-allocated PIP" || echo "**FAIL**")"
} >> "$REPORT"

exit $RC
