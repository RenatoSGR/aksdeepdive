## Set up Overlay clusters
 **Note**

You must have CLI version 2.48.0 or later to use the --network-plugin-mode argument. For Windows, you must have the latest aks-preview Azure CLI extension installed and can follow the instructions below.

Create a cluster with Azure CNI Overlay using the az aks create command. Make sure to use the argument --network-plugin-mode to specify an overlay cluster. If the pod CIDR isn't specified, then AKS assigns a default space: viz. 10.244.0.0/16.

```bash

clusterName="myOverlayCluster"
resourceGroup="myResourceGroup"
location="westcentralus"

az aks create -n $clusterName -g $resourceGroup \
  --location $location \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --pod-cidr 192.168.0.0/16
```

### Add a new nodepool to a dedicated subnet

After you have created a cluster with Azure CNI Overlay, you can create another nodepool and assign the nodes to a new subnet of the same VNet. This approach can be useful if you want to control the ingress or egress IPs of the host from/ towards targets in the same VNET or peered VNets.

```bash

clusterName="myOverlayCluster"
resourceGroup="myResourceGroup"
location="westcentralus"
nodepoolName="newpool1"
subscriptionId=$(az account show --query id -o tsv)
vnetName="yourVnetName"
subnetName="yourNewSubnetName"
subnetResourceId="/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Network/virtualNetworks/$vnetName/subnets/$subnetName"

az aks nodepool add  -g $resourceGroup --cluster-name $clusterName \
  --name $nodepoolName --node-count 1 \
  --mode system --vnet-subnet-id $subnetResourceId

```

### Upgrade an existing cluster to CNI Overlay
 **Note**

You can update an existing Azure CNI cluster to Overlay if the cluster meets the following criteria:

The cluster is on Kubernetes version 1.22+.
Doesn't use the dynamic pod IP allocation feature.
Doesn't have network policies enabled. Network Policy engine can be uninstalled before the upgrade, see Uninstall Azure Network Policy Manager or Calico
Doesn't use any Windows node pools with docker as the container runtime.
 
**Note**

Because Routing domain is not yet supported for ARM, CNI Overlay is not yet supported on ARM-based (ARM64) processor nodes.

Upgrading an existing cluster to CNI Overlay is a non-reversible process.

 **Warning**

Upgrading an existing cluster to CNI Overlay is a non-reversible process.

**Warning**

Prior to Windows OS Build 20348.1668, there was a limitation around Windows Overlay pods incorrectly SNATing packets from host network pods, which had a more detrimental effect for clusters upgrading to Overlay. To avoid this issue, use Windows OS Build greater than or equal to 20348.1668.

**Warning**

If using a custom azure-ip-masq-agent config to include additional IP ranges that should not SNAT packets from pods, upgrading to Azure CNI Overlay can break connectivity to these ranges. Pod IPs from the overlay space will not be reachable by anything outside the cluster nodes. Additionally, for sufficiently old clusters there might be a ConfigMap left over from a previous version of azure-ip-masq-agent. If this ConfigMap, named azure-ip-masq-agent-config, exists and is not intentionally in-place it should be deleted before running the update command. If not using a custom ip-masq-agent config, only the azure-ip-masq-agent-config-reconciled ConfigMap should exist with respect to Azure ip-masq-agent ConfigMaps and this will be updated automatically during the upgrade process.

The upgrade process triggers each node pool to be re-imaged simultaneously. Upgrading each node pool separately to Overlay isn't supported. Any disruptions to cluster networking are similar to a node image upgrade or Kubernetes version upgrade where each node in a node pool is re-imaged.

### Azure CNI Cluster Upgrade
Update an existing Azure CNI cluster to use Overlay using the az aks update command.

```bash
clusterName="myOverlayCluster"
resourceGroup="myResourceGroup"
location="westcentralus"

az aks update --name $clusterName \
--resource-group $resourceGroup \
--network-plugin-mode overlay \
--pod-cidr 192.168.0.0/16
The --pod-cidr parameter is required when upgrading from legacy CNI because the pods need to get IPs from a new overlay space, which doesn't overlap with the existing node subnet. The pod CIDR also can't overlap with any VNet address of the node pools. For example, if your VNet address is 10.0.0.0/8, and your nodes are in the subnet 10.240.0.0/16, the --pod-cidr can't overlap with 10.0.0.0/8 or the existing service CIDR on the cluster.
    
    ``` 
    