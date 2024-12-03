FROM busybox:1.36.1-musl

COPY installation-scripts-onm /sal-scripts/installation-scripts-onm
COPY k8s /sal-scripts/k8s
COPY serverless /sal-scripts/serverless