#!/bin/bash
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd 2>/dev/null)
LATEST_VER=5.4.1

figure_host_info() {
    if [ -x /usr/bin/lsb_release ]; then
        HOST_ID=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        HOST_RELEASE=$(lsb_release -sr)
    elif [ -f /etc/system-release-cpe ]; then
        HOST_ID=$(cat /etc/system-release-cpe | cut -d: -f 3)
        HOST_RELEASE=$( cat /etc/system-release-cpe | cut -d: -f 5)
    fi

    HOST_TYPE=${HOST_ID}-${HOST_RELEASE}
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

check_jdk(){
    JAVA_NAME=openjdk6
    if [ -h /usr/lib/jvm/default-java ]; then
        DEFAULT_JAVA=$(readlink /usr/lib/jvm/default-java)
        if [ ! -z "$DEFAULT_JAVA" ]; then
            case $DEFAULT_JAVA in 
            java-1.6.0*)
                JAVA_NAME=openjdk6 ;;
            java-1.7.0*)
                JAVA_NAME=openjdk7 ;;
            esac 
        fi
    fi
}

find_collectd(){
    COLLECTD=
    for x in /opt/signalfx-collectd/sbin/collectd /usr/local/sbin/collectd /usr/sbin/collectd; do
        if [ -x ${x} ]; then
            COLLECTD=${x};
            COLLECTD_VER=$(${COLLECTD} -h | grep -oP 'collectd \K.*,' | cut -d, -f1)
            break;
        fi
    done 
    if [ -z ${COLLECTD} ]; then
        echo "Unable to find a working collectd. Downloading.."
        get_sfx_collectd
    else 
        outofdate=$(vercomp "$COLLECTD_VER" $LATEST_VER)
        if [ "$outofdate" -eq 2 ]; then
           echo "Installed collectd version (${COLLECTD_VER}) is not the latest version ($LATEST_VER)."
           read -p "Would you like to install the latest version (y|n|q)" INSTALL_LATEST
           while [ "$INSTALL_LATEST" != "y" -a "$INSTALL_LATEST" != "n" -a "$INSTALL_LATEST" != "q" ]; do
               read -p "Invalid input. Would you like to install the latest version (y|n|q)" INSTALL_LATEST
           done

           case $INSTALL_LATEST in
           "y")
               get_sfx_collectd ;;
           "n") ;;
           "q")
               exit 1;
           esac
        fi
    fi
}

get_sfx_collectd(){
    check_jdk
    curl "https://dl.signalfuse.com/signalfx-collectd/${HOST_ID}/${HOST_RELEASE}/${JAVA_NAME}/signalfx-collectd-${HOST_TYPE}-${LATEST_VER}-latest-${JAVA_NAME}.tar.gz" -o /tmp/signalfx-collectd.tar.gz
    tar Cxzf /opt /tmp/signalfx-collectd.tar.gz 
    COLLECTD=/opt/signalfx-collectd/sbin/collectd
} 

install_signalfx_plugin(){
    if [ -d /opt/signalfx-collectd-plugin ]; then
        echo "Updating signalfx collectd plugin"
        (cd /opt/signalfx-collectd-plugin && git pull --rebase)
    else
       echo "Fetching signalfx collectd plugin"
       (cd /opt && git clone https://github.com/signalfx/signalfx-collectd-plugin)
    fi
} 

main() {
  figure_host_info
  find_collectd
  install_signalfx_plugin
  
  "${SCRIPT_DIR}/install.sh" "$@" ${COLLECTD}
}

main "$@"
