FROM quay.io/spryor/tgis

RUN yum -y install git && \
    git clone https://github.com/caikit/caikit-nlp && \
    pip install --no-cache-dir -y ./caikit-nlp && \
    mkdir -p /opt/models && \
    mkdir -p /caikit/config

COPY caikit-tgis-local.yml /caikit/config

ENV RUNTIME_LIBRARY='caikit_nlp' \
    RUNTIME_LOCAL_MODELS_DIR='/opt/models' \
    CONFIG_FILES='/caikit/config/caikit-tgis-local.yml'

CMD [ "python3 -m caikit.runtime.grpc_server" ]