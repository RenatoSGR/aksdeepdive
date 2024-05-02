## Pre-requisites for the Global Azure Demo AKS environment



```bash
# create the demo variables
export SUBSCRIPTION_ID=""
export RESOURCE_GROUP=GlobalAzureDemo
export CLUSTER=globalazure-demo
export LOCATION=westeurope
export DNS_ZONE=globalazuredemomsft.com
export VAULT_NAME=globalazuredemokv
```

```bash
# create and AKS with Azure CNI Overlay Network Plugin

az aks create -n $CLUSTER -g $RESOURCE_GROUP --location $LOCATION --network-plugin azure --network-plugin-mode overlay --pod-cidr 192.168.0.0/16
```

or 
```bash
# create and AKS with Azure CNI (in the demo we have a step to convert it to Azure CNI Overlay Network Plugin)
az aks create -n $CLUSTER -g $RESOURCE_GROUP --location $LOCATION --network-plugin azure --generate-ssh-keys
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
az network dns zone create -g $RESOURCE_GROUP -n $DNS_ZONE

```

```bash
# enable the oidc issuer and workload identity on the cluster
az aks update -g $RESOURCE_GROUP -n $CLUSTER --enable-oidc-issuer --enable-workload-identity --no-wait
```

```bash	
# enable the mesh addon on the cluster
az aks mesh enable --resource-group $RESOURCE_GROUP --name $CLUSTER --no-wait
```

```bash
# enable the app-routing addon on the cluster
az aks approuting enable -g $RESOURCE_GROUP -n $CLUSTER 
```


```bash
# create a self signed certificate (already created via pre-requisites section)
openssl req -new -x509 -nodes -out aks-ingress-tls.crt -keyout aks-ingress-tls.key -subj "/CN=store-front.globalazuredemomsft.com" -addext "subjectAltName=DNS:store-front.globalazuredemomsft.com"

openssl pkcs12 -export -in aks-ingress-tls.crt -inkey aks-ingress-tls.key -out aks-ingress-tls.pfx

# import the certificate into azure key vault
az keyvault certificate import --vault-name $VAULT_NAME -n aks-ingress-tls -f aks-ingress-tls.pfx 

# retrieve the certificate from Azure Key Vault
az keyvault certificate show --vault-name $VAULT_NAME -n aks-ingress-tls --query "id" --output tsv

# enable azure key vault integration (this will enable secretcsi provider if not already enabled)
az keyvault show --name $VAULT_NAME --query "id" --output tsv

az aks approuting update -g $RESOURCE_GROUP -n $CLUSTER --enable-kv --attach-kv /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$VAULT_NAME

# attach dns zone to app routing
az network dns zone show -g $RESOURCE_GROUP -n $DNS_ZONE --query "id" --output tsv

az aks approuting zone add -g $RESOURCE_GROUP -n $CLUSTER --ids=/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/dnszones/$DNS_ZONE --attach-zones

```

### 3.1. Create the AKS Cluster with Cilium Network Data Plane & CNI Overlay Network Plugin

```bash	
# create a cilium cluster for Node Auto Provisioning (NAP) that we will use later on
az aks create --name aks-nap --resource-group fleet-aks --node-provisioning-mode Auto --network-plugin azure --network-plugin-mode overlay --network-dataplane cilium
```

