#!/bin/bash
echo "Worker start script"
if [[ "$CONTAINERIZATION_FLAVOR" != "k3s" ]]; then
else
    sudo kubeadm reset --force
    echo $variables_kubeCommand
    sudo $variables_kubeCommand
fi