#!/bin/bash
set -e

get_collectd_config() {
    COLLECTD_CONFIG=$(${COLLECTD} -h 2>/dev/null | grep 'Config file' | awk '{ print $3; }')
    if [ -z "$COLLECTD_CONFIG" ]; then
        echo "Unable to get Config file from ${COLLECTD}"
        exit 2;
    fi
    COLLECTD_ETC=$(dirname "${COLLECTD_CONFIG}")
    COLLECTD_MANAGED_CONFIG_DIR=${COLLECTD_ETC}/managed_config
    if [ -x /usr/bin/strings ]; then
        TYPESDB=$(strings "${COLLECTD}" | grep /types.db)
    else 
        TYPESDB=$(grep -oP -a "/[-_/[:alpha:]0-9]+/types.db\x00" "${COLLECTD}")
    fi
    COLLECTD_VER=$(${COLLECTD} -h | grep -oP 'collectd \K.*,' | cut -d, -f1)
}

vercomp () {
    if [[ $1 == "$2" ]]
    then
        echo 0
        return 
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            echo 1
            return
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            echo 2
            return
        fi
    done
    echo 0
}

get_source_config() {
    if [ -z "$SOURCE_TYPE" ]; then 
        echo "There are three ways to configure the source name to be used by collectd"
        echo "when reporting metrics."
        echo "dns - Use the name of the host by resolving it in dns"
        echo "input - You can enter a hostname to use as the source name"
        echo "aws - Use the AWS instance id. This is is helpful if you use tags"
        echo "      or other AWS attributes to group metrics"
        echo
        read -p "How would you like to configure your Hostname? (dns, input, or aws): " SOURCE_TYPE

        while [ "$SOURCE_TYPE" != "dns" -a "$SOURCE_TYPE" != "input" -a "$SOURCE_TYPE" != "aws" ]; do
            read -p "Invalid answer. How would you like to configure your Hostname? (dns, input, or aws): " SOURCE_TYPE
        done 
    fi

    case $SOURCE_TYPE in
    "aws") 
        SOURCE_NAME_INFO="Hostname \"$(curl -s http://169.254.169.254/latest/meta-data/instance-id)\""
        ;;
    "input")
        if [ -z "$HOSTNAME" ]; then
            read -p "Input hostname value: " HOSTNAME
            while [ -z "$HOSTNAME" ]; do
              read -p "Invalid input. Input hostname value: " HOSTNAME
            done 
        fi
        SOURCE_NAME_INFO="Hostname \"${HOSTNAME}\""
    ;;
    "dns")
        SOURCE_NAME_INFO="FQDNLookup   true"
        ;;
    *)
       echo "Invalid SOURCE_TYPE value ${SOURCE_TYPE}";
       exit 2; 
    esac 
       
}

check_for_err() {
    if [ $? != 0 ]; then
	printf "FAILED\n";
	exit 1;
    else
	printf "$@";
    fi
}

usage(){
    echo "$0 [-s|--source_type SOURCE_TYPE] [-t|--api_token API_TOKEN] [-u|--user SIGNALFUSE_USER]"
    echo "   [-o| --org SIGNALFUSE_ORG] [--hostname HOSTNAME] [/path/to/collectd]"
    echo "Installs collectd.conf and configures it for talking to SignalFuse."
    echo "If path to collectd is not specified then it will be searched for in well know places."
    echo 
    echo "  -s | --source_type SOURCE_TYPE : How to configure the Hostname field in collectd.conf:"
    echo "                      aws - use the aws instance id."
    echo "                      hostname - set a hostname. See --hostname" 
    echo "                      dns - use FQDN of the host as the Hostname"
    echo
    echo " --hostanme HOSTNAME: The Hostname value to use if you selected hostname as your source_type"
    echo
    echo "  Configuring SignalFX access"
    echo "------------------------------"
    echo "  -t | --api_token API_TOKEN: If you already know your SignalFuse Token you can specify it."
    echo "  -u | --user SIGNALFUSE_USER: The SignalFuse user name to use to fetch a user token"
    echo "  -o | --org SIGNALFUSE_ORG: If the SignalFuse user is part of more than one organization this"
    echo "                             parameter is required."
    echo 
    exit "$1";
}
parse_args(){
    TEMP=$(getopt -oo:s:t:u:h --longoptions source_type::,hostname::,api_token::,user::,org::,help \
                 -n 'install-collectd' -- "$@")

    if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

    # Note the quotes around `$TEMP': they are essential!
    eval set -- "$TEMP"


    while true; do
        case "$1" in
           -s | --source_type )
               SOURCE_TYPE="$2"; shift 2 ;;
           --hostname )
               HOSTNAME="$2"; shift 2 ;;
           -t | --api_token)
               API_TOKEN="$2"; shift 2 ;;
           -u | --user)
               SFX_USER="$2"; shift 2 ;;
           -o | --org)
               SFX_ORG="--org $2"; shift 2 ;;
           -h | --help)
              usage 0; ;;
           -- ) shift; break ;;
           * ) break ;;
       esac
    done

    COLLECTD=$1
    if [ -z "${COLLECTD}" ]; then
        for p in /opt/signalfx-collectd/sbin/collectd /usr/sbin/collectd "/usr/local/sbin/collectd"; do
           if [ -x $p ]; then
               COLLECTD=${p}
               break;
           fi
        done
        if [ -z "${COLLECTD}" ]; then
            echo "Unable to find collectd"
            usage 2
        else
            echo "Collectd not specified using: ${COLLECTD}"
        fi
   fi
}

install_config(){
    echo "Installing $2"
    cp "${MANAGED_CONF_DIR}/$1" "${COLLECTD_MANAGED_CONFIG_DIR}"
}

install_signalfx_plugin(){
    echo "Installing SignalFuse plugin"
    PLUGIN_INSTALL_DIR=/opt/signalfx-collectd-plugin
    if [ ! -d $PLUGIN_INSTALL_DIR ]; then
       echo "Please install https://github.com/signalfx/signalfx-collectd-plugin in /opt" 
       exit 1;
    fi
    if [ -z "$API_TOKEN" ]; then
       if [ -z "${SFX_USER}" ]; then
           read -p "Input SignalFuse user name: " SFX_USER 
           while [ -z "${SFX_USER}" ]; do
               read -p "Invalid input. Input SignalFuse user name: " SFX_USER
           done
       fi
       API_TOKEN=$(python ${PLUGIN_INSTALL_DIR}/get_all_auth_tokens.py --error_on_multiple ${SFX_ORG} "${SFX_USER}")
    fi
    sed -e "s#%%%API_TOKEN%%%#${API_TOKEN}#" \
        -e "s#TypesDB \".*\"#TypesDB \"${TYPESDB}\"#" \
        "${MANAGED_CONF_DIR}/10-signalfx.conf" > "${COLLECTD_MANAGED_CONFIG_DIR}/10-signalfx.conf"
}

copy_configs(){
   okay_ver=$(vercomp "$COLLECTD_VER" 5.2)
   if [ "$okay_ver" !=  2 ]; then
       install_config 10-aggregation-cpu.conf "CPU Aggregation Plugin"
   fi
   install_signalfx_plugin
}

verify_configs(){
    echo "Verifying config"
    ${COLLECTD} -t
    echo "All good"
}

main() {
    get_collectd_config
    get_source_config

    mkdir -p "${COLLECTD_MANAGED_CONFIG_DIR}"

    if [ -e "${COLLECTD_CONFIG}" ]; then
        printf "Backing up %s: " "${COLLECTD_CONFIG}";
        _bkupname=${COLLECTD_CONFIG}.$(date +"%Y-%m-%d-%T");
        mv "${COLLECTD_CONFIG}" "${_bkupname}"
        check_for_err "Success(${_bkupname})\n";
    fi
    printf "Installing signalfx collectd configuration to %s: " "${COLLECTD_CONFIG}"
    sed -e "s#%%%TYPESDB%%%#${TYPESDB}#" \
        -e "s#%%%SOURCENAMEINFO%%%#${SOURCE_NAME_INFO}#" \
        -e "s#%%%COLLECTDMANAGEDCONFIG%%%#${COLLECTD_MANAGED_CONFIG_DIR}#" \
        "${BASE_DIR}/collectd.conf.tmpl" > "${COLLECTD_CONFIG}"
    check_for_err "Success\n"

    #install managed_configs
    copy_configs
    
    verify_configs

    echo "Starting collectd"
    ${COLLECTD}
}

BASE_DIR=$(cd "$(dirname "$0")" && pwd 2>/dev/null)
MANAGED_CONF_DIR=${BASE_DIR}/managed_config

parse_args "$@"
main
