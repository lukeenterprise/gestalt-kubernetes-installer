#!/bin/bash

# Generic functions are in utilities-bash.sh

echo "BASH VERSION: $BASH_VERSION $POSIXLY_CORRECT"
# ["key"]="declare"
#   ["key"]="ADMIN_USERNAME"
#   ["key"]="ADMIN_PASSWORD"
#   ["key"]="ADMIN_USERNAME"
#   ["key"]="DATABASE_HOSTNAME"
#   ["key"]="DATABASE_PASSWORD"
#   ["key"]="DATABASE_USERNAME"
#   ["key"]="DOTNET_EXECUTOR_IMAGE"
#   ["key"]="ELASTICSEARCH_HOST"
#   ["key"]="ELASTICSEARCH_IMAGE"
#   ["key"]="GOLANG_EXECUTOR_IMAGE"
#   ["key"]="GWM_EXECUTOR_IMAGE"
#   ["key"]="JS_EXECUTOR_IMAGE"
#   ["key"]="JVM_EXECUTOR_IMAGE"
#   ["key"]="KONG_IMAGE"
#   ["key"]="KONG_0_VIRTUAL_HOST"
#   ["key"]="KUBECONFIG_BASE64"
#   ["key"]="LOGGING_IMAGE"
#   ["key"]="META_HOSTNAME"
#   ["key"]="META_IMAGE"
#   ["key"]="META_PORT"
#   ["key"]="META_PROTOCOL"
#   ["key"]="NODEJS_EXECUTOR_IMAGE"
#   ["key"]="POLICY_IMAGE"
#   ["key"]="PYTHON_EXECUTOR_IMAGE"
#   ["key"]="RABBIT_HOST"
#   ["key"]="RABBIT_HOSTNAME"
#   ["key"]="RABBIT_HTTP_PORT"
#   ["key"]="RABBIT_IMAGE"
#   ["key"]="RABBIT_PORT"
#   ["key"]="RUBY_EXECUTOR_IMAGE"
#   ["key"]="SECURITY_HOSTNAME"
#   ["key"]="SECURITY_IMAGE"
#   ["key"]="SECURITY_PORT"
#   ["key"]="SECURITY_PROTOCOL"
#   ["key"]="UI_HOSTNAME"
#   ["key"]="UI_IMAGE"
#   ["key"]="UI_PORT"
#   ["key"]="UI_PROTOCOL"
# )

random() { cat /dev/urandom | env LC_CTYPE=C tr -dc $1 | head -c $2; echo; }

randompw() {
  # Generate a random password (16 characters) that starts with an alpha character
  echo `random [:alpha:] 1``random [:alnum:] 15`
}

getsalt_installer_load_configmap() {

  # check_for_required_variables RELEASE_NAME RELEASE_NAMESPACE REPORTING_SECRET gestalt_config
  check_for_required_variables gestalt_config

  # Convert Yaml config to JSON for easier parsing
  echo "Creating $gestalt_config from $gestalt_config_yaml..."
  yaml2json ${gestalt_config_yaml} > ${gestalt_config}

  validate_json ${gestalt_config}
  convert_json_to_env_variables ${gestalt_config}
  convert_configmap_to_env_variables "${RELEASE_NAME}-deployer-config" deployer_config_to_env
  check_for_required_variables GESTALT_INSTALL_LOGGING_LVL
  logging_lvl=${GESTALT_INSTALL_LOGGING_LVL}
  log_set_logging_lvl
  logging_lvl_validate 
  # print_env_variables #will print only if debug
}

get_configmap_data() {
  echo $( kubectl -n ${RELEASE_NAMESPACE} get configmap ${1} -o json | jq '.data' )
}

convert_configmap_to_env_variables() {
  local CONFIGMAP=$1
  local KEYMAP=$2
  local JSON_DATA=$( get_configmap_data $CONFIGMAP )
}


getsalt_installer_setcheck_variables() {

  export EXTERNAL_GATEWAY_HOST=localhost
  export EXTERNAL_GATEWAY_PROTOCOL=http

  # Check all variables in one call
  check_for_required_variables \
    ADMIN_PASSWORD \
    ADMIN_USERNAME \
    DATABASE_HOSTNAME \
    DATABASE_PASSWORD \
    DATABASE_USERNAME \
    DOTNET_EXECUTOR_IMAGE \
    ELASTICSEARCH_HOST \
    ELASTICSEARCH_IMAGE \
    GOLANG_EXECUTOR_IMAGE \
    GWM_EXECUTOR_IMAGE \
    JS_EXECUTOR_IMAGE \
    JVM_EXECUTOR_IMAGE \
    KONG_IMAGE \
    KONG_0_VIRTUAL_HOST \
    KUBECONFIG_BASE64 \
    LOGGING_IMAGE \
    META_HOSTNAME \
    META_IMAGE \
    META_PORT \
    META_PROTOCOL \
    NODEJS_EXECUTOR_IMAGE \
    POLICY_IMAGE \
    PYTHON_EXECUTOR_IMAGE \
    RABBIT_HOST \
    RABBIT_HOSTNAME \
    RABBIT_HTTP_PORT \
    RABBIT_IMAGE \
    RABBIT_PORT \
    RUBY_EXECUTOR_IMAGE \
    SECURITY_HOSTNAME \
    SECURITY_IMAGE \
    SECURITY_PORT \
    SECURITY_PROTOCOL \
    UI_HOSTNAME \
    UI_IMAGE \
    UI_PORT \
    UI_PROTOCOL

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

gestalt_installer_generate_helm_config() {

  check_for_required_variables \
    SECURITY_IMAGE \
    SECURITY_HOSTNAME \
    SECURITY_PORT \
    SECURITY_PROTOCOL \
    ADMIN_USERNAME \
    ADMIN_PASSWORD \
    POSTGRES_IMAGE_NAME \
    POSTGRES_IMAGE_TAG \
    DATABASE_NAME \
    DATABASE_PASSWORD \
    DATABASE_USERNAME \
    KUBECONFIG_BASE64 \
    RABBIT_IMAGE \
    RABBIT_HOSTNAME \
    RABBIT_PORT \
    RABBIT_HTTP_PORT \
    ELASTICSEARCH_IMAGE \
    META_IMAGE \
    META_HOSTNAME \
    META_PORT \
    META_PROTOCOL \
    META_NODEPORT \
    KONG_NODEPORT \
    LOGGING_NODEPORT \
    UI_IMAGE \
    UI_NODEPORT \
    internal_database_pv_storage_size \
    internal_database_pv_storage_class \
    postgres_persistence_subpath \
    postgres_memory_request \
    postgres_cpu_request


  cat > helm-config.yaml <<EOF
common:
  # imagePullPolicy: IfNotPresent
  imagePullPolicy: Always

secrets:
  databaseUsername: "${DATABASE_USERNAME}"
  databasePassword: "${DATABASE_PASSWORD}"
  adminUser: "${ADMIN_USERNAME}"
  adminPassword: "${ADMIN_PASSWORD}"

security:
  exposedServiceType: NodePort
  image: "${SECURITY_IMAGE}"
  hostname: "${SECURITY_HOSTNAME}"
  port: "${SECURITY_PORT}"
  protocol: "${SECURITY_PROTOCOL}"
  databaseName: gestalt-security

db:
  hostname: ${DATABASE_HOSTNAME}
  port: 5432
  databaseName: postgres

rabbit:
  image: "${RABBIT_IMAGE}"
  hostname: "${RABBIT_HOSTNAME}"
  port: ${RABBIT_PORT}
  httpPort: ${RABBIT_HTTP_PORT}

elastic:
  image: ${ELASTICSEARCH_IMAGE}
#  initController:
#    image: ${ELASTICSEARCH_INIT_IMAGE}
  restPort: 9200
  transportPort: 9300
  initContainer:
    image: busybox:1.27.2

meta:
  image: ${META_IMAGE}
  exposedServiceType: NodePort
  hostname: ${META_HOSTNAME}
  port: ${META_PORT}
  protocol: ${META_PROTOCOL}
  databaseName: gestalt-meta
  nodePort: ${META_NODEPORT}

# kong:
#   nodePort: ${KONG_NODEPORT}

logging:
  nodePort: ${LOGGING_NODEPORT}

ui:
  image: ${UI_IMAGE}
  exposedServiceType: NodePort
  nodePort: ${UI_NODEPORT}
  ingress:
    host: localhost
EOF


cat >> helm-config.yaml <<EOF

postgresql:
  image: "${POSTGRES_IMAGE_NAME}"
  imageTag: "${POSTGRES_IMAGE_TAG}"
  postgresUser: ${DATABASE_USERNAME}
  postgresPassword: "${DATABASE_PASSWORD}"
  postgresDatabase: ${DATABASE_NAME}
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

wait_for_database_pod() {
  if [ "$PROVISION_INTERNAL_DATABASE" == "Yes" ]; then
    wait_for_pod_start "gestalt-postgresql"
  fi
}

wait_for_database() {
  echo "Waiting for database service..."
  secs=30
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
  namespace: gestalt-system
type: Opaque
EOF
}

wait_for_pod_start() {

  local previous_status=""
  local pod=$1

  echo "Waiting for $pod to launch"
  for i in `seq 1 30`; do
    status=$(kubectl get pod -n gestalt-system --no-headers | grep $pod | awk '{print $3}')

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

  wait_for_pod_start "gestalt-security"

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

  wait_for_pod_start "gestalt-meta"

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
  cd -
  echo "Gestalt resource(s) created."
}


servicename_is_unique_or_exit() {
  local service_name=$1
  # Get a list of all services by name across all namespaces
  local list=$(kubectl get svc --all-namespaces -ojson | jq -r '.items[].metadata.name')
  local found="false"
  for s in $list; do
    echo "Inspecting service '$s'"
    # Trying to find a unique service name.  If the service was already found before, it's not a unique name
    if [ "$found" == "true" ]; then
      if [ "$s" == "$service_name" ]; then
        exit_with_error "Found multiple services with name '$service_name', aborting"
      fi
    fi

    if [ "$s" == "$service_name" ]; then
      found="true"
      echo "Found service with name '$s'"
    fi
  done

  if [ "$found" != "true" ]; then 
    exit_with_error "Did not find a unique '$service_name' service"
  fi

  echo "Found uniquely named service '$service_name'"
}

get_service_namespace() {
  kubectl get svc --all-namespaces -ojson | jq -r ".items[].metadata | select(.name==\"$1\") | .namespace"
}


set_kong_service_namespace() {
  export KONG_SERVICE_NAMESPACE=$(get_service_namespace kng-ext)
  echo "KONG_SERVICE_NAMESPACE == ${KONG_SERVICE_NAMESPACE}"
}

if_kong_ingress_service_name_is_set() {
  local run_command=$*
  echo "---------- Checking KONG_INGRESS_SERVICE_NAME for '$run_command' ----------"

  if [ -z $KONG_INGRESS_SERVICE_NAME ]; then
    echo "KONG_INGRESS_SERVICE_NAME not provided!  Skipping '$run_command'"
    return 99
  else
    set_kong_service_namespace
    echo "KONG_INGRESS_SERVICE_NAME was '${KONG_SERVICE_NAMESPACE}/${KONG_INGRESS_SERVICE_NAME}'"
    echo "Running '$run_command'"
    $run_command
  fi
}

get_kong_service_port() {
  kubectl -n $KONG_SERVICE_NAMESPACE get svc $KONG_INGRESS_SERVICE_NAME -o json | jq -r ".spec.ports[] | select(.name==\"public-url\") | .port"
}

and_health_api_is_working() {
  local run_cmd=$*
  echo "---------- Checking health API for '$run_cmd' ----------"
  local kong_service_port=$(get_kong_service_port)
  local health_url="http://${KONG_INGRESS_SERVICE_NAME}.${KONG_SERVICE_NAMESPACE}:${kong_service_port}/health"

  local try_limit=5
  local exit_code=1
  local tries=0

  echo "Attempting to hit URL $health_url"
  curl_cmd="curl -i -s -S --connect-timeout 5 --stderr - $health_url"
  while [ $exit_code -ne 0 -a $tries -lt $try_limit ]; do
    echo "Running '$curl_cmd'"
    response="$($curl_cmd)"
    exit_code=$?
    echo "${response}"
    echo "exit code was $exit_code"
    if [ $exit_code -eq 0 ]; then
      echo "---------- Health API success at ${health_url} ---------"
      $run_cmd
      return $?
    else
      echo "---------- Health API FAILED at ${health_url} ----------"
    fi
    echo "Retrying in 10 seconds..."
    sleep 10
    tries=`expr $tries + 1`
  done
  echo "Healthcheck FAILED at API endpoint ${health_url} ----------"
  return $exit_code
}

create_kong_readiness_probe() {
  local namespace=$KONG_SERVICE_NAMESPACE

  echo "Creating readinessProbe for deployment '${namespace}/kng"

  kubectl apply -f - <<EOF
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: kng
  namespace: $namespace
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: kng
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
            scheme: HTTP
EOF

  exit_on_error "Could not create Kong readinessProbe"
  
  echo "Kong readiness probe created!"
}

create_kong_ingress_v2() {
#  if [ -z $KONG_INGRESS_SERVICE_NAME ]; then
#    echo "Skipping Kong Ingress setup since KONG_INGRESS_SERVICE_NAME not provided"
#    return 0
#    # KONG_INGRESS_SERVICE_NAME=kng
#    # echo "KONG_INGRESS_SERVICE_NAME not defined, defaulting to $KONG_INGRESS_SERVICE_NAME"
#  fi

  if [ -z $KONG_INGRESS_HOSTNAME ]; then
    # Note - if EXTERNAL_GATEWAY_HOST isn't specified, providing an empty host will result
    # in '*' for the host for the ingress - which means any host would apply
    export KONG_INGRESS_HOSTNAME=localhost
  fi

  local service_name=$KONG_INGRESS_SERVICE_NAME
  local hostname=$KONG_INGRESS_HOSTNAME

  servicename_is_unique_or_exit $service_name

  local service_namespace=$(get_service_namespace $service_name)

  echo "Namespace for Kong service '$service_name' is '$service_namespace'"

  echo "Creating Kubernetes Ingress resource for service ${KONG_INGRESS_SERVICE_NAME} hostname ${KONG_INGRESS_HOSTNAME}..."

  kubectl apply -f - <<EOF
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: $service_name
  namespace: $service_namespace
spec:
  backend:
    serviceName: $service_name
    servicePort: 8000
  rules:
  - host: $hostname
    http:
      paths:
      - backend:
          serviceName: $service_name
          servicePort: 8001
EOF

  exit_on_error "Could not create ingress to '$service_namespace/$service_name' for ''$host' (kubectl error code $?), aborting."

  echo "Kong ingress to '$service_namespace/$service_name' configured for '$hostname'."
}
