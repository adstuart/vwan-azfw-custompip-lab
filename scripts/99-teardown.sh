#!/usr/bin/env bash
# Phase 99: destroy everything.
source "$(dirname "$0")/00-vars.sh"

echo "== [99] Deleting RG $RG (cascades vWAN, hub, FW, PIPs, VM, prefix)... =="
az group delete -n "$RG" --yes --no-wait
echo "Delete initiated. Monitor with:"
echo "  watch -n 30 \"az group show -n $RG --query properties.provisioningState -o tsv 2>&1\""

{
  echo
  echo "## Teardown — $(date -Iseconds)"
  echo
  echo "- \`az group delete -n $RG --yes --no-wait\` issued. Cascade removes vWAN, hub, AzFW, PIPs, prefix, VM."
} >> "$REPORT"
