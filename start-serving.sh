#!/bin/sh

TGIS_CONFIG_TEMPLATE='/caikit/config/caikit-tgis.template.yml'
TGIS_CONFIG_FILE='/caikit/config/caikit-tgis.yml'

sed "s/TGIS_HOSTNAME/${TGIS_HOSTNAME}/" "${TGIS_CONFIG_TEMPLATE}" > "${TGIS_CONFIG_FILE}"
export CONFIG_FILES="${TGIS_CONFIG_FILE}

exec python3 -m caikit.runtime.grpc_server