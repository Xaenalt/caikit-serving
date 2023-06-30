# KServe with Caikit + TGIS runtime

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

# Reference
- https://github.com/maistra/odh-manifests/blob/ossm_plugin_templates/enabling-ossm.md
- https://github.com/ReToCode/knative-kserve#installation-with-istio--mesh
- https://knative.dev/docs/install/operator/knative-with-operators/#create-the-knative-serving-custom-resource
- 

# Steps
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

# kserve/knative
oc create ns kserve
oc create ns kserve-demo
oc create ns knative-serving
oc apply -f knative-kserve/service-mesh/smmr.yaml
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

# Generate wildcard cert for a gateway.
export BASE_DIR=/tmp/certs
export DOMAIN_NAME=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' | awk -F'.' '{print $(NF-1)"."$NF}')
export COMMON_NAME=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}'|sed 's/apps.//')

mkdir ${BASE_DIR}
## Playbook way
#git clone git@github.com:Jooho/ansible-cheat-sheet.git
#cd ansible-cheat-sheet/ansible-playbooks/ansible-playbook-generate-self-signed-cert/

#ansible-playbook ./playbook.yaml -e use_intermediate_cert=false -e cert_commonName=*.$COMMON_NAME -e cert_base_dir=${BASE_DIR} -b  -vvvv
#cp ${BASE_DIR}/wild.$COMMON_NAME/wild.$COMMON_NAME.cert.pem ${BASE_DIR}/wildcard.crt
#cp ${BASE_DIR}/wild.$COMMON_NAME/wild.$COMMON_NAME.key.pem ${BASE_DIR}/wildcard.key

## openssl
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 \
-subj "/O=Example Inc./CN=${DOMAIN_NAME}" \
-keyout $BASE_DIR/root.key \
-out $BASE_DIR/root.crt

openssl req -nodes -newkey rsa:2048 \
-subj "/CN=*.${COMMON_NAME}/O=Example Inc." \
-keyout $BASE_DIR/wildcard.key \
-out $BASE_DIR/wildcard.csr

openssl x509 -req -days 365 -set_serial 0 \
-CA $BASE_DIR/root.crt \
-CAkey $BASE_DIR/root.key \
-in $BASE_DIR/wildcard.csr \
-out $BASE_DIR/wildcard.crt

openssl x509 -in ${BASE_DIR}/wildcard.crt -text

# Create the Knative gateways
oc create secret tls wildcard-certs --cert=${BASE_DIR}/wildcard.crt --key=${BASE_DIR}/wildcard.key -n istio-system
oc apply -f custom-manifests/serverless/gateways.yaml

# KServe Kfdef
git clone --branch manifests git@github.com:Jooho/kserve.git
rm -rf  custom-manifests/opendatahub/.cache  custom-manifests/opendatahub/kustomize /tmp/odh-manifests.gzip
tar czvf /tmp/odh-manifests.gzip kserve/opendatahub/odh-manifests
kfctl build -V -f custom-manifests/opendatahub/kfdef-kserve.yaml -d | oc create -n kserve -f -

# Minio Deploy
ACCESS_KEY_ID=THEACCESSKEY
SECRET_ACCESS_KEY=$(openssl rand -hex 32)

oc new-project minio
sed "s/<accesskey>/$ACCESS_KEY_ID/g"  ./custom-manifests/minio/minio.yaml | sed "s+<secretkey>+$SECRET_ACCESS_KEY+g" | tee ./minio-current.yaml | oc -n minio apply -f -
sed "s/<accesskey>/$ACCESS_KEY_ID/g" ./custom-manifests/minio/minio-secret.yaml | sed "s+<secretkey>+$SECRET_ACCESS_KEY+g" | tee ./minio-secret-current.yaml | oc -n minio apply -f - 

# Create Caikit Serving runtime
oc project kserve-demo
oc apply -f ./custom-manifests/caikit/caikit-servingruntime.yaml

# Deploy model
oc apply -f ./minio-secret-current.yaml 
oc create -f ./custom-manifests/minio/serviceaccount-minio.yaml
oc adm policy add-scc-to-user anyuid -z sa -n kserve-demo

oc apply -f ./custom-manifests/caikit/caikit-isvc.yaml -n kserve-demo

# Test
export KSVC_HOSTNAME=$(oc get ksvc caikit-example-isvc-predictor -o jsonpath='{.status.url}' | cut -d'/' -f3)
grpcurl -insecure -d '{"text": "At what temperature does liquid Nitrogen boil?"}' -H "mm-model-id: bloom-560m" ${KSVC_HOSTNAME}:443 caikit.runtime.Nlp.NlpService/TextGenerationTaskPredict
~~~
