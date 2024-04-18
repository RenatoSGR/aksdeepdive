# create the demo variables
$SUBSCRIPTION_ID="fef74fbe-24ca-4d9a-ba8e-30a17e95608b"
$RESOURCE_GROUP="GlobalAzureDemo"
$CLUSTER="globalazure-demo"
$LOCATION="westeurope"
$DNS_ZONE="globalazuredemomsft.com"
$VAULT_NAME="globalazuredemokv"


#########################
######   ISTIO   ########
#########################
# get revisions
az aks mesh get-revisions --location $LOCATION -o table

# check the profiles of the addon
az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER  --query 'serviceMeshProfile.mode'

# label the demo namespace with the previously enabled Istio revision 
kubectl label namespace aksappga istio.io/rev=asm-1-20

### if needed restart the demo app for assume the Istio sidecar
kubectl rollout restart deployment <deployment name> -n aksappga

# apply the gateway configuration
kubectl apply -f .\gateway.yaml

# get the gateway IP 
kubectl get svc aks-istio-ingressgateway-external -n aks-istio-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

#########################
###### App-Routing ######
#########################

# create the app-routing-ingress yaml definition
kubectl apply -f .\app-routing-ingress.yaml


# retry the certificate uri from the key vault needed for the ingress definition
az keyvault certificate show --vault-name  $VAULT_NAME -n aks-ingress-tls --query "id" --output tsv

#copy the uri to the app-routing-ingress-tls.yaml file and apply it
kubectl apply -f .\app-routing-ingress-tls.yaml  

#########################
###### Observabiliy  ####
#########################

az grafana show --name grafana-globalazure --resource-group $RESOURCE_GROUP --query id --output tsv

az resource show --resource-group $RESOURCE_GROUP --name globalazureworkspace --resource-type "Microsoft.Monitor/accounts" --query id --output tsv
## see if the ama pods are running
kubectl get po -owide -n kube-system | grep ama-

# grafana dashboard
 https://grafana-globalazure-e2gsb0dzbza3f0gk.weu.grafana.azure.com 


#########################
#### Workload Itentity ##
#########################

# verify that csi secret provider is enabled
kubectl get pods -n kube-system -l 'app in (secrets-store-csi-driver,secrets-store-provider-azure)'

# create the identity for the workload identity (already created)
export UAMI=wiglobalazurepmsi2

# create te identity (already created)
az identity create --name $UAMI --resource-group $RESOURCE_GROUP

export USER_ASSIGNED_CLIENT_ID="$(az identity show -g $RESOURCE_GROUP --name $UAMI --query 'clientId' -o tsv)"
export IDENTITY_TENANT=$(az aks show --name $CLUSTER --resource-group $RESOURCE_GROUP --query identity.tenantId -o tsv)
export KEYVAULT_SCOPE=$(az keyvault show --name $VAULT_NAME --query id -o tsv)

# create the role assignment for the identity to access the key vault (already created)
az role assignment create --role "Key Vault Administrator" --assignee $USER_ASSIGNED_CLIENT_ID --scope $KEYVAULT_SCOPE

export AKS_OIDC_ISSUER="$(az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER --query "oidcIssuerProfile.issuerUrl" -o tsv)"
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
export FEDERATED_IDENTITY_NAME="aksglobalazurefederatedidentity2"

# create the federated identity for the workload identity
az identity federated-credential create --name $FEDERATED_IDENTITY_NAME --identity-name $UAMI --resource-group $RESOURCE_GROUP --issuer ${AKS_OIDC_ISSUER} --subject system:serviceaccount:${SERVICE_ACCOUNT_NAMESPACE}:${SERVICE_ACCOUNT_NAME}

# create the secret in the key vault
az keyvault secret show --vault-name $VAULT_NAME --name openaiapikey

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
    keyvaultName: ${VAULT_NAME}         # Set to the name of your key vault
    cloudName: ""                          # [OPTIONAL for Azure] if not provided, the Azure environment defaults to AzurePublicCloud
    objects:  |
      array:
        - |
          objectName: openaiapikey        # Set to the name of your secret
          objectType: secret              # object types: secret, key, or cert
          objectVersion: ""               # [OPTIONAL] object versions, default to latest if empty
    tenantId: "${IDENTITY_TENANT}"        # The tenant ID of the key vault
EOF

# verify the secret provider class created
kubectl get secretproviderclass -n aksappga

# describe the secret provider class 
kubectl describe secretproviderclass globalazure-wi -n aksappga

# verify the secret created
kubectl get secret openaisecret -n aksappga

# apply the ai-service deployment
kubectl apply -f ai-service-v2.yaml

kubectl get pods -n aksappga

# check the env vars on pod, and confirm the openai api key is being retrieved from the key vault
kubectl get pods -n aksappga
kubectl -n aksappga exec -it <pod-name> -c ai-service -- /bin/sh
env


#########################
###### Karpenter ########
#########################
# create variables for the cilium cluster
export RESOURCE_GROUP_NAP=fleet-aks
export CLUSTER_NAP=aks-karp

#login into the AKS Cluster with cilium network data plane
az aks get-credentials --resource-group $RESOURCE_GROUP_NAP --name $CLUSTER_NAP --overwrite-existing

# check the default node class to change the node sku and topology 
kubectl edit aksnodeclass default

# check the karpenter events to see the scaling events
kubectl get events -A --field-selector source=karpenter -w

# create a stress deployment to trigger the scaling
kubectl apply -f stress-deployment.yaml 