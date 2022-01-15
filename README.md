# k8s-patch-script

These scripts exist to patch k8s certificates on LODS kubernetes labs during build-out.

For labs where there are no workers nodes, use k8s-certs-only.bash on the master. Do not add a lab variable.

## Lab Variable
First, an environment variable must be added to the lab instruction manual. 
This is used to transfer the new join token from the master node to the worker nodes once the certificates are updated.

| Name	| Value |	Token	|
|---|---|---|
| k8sToken | init | @lab.Variable(k8sToken)	|

## k8s-master.bash / k8s-certs-only.bash
The k8s-master.bash script should be employed as an LCA targeting the k8s-master VM.
k8s-certs-only.bash should be configured in the same manner.

This LCA should be configured as follows:
||Value|
|---|---|
| Action	| Execute Script in Virtual Machine |
| Event | First Displayable |
| Blocking |Yes|
| Machine |	*Master VM* |
| Language |	Bash |
| Delay | 10 Seconds |
| Timeout	| 5 Minutes |
| Error Action |	End Lab |

> ## WORKERNODES
> k8s-master.bash also containes an array names WORKERNODES which must be updated to list all worker nodes added to the cluster at the time of lab build.
> By default it lists:
> 
> WORKERNODES=("k8s-worker1" "k8s-worker2")

k8s-master.bash updates the certificates used by the cluster, removes all workers listed in WORKERNODES, and generates a new "join token" which is then saved into the k8sToken lab variable.

k8s-certs-only.bash updates the certificates used by the cluster.

## k8s-worker.bash
The k8s-worker.bash script should be employed as an LCA targeting each k8s-worker VM.

This LCAs should be configured as follows:
||Value|
|---|---|
| Action	| Execute Script in Virtual Machine |
| Event | First Displayable |
| Blocking | **No for all but the last VM, which should be Yes.** |
| Machine |	*Worker VMs* |
| Language |	Bash |
| Delay | 0 Seconds |
| Timeout	| 1 Minutes |
| Error Action |	End Lab |

## Notification LCA
Finally, an LCA should be added to alert the user that they may proceed with the lab.
Blocking on only one worker will allow the worker re-joins to happen concurrently

"All challenge resources have successfully deployed. You may now begin your challenge."
