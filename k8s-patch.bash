#!/bin/bash

# Install sshpass, this will be used later to provide the password to the worker node ssh connection and 
# transmit the token to re-join the cluster.
# echo 'Passw0rd!' | sudo -S is also used to provide the sudo permissions for this shell session
echo 'Passw0rd!' | sudo -S apt-get install sshpass

# Check certificate expiration

########################
## Certificate Update ##
########################

if sudo kubeadm alpha certs check-expiration | grep -q 'invalid'; 
then
    printf "[Certificate Renewal] Invalid certificates found, attempting to update. \n" 1>&2

    # Make backup of certificates

    mkdir -p "$HOME"/k8s-old-certs/pki
    sudo /bin/cp -p /etc/kubernetes/pki/*.* "$HOME"/k8s-old-certs/pki
    #ls -l "$HOME"/k8s-old-certs/pki/

    sudo /bin/cp -p /etc/kubernetes/*.conf $HOME/k8s-old-certs
    #ls -ltr "$HOME"/k8s-old-certs

    mkdir -p "$HOME"/k8s-old-certs/.kube
    sudo /bin/cp -p ~/.kube/config "$HOME"/k8s-old-certs/.kube/.
    #ls -l "$HOME"/k8s-old-certs/.kube/.

    #Renew certificates and check expiration dates

    sudo kubeadm alpha certs renew all

    #Check that the certificates have been renewed by looking for the "residual time" value of invalid.
    #This will be present if ANY certificate is invalid.
    if sudo kubeadm alpha certs check-expiration | grep -q 'invalid'; 
    then
        printf "[sudo kubeadm alpha certs renew all] Failed to update all certificates. \n " 1>&2
        exit 2
    else
        printf "[sudo kubeadm alpha certs renew all] Successfully updated certificates. \n" 1>&2
    fi

    # Verify if kublet.conf file was updated with new certificate information by comparing it with backup file

    #sudo diff $HOME/k8s-old-certs/kubelet.conf /etc/kubernetes/kubelet.conf

    # If no output, file was not updated. Update kubelet.conf.

    cd /etc/kubernetes || exit

    sudo chmod 666 kubelet.conf

    sudo kubeadm alpha kubeconfig user --org system:nodes --client-name system:node:"$(hostname)" > kubelet.conf 2>/dev/null

    # Verify update to kubelet.conf file.

    #sudo diff $HOME/k8s-old-certs/kubelet.conf /etc/kubernetes/kubelet.conf

    # Copy updated admin.conf to user config file

    sudo cp /etc/kubernetes/admin.conf ~/.kube/config

    #Verify update to file. You should see output. If no output, something is wrong. Check your steps.

    #sudo diff ~/.kube/config $HOME/k8s-old-certs/.kube/config

    #Restart the kubelet service

    sudo systemctl daemon-reload
    sudo systemctl restart kubelet

    #Wait on previous child processes to complete (systemctrl restart)
    wait

    #Check that the certificates have been applied and the user can connect to kubectl
    #Will return a connection error if this is not possible. 
    #This test will make 5 attempts, and wait 1 second between each failed check.
    tries=0
    while "$tries" -lt 5;
    do
        if kubectl get nodes | grep -q 'k8s-master1'; 
            then
                printf "[Certificate renewal] Successfully connected to kubectl \n" 1>&2
            else
                printf "[Certificate renewal] Failed to place updated certificates in all locations \n" 1>&2
                exit 3
        fi
        sleep 1
        ((tries++))
    done

else
    printf "[Certificate Renewal] No invalid certificates. \n " 1>&2
fi


################
## Node Reset ##
################

# Delete the worker nodes to re-join with updated certificates
if kubectl get nodes | grep -q 'k8s-worker1'; then
    printf "Deleting node 1"
    kubectl delete node k8s-worker1
fi

if kubectl get nodes | grep -q 'k8s-worker2'; then
    printf "Deleting node 2'"
    kubectl delete node k8s-worker2
fi

wait

#Confirm that all workers are deleted from master
if kubectl get nodes | grep -q 'k8s-worker1\|k8s-worker2'; 
then
    printf "[Delete k8s-worker1 and k8s-worker2] Failed to delete all worker nodes from master \n" 1>&2
    exit 4
else
    printf "[Delete k8s-worker1 and k8s-worker2] Successfully deleted all worker nodes from master \n" 1>&2
fi

#Generate an up-to-date boot-strap token to join new worker nodes to the VM
TOKEN=$(kubeadm token create --print-join-command 2>/dev/null)
echo "$TOKEN"

#Test the existence of the new token by confirming the existence of the kubeadm join command.
if echo "$TOKEN" | grep -q -F 'kubeadm join'; 
then
    printf "[Token creation] Successfully created new token \n" 1>&2
else
    printf "[Token creation] Failed to create new token \n" 1>&2
    exit 5
fi


#Verify that the k8s-worker1 has not already joined and then use remote ssh execution to reset the node and invoke the new token.
if kubectl get nodes | grep -q 'k8s-worker1'; then
	printf "k8s-worker1 already joined \n"
else
	printf "Connecting to k8s-worker1 \n"
	sshpass -p "Passw0rd!" ssh -o "StrictHostKeyChecking no" root@192.168.1.31 "kubeadm reset --force --ignore-preflight-errors strings" 2>/dev/null
	sshpass -p "Passw0rd!" ssh root@192.168.1.31 "$TOKEN" 2>/dev/null
    printf " k8s-worker1 reset \n"
fi

#Verify that the k8s-worker2 has not already joined and then use remote ssh execution to reset the node and invoke the new token.
if kubectl get nodes | grep -q 'k8s-worker2'; then
	printf "k8s-worker2 already joined \n"
else
	printf "Connecting to k8s-worker2 \n"
	sshpass -p "Passw0rd!" ssh -o "StrictHostKeyChecking no" root@192.168.1.32 "kubeadm reset --force --ignore-preflight-errors strings" 2>/dev/null
	sshpass -p "Passw0rd!" ssh root@192.168.1.32 "$TOKEN" 2>/dev/null
    printf "k8s-worker1 reset \n"
fi

wait


##################
## Node Testing ##
##################

#Test that both new nodes have joined the cluster as expected. They will be in a NotReady state for some time. 
if kubectl get nodes | grep -q 'k8s-worker1'; 
then
    printf "[Rejoin workers] Successfully rejoined k8s-worker1 to k8s-master1 \n" 1>&2

else
    printf "[Rejoin workers] Failed to rejoin k8s-worker1 to k8s-master1 \n" 1>&2
    exit 6
fi

if kubectl get nodes | grep -q 'k8s-worker2'; 
then
    printf "[Rejoin workers] Successfully rejoined k8s-worker2 to k8s-master1 \n" 1>&2

else
    printf "[Rejoin workers] Failed to rejoin k8s-worker2 to k8s-master1 \n" 1>&2
    exit 6
fi

#Test Status
tries=0
while "$tries" -lt 30;
do
    if kubectl get nodes | grep -q 'NotReady'; 
        then
            sleep 1
            ((tries++))
        else
            printf "[Certificate renewal] All nodes reporting as Ready\n" 1>&2
            exit
    fi
done

#After 30 seconds, if the Worker nodes are not yet ready, the script will report a failure.
printf "[Certificate renewal] Failed to place updated certificates in all locations \n" 1>&2
exit 7
