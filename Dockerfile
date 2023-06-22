FROM quay.io/spryor/tgis:latest

ARG CAIKIT_NLP_REPO=https://github.com/caikit/caikit-nlp

RUN yum -y install git && \
    git clone ${CAIKIT_NLP_REPO} && \
    pip install --no-cache-dir ./caikit-nlp && \
    mkdir -p /opt/models && \
    mkdir -p /caikit/config

COPY caikit-tgis.template.yml /caikit/config
COPY start-serving.sh /

ENV RUNTIME_LIBRARY='caikit_nlp' \
    RUNTIME_LOCAL_MODELS_DIR='/opt/models'

CMD [ "start-serving.sh" ]