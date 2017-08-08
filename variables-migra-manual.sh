export CONFIGURATION="fullstack"
export TARGET="open-release/eucalyptus.1rc2"
#export TARGET="named-release/dogwood.rc"
# export TARGET="open-release/eucalyptus/latest"
# export TARGET="master"
export INTERACTIVE=true
export OPENEDX_ROOT="/edx"
export APPUSER=www-data
APPUSER=edxapp
if [[ $CONFIGURATION == fullstack ]] ; then
  APPUSER=www-data
fi

# Setear el server_vars como corresponde para no perder ningún settings de configuración.
if [[ -f ${OPENEDX_ROOT}/app/edx_ansible/server-vars.yml ]]; then
  SERVER_VARS="--extra-vars=\"@${OPENEDX_ROOT}/app/edx_ansible/server-vars.yml\""
fi
