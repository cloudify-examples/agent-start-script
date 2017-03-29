#! /bin/bash -e

####################################################
# This script will start a Cloudify agent that will
# connect to a Cloudify manager verion 3.4.x.  
####################################################

function usage()
{
    echo "usage: start-agent.sh [arg=value,...]"
    echo "   --manager-ip         manager ip address"
    echo "                        env var: CLOUDIFY_MANAGER_IP" 
    echo "   --node-instance-id   node instance id from manager"
    echo "                        env var: NODE_INSTANCE_ID" 
    echo "   --deployment-id      deployment id from manager"
    echo "                        env var: CLOUDIFY_DAEMON_DEPLOYMENT_ID" 
    echo "  [--daemon-user]       user to run agent as"   
    echo "                        env var: CLOUDIFY_DAEMON_USER" 
    echo "  [--broker-user]       user to access rabbitmq"
    echo "                        env var: CLOUDIFY_BROKER_USER" 
    echo "  [--broker-password]   user to access rabbitmq"
    echo "                        env var: CLOUDIFY_BROKER_PASS" 
    echo "  [--fileserver-url]    fileserver url"
    echo "                        env var: FILESERVER_URL" 
    echo "  [--manager-rest-port] manager rest API port"
    echo "                        env var: MANAGER_REST_PORT" 
    echo "  [-h --help]                this message"
    echo ""
}


if [ $USER != "root" ]; then
  echo "ERROR: script must be run as root"
  exit 1
fi

while [ -n "$1" ]; do
  echo "arg = $1"
  PARAM=`echo $1 | awk -F= '{print $1}'`
  VALUE=`echo $1 | awk -F= '{print $2}'`
  echo "  param=$PARAM value=$VALUE"
  case $PARAM in
    --help)
      usage
      exit
      ;;
    --manager-ip)
      CLOUDIFY_MANAGER_IP=$VALUE
      echo "set CLOUDIFY_MANAGER_IP=$VALUE"
      ;;
    --node-instance-id)
      NODE_INSTANCE_ID=$VALUE
      ;;
    --deployment-id)
      CLOUDIFY_DAEMON_DEPLOYMENT_ID=$VALUE
      ;;
    --daemon-user)
      CLOUDIFY_DAEMON_USER=$VALUE
      ;;
    --broker-user)
      CLOUDIFY_BROKER_USER=$VALUE
      ;;
    --broker-password)
      CLOUDIFY_BROKER_PASS=$VALUE
      ;;
    --fileserver-url)
      FILESERVER_URL=$VALUE
      ;;
    --manager-rest-port)
      MANAGER_REST_PORT=$VALUE
      ;;
  esac
  shift
done      

ERR=0
if [ -z "$CLOUDIFY_MANAGER_IP"  ]; then
  echo "ERROR: Manager IP not set"
  ERR=1
fi
if [ -z "$NODE_INSTANCE_ID"  ]; then
  echo "ERROR: Instance ID not set"
  ERR=1
fi
if [ -z "$CLOUDIFY_DAEMON_DEPLOYMENT_ID"  ]; then
  echo "ERROR: Deployment ID not set"
  ERR=1
fi
if [ $ERR -ne 0 ]; then
  usage
  exit 1
fi


# THESE NEED TO BE SET
export CLOUDIFY_MANAGER_IP
export NODE_INSTANCE_ID
export CLOUDIFY_DAEMON_DEPLOYMENT_ID

# UNLIKELY TO NEED CUSTOMIZATION
export CLOUDIFY_DAEMON_USER=${CLOUDIFY_DAEMON_USER-$USER}
export CLOUDIFY_BROKER_USER=${CLOUDIFY_BROKER_USER:-cloudify}
export CLOUDIFY_BROKER_PASS=${CLOUDIFY_BROKER_PASS:-c10udify}
export MANAGER_FILESERVER_PORT=${MANAGER_FILESERVER_PORT:-53229}
export MANAGER_REST_PORT=${MANAGER_REST_PORT:-8101}

export MANAGER_FILE_SERVER_DEPLOYMENTS_ROOT_URL=http://${CLOUDIFY_MANAGER_IP}:${MANAGER_FILESERVER_PORT}/deployments
export MANAGER_FILE_SERVER_BLUEPRINTS_ROOT_URL=http://${CLOUDIFY_MANAGER_IP}:${MANAGER_FILESERVER_PORT}/blueprints
export MANAGER_FILE_SERVER_URL=http://${CLOUDIFY_MANAGER_IP}:${MANAGER_FILESERVER_PORT}
if [ -n "$FILE_SERVER_URL" ]; then
  MANAGER_FILE_SERVER_URL=$FILE_SERVER_URL
fi

eval "BASEDIR=~${CLOUDIFY_DAEMON_USER}"
export CLOUDIFY_DAEMON_STORAGE_DIRECTORY=${BASEDIR}/.cfy-agent
export CELERY_TASK_SERIALIZER=json
export CELERY_RESULT_SERIALIZER=json
export CELERY_APP=cloudify_agent.app.app
export CELERY_WORK_DIR=${BASEDIR}/$NODE_INSTANCE_ID/work
export BASEDIR=/tmp
export CELERY_CONFIG_MODULE=cloudify.broker_config
export PACKAGE_URL=""
export AGENTDIR=$CLOUDIFY_DAEMON_STORAGE_DIRECTORY
export ENVDIR=$AGENTDIR/env
export VIRTUALENV=${ENVDIR}

export CLOUDIFY_DAEMON_PROCESS_MANAGEMENT=detach
export CLOUDIFY_DAEMON_NAME=$NODE_INSTANCE_ID
export CLOUDIFY_DAEMON_QUEUE=$NODE_INSTANCE_ID
export CLOUDIFY_DAEMON_WORKDIR=${CELERY_WORK_DIR}

download()
{
    if command -v wget > /dev/null 2>&1; then
        wget $1 -O $2
    elif command -v curl > /dev/null 2>&1; then
        curl -L -o $2 $1
    else
        echo >&2 "error: wget/curl not found. cannot download agent package"; return 1
    fi
}
export -f download

package_url()
{
    if [[ ! -z "$PACKAGE_URL" ]]; then
        echo "$PACKAGE_URL"
    else
        local distro="$(python -c 'import sys, platform; sys.stdout.write(platform.dist()[0].lower())')"
        local distro_codename="$(python -c 'import sys, platform; sys.stdout.write(platform.dist()[2].lower())')"
        echo "${MANAGER_FILE_SERVER_URL}/packages/agents/${distro}-${distro_codename}-agent.tar.gz"
    fi
}
export -f package_url

download_and_extract_agent_package()
{
    echo "MGR_FS_URL=${MANAGER_FILE_SERVER_URL}"
    download $(package_url) ${BASEDIR}/agent.tar.gz
    mkdir -p ${AGENTDIR}
    tar xzf ${BASEDIR}/agent.tar.gz --strip=1 -C ${AGENTDIR}
}
export -f download_and_extract_agent_package

export_daemon_env()
{
    local agent_env_bin=${ENVDIR}/bin
    export AGENT_PYTHON_INTERPRETER=${agent_env_bin}/python
    export AGENT_CLI=${agent_env_bin}/cfy-agent
    export PATH=${agent_env_bin}:$PATH
}
export -f export_daemon_env

configure_virtualenv()
{
    export_daemon_env
    # configure command is run explicily as the virtualenv has not been "fixed"
    # yet
    ${AGENT_PYTHON_INTERPRETER} ${AGENT_CLI} configure --relocated-env
}
export -f configure_virtualenv

start_daemon()
{
    export_daemon_env
    echo $PATH
    cfy-agent daemons create $PM_OPTIONS
    cfy-agent daemons configure
    cfy-agent daemons start
}
export -f start_daemon

install_agent()
{
    su ${CLOUDIFY_DAEMON_USER} --shell /bin/bash -c "set -e; download_and_extract_agent_package"
    su ${CLOUDIFY_DAEMON_USER} --shell /bin/bash -c "set -e; configure_virtualenv"
#    disable_requiretty
}
export -f install_agent

install_and_start_agent()
{
    install_agent
    su ${CLOUDIFY_DAEMON_USER} --shell /bin/bash -c "set -e; start_daemon"
}
export -f install_and_start_agent

install_and_start_agent
