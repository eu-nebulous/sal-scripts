#!/bin/bash
echo "Worker start script"

echo "modprobe br_netfilter"
sudo modprobe br_netfilter
echo "modprobe br_netfilter done"

if [[ "$CONTAINERIZATION_FLAVOR" != "k3s" ]]; then
    sudo kubeadm reset --force
    echo "Join command: $variables_kubeCommand"
    sudo $variables_kubeCommand
fi
