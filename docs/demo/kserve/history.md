# ODH with OSSM enabled

## Prerequisite
- Openshift Cluster 
  - This doc is written based on ROSA cluster
- CLI tools
  - oc cli

- Installed operators
  - [Kiali](https://docs.openshift.com/container-platform/4.13/service_mesh/v2x/installing-ossm.html)
  - [Red Hat OpenShift distributed tracing platform](https://docs.openshift.com/container-platform/4.13/service_mesh/v2x/installing-ossm.html)
  - [Red Hat OpenShift Service Mesh](https://docs.openshift.com/container-platform/4.13/service_mesh/v2x/installing-ossm.html)
    - ServiceMeshControlPlan
  - [Openshift Serverless](https://docs.openshift.com/serverless/1.29/install/install-serverless-operator.html)
  - [OpenDataHub](https://opendatahub.io/docs/quick-installation/)
  - [Authorino](https://github.com/Kuadrant/authorino-operator)

## Reference
- https://github.com/maistra/odh-manifests/blob/ossm_plugin_templates/enabling-ossm.md
- https://github.com/ReToCode/knative-kserve#installation-with-istio--mesh
- https://knative.dev/docs/install/operator/knative-with-operators/#create-the-knative-serving-custom-resource
 
## Setup pre-requisite
~~~
git clone https://github.com/ReToCode/knative-kserve

# Install Service Mesh operators
oc apply -f knative-kserve/service-mesh/operators.yaml
sleep 30
oc wait --for=condition=ready pod -l name=istio-operator -n openshift-operators --timeout=300s
oc wait --for=condition=ready pod -l name=jaeger-operator -n openshift-operators --timeout=300s
oc wait --for=condition=ready pod -l name=kiali-operator -n openshift-operators --timeout=300s

# Create an istio instance
oc create ns istio-system
oc apply -f custom-manifests/service-mesh/smcp.yaml
sleep 15
oc wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s
oc wait --for=condition=ready pod -l app=prometheus -n istio-system --timeout=300s
oc wait --for=condition=ready pod -l app=istio-ingressgateway -n istio-system --timeout=300s
oc wait --for=condition=ready pod -l app=istio-egressgateway -n istio-system --timeout=300s
oc wait --for=condition=ready pod -l app=jaeger -n istio-system --timeout=300s

# Install Authorino/Opendatahub operator
oc create -f custom-manifests/authorino/operators.yaml  
operator-sdk run bundle quay.io/maistra-dev/opendatahub-operator-bundle:v0.0.4 --namespace openshift-operators --timeout 5m0s
#operator-sdk run bundle quay.io/cgarriso/opendatahub-operator-bundle:dev-0.0.2 --namespace openshift-operators --timeout 5m0s
sleep 15
oc wait --for=condition=ready pod -l control-plane=authorino-operator -n openshift-operators --timeout=300s
oc wait --for=condition=ready pod -l control-plane=controller-manager -n openshift-operators --timeout=300s
 
# Deploy opendatahub ossm
oc create ns auth-provider
oc create -f custom-manifests/opendatahub/kfdef-plugins.yaml
oc wait --for condition=available kfdef --all --timeout 360s -n opendatahub
oc wait --for condition=ready pod --all --timeout 360s opendatahub
oc get pods -n opendatahub -o yaml | grep -q istio-proxy || oc get deployments -o name -n opendatahub | xargs -I {} oc rollout restart {} -n opendatahub

# Workaround
export TOKEN=sha256~x07wD1VrTUaFGam8FTfVcGFfEQlsFTgOH3SCvHV2mJs
result=$(oc create -o jsonpath='{.status.audiences[0]}' -f -<<EOF
apiVersion: authentication.k8s.io/v1
kind: TokenReview
spec:
  token: "$TOKEN"
  audiences: []
EOF
)

kubectl patch authconfig odh-dashboard-protection -n opendatahub --type='json' -p="[{'op': 'replace', 'path': '/spec/identity/0/kubernetes/audiences', 'value': ['${result}']}]"

oc adm policy add-cluster-role-to-user cluster-admin joe

export ODH_ROUTE=$(oc get route --all-namespaces -l maistra.io/gateway-namespace=opendatahub -o yaml | yq '.items[].spec.host')
xdg-open https://$ODH_ROUTE > /dev/null 2>&1 &    


# kserve/knative
oc create ns kserve
oc create ns kserve-demo
oc create ns knative-serving
oc apply -f custom-manifests/service-mesh/smmr.yaml
oc apply -f custom-manifests/service-mesh/peer-authentication.yaml
oc apply -f knative-kserve/service-mesh/peer-authentication.yaml # we need this because of https://access.redhat.com/documentation/en-us/openshift_container_platform/4.12/html/serverless/serving#serverless-domain-mapping-custom-tls-cert_domain-mapping-custom-tls-cert

oc apply -f knative-kserve/serverless/operator.yaml
sleep 30
oc wait --for=condition=ready pod -l name=knative-openshift -n openshift-serverless --timeout=300s
oc wait --for=condition=ready pod -l name=knative-openshift-ingress -n openshift-serverless --timeout=300s
oc wait --for=condition=ready pod -l name=knative-operator -n openshift-serverless --timeout=300s

# Create a Knative Serving installation
oc apply -f knative-kserve/serverless/knativeserving-istio.yaml
sleep 15
oc wait --for=condition=ready pod -l app=controller -n knative-serving --timeout=300s
oc wait --for=condition=ready pod -l app=net-istio-controller -n knative-serving --timeout=300s
oc wait --for=condition=ready pod -l app=net-istio-webhook -n knative-serving --timeout=300s
oc wait --for=condition=ready pod -l app=autoscaler-hpa -n knative-serving --timeout=300s
oc wait --for=condition=ready pod -l app=domain-mapping -n knative-serving --timeout=300s
oc wait --for=condition=ready pod -l app=webhook -n knative-serving --timeout=300s
oc wait --for=condition=ready pod -l app=activator -n knative-serving --timeout=300s
oc wait --for=condition=ready pod -l app=autoscaler -n knative-serving --timeout=300s

# Create the Knative gateways

git clone git@github.com:Jooho/ansible-cheat-sheet.git
cd ansible-cheat-sheet/ansible-playbooks/ansible-playbook-generate-self-signed-cert/

export COMMON_NAME=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}'|sed 's/apps.//')
ansible-playbook ./playbook.yaml -e use_intermediate_cert=false -e cert_commonName=*.$COMMON_NAME -e cert_base_dir=/home/jooho/cert_base -b  -vvvv

openssl x509 -in /home/jooho/cert_base/wild.$COMMON_NAME/wild.$COMMON_NAME.cert.pem -text

oc create secret tls wildcard-certs --cert=/home/jooho/cert_base/wild.$COMMON_NAME/wild.$COMMON_NAME.cert.pem --key=/home/jooho/cert_base/wild.$COMMON_NAME/wild.$COMMON_NAME.key.pem -n istio-system
oc apply -f custom-manifests/serverless/gateways.yaml


# KServe Kfdef
git clone --branch manifests git@github.com:Jooho/kserve.git
rm -rf  custom-manifests/opendatahub/.cache  custom-manifests/opendatahub/kustomize /tmp/odh-manifests.gzip
tar czvf /tmp/odh-manifests.gzip kserve/opendatahub/odh-manifests
kfctl build -V -f custom-manifests/opendatahub/kfdef-kserve.yaml -d | oc create -n kserve -f -

# KServe Kustomize
#kustomize build kserve/opendatahub/odh-manifests/kserve/base/

# Minio Deploy
ACCESS_KEY_ID=THEACCESSKEY
SECRET_ACCESS_KEY=$(openssl rand -hex 32)

oc new-project minio
sed "s/<accesskey>/$ACCESS_KEY_ID/g"  ./minio.yaml | sed "s+<secretkey>+$SECRET_ACCESS_KEY+g" | tee ./minio-current.yaml | oc -n minio apply -f -
sed "s/<accesskey>/$ACCESS_KEY_ID/g" ./minio-secret.yaml | sed "s+<secretkey>+$SECRET_ACCESS_KEY+g" | tee ./minio-secret-current.yaml | oc -n minio apply -f - 


# TGIS
oc project kserve-demo
oc apply -f ./caikit-servingruntime.yaml

# Deploy model
oc apply -f ./minio-secret-current.yaml 
oc create -f serviceaccount-minio.yaml
oc adm policy add-scc-to-user anyuid -z sa -n kserve-demo


oc apply -f ./caikit-isvc.yaml










# -insecure because the cert is self-signed in this demo environment
# The header mm-model-id is the name of the model loaded in caikit, named the same as the directory the caikit model resides in

grpcurl -insecure -d '{"text": "At what temperature does liquid Nitrogen boil?"}' -H "mm-model-id: bloom-560m" caikit-example-isvc-predictor-kserve-demo.apps.jlee-test.ugub.p1.openshiftapps.com:443 caikit.runtime.Nlp.NlpService/TextGenerationTaskPredict




# Bootstrap process(optional)
yum -y install git git-lfs
git lfs install
git clone https://huggingface.co/bigscience/bloom-560m

python3 -m virtualenv venv
source venv/bin/activate


git clone https://github.com/Xaenalt/caikit-nlp
python3.9 -m pip install ./caikit-nlp/   (python 3.11 can not compile)  <pip install ./caikit-nlp>
cp ../convert.py .
./convert.py --model-path ./bloom-560m/ --model-save-path ./bloom-560m-caikit

~~~


make docker-build
docker tag kserve-controller:latest quay.io/jooholee/kserve-controller:latest
docker push quay.io/jooholee/kserve-controller:latest





 
rm -rf  kserve/opendatahub/kfdef/.cache  kserve/opendatahub/kfdef/kustomize /tmp/odh-manifests.gzip 
tar czvf /tmp/odh-manifests.gzip kserve/opendatahub/odh-manifests
kfctl build -V -f kserve/opendatahub/kfdef/kfdef-upstream.yaml -d | oc create -f -
kfctl build -V -f kserve/opendatahub/kfdef/kfdef-upstream.yaml -d | oc delete -f -
kfctl build -V -f kserve/opendatahub/kfdef/kfdef-upstream.yaml -d >/tmp/a.yaml
 oc edit crd inferenceservices.serving.kserve.io






`OAuth flow failed`
~~~
kubectl logs $(kubectl get pod -l app=oauth-openshift -n openshift-authentication -o name|head -n1) -n openshift-authentication  

kubectl get oauthclient.oauth.openshift.io opendatahub-oauth2-client
kubectl exec $(kubectl get pods -n istio-system -l app=istio-ingressgateway  -o jsonpath='{.items[*].metadata.name}') -n istio-system -c istio-proxy -- cat /etc/istio/opendatahub-oauth2-tokens/token-secret.yaml
kubectl get secret opendatahub-oauth2-tokens -n istio-system -o yaml

kubectl rollout restart deployment -n istio-system istio-ingressgateway 

oc create -o yaml -f -<<EOF
apiVersion: authentication.k8s.io/v1
kind: TokenReview
spec:
  token: "$TOKEN"
  audiences: []
EOF
~~~
