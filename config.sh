#!/bin/bash

while (( "$#" )); do
  case "$1" in
    -s|--subscription)
        subscription=$2
        shift 2
        ;;
    -g|--resource-group)
        RG=$2
        shift 2
        ;;
    -n|--name)
        apimName=$2
        shift 2
        ;;
    --gateway)
        gateway=$2
        shift 2
        ;;
    -l|--location)
        location=$2
        shift 2
        ;;
    -h|--help)
      echo "Usage: ./config.sh -s {Subscription Name} -n {API Management Name} -g {Resource Group} --gateway {APIM Gateway Name} -l {location}"
      exit 0
      ;;
    --) 
      shift
      break
      ;;
    -*|--*=) 
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
  esac
done

container="bjd145\/apimrotate:1.4"
role="API Management Service Contributor"
msiUserName=${apimName}-identity

echo Creating Managed Identity - ${msiUserName}
msi=`az identity create -n ${msiUserName} -g ${RG} -l ${location}`
msiObjectId=`echo ${msi} | jq '.principalId' | tr -d "\""`
msiClientId=`echo ${msi} | jq '.clientId' | tr -d "\""`
resourceId=`echo ${msi} | jq '.id' | tr -d "\""`

echo Pause 30 seconds to allow ${msiUserName} to propogate 
sleep 30

echo Assigning \"${role}\" role to ${RG}
az role assignment create --assignee-object-id ${msiObjectId} --role "${role}"  -g ${RG}

echo Updating Kubernetes Deployment Files
sed -e "s/{{MSI_USERNAME}}/${msiUserName}/g"  \
    -e "s/{{AZURE_SUBSCRIPTION}}/${subscription}/g"  \
    -e "s/{{AZURE_RESOURCE_GROUP}}/${RG}/g"  \
    -e "s/{{AZURE_API_MANAGEMENT}}/${apimName}/g"  \
    -e "s/{{AZURE_APIM_GATEWAY}}/${gateway}/g"  \
    -e "s/{{DOCKER_IMAGE}}/${container}/g"  \
rotation-cronjob.yaml.template >> rotation-cronjob.yaml

cat >> ./rotation-cronjob.yaml<< EOF
---
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentity
metadata:
  name: $msiUserName
spec:
  type: 0
  resourceID: ${resourceId}
  clientID: ${msiClientId}
EOF

cat >> ./rotation-cronjob.yaml<< EOF
---
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentityBinding
metadata:
  name: ${msiUserName}-binding
spec:
  azureIdentity: $msiUserName
  selector: $msiUserName
EOF

echo Please inspect and then apply - kubectl apply -f ./rotation-cronjob.yaml