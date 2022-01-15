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
