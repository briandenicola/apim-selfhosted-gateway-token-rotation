# Azure API Management Self-Hosted Gateway Token Rotation
## Overview
Azure API Management recently introduced a new featured called self-hosted gateway. This allows you to put the APIM gateway proxy (the actual resource that accepts incoming requests) closer to your actual APIs.  This gateway can be hosted in any Docker or Kubernetes cluster anywhere you want.  The gateway authenticates back to APIM via a token that expires at most every 30 days. So this token needs to be cycled. 

How follows in this repo is a demostration on how you can use a Kubernetes cronjob to update the token and cycle the gateway's keys.  The token will cycle on the 1st and 15th of every month and be valid for 29 days. 

## Variables and Environment Information 
* In this example:
    * APIM name - bjdapim002
    * Gateway name - demo
    * Hostname - api.bjd.demo 
* Certificates were generated using Let's Encrypt
    * acme.sh --issue -d *.bjd.demo --yes-I-know-dns-manual-mode-enough-go-ahead-please --dns 
* Traefik is the Kuberenetes Ingress Controller
    * helm upgrade traefik stable/traefik --set ssl.insecureSkipVerify=true --set ssl.enabled=true --set rbac.enabled=true
* Azure Pod Identitiy was deployed to the cluster 
    * helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
    * helm install aad-pod-identity aad-pod-identity/aad-pod-identity

## Setup
1. Create an APIM Gateway on Existing APIM Deployment
    * This [code snippet](https://gist.github.com/briandenicola/3f5cce6eb6787ee4fde621c32a1ffc4b) shows how to create a self-hosted gateway using an ARM template.

2. Create Initial Token for APIM Gateway 
_Use Portal or the steps below_
    * apimName={name of APIM}
    * gateway={name of APIM Gateway}
    * RG={APIM's Resource Group}
    * id=`az account show -o tsv --query id`
    * uri="https://management.azure.com/subscriptions/${id}/resourceGroups/${RG}/providers/Microsoft.ApiManagement/service/${apimName}/gateways/${gateway}"
    * expiry=`date -d "1970-01-01 00:00:$(date +"%s + 2505600" | xargs expr)" +"%Y-%m-%dT%H:%m:00Z"`
    * token=`az rest --method POST --uri "${uri}/generateToken/?api-version=2019-12-01" --body "{ \"expiry\": \"${expiry}\", \"keyType\": \"primary\" }" | jq .value | tr -d "\"" `
    * kubectl create secret generic ${gateway}-token --from-literal=value="GatewayKey ${token}" --type=Opaque

3. Deploy SSL Certificate and Ingress Controller Configuration 
    * ./create_tls_secret.sh 
    * kubectl apply -f ./azure-apim-self-hosted-gateway.yaml

4. Deploy APIM Gateway on Kubernetes
    * kubectl apply -f ./azure-apim-traefik-ingress.yaml

5. Build Container for Kubernetes Cronjob
_Replace bjd145 with your Docker Hub repo. config.sh will also need to be updated_
    * docker build -t bjd145/apimrotate:1.4 .
    * docker push bjd145/apimrotate:1.4

6. Run Configuration Script
    * ./config.sh -s APP02_Subscription -n bjdapim002 -g APIM_RG --gateway demo -l centralus

7. Apply Cronjob Yaml configuration 
_Schedule to run cronjob every 15 days_
    * kubectl -f ./rotation-cronjob.yaml

## TBD
- [X] A better way to switch between 'primary' and 'secondary' keys for token generation.  