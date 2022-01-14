#!/bin/bash

WORKERNODES=("k8s-worker1" "k8s-worker2")

# Install sshpass, this will be used later to provide the password to the worker node ssh connection and 
# transmit the token to re-join the cluster.
# echo 'Passw0rd!' | sudo -S is also used to provide the sudo permissions for this shell session
echo 'Passw0rd!' | sudo -S apt-get install sshpass 2>/dev/null

# Check certificate expiration

########################
## Certificate Update ##
########################

if sudo kubeadm alpha certs check-expiration | grep -q 'invalid'; 
then
    printf "[Certificate Renewal] Invalid certificates found, attempting to update. \n"

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
        set_activity_result 0 "[sudo kubeadm alpha certs renew all] Failed to update all certificates"
        printf "[sudo kubeadm alpha certs renew all] Failed to update all certificates \n " 1>&2
        #exit 2
    else
        printf "[sudo kubeadm alpha certs renew all] Successfully updated certificates \n"
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
    # wait

    #Check that the certificates have been applied and the user can connect to kubectl
    #Will return a connection error if this is not possible. 
    #This test will make 5 attempts, and wait 1 second between each failed check.
    i=0
    while [ "$i" -le 30 ];
    do
        if kubectl get nodes 2>&1 | grep -q 'refused'; 
        then
            printf "kubectl connection try: %s\n" "$i"
        else
            break
        fi        
        sleep 1
        ((i++))
    done

    if kubectl get nodes 2>&1 | grep -q 'k8s-master1'; 
    then
        set_activity_result 1 "[Certificate renewal] Successfully updated certificates \n"
    else
        set_activity_result 0 "[Certificate renewal] Failed to place updated certificates in all locations"
        printf "[Certificate renewal] Failed to place updated certificates in all locations \n" 1>&2
        #exit 3
    fi   

else    
    set_activity_result .5 "[Certificate Renewal] Warning: No invalid certificates, attempting to update Nodes"
    printf "[Certificate Renewal] Warning: No invalid certificates, attempting to update Nodes \n "
fi


###################
## Node Deletion ##
###################
# Delete the worker nodes to re-join with updated certificates
#Each node will be attempted up-to 5 times, but are expected to succeed on the first.
#A connection failure will trigger and exit with error 3


# Attempt deletion of Worker1
i=0
while [ "$i" -le 5 ];
do
    if kubectl get nodes 2>&1 | grep -q 'refused'; 
    then
        set_activity_result 0 "[Delete Worker1] Failed to connect to kubectl on attempt: %s" "$i"
        printf "[Delete Worker1] Failed to connect to kubectl on attempt: %s\n" "$i" 1>&2
        #exit 3
    fi  

    if kubectl get nodes | grep -q 'k8s-worker1'; 
    then
        printf "Attempting to deleting node Worker1"
        kubectl delete node k8s-worker1
    else
        printf "[Delete Worker1] Successfully deleted Worker1 from master \n"
        break
    fi      
    sleep 1
    ((i++))
done

# Attempt deletion of worker2
i=0
while [ "$i" -le 5 ];
do
    if kubectl get nodes 2>&1 | grep -q 'refused'; 
    then
        set_activity_result 0 "[Delete Worker2] Failed to connect to kubectl on attempt: %s" "$i"
        printf "[Delete Worker2] Failed to connect to kubectl on attempt: %s\n" "$i" 1>&2
        #exit 3
    fi  

    if kubectl get nodes | grep -q 'k8s-worker2'; 
    then
        printf "Attempting to deleting node Worker2"
        kubectl delete node k8s-worker2
    else
        printf "[Delete Worker2] Successfully deleted Worker2 from master \n"
        break
    fi      
    sleep 1
    ((i++))
done

#wait

#Confirm that all workers are deleted from master
if kubectl get nodes 2>&1 | grep -q 'refused'
then
    set_activity_result 0 "[Verify no workers] Failed to connect to kubectl"
    printf "[Verify no workers] Failed to connect to kubectl \n" 1>&2
    #exit 3
else
    if kubectl get nodes | grep -q 'k8s-worker1\|k8s-worker2'; 
    then
        set_activity_result 0 "[Verify no workers] Failed to delete all worker nodes from master"
        printf "[Verify no workers] Failed to delete all worker nodes from master \n" 1>&2
        #exit 4
    else
        set_activity_result 1 "[Verify no workers] Successfully deleted all worker nodes from master"
        printf "[Verify no workers] Successfully deleted all worker nodes from master \n"
    fi
fi

##################
## Create Token ##
##################

#Generate an up-to-date boot-strap token to join new worker nodes to the VM
TOKEN=$(kubeadm token create --print-join-command 2>/dev/null)
echo "$TOKEN"

#Test the existence of the new token by confirming the existence of the kubeadm join command.
if echo "$TOKEN" | grep -q -F 'kubeadm join'; 
then
    set_activity_result 1 "[Token creation] Successfully created new token"
    printf "[Token creation] Successfully created new token \n"
else
    set_activity_result 0 "[Token creation] Failed to create new token"
    printf "[Token creation] Failed to create new token \n" 1>&2
    #exit 5
fi
