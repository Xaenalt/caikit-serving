#!/bin/sh

sed "s/TGIS_HOSTNAME/${TGIS_HOSTNAME}/" /caikit/config/caikit-tgis.template.yml > /caikit/config/caikit-tgis.yml
export CONFIG_FILES=/caikit/config/caikit-tgis.yml

exec python3 -m caikit.runtime.grpc_server