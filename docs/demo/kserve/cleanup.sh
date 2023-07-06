#/bin/bash

directories="servicemesh serverless authorino"
# directories="servicemesh serverless authorino opendatahub"  # until this pr merged (https://github.com/bartoszmajsak/opendatahub-operator/tree/kf_ossm_plugin/pkg/kfapp/ossm)


oc delete smcp basic -n istio-system --force --grace-period=0


for dir in ${directories};
do
  echo "Delete ${dir} operator"
  oc delete -f custom-manifests/${dir}/operators.yaml   
done

# opendatahub 
operator-sdk cleanup opendatahub-operator --namespace openshift-operators --timeout 5m0s

oc project openshift-operators

for csv in kiali jaeger servicemesh authorino
do
  oc get csv |grep $csv |awk '{print $1}' | xargs oc delete csv  
done






# oc delete MutatingWebhookConfiguration istiod-basic-istio-system
# oc delete MutatingWebhookConfiguration openshift-operators.servicemesh-resources.maistra.io
# oc delete validatingWebhookConfiguration openshift-operators.servicemesh-resources.maistra.io

# for i in $( oc get crd|grep istio |awk '{print $1}')
# do
#   oc delete crd $i
# done


#ossm

# KFDEF=${KFDEF:-odh-mesh}

# kubectl delete kfdef ${KFDEF} -n opendatahub
# kubectl delete oauthclient.oauth.openshift.io opendatahub-oauth2-client
# echo "opendatahub auth-provider" | xargs -n 1 kubectl delete ns
# echo "opendatahub auth-provider" | xargs -n 1 kubectl create ns
