#!/bin/bash
echo "Worker start script"
echo "modprobe br_netfilter"
sudo modprobe br_netfilter
echo "modprobe br_netfilter done"

sudo kubeadm reset --force
echo $variables_kubeCommand
sudo $variables_kubeCommand
