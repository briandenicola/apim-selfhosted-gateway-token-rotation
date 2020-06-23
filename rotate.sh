#!/bin/bash

export subscription=${AZURE_SUBSCRIPTION}
export RG=${AZURE_RESOURCE_GROUP}
export apimName=${AZURE_API_MANAGEMENT}
export gateway=${AZURE_APIM_GATEWAY}

if [ $(date +%m) -le 15 ]; then 
    export keyType="secondary" 
else
    export keyType="primary" 
fi

echo "Log into Azure via Managed Identity"
az login --identity 

echo "Set Azure Subscription to ${subscription}"
az account set -s ${subscription}
id=`az account show -o tsv --query id`
uri="https://management.azure.com/subscriptions/${id}/resourceGroups/${RG}/providers/Microsoft.ApiManagement/service/${apimName}/gateways/${gateway}"

expiry=`date -d "1970-01-01 00:00:$(date +"%s + 2505600" | xargs expr)" +"%Y-%m-%dT%H:%m:00Z"`
echo "Get Token set to expired on ${expiry}"
token=`az rest --method POST --uri "${uri}/generateToken/?api-version=2019-12-01" --body "{ \"expiry\": \"${expiry}\", \"keyType\": \"${keyType}\" }" | jq .value | tr -d "\"" `

echo "Update Secret in Kubernetes"
kubectl delete secret ${gateway}-token
kubectl create secret generic ${gateway}-token --from-literal=value="GatewayKey ${token}"  --type=Opaque

echo "Rollout Deployment in Kubernetes"
kubectl rollout restart deployment ${gateway}

if [ $keyType == "primary" ]; then 
    rotatedKey="secondary"
else
    rotatedKey="primary"
fi

#echo "Rotate ${rotatedKey} Key"
az rest --method POST --uri "${uri}/regenerateKey?api-version=2019-12-01" --body "{ \"keyType\": \"${rotatedKey}\" }" 