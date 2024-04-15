# AKSDeepDive-GA
Repo for the demo on Global Azure Portugal 2024

**Table Of Contents**

1. [Demo Objectives](#1-learning-objectives)
2. [Pre-Requisites](#2-pre-requisites)
    - 2.1 [Create Azure Resources](#21-create-azure-resources)
3. [Manual Setup Environment ](#3-manual-setup-environment)
    - 3.1 [Create the AKS Cluster with Cilium Network Data Plane & CNI Overlay Network Plugin](#31-create-the-aks-cluster-with-cilium-network-data-plane--cni-overlay-network-plugin)
    - 3.2 [Login into the cluster](#32-login-into-the-cluster)
    - 3.3 [Enable cost analysis addon on the AKS cluster](#33-enable-cost-analysis-addon-on-the-aks-cluster)
    - 3.4 [Update the AKS cluster from Azure CNI plugin to Azure CNI Overlay](#34-update-the-aks-cluster-from-azure-cni-plugin-to-azure-cni-overlay)
4. [Installing unmanaged community nginx ingress controller](#4-installing-unmanaged-community-nginx-ingress-controller)
5. [Deploy the Application - AKS Store Demo](#5-deploy-the-application---aks-store-demo)
6. [Enable Istio addon](#6-enable-istio-addon)
    - 6.1 [Expose the store-front service via Istio ingress gateway - public gateway](#61-expose-the-store-front-service-via-istio-ingress-gateway---public-gateway)
7. [Expose the store-admin service via app-routing addon](#7-expose-the-store-admin-service-via-app-routing-addon)
    - 7.1 [Set up a custom domain name and SSL certificate with the app routing add-on](#71-set-up-a-custom-domain-name-and-ssl-certificate-with-the-app-routing-add-on-we-can-step-to-82-section)
    - 7.2 [Create the Ingress that uses a host name and a certificate from Azure Key Vault](#72-create-the-ingress-that-uses-a-host-name-and-a-certificate-from-azure-key-vault)
    - 7.3 [Add to hosts file the subdomain](#73-add-to-hosts-file-the-subdomain)
8. [Enable Monitoring into the cluster via managed Prometheus & Grafana](#8-enable-monitoring-into-the-cluster-via-managed-prometheus--grafana)
    - 8.1 [Enable Network Observability](#81-enable-network-observability)
9. [Deploy the AI service connected to azure openai with keyvault to store the secrets (Open AI api key) - using the Microsoft Entra Workload ID - workload identity method](#9-deploy-the-ai-service-connected-to-azure-openai-with-keyvault-to-store-the-secrets-open-ai-api-key---using-the-microsoft-entra-workload-id---workload-identity-method)
10. [Node autoprovisioning (preview) with karpenter dynamic cluster scaling](#10-node-autoprovisioning-preview-with-karpenter-dynamic-cluster-scaling)
11. [AKS Fleet Manager - manage at scale](#11-aks-fleet-manager---manage-at-scale)
    - 11.1 [Create a fleet with a hub cluster (enables workload propagation and multi-cluster load balancing)](#111-create-a-fleet-with-a-hub-cluster-enables-workload-propagation-and-multi-cluster-load-balancing)
    - 11.2 [Upgrade all members](#112-upgrade-all-members)


## 1. Learning Objectives
Deep Dive in AKS, to learn to deploy and configure a production ready AKS Cluster and prepare workloads to run on it with all the configurations needed for a proper lifecycle on AKS CLusters. 

## 2. Pre-Requisites
- **Azure Subscription** - [Signup for a free account.](https://azure.microsoft.com/free/)
- **Visual Studio Code** - [Download it for free.](https://code.visualstudio.com/download)
- **GitHub Account** - [Signup for a free account.](https://github.com/signup)
- **AKS Cluster** - [Learn about the Service.](https://azure.microsoft.com/en-us/products/kubernetes-service)
- **Azure Kubernetes Fleet Manager** - [Learn about the Service.](https://azure.microsoft.com/en-us/products/kubernetes-fleet-manager)
- **Key Vault and Container Registry** - Required for the Demo 

### 2.1. Create Azure resources

We setup our development environment in the previous step. In this step, we'll **provision Azure resources** for our demo, ready to use.
- AKS (Azure Kubernetes Services) - CNI Overlay Network Plugin & Standard API
- Azure Key Vault - Store secrets and certificates
- Azure Kubernetes Fleet Manager - Manage multiple AKS clusters
- AKS (Azure Kubernetes Services) - Cilium Network Data Plane & CNI Overlay Network Plugin

## 3. Manual Setup Environment

```powershell
Set-Alias -Name k -Value kubectl
```

```bash
# enable extensions and providers
az extension add --name aks-preview
az extension update --name aks-preview
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.NetworkFunction
az provider register --namespace Microsoft.ServiceNetworking
az feature register --namespace "Microsoft.ContainerService" --name "NodeAutoProvisioningPreview"
az extension add --name alb
az extension add --name fleet
az provider register --namespace Microsoft.ContainerService
```

```bash
# create a public dns zone for the app routing addon that we will use later on
az network dns zone create -g GlobalAzureDemo -n globalazuredemomsft.com

# add an A record to the dns zone for the app routing addon demo app
az network dns record-set a add-record -g GlobalAzureDemo -z globalazuredemomsft.com -n store-front -a 
```

```bash
# enable the oidc issuer and workload identity on the cluster
az aks update -g GlobalAzureDemo -n globalazure-demo --enable-oidc-issuer --enable-workload-identity
```

```bash	
# enable the mesh addon on the cluster
az aks mesh enable --resource-group GlobalAzureDemo --name globalazure-demo
```

```bash
# enable the app-routing addon on the cluster
az aks approuting enable -g GlobalAzureDemo -n globalazure-demo
```


```bash
# create a self signed certificate (already created via pre-requisites section)
openssl req -new -x509 -nodes -out aks-ingress-tls.crt -keyout aks-ingress-tls.key -subj "/CN=store-front.globalazuredemomsft.com" -addext "subjectAltName=DNS:store-front.globalazuredemomsft.com"

openssl pkcs12 -export -in aks-ingress-tls.crt -inkey aks-ingress-tls.key -out aks-ingress-tls.pfx

# import the certificate into azure key vault
az keyvault certificate import --vault-name globalazuredemokv -n aks-ingress-tls -f aks-ingress-tls.pfx 

# enable azure key vault integration (this will enable secretcsi provider if not already enabled)
az keyvault show --name globalazuredemokv --query "id" --output tsv

az aks approuting update -g GlobalAzureDemo -n globalazure-demo --enable-kv --attach-kv /subscriptions/fef74fbe-24ca-4d9a-ba8e-30a17e95608b/resourceGroups/GlobalAzureDemo/providers/Microsoft.KeyVault/vaults/globalazuredemokv

### attach dns zone to app routing
az network dns zone show -g GlobalAzureDemo -n globalazuredemomsft.com --query "id" --output tsv

az aks approuting zone add -g GlobalAzureDemo -n globalazure-demo --ids=/subscriptions/fef74fbe-24ca-4d9a-ba8e-30a17e95608b/resourceGroups/globalazuredemo/providers/Microsoft.Network/dnszones/globalazuredemomsft.com --attach-zones

### Create the Ingress that uses a host name and a certificate from Azure Key Vault
az keyvault certificate show --vault-name globalazuredemokv -n aks-ingress-tls --query "id" --output tsv
```



### 3.1. Create the AKS Cluster with Cilium Network Data Plane & CNI Overlay Network Plugin

```bash	
# create a cilium cluster for Node Auto Provisioning (NAP) that we will use later on
az aks create --name aks-nap --resource-group fleet-aks --node-provisioning-mode Auto --network-plugin azure --network-plugin-mode overlay --network-dataplane cilium
```


### 3.2. Login into the cluster
```bash
#login into the AKS Cluster
subscriptionId=""
az account set --subscription $subscriptionId
az aks get-credentials --resource-group GlobalAzureDemo --name globalazure-demo --overwrite-existing
```

### 3.3. Enable cost analysis addon on the AKS cluster
```bash
# enable cost analysis on the cluster - only possible with Standard API mode
az aks update --resource-group GlobalAzureDemo --name globalazure-demo --enable-cost-analysis
```

### 3.4. Update the AKS cluster from Azure CNI plugin to Azure CNI Overlay

Before doing this task, please read the [documentation](https://learn.microsoft.com/en-us/azure/aks/azure-cni-overlay?tabs=kubectl#upgrade-an-existing-cluster-to-cni-overlay) regarding the limitations and criteria for this operation.

```bash
clusterName="globalazure-demo"
resourceGroup="GlobalAzureDemo"
location="westeurope"
az aks update --name $clusterName --resource-group $resourceGroup --network-plugin-mode overlay --pod-cidr 192.168.0.0/16
```

## 4. Installing unmanaged community nginx ingress controller
```bash
# install nginx ingress controller chart (https://github.com/kubernetes/ingress-nginx) 
helm install ingress-nginx ingress-nginx/ingress-nginx `
--create-namespace `
--namespace ingress-nginx `
--set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz `
--set controller.nodeSelector."kubernetes\.io/os"=linux `
--set controller.replicaCount=2 
#--set controller.service.loadBalancerIP="" 
#--set controller.nodeSelector.agentpool=
#--set controller.ingressClass=""
#--set controller.ingressClassResource.name=""
#--set controller.ingressClassResource.controllerValue="k8s.io/ingress-nginx"
```

## 5. Deploy the Application - AKS Store Demo 

**Github Repo:** [AKS Store Demo](https://github.com/Azure-Samples/aks-store-demo)

***Architecture:***

![alt text](./content/image.png)


```bash	
# create the namespace where the demo app will be deployed
kubectl create ns aksappga

# deploy the app into the namespace
kubectl apply -f https://raw.githubusercontent.com/Azure-Samples/aks-store-demo/main/aks-store-all-in-one.yaml -n aksappga

# expose the store-front service via unmanaged nginx ingress controller
kubectl apply -f .\nginx-ingress.yaml

# get the public IP of the ingress controller
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# curl the store-front service
curl http://<ingress-ip>
```

## 6. Enable Istio addon 

```bash
# enable the addon on the cluster (already enabled via pre-requisites section)
az aks mesh get-revisions --location westeurope -o table
az aks mesh enable --resource-group GlobalAzureDemo --name globalazure-demo

# check the profiles of the addon
az aks show --resource-group GlobalAzureDemo --name globalazure-demo  --query 'serviceMeshProfile.mode'

# label the demo namespace with the previously enabled Istio revision 
kubectl label namespace aksappga istio.io/rev=asm-1-20

### if needed restart the demo app for assume the Istio sidecar
kubectl rollout restart deployment <deployment name> -n <deployment namespace>
```

### 6.1. Expose the store-front service via Istio ingress gateway - public gateway

```bash
# apply the gateway configuration
kubectl apply -f .\gateway.yaml

# get the gateway IP 
kubectl get svc aks-istio-ingressgateway-external -n aks-istio-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# curl the store-front service via the Istio gateway
curl http://<gateway-ip>
```

## 7. Expose the store-admin service via app-routing addon 

***Note:*** It supports already internal ingress (LB) mode - https://learn.microsoft.com/en-us/azure/aks/app-routing-nginx-configuration#create-an-internal-nginx-ingress-controller-with-a-private-ip-address)

```bash
# enable the app-routing addon on the cluster (already enabled via pre-requisites section)
az aks approuting enable -g GlobalAzureDemo -n globalazure-demo
```

```bash	
# create the app-routing-ingress yaml definition
kubectl apply -f .\app-routing-ingress.yaml

# get the public IP of the app-routing addon
kubectl get svc nginx -n app-routing-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# curl the store-admin service via the app-routing addon
curl http://<app-routing-ip>
```

### 7.1 Set up a custom domain name and SSL certificate with the app routing add-on (we can step to 8.2 section)

On this section we will use the Azure Key Vault integration with the app-routing addon to store the SSL certificate and use it to expose the store-front service via the app-routing addon with a custom domain name.

We will use a self signed certificate for demo purposes.

```bash
# create a self signed certificate (already created via pre-requisites section)
openssl req -new -x509 -nodes -out aks-ingress-tls.crt -keyout aks-ingress-tls.key -subj "/CN=store-front.globalazuredemomsft.com" -addext "subjectAltName=DNS:store-front.globalazuredemomsft.com"

openssl pkcs12 -export -in aks-ingress-tls.crt -inkey aks-ingress-tls.key -out aks-ingress-tls.pfx

# import the certificate into azure key vault
az keyvault certificate import --vault-name globalazuredemokv -n aks-ingress-tls -f aks-ingress-tls.pfx 

# enable azure key vault integration (this will enable secretcsi provider if not already enabled)
az keyvault show --name globalazuredemokv --query "id" --output tsv

az aks approuting update -g GlobalAzureDemo -n globalazure-demo --enable-kv --attach-kv /subscriptions/fef74fbe-24ca-4d9a-ba8e-30a17e95608b/resourceGroups/GlobalAzureDemo/providers/Microsoft.KeyVault/vaults/globalazuredemokv

### attach dns zone to app routing
az network dns zone show -g GlobalAzureDemo -n globalazuredemomsft.com --query "id" --output tsv

az aks approuting zone add -g GlobalAzureDemo -n globalazure-demo --ids=/subscriptions/fef74fbe-24ca-4d9a-ba8e-30a17e95608b/resourceGroups/globalazuredemo/providers/Microsoft.Network/dnszones/globalazuredemomsft.com --attach-zones
```	

### 7.2. Create the Ingress that uses a host name and a certificate from Azure Key Vault

```bash
# retry the certificate uri from the key vault needed for the ingress definition
az keyvault certificate show --vault-name globalazuredemokv -n aks-ingress-tls --query "id" --output tsv

#copy the uri to the app-routing-ingress-tls.yaml file and apply it
kubectl apply -f .\app-routing-ingress-tls.yaml  
```

We can then check the secret being created on AKS, and the dns zone updated with an A record for the subdomain previously created (store-front.globalazuredemomsft.com).

### 7.3 Add to hosts file the subdomain

Add to the the local hosts file, the subdomain name store-front.globalazuredemomsft.com pointing to the app-routing ip and then we can hit [on browser](https://store-front.globalazuredemomsft.com/) and check the store-admin service with th self signed certificate and exposed via tls using the app-routing addon.


## 8. Enable Monitoring into the cluster via managed Prometheus & Grafana 

In this section we will enable the monitoring addon on the AKS cluster, enabling the managed prometheus and check the metrics on the managed grafana dashboard.

[Learn about on documentation ](https://techcommunity.microsoft.com/t5/azure-observability-blog/comprehensive-network-observability-for-aks-through-azure/ba-p/3825852)

```bash
# create azure monitor resource (already created via pre-requisites section)
az resource create --resource-group GlobalAzureDemo --namespace microsoft.monitor --resource-type accounts --name globalazuremonitor --location westeurope --properties '{}'

# create grafana instance (already created via pre-requisites section)
az grafana create --name globalazuregf --resource-group GlobalAzureDemo 

# place grafana and monitor id into variables
grafanaId=$(az grafana show --name globalazuregf --resource-group GlobalAzureDemo --query id --output tsv)
azuremonitorId=$(az resource show --resource-group GlobalAzureDemo --name globalazuremonitor --resource-type "Microsoft.Monitor/accounts" --query id --output tsv)

# link monitor and grafana to AKS cluster
az aks update --name globalazure-demo --resource-group GlobalAzureDemo --enable-azure-monitor-metrics --azure-monitor-workspace-resource-id $azuremonitorId --grafana-resource-id $grafanaId

## see the ama pods are running
kubectl get po -owide -n kube-system | grep ama-
or for powershell
kubectl get po -owide -n kube-system | Select-String "ama-"
```	

### 8.1. Enable Network Observability 

[Network observability] (https://learn.microsoft.com/en-us/azure/aks/network-observability-managed-cli?tabs=non-cilium) is an important part of maintaining a healthy and performant Kubernetes cluster. By collecting and analyzing data about network traffic, you can gain insights into how your cluster is operating and identify potential problems before they cause outages or performance degradation.

![alt text](content/network-obs.png)

(https://learn.microsoft.com/en-us/azure/aks/network-observability-managed-cli?tabs=non-cilium) - we can talk about retina - cloud agnostic open-source Kubernetes Network Observability platform (https://retina.sh/docs/intro)
az aks update --resource-group GlobalAzureDemo --name globalazure-demo --enable-network-observability

Learn more about Retina (https://azure.microsoft.com/en-us/blog/microsoft-open-sources-retina-a-cloud-native-container-networking-observability-platform/)

![alt text](content/retina.png)

Learn more about [control plane metrics](https://learn.microsoft.com/en-us/azure/aks/monitor-control-plane-metrics) with API server and etcd metrics Grafana dashboards integration.


## 9. Deploy the AI service connected to azure openai with keyvault to store the secrets (Open AI api key) - using the Microsoft Entra Workload ID - workload identity method

Learn more about [workload identity](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-identity-access#access-with-a-microsoft-entra-workload-id)

Learn more about [csi secret store integration with AKS](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-configuration-options#set-an-environment-variable-to-reference-kubernetes-secrets)

After enabling the workload identity and the csi driver on the pre-requisites section, we can now deploy the AI service connected to the azure openai api with the keyvault to store the api keys and secrets.

```bash
# verify that csi secret provider is enabled
kubectl get pods -n kube-system -l 'app in (secrets-store-csi-driver,secrets-store-provider-azure)'

# create the identity for the workload identity (already created)
export SUBSCRIPTION_ID=fef74fbe-24ca-4d9a-ba8e-30a17e95608b
export RESOURCE_GROUP=GlobalAzureDemo
export UAMI=wiglobalazurepmsi
export KEYVAULT_NAME=globalazuredemokv
export CLUSTER_NAME=globalazure-demo

# create te identity (already created)
az identity create --name $UAMI --resource-group $RESOURCE_GROUP

export USER_ASSIGNED_CLIENT_ID="$(az identity show -g $RESOURCE_GROUP --name $UAMI --query 'clientId' -o tsv)"
export IDENTITY_TENANT=$(az aks show --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP --query identity.tenantId -o tsv)
export KEYVAULT_SCOPE=$(az keyvault show --name $KEYVAULT_NAME --query id -o tsv)

# create the role assignment for the identity to access the key vault (already created)
az role assignment create --role "Key Vault Administrator" --assignee $USER_ASSIGNED_CLIENT_ID --scope $KEYVAULT_SCOPE

export AKS_OIDC_ISSUER="$(az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --query "oidcIssuerProfile.issuerUrl" -o tsv)"
echo $AKS_OIDC_ISSUER
export SERVICE_ACCOUNT_NAME="workload-identity-sa"  
export SERVICE_ACCOUNT_NAMESPACE="aksappga" 

# create the service account with the workload identity annotation clientID
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: ${USER_ASSIGNED_CLIENT_ID}
  name: ${SERVICE_ACCOUNT_NAME}
  namespace: ${SERVICE_ACCOUNT_NAMESPACE}
EOF

# create the federated identity for the workload identity
export FEDERATED_IDENTITY_NAME="aksglobalazurefederatedidentity"
az identity federated-credential create --name $FEDERATED_IDENTITY_NAME --identity-name $UAMI --resource-group $RESOURCE_GROUP --issuer ${AKS_OIDC_ISSUER} --subject system:serviceaccount:${SERVICE_ACCOUNT_NAMESPACE}:${SERVICE_ACCOUNT_NAME}

# create the secret provider class with the workload identity to access the key vault to retrieve the openai api key
cat <<EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: globalazure-wi                     # needs to be unique per namespace
  namespace: aksappga
spec:
  provider: azure
  secretObjects:                           # [OPTIONAL] SecretObjects defines the desired state of synced Kubernetes secret objects
  - data:
    - key: keyopenai                       # data field to populate
      objectName: openaiapikey             # name of the mounted content to sync; this could be the object name or the object alias
    secretName: openaisecret               # name of the Kubernetes secret object
    type: Opaque       
  parameters:
    usePodIdentity: "false"
    clientID: "${USER_ASSIGNED_CLIENT_ID}" # Setting this to use workload identity
    keyvaultName: ${KEYVAULT_NAME}         # Set to the name of your key vault
    cloudName: ""                          # [OPTIONAL for Azure] if not provided, the Azure environment defaults to AzurePublicCloud
    objects:  |
      array:
        - |
          objectName: openaiapikey        # Set to the name of your secret
          objectType: secret              # object types: secret, key, or cert
          objectVersion: ""               # [OPTIONAL] object versions, default to latest if empty
    tenantId: "${IDENTITY_TENANT}"        # The tenant ID of the key vault
EOF
```

```bash
# apply the ai-service deployment
kubectl apply -f ai-service-v2.yaml

# check the env vars on pod, and confirm the openai api key is being retrieved from the key vault
kubectl -n aksappga exec -it <pod-name> -c ai-service -- /bin/sh
```

We can now test the store-admin integration with openai, by creating a product to inventory, and ask for help on the description geerator powered by azure openai gpt-3.5-turbo model.

**Note:** We can configure on ai-service deployment the azure openai access also via [managed identity](https://learn.microsoft.com/en-us/azure/aks/open-ai-secure-access-quickstart) under the azure context.


## AKS Scaling

## 10. Node autoprovisioning (preview) with karpenter dynamic cluster scaling

In this section we will enable the [node autoprovisioning feature](https://learn.microsoft.com/en-us/azure/aks/node-autoprovision?tabs=azure-cli) on the AKS cluster, using the karpenter dynamic cluster scaling feature

**Limitations**
- The only network configuration allowed is Cilium + Overlay + Azure
- You can't enable in a cluster where node pools have cluster autoscaler enabled

```bash
#login into the AKS Cluster with cilium network data plane
az aks get-credentials --resource-group <rg> --name <cilium-cluster-name> --overwrite-existing

# check the default node class to change the node sku and topology 
kubectl edit aksnodeclass default
```

Lets deploy an [application](https://github.com/wdhif/docker-stress-ng) that will create stress into the nodes to trigger the karpenter dynamic cluster scaling feature 

```bash
# check the karpenter events to see the scaling events
kubectl get events -A --field-selector source=karpenter -w

# create a stress deployment to trigger the scaling
kubectl apply -f stress-deployment.yaml 
```

## 11. AKS Fleet Manager - manage at scale

In this section we will create an AKS Fleet Manager resource and onoboard new AKS clusters to the fleeet hub, in order to perform operations at scale like and upgrade or resource proliferation between multiple clusters.


[Azure Kubernetes Fleet Manager (Fleet)](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/overview) enables at-scale management of multiple Azure Kubernetes Service (AKS) clusters. Fleet supports the following scenarios:

-  Create a Fleet resource and join AKS clusters across regions and subscriptions as member clusters.

- Orchestrate Kubernetes version upgrades and node image upgrades across multiple clusters by using update runs, stages, and groups.

- Create Kubernetes resource objects on the Fleet resource's hub cluster and control their propagation to member clusters (preview).

- Export and import services between member clusters, and load balance incoming layer-4 traffic across service endpoints on multiple clusters (preview).

![alt text](content/fleetmanager.png)



## 11.1 Create a fleet with a hub cluster (enables workload propagation and multi-cluster load balancing)

```bash
# create the fleet resource with a hub cluster (already created)
az fleet create --resource-group fleet-aks --name fleetmgr-globalazure-demo --location westeurope --enable-hub

# create variables for the member clusters
export MEMBER_NAME_1=globalazure-demo
export MEMBER_CLUSTER_ID_1=/subscriptions/fef74fbe-24ca-4d9a-ba8e-30a17e95608b/resourceGroups/fleet-aks/providers/Microsoft.ContainerService/managedClusters/globalazure-demo

## Join the first member cluster
az fleet member create --resource-group fleet-aks --fleet-name fleetmgr-globalazure-demo --name globalazure-demo --update-group dev --member-cluster-id /subscriptions/fef74fbe-24ca-4d9a-ba8e-30a17e95608b/resourceGroups/fleet-aks/providers/Microsoft.ContainerService/managedClusters/globalazure-demo

## list members
az fleet member list --resource-group fleet-aks --fleet-name fleetmgr-globalazure-demo -o table
```


### 11.2. Upgrade all members 

Platform admins managing large number of clusters often have problems with staging the updates of multiple clusters (for example, upgrading node OS image versions, upgrading Kubernetes versions) in a safe and predictable way. To address this pain point, Azure Kubernetes Fleet Manager (Fleet) allows you to orchestrate updates across multiple clusters using update runs, stages, groups, and strategies.

[Learn more about at scale cluster upgrades] (https://learn.microsoft.com/en-us/azure/kubernetes-fleet/update-orchestration?tabs=cli)

We can use both Azure portal or azure cli

```bash
az fleet updaterun create --resource-group fleet-aks --fleet-name fleetmgr-globalazure-demo --name run-1 --upgrade-type Full --kubernetes-version 1.26.0
```

***extra arguments***

- --upgrade-type NodeImageOnly

**Update clusters in a specific order**

```bash
#https://learn.microsoft.com/en-us/azure/kubernetes-fleet/update-orchestration?tabs=cli#update-clusters-in-a-specific-order
az fleet member update --resource-group $GROUP --fleet-name $FLEET --name member1 --update-group dev
```

