#!/bin/bash

# Generic functions are in utilities-bash.sh

echo "BASH VERSION: $BASH_VERSION $POSIXLY_CORRECT"
declare -A CONFIG_TO_ENV=(
  ["common.name"]="EULA_NAME"
  ["common.email"]="EULA_EMAIL"
  ["common.companyName"]="EULA_COMPANY"
  ["secrets.adminPassword"]="ADMIN_PASSWORD"
  ["secrets.adminUser"]="ADMIN_USERNAME"
  ["db.waitImage"]="DATABASE_WAIT_IMAGE"
  ["db.host"]="DATABASE_HOSTNAME"
  ["db.port"]="DATABASE_PORT"
  ["db.name"]="DATABASE_NAME"
  ["db.username"]="DATABASE_USERNAME"
  ["db.password"]="DATABASE_PASSWORD"
  ["laser.dotnetExecutor.image"]="DOTNET_EXECUTOR_IMAGE"
  ["elastic.image"]="ELASTICSEARCH_IMAGE"
  ["elastic.initContainer.image"]="ELASTICSEARCH_INIT_IMAGE"
  ["laser.golangExecutor.image"]="GOLANG_EXECUTOR_IMAGE"
  ["gatewayManager.image"]="GWM_EXECUTOR_IMAGE"
  ["laser.jsExecutor.image"]="JS_EXECUTOR_IMAGE"
  ["laser.jvmExecutor.image"]="JVM_EXECUTOR_IMAGE"
  ["kong.image"]="KONG_IMAGE"
  ["api.gateway.protocol"]="KONG_SERVICE_PROTOCOL"
  ["api.gateway.host"]="KONG_SERVICE_HOST"
  ["api.gateway.port"]="KONG_SERVICE_PORT"
  ["api.gateway.nodePort"]="KONG_NODEPORT"
  ["api.gateway.staticIP"]="KONG_STATIC_IP"
  ["api.admin.protocol"]="KONG_ADMIN_PROTOCOL"
  ["api.admin.port"]="KONG_ADMIN_PORT"
  ["api.admin.nodePort"]="KONG_ADMIN_NODEPORT"
  ["logging.image"]="LOGGING_IMAGE"
  ["logging.protocol"]="LOGGING_PROTOCOL"
  ["logging.port"]="LOGGING_PORT"
  ["logging.ingress.host"]="LOGGING_SERVICE_HOST"
  ["meta.image"]="META_IMAGE"
  ["meta.port"]="META_PORT"
  ["meta.protocol"]="META_PROTOCOL"
  ["laser.nodejsExecutor.image"]="NODEJS_EXECUTOR_IMAGE"
  ["policy.image"]="POLICY_IMAGE"
  ["laser.pythonExecutor.image"]="PYTHON_EXECUTOR_IMAGE"
  ["rabbit.host"]="RABBIT_HOST"
  ["rabbit.httpPort"]="RABBIT_HTTP_PORT"
  ["rabbit.image"]="RABBIT_IMAGE"
  ["rabbit.port"]="RABBIT_PORT"
  ["laser.rubyExecutor.image"]="RUBY_EXECUTOR_IMAGE"
  ["security.image"]="SECURITY_IMAGE"
  ["security.port"]="SECURITY_PORT"
  ["security.protocol"]="SECURITY_PROTOCOL"
  ["ui.image"]="UI_IMAGE"
  ["ui.nodePort"]="UI_NODEPORT"
  ["ui.ingress.protocol"]="UI_PROTOCOL"
  ["ui.ingress.host"]="UI_HOST"
  ["ui.ingress.port"]="UI_PORT"
  ["ui.ingress.staticIP"]="UI_STATIC_IP"
)

random() { cat /dev/urandom | env LC_CTYPE=C tr -dc $1 | head -c $2; echo; }

randompw() {
  # Generate a random password (16 characters) that starts with an alpha character
  echo `random [:alpha:] 1``random [:alnum:] 15`
}

getsalt_installer_load_configmap() {

  map_env_vars_for_configyaml
  # The deployer ConfigMap will only exist for a GCP Marketplace install
  if [ -z $MARKETPLACE_IMSTALL ] && [ ${K8S_PROVIDER:=default} == "gke" ]; then
    convert_configmap_to_env_variables "${RELEASE_NAME:=gestalt}-deployer-config"
  fi

  check_for_required_variables GESTALT_INSTALL_LOGGING_LVL
  logging_lvl=${GESTALT_INSTALL_LOGGING_LVL:=debug}

  log_set_logging_lvl
  logging_lvl_validate 
  # print_env_variables #will print only if debug
}

map_env_vars_for_configyaml() {
  check_for_required_variables gestalt_config
  # Convert Yaml config to JSON for easier parsing
  echo "Creating $gestalt_config from $gestalt_config_yaml..."
  yaml2json ${gestalt_config_yaml} > ${gestalt_config}
  validate_json ${gestalt_config}
  convert_json_to_env_variables ${gestalt_config}
}

get_configmap_data() {
  echo $( kubectl -n ${RELEASE_NAMESPACE} get configmap ${1} -o json | jq -c '.data' )
}

mask_db_fields_if_provisioning_internal_db() {
  echo "$1" | jq -r 'del(.["db.host","db.port","db.name","db.username","db.password"])'
}

get_db_password_from_secret() {
  kubectl get secrets -n ${RELEASE_NAMESPACE} "${RELEASE_NAME}-secrets" -ojsonpath='{.data.db-password}' | base64 -d
}

# We only want to create a LoadBalancer service if the static IP is not null
# and is numeric (ie. 10.0.10.5) rather than a named IP reservation...
should_create_loadbalancer_service_for_ip() {
  local STATIC_IP=${1:-""}
  if [[ "$STATIC_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    true
  else
    false
  fi
}

map_env_vars_for_configmap() {
  local JSON_DATA=$1
  [ -z "${JSON_DATA}" ] && return
  local VAR_NAME
  local VAR_VALUE
  local PRETTY_JSON=$( echo "${JSON_DATA}" | jq -r -S )
  echo "ConfigMap JSON Data: $PRETTY_JSON"
  echo "CONFIG_TO_ENV has ${#CONFIG_TO_ENV[@]} entries"

  local PROVISION_DB=$( echo "$JSON_DATA" | jq -r '.["postgresql.provisionInstance"]' )
  shopt -s nocasematch
  if [[ "$PROVISION_DB" =~ ^true ]]; then
    JSON_DATA=$( mask_db_fields_if_provisioning_internal_db "${JSON_DATA}" )
    local MASKED_JSON=$( echo "${JSON_DATA}" | jq -r -S )
    echo "Masked JSON Data: $MASKED_JSON"
    DATABASE_PASSWORD=$( get_db_password_from_secret )
    echo "Obtained db-password from '${RELEASE_NAME}-secrets' : '$DATABASE_PASSWORD'"
    export PROVISION_INTERNAL_DATABASE="Yes"
  else
    export PROVISION_INTERNAL_DATABASE="No"
  fi
  shopt -u nocasematch

  local KEY_NAME
  for KEY_NAME in ${CONFIG_TO_ENV[@]}; do
    echo "$KEY_NAME / ${CONFIG_TO_ENV[$KEY_NAME]}"
  done
  # Feed the JSON through jq to get just the keys, strip all quote chars, and loop through each key name
  for KEY in $( echo $JSON_DATA | jq 'keys | @sh' | sed "s/'//g" | xargs echo ); do
    # Get the name of the ENV var to map for the JSON key or the key itself if there is no key to env var map
    if [ ${#CONFIG_TO_ENV[@]} -eq 0 ]; then
      VAR_NAME=""
    else
      VAR_NAME="${CONFIG_TO_ENV[$KEY]}"
    fi
    if [ -z ${VAR_NAME:+x} ]; then
      echo "No ENV var mapped for ConfigMap key '${KEY}'"
    else
      echo "Mapping ENV var '${VAR_NAME}' for ConfigMap key '${KEY}'"
      # Get the value for the key from the JSON via jq, strip the quote chars again, and make that the value of the ENV var
      VAR_VALUE=$( echo $JSON_DATA | jq ".[\"$KEY\"]" | sed 's/"//g')
      if [ -z "${VAR_VALUE}" ]; then
        echo "JSON Data for ConfigMap key '${KEY}' is blank or null!"
      else
        echo "Setting ENV var '$VAR_NAME' to '$VAR_VALUE'"
        export $VAR_NAME="${VAR_VALUE}"
      fi
    fi
  done

  should_create_loadbalancer_service_for_ip $UI_STATIC_IP && UI_SERVICE_TYPE="LoadBalancer"
  should_create_loadbalancer_service_for_ip $KONG_STATIC_IP && KONG_SERVICE_TYPE="LoadBalancer"

  echo "postgres connection info ${DATABASE_USERNAME}@${DATABASE_HOSTNAME}:${DATABASE_PORT}/${DATABASE_NAME}"
}

# We only want to create a LoadBalancer service if the static IP is not null
# and is numeric (ie. 10.0.10.5) rather than a named IP reservation...
should_create_load_balancer_service_for_ip() {
  local STATIC_IP=${1:-""}
  if [[ "$STATIC_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    true
  else
    false
  fi
}

convert_configmap_to_env_variables() {
  local CONFIGMAP=$1
  echo "Obtaining ConfigMap data for $CONFIGMAP"
  local JSON_DATA=$( get_configmap_data $CONFIGMAP )
  local EXIT_CODE=$?
  echo "Mapping ConfigMap data for $CONFIGMAP"
  # If the ConfigMap was found, map the config values to env vars - ignore if not found
  [ $EXIT_CODE -eq 0 ] && map_env_vars_for_configmap "$JSON_DATA"
  local EXIT_CODE2=$?
  if [ $EXIT_CODE2 -eq 0 ]; then
    echo "SUCCESS mapping ConfigMap data for $CONFIGMAP"
  else
    echo "FAIL mapping ConfigMap data for $CONFIGMAP"
  fi
}

getsalt_installer_setcheck_variables() {

  if [ -z ${MARKETPLACE_INSTALL} ]; then

    # Non-marketplace installs

    if [ -z $LOGGING_SERVICE_HOST ]; then
      check_for_required_variables \
        GESTALT_URL

      export LOGGING_SERVICE_HOST=$(echo $GESTALT_URL | awk -F/ '{print $3}')/log
      export LOGGING_SERVICE_PROTOCOL=$(echo $GESTALT_URL | awk -F: '{print $1}')
    fi

    if [ -z $KONG_SERVICE_HOST ]; then
      check_for_required_variables \
        KONG_URL

      export KONG_SERVICE_HOST=$(echo $KONG_URL | awk -F/ '{print $3}')
      export KONG_SERVICE_PROTOCOL=$(echo $KONG_URL | awk -F: '{print $1}')
    fi
  else

    if [ -z "$GESTALT_URL" ]; then
      if [[ "$UI_PROTOCOL" == "http" && "$UI_PORT" == "80" ]]; then
        GESTALT_URL="$UI_PROTOCOL://$UI_HOST"
      elif [[ "$UI_PROTOCOL" == "https" && "$UI_PORT" == "443" ]]; then
        GESTALT_URL="$UI_PROTOCOL://$UI_HOST"
      else
        GESTALT_URL="$UI_PROTOCOL://$UI_HOST:$UI_PORT"
      fi
    fi

    if [ -z "$KONG_URL" ]; then
      if [[ "$KONG_SERVICE_PROTOCOL" == "http" && "$KONG_SERVICE_PORT" == "80" ]]; then
        KONG_URL="$KONG_SERVICE_PROTOCOL://$KONG_SERVICE_HOST"
      elif [[ "$KONG_SERVICE_PROTOCOL" == "https" && "$KONG_SERVICE_PORT" == "443" ]]; then
        KONG_URL="$KONG_SERVICE_PROTOCOL://$KONG_SERVICE_HOST"
      else
        KONG_URL="$KONG_SERVICE_PROTOCOL://$KONG_SERVICE_HOST:$KONG_SERVICE_PORT"
      fi
    fi

  fi

  if [ "$PROVISION_INTERNAL_DATABASE" == "Yes" ]; then
    export DATABASE_HOSTNAME="${RELEASE_NAME}-postgresql.${RELEASE_NAMESPACE}.svc.cluster.local"
  fi

  # Check all variables in one call
  check_for_required_variables \
    ADMIN_PASSWORD \
    ADMIN_USERNAME \
    DATABASE_HOSTNAME \
    DATABASE_PORT \
    DATABASE_NAME \
    DATABASE_PASSWORD \
    DATABASE_USERNAME \
    DOTNET_EXECUTOR_IMAGE \
    ELASTICSEARCH_IMAGE \
    ELASTICSEARCH_INIT_IMAGE \
    GOLANG_EXECUTOR_IMAGE \
    GWM_EXECUTOR_IMAGE \
    JS_EXECUTOR_IMAGE \
    JVM_EXECUTOR_IMAGE \
    KONG_IMAGE \
    KONG_SERVICE_HOST \
    KONG_SERVICE_PROTOCOL \
    LOGGING_IMAGE \
    META_IMAGE \
    META_PORT \
    META_PROTOCOL \
    NODEJS_EXECUTOR_IMAGE \
    POLICY_IMAGE \
    PYTHON_EXECUTOR_IMAGE \
    RABBIT_HTTP_PORT \
    RABBIT_IMAGE \
    RABBIT_PORT \
    REDIS_IMAGE \
    REDIS_PORT \
    RUBY_EXECUTOR_IMAGE \
    SECURITY_IMAGE \
    SECURITY_PORT \
    SECURITY_PROTOCOL \
    UI_IMAGE \
    UI_PORT \
    UI_PROTOCOL

  if [ ! -z ${MARKETPLACE_INSTALL} ]; then
    check_for_required_variables \
        GCP_TRACKING_SERVICE_IMAGE \
        GCP_UBB_IMAGE \
        UBB_PORT
  fi

  # Compute in-cluster hostnames
  export SECURITY_HOSTNAME=`get_internal_hostname security`
  export META_HOSTNAME=`get_internal_hostname meta`
  export UI_HOSTNAME=`get_internal_hostname ui`
  export RABBIT_HOSTNAME=`get_internal_hostname rabbit`
  export REDIS_HOSTNAME=`get_internal_hostname redis`
  export ELASTICSEARCH_HOSTNAME=`get_internal_hostname elastic`
  export KONG_ADMIN_HOSTNAME="kng.${RELEASE_NAMESPACE}.svc.cluster.local"

  export SECURITY_URL="$SECURITY_PROTOCOL://$SECURITY_HOSTNAME:$SECURITY_PORT"
  export META_URL="$META_PROTOCOL://$META_HOSTNAME:$META_PORT"
  export UI_URL="$UI_PROTOCOL://$UI_HOSTNAME:$UI_PORT"

  # Acces points - uris
  check_for_required_variables \
    SECURITY_URL \
    META_URL \
    UI_URL

  check_for_optional_variables \
    META_BOOTSTRAP_PARAMS
}

get_internal_hostname() {
  echo "${RELEASE_NAME}-${1}.${RELEASE_NAMESPACE}.svc.cluster.local"
}

gestalt_installer_generate_helm_config() {

  check_for_required_variables \
    SECURITY_IMAGE \
    SECURITY_PORT \
    SECURITY_PROTOCOL \
    ADMIN_USERNAME \
    ADMIN_PASSWORD \
    POSTGRES_IMAGE \
    DATABASE_HOSTNAME \
    DATABASE_PORT \
    DATABASE_NAME \
    DATABASE_USERNAME \
    DATABASE_PASSWORD \
    RABBIT_IMAGE \
    RABBIT_PORT \
    RABBIT_HTTP_PORT \
    ELASTICSEARCH_IMAGE \
    ELASTICSEARCH_INIT_IMAGE \
    META_IMAGE \
    META_PORT \
    META_PROTOCOL \
    META_NODEPORT \
    KONG_NODEPORT \
    LOGGING_NODEPORT \
    REDIS_IMAGE \
    REDIS_PORT \
    UI_IMAGE \
    UI_NODEPORT \
    GESTALT_URL \
    internal_database_pv_storage_size \
    internal_database_pv_storage_class \
    postgres_persistence_subpath \
    postgres_memory_request \
    postgres_cpu_request

  [ ${K8S_PROVIDER:=default} == 'gke' ] && internal_database_pv_storage_class="standard"

  if [ "$PROVISION_INTERNAL_DATABASE" == "Yes" ]; then
    export PROVISION_POSTGRES_INSTANCE="true"
  else
    export PROVISION_POSTGRES_INSTANCE="false"
  fi

  cat > helm-config.yaml <<EOF
common:
  imagePullPolicy: Always
  releaseVersion: 2.4
  gestaltUrl: "${GESTALT_URL}"

secrets:
  adminUser: "${ADMIN_USERNAME}"
  adminPassword: "${ADMIN_PASSWORD}"
  generatedPassword: "${DATABASE_PASSWORD}"

security:
  exposedServiceType: ${SECURITY_SERVICE_TYPE:-NodePort}
  image: "${SECURITY_IMAGE}"
  port: ${SECURITY_PORT}
  protocol: "${SECURITY_PROTOCOL}"
  databaseName: gestalt-security
  enableReadinessProbe: ${SECURITY_ENABLE_READINESS_PROBE:-"false"}
  enableLivenessProbe: ${SECURITY_ENABLE_LIVENESS_PROBE:-"false"}
  enableIngress: ${SECURITY_ENABLE_INGRESS:="false"}

db:
  waitImage: "${DATABASE_WAIT_IMAGE}"
  host: ${DATABASE_HOSTNAME}
  port: ${DATABASE_PORT}
  name: "${DATABASE_NAME}"
  username: "${DATABASE_USERNAME}"
  password: "${DATABASE_PASSWORD}"

rabbit:
  image: "${RABBIT_IMAGE}"
  port: ${RABBIT_PORT}
  httpPort: ${RABBIT_HTTP_PORT}

elastic:
  image: ${ELASTICSEARCH_IMAGE}
  initContainer:
    image: ${ELASTICSEARCH_INIT_IMAGE}
  restPort: 9200
  transportPort: 9300

meta:
  image: ${META_IMAGE}
  exposedServiceType: ${META_SERVICE_TYPE:-NodePort}
  port: ${META_PORT}
  protocol: ${META_PROTOCOL}
  databaseName: gestalt-meta
  nodePort: ${META_NODEPORT}
  upgradeCheckEnabled: ${META_UPGRADE_CHECK_ENABLED}
  upgradeUrl: ${META_UPGRADE_URL}
  upgradeCheckHours: ${META_UPGRADE_CHECK_HOURS}
  enableReadinessProbe: ${META_ENABLE_READINESS_PROBE:-"true"}
  enableLivenessProbe: ${META_ENABLE_LIVENESS_PROBE:-"true"}
  enableIngress: ${META_ENABLE_INGRESS:="false"}

logging:
  image: ${LOGGING_IMAGE}
  nodePort: ${LOGGING_NODEPORT}
  port: ${LOGGING_PORT}
  protocol: ${LOGGING_PROTOCOL}

ui:
  image: ${UI_IMAGE}
  exposedServiceType: ${UI_SERVICE_TYPE:-NodePort}
  nodePort: ${UI_NODEPORT}
  ingress:
    enableIngress: true
    host: ${UI_HOST}
    port: ${UI_PORT}
    protocol: ${UI_PROTOCOL}
    staticIP: '${UI_STATIC_IP}'

api:
  image: ${KONG_IMAGE}
  exposedServiceType: ${KONG_SERVICE_TYPE:-NodePort}
  gateway:
    enableIngress: true
    host: ${KONG_SERVICE_HOST}
    port: ${KONG_SERVICE_PORT}
    nodePort: ${KONG_NODEPORT}
    protocol: ${KONG_SERVICE_PROTOCOL}
    staticIP: '${KONG_STATIC_IP}'
  admin:
    port: ${KONG_ADMIN_PORT}
    nodePort: ${KONG_ADMIN_NODEPORT}
    protocol: ${KONG_ADMIN_PROTOCOL}

redis:
  image: ${REDIS_IMAGE}
  port: ${REDIS_PORT}

postgresql:
  image: "${POSTGRES_IMAGE}"
  provisionInstance: ${PROVISION_POSTGRES_INSTANCE}
  defaultName: 'postgres'
  defaultUser: 'postgres'
  secretKey:
    database: 'db-database'
    username: 'db-username'
    password: 'db-password'
  enableReadinessProbe: ${POSTGRES_ENABLE_READINESS_PROBE:-"true"}
  enableLivenessProbe: ${POSTGRES_ENABLE_LIVENESS_PROBE:-"true"}
  persistence:
    size: ${internal_database_pv_storage_size}
    storageClass: "${internal_database_pv_storage_class}"
    subPath: "${postgres_persistence_subpath}"
  resources:
    requests:
      memory: ${postgres_memory_request}
      cpu: ${postgres_cpu_request}
  service:
    port: 5432
    type: ClusterIP
EOF

  # Marketplace specific
  if [ -z ${MARKETPLACE_INSTALL+x} ]; then
    cat >> helm-config.yaml <<EOF

ubb:
  image: ${GCP_UBB_IMAGE}
  port: ${UBB_PORT}

trackingService:
  image: ${GCP_TRACKING_SERVICE_IMAGE}
EOF
fi

  echo "START Helm chart values -----------"
  cat helm-config.yaml
  echo "END Helm chart values -----------"
}

http_post() {
  # store the whole response with the status as last line
  if [ -z "$2" ]; then
    HTTP_RESPONSE=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" -X POST -H "Content-Type: application/json" $1)
  else
    HTTP_RESPONSE=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" -X POST -H "Content-Type: application/json" $1 -d $2)
  fi

  HTTP_BODY=$(echo $HTTP_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')
  HTTP_STATUS=$(echo $HTTP_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  unset HTTP_RESPONSE
}

send_marketplace_eula_slack_message() {

  check_for_required_variables \
      UI_IMAGE \
      EULA_NAME \
      EULA_EMAIL \
      EULA_COMPANY

  local PROVIDER="MARKETPLACE ${K8S_PROVIDER:=default}"

  local UI_VERSION=$(echo $UI_IMAGE | awk -F':' '{print $2}')

  local payload=$(create_slack_payload "$PROVIDER" "$UI_VERSION" "$EULA_NAME" "$EULA_COMPANY" "$EULA_EMAIL")
  send_slack_message "$payload"
}

wait_for_database_pod() {
  if [ "$PROVISION_INTERNAL_DATABASE" == "Yes" ]; then
    wait_for_system_pod "${RELEASE_NAME}-postgresql"
  fi
}

wait_for_database() {
  echo "Waiting for database service..."
  secs=10
  for i in `seq 1 20`; do
    echo "Attempting database connection. (attempt $i)"
    ./psql.sh -c '\l'
    if [ $? -eq 0 ]; then
      echo "Database is available."
      return 0
    fi

    echo "Database not available, trying again in $secs seconds. (attempt $i)"
    sleep $secs
  done

  exit_with_error "Database did not become availble, aborting."
}

init_database() {

  echo "Dropping existing databases..."

  echo "TODO: Unhardcode database names"
  for db in gestalt-meta gestalt-security kong-db laser-db gateway-db ; do
    ./drop_database.sh $db --yes
    exit_on_error "Failed to initialize database, aborting."
  done

  echo "Attempting to initalize database..."
  ./create_initial_databases.sh
  exit_on_error "Failed to initialize database, aborting."
  echo "Database initialized."
}

invoke_security_init() {
  echo "Initializing Security..."
  secs=20
  for i in `seq 1 20`; do
    do_invoke_security_init
    if [ $? -eq 0 ]; then
      return 0
    fi

    echo "Trying again in $secs seconds. (attempt $i)"
    sleep $secs
  done

  exit_with_error "Failed to initialize Security, aborting."
}

do_invoke_security_init() {
  echo "Invoking $SECURITY_URL/init..."

  # sets HTTP_STATUS and HTTP_BODY
  http_post $SECURITY_URL/init "{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}"

  if [ ! "$HTTP_STATUS" -eq "200" ]; then
    echo "Error invoking $SECURITY_URL/init ($HTTP_STATUS returned)"
    return 1
  fi

  echo "$HTTP_BODY" > init_payload

  do_get_security_credentials

  echo "Security initialization invoked, API key and secret obtained."
}

do_get_security_credentials() {

  export SECURITY_KEY=`cat init_payload | jq '.[] .apiKey' | sed -e 's/^"//' -e 's/"$//'`
  exit_on_error "Failed to obtain or parse API key (error code $?), aborting."

  export SECURITY_SECRET=`cat init_payload | jq '.[] .apiSecret' | sed -e 's/^"//' -e 's/"$//'`
  exit_on_error "Failed to obtain or parse API secret (error code $?), aborting."
}

create_gestalt_security_creds_secret() {
  kubectl create -f - <<EOF
apiVersion: v1
data:
  API_KEY: `echo $SECURITY_KEY | base64`
  API_SECRET: `echo $SECURITY_SECRET | base64`
kind: Secret
metadata:
  name: gestalt-security-creds
  namespace: $RELEASE_NAMESPACE
type: Opaque
EOF
}

wait_for_system_pod() {
  wait_for_pod $1 $RELEASE_NAMESPACE
}

wait_for_pod() {
  local previous_status=""
  local pod=$1
  local scope="--all-namespaces"
  index=4
  if [ ! -z "$2" ]; then
    scope="-n $2"
    index=3
  fi

  echo "Waiting for $pod to launch"
  for i in `seq 1 120`; do
    status=$(kubectl get pod $scope --no-headers | grep ${pod}- | awk "{print \$$index}")

    if [ "$status" != "$previous_status" ]; then
      echo -n " $status "
      previous_status=$status
    else
      echo -n "."
    fi

    if [ "$status" == "Running" ]; then
      echo
      return 0
    elif [ "$status" == "Completed" ]; then
      echo
      return 0
    fi

    sleep 2
  done

  echo
  exit_with_error "$pod did not launch within expected timeframe, aborting"  
  return 1
}

wait_for_security_init() {

  wait_for_system_pod "${RELEASE_NAME}-security"

  echo "Waiting for Security to initialize..."
  secs=20

  for i in `seq 1 20`; do
    if [ "`curl $SECURITY_URL/init | jq '.initialized'`" == "true" ]; then
      echo "Security initialized."
      return 0
    fi
    echo "Not yet, trying again in $secs seconds. (attempt $i)"
    sleep $secs
  done

  exit_with_error "Security did not initialize, aborting."
}

init_meta() {
  echo "Initializing Meta..."

  if [ -z "$SECURITY_KEY" ]; then
    echo "Parsing security credentials."
    do_get_security_credentials
  fi

  secs=20
  for i in `seq 1 20`; do
    do_init_meta
    if [ $? -eq 0 ]; then
      return 0
    fi

    echo "Trying again in $secs seconds. (attempt $i)"
    sleep $secs
  done

  exit_with_error "Failed to initialize Meta."
}

do_init_meta() {

  wait_for_system_pod "${RELEASE_NAME}-meta"

  echo "Polling $META_URL/root..."
  # Check if meta initialized (ready to bootstrap when /root returns 500)
  HTTP_STATUS=$(curl -s -o /dev/null -u $SECURITY_KEY:$SECURITY_SECRET -w '%{http_code}' $META_URL/root)
  if [ "$HTTP_STATUS" == "500" ]; then

    echo "Bootstrapping Meta at $META_URL/bootstrap..."
    HTTP_STATUS=$(curl -X POST -s -o /dev/null -u $SECURITY_KEY:$SECURITY_SECRET -w '%{http_code}' $META_URL/bootstrap?$META_BOOTSTRAP_PARAMS)

    if [ "$HTTP_STATUS" -ge "200" ] && [ "$HTTP_STATUS" -lt "300" ]; then
      echo "Meta bootstrapped (returned $HTTP_STATUS)."
    else
      exit_with_error "Error bootstrapping Meta, aborting."
    fi

    echo "Syncing Meta at $META_URL/sync..."
    HTTP_STATUS=$(curl -X POST -s -o /dev/null -u $SECURITY_KEY:$SECURITY_SECRET -w '%{http_code}' $META_URL/sync)

    if [ "$HTTP_STATUS" -ge "200" ] && [ "$HTTP_STATUS" -lt "300" ]; then
      echo "Meta synced (returned $HTTP_STATUS)."
    else
      exit_with_error "Error syncing Meta, aborting."
    fi
  else
    echo "Meta not yet ready."
    return 1
  fi
}

gestalt_cli_set_opts() {
  if [ "${FOGCLI_DEBUG}" == "true" ]; then
    fog config set debug=true
  fi
}

gestalt_cli_login() {
  md5sum `which fog`
  cmd="fog login $UI_URL -u $ADMIN_USERNAME -p $ADMIN_PASSWORD"
  echo "Running 'fog login'..."
  $cmd
  exit_on_error "Failed to login to Gestalt, aborting."
}

gestalt_cli_license_set() {
  check_for_required_files ${gestalt_license}
  fog admin update-license -f ${gestalt_license}
  exit_on_error "Failed to upload license '${gestalt_license}' (error code $?), aborting."
}

gestalt_cli_context_set() {
  fog context set --path /root
  exit_on_error "Failed to set fog context '/root' (error code $?), aborting."
}

gestalt_cli_create_resources() {
  cd /app/install/resource_templates

  # Always assume there's a script called run.sh
  if [ -f ./run.sh ]; then 
    # Source run.sh so that it has access to higher-level functions
    . run.sh
    exit_on_error "Gestalt resource setup did not succeed (error code $?), aborting."
  else
    echo "Warning - Not running resource templates script, /resource_templates/run.sh not found"
  fi
  cd ~-
  echo "Gestalt resource(s) created."
}

servicename_is_unique_or_exit() {
  local service_name=$1
  # Get a list of all services by name across all namespaces
  local list=$(kubectl get svc --all-namespaces -ojson | jq -r '.items[].metadata.name')
  local found="false"
  for s in $list; do
    # Trying to find a unique service name.  If the service was already found before, it's not a unique name
    if [ "$s" == "$service_name" ]; then
      [ "$found" == "true" ] && exit_with_error "Found multiple services with name '$service_name', aborting"
      found="true"
    fi
  done

  if [ "$found" != "true" ]; then 
    exit_with_error "Could not find any services with name '$service_name'!"
  fi
}

get_service_namespace() {
  local SVC=$1
  servicename_is_unique_or_exit $SVC
  kubectl get svc --all-namespaces -ojson | jq -r ".items[].metadata | select(.name==\"$SVC\") | .namespace"
}

get_deployment_namespace() {
  local DEPLOY=$1
  kubectl get deployment --all-namespaces -ojson | jq -r ".items[].metadata | select(.name==\"$DEPLOY\") | .namespace"
}

get_gestalt_app_service_name() {
  local APP=$1
  kubectl get svc --all-namespaces -l "gestalt-app=${APP}" -o jsonpath="{.items[0].metadata.name}"
}

get_gestalt_app_deployment_name() {
  local APP=$1
  kubectl get deployment --all-namespaces -l "gestalt-app=${APP}" -o jsonpath="{.items[0].metadata.name}"
}

create_readiness_probe() {
  local deployment=$1
  local container=${2:-"$deployment"}
  local endpoint=${3:-"/"}
  local port=${4:-80}
  local namespace=${5:-$RELEASE_NAMESPACE}

  [ -z $deployment ] && exit_with_error "deployment name blank or undefined for create_readiness_probe"
  [ -z $namespace ] && namespace=$(get_deployment_namespace $deployment)

  echo "Creating ${deployment} readinessProbe in deployment '${namespace}/${deployment}'"
  echo "Creating ${deployment} readinessProbe on endpoint '${endpoint}' port '$port'"

  kubectl apply -f - <<EOF
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: $deployment
  namespace: $namespace
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: $container
        readinessProbe:
          httpGet:
            path: $endpoint
            port: $port
            scheme: HTTP
EOF

  exit_on_error "Could not create ${deployment} readinessProbe on endpoint '${endpoint}' port '$port'"
  
  echo "SUCCESS created readiness probe for '${deployment}' on endpoint '${endpoint}' port '$port'!"
}

create_ingress() {
  local service=$1
  local port=${2:-80}
  local namespace=${3:-$RELEASE_NAMESPACE}

  [ -z $service ] && exit_with_error "service name blank or undefined for create_ingress"

  [ -z $namespace ] && namespace=$(get_service_namespace $service)

  echo "Namespace for service '$service' is '$namespace'"

  echo "Creating Kubernetes Ingress resource for service '${namespace}/${service}' port '${port}'"

  kubectl apply -f - <<EOF
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: $service
  namespace: $namespace
spec:
  backend:
    serviceName: $service
    servicePort: $port
EOF

  exit_on_error "Could not create ingress to '$namespace/$service' port '$port' (kubectl error code $?), aborting."

  echo "SUCCESS created ingress to '$namespace/$service' port '$port'!"
}

set_kong_service_namespace() {
  local service=$1
  export KONG_SERVICE_NAMESPACE=$(get_service_namespace $service)
  echo "KONG_SERVICE_NAMESPACE == ${KONG_SERVICE_NAMESPACE}"
}

if_kong_ingress_service_name_is_set() {
  local run_command=$*
  echo "---------- Checking KONG_INGRESS_SERVICE_NAME for '$run_command' ----------"

  if [ -z $KONG_INGRESS_SERVICE_NAME ]; then
    echo "KONG_INGRESS_SERVICE_NAME not provided!  Skipping '$run_command'"
    return 99
  else
    set_kong_service_namespace ${KONG_INGRESS_SERVICE_NAME}
    echo "KONG_INGRESS_SERVICE_NAME was '${KONG_SERVICE_NAMESPACE}/${KONG_INGRESS_SERVICE_NAME}'"
    echo "Running '$run_command'"
    $run_command
  fi
}

get_kong_service_port() {
  kubectl -n $KONG_SERVICE_NAMESPACE get svc $KONG_INGRESS_SERVICE_NAME -o json | jq -r ".spec.ports[] | select(.name==\"public-url\") | .port"
}

endpoint_is_working() {
  local SVC=$1
  local PORT=${2:-80}
  local ENDPOINT=${3:-"/"}
  local NAMESPACE=${4:-$RELEASE_NAMESPACE}

  local URL="http://${SVC}.${NAMESPACE}:${PORT}${ENDPOINT}"

  local try_limit=5
  local tries=0
  local exit_code=1
  echo "Attempting to hit URL $URL"
  curl_cmd="curl -i -s -S --fail --connect-timeout 5 --stderr - $URL"
  while [ $exit_code -ne 0 -a $tries -lt $try_limit ]; do
    tries=`expr $tries + 1`
    echo "Running try $tries '$curl_cmd'"
    response="$($curl_cmd)"
    exit_code=$?
    echo "${response}"
    echo "exit code was $exit_code"
    if [ $exit_code -eq 0 ]; then
      echo "---------- SUCCESS requesting $URL ---------"
    else
      echo "---------- FAILED requesting $URL ----------"
    fi
    if [ $exit_code -ne 0 -a $tries -lt $try_limit ]; then
      echo "Retrying in 10 seconds..."
      sleep 10
    fi
  done
  [ $exit_code -ne 0 ] && echo "---------- $tries FAILED requests for $URL ----------"
  [ $exit_code -eq 0 ]
}

if_security_healthcheck_is_working() {
  local run_cmd=$*
  echo "---------- Checking Security Health API for '$run_cmd' ----------"
  local SVC=$( get_security_service_name )
  local PORT=$( get_security_service_port )

  if endpoint_is_working $SVC $PORT "/health"; then
    echo "---------- Security Health API success ---------"
    $run_cmd
  else
    echo "---------- Security Health API FAILED ---------"
    false
  fi
}

if_meta_healthcheck_is_working() {
  local run_cmd=$*
  echo "---------- Checking Meta Health API for '$run_cmd' ----------"
  local SVC=$( get_meta_service_name )
  local PORT=$( get_meta_service_port )

  if endpoint_is_working $SVC $PORT "/health"; then
    echo "---------- Meta Health API success ---------"
    $run_cmd
  else
    echo "---------- Meta Health API FAILED ---------"
    false
  fi
}

and_kong_healthcheck_is_working() {
  local run_cmd=$*
  echo "---------- Checking Kong Health API for '$run_cmd' ----------"
  local PORT=$( get_kong_service_port )

  if endpoint_is_working $KONG_INGRESS_SERVICE_NAME $PORT "/health" $KONG_SERVICE_NAMESPACE; then
    echo "---------- Kong Health API success ---------"
    $run_cmd
  else
    echo "---------- Kong Health API FAILED ---------"
    false
  fi
}

rebuild_kong_ingress() {
  echo "Rebuilding the Kong Ingress after adding readinessProbe"
  local ING_YAML=$( kubectl -n $KONG_SERVICE_NAMESPACE get ingress kng -o yaml )
  echo "---------- Kong INGRESS YAML ---------"
  echo "$ING_YAML"
  echo "---------- Kong INGRESS YAML ---------"
  echo "Deleting Kong Ingesss"
  kubectl -n $KONG_SERVICE_NAMESPACE delete ingress kng
  echo "Sleeping 30 seconds"
  sleep 30
  echo "Recreating Kong Ingress"
  echo "$ING_YAML" | kubectl create -f -
}

must_rebuild_kong_ingress_for_gke() {
  [ "${K8S_PROVIDER:=default}" == 'gke' ] && [ "$KONG_SERVICE_TYPE" == "NodePort" ]
}

create_kong_readiness_probe() {
  # create_readiness_probe deployment [container] [endpoint_path] [port] [namespace]
  create_readiness_probe kng kng "/health" 8000 $KONG_SERVICE_NAMESPACE
  if must_rebuild_kong_ingress_for_gke ; then
    rebuild_kong_ingress
  fi
}

create_kong_ingress_v2() {
  # create_ingress service [port] [namespace]
  create_ingress $KONG_INGRESS_SERVICE_NAME 'public-url' $KONG_SERVICE_NAMESPACE
}

get_security_service_name() {
  [ -z "$SECURITY_INGRESS_SERVICE_NAME" ] && SECURITY_INGRESS_SERVICE_NAME=$( get_gestalt_app_service_name security )
  echo "$SECURITY_INGRESS_SERVICE_NAME"
}

get_security_service_port() {
  local SVC=$( get_security_service_name )
  kubectl -n $RELEASE_NAMESPACE get svc $SVC -o json | jq -r ".spec.ports[] | select(.name==\"service-api\") | .port"
}

get_security_deployment_name() {
  [ -z "$SECURITY_DEPLOYMENT_NAME" ] && SECURITY_DEPLOYMENT_NAME=$( get_gestalt_app_deployment_name security )
  echo "$SECURITY_DEPLOYMENT_NAME"
}

create_security_readiness_probe() {
  local DEPLOYMENT=$( get_security_deployment_name )
  # create_readiness_probe deployment [container] [endpoint_path] [port] [namespace]
  create_readiness_probe $DEPLOYMENT $DEPLOYMENT "/health" service-api
}

create_security_ingress() {
  local SVC=$( get_security_service_name )
  # create_ingress service [port] [namespace]
  create_ingress $SVC service-api
}

get_meta_service_name() {
  [ -z "$META_INGRESS_SERVICE_NAME" ] && META_INGRESS_SERVICE_NAME=$( get_gestalt_app_service_name meta )
  echo "$META_INGRESS_SERVICE_NAME"
}

get_meta_service_port() {
  local SVC=$( get_meta_service_name )
  kubectl -n $RELEASE_NAMESPACE get svc $SVC -o json | jq -r ".spec.ports[] | select(.name==\"http-api\") | .port"
}

get_meta_deployment_name() {
  [ -z "$META_DEPLOYMENT_NAME" ] && META_DEPLOYMENT_NAME=$( get_gestalt_app_deployment_name meta )
  echo "$META_DEPLOYMENT_NAME"
}

create_meta_readiness_probe() {
  local DEPLOYMENT=$( get_meta_deployment_name )
  # create_readiness_probe deployment [container] [endpoint_path] [port] [namespace]
  create_readiness_probe $DEPLOYMENT $DEPLOYMENT "/health" service-api
}

create_meta_ingress() {
  local SVC=$( get_meta_service_name )
  # create_ingress service [port] [namespace]
  create_ingress $SVC http-api
}
