#!/bin/bash
echo "Worker start script"
if [[ "$CONTAINERIZATION_FLAVOR" != "k3s" ]]; then
    sudo kubeadm reset --force
    echo "Join command: $variables_kubeCommand"
    sudo $variables_kubeCommand
fi