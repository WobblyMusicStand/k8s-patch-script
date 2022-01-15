#!/bin/bash

echo 'Passw0rd!' | sudo -S kubeadm reset --force --ignore-preflight-errors strings 2>/dev/null

if sudo @lab.Variable(k8sToken) 2>&1 | grep -q -F 'This node has joined the cluster'; 
then
    printf "[Worker 2 Join] Successfully joined cluster \n"
    echo true
else
    printf "[Worker 2 Join] Failed to join cluster with token: @lab.Variable(k8sToken) \n" 1>&2
    echo false
fi
