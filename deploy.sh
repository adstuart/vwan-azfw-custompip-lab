#!/usr/bin/env bash
# Orchestrator. Runs each phase with a pause so you can inspect results.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$HERE/docs"
: > "$HERE/docs/RESULTS.md"
{
  echo "# Lab results log"
  echo
  echo "Generated from live runs of the scripts under \`scripts/\`."
} > "$HERE/docs/RESULTS.md"

PHASES=(01-deploy-core 02-deploy-spoke 03-baseline-test \
        04-custom-pip-prefix-add-attempt 05-custom-pip-swap \
        06-verify-egress-new-pip)

for p in "${PHASES[@]}"; do
  echo
  echo "############################################################"
  echo "# RUNNING: $p"
  echo "############################################################"
  bash "$HERE/scripts/${p}.sh"
  echo
  read -rp "Press Enter to continue to next phase, or Ctrl-C to stop... "
done

echo
echo "All phases complete. Review docs/RESULTS.md. Run scripts/99-teardown.sh to destroy."
