#!/usr/bin/env bash
# label-serverless-services.sh

set -euo pipefail

# === CONFIGURATION ===
LABEL_KEY="networking.knative.dev/visibility"
LABEL_VAL="cluster-local"
INTERVAL_SECONDS=120

# === MAIN LOOP ===
while true; do
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  SERVICES="$(printenv LOCAL_SERVERLESS_SERVICES || true)"

  if [[ -z "$SERVICES" ]]; then
    echo "Skipping: LOCAL_SERVERLESS_SERVICES is not set or empty."
  else
    IFS=',' read -ra SVC_LIST <<< "$SERVICES"
    for KSVC_NAME in "${SVC_LIST[@]}"; do
      echo "Applying label to kservice/${KSVC_NAME}..."
      if kubectl label kservice "$KSVC_NAME" \
           "${LABEL_KEY}=${LABEL_VAL}" \
           --overwrite; then
        echo "${KSVC_NAME} labeled."
      else
        echo "Failed on ${KSVC_NAME}." >&2
      fi
    done
  fi

  echo "Sleeping for ${INTERVAL_SECONDS}s..."
  sleep "$INTERVAL_SECONDS"
done
