#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd 2>/dev/null)
source "${SCRIPT_DIR}/install_helpers"

figure_host_info() {
    if [ -x /usr/bin/lsb_release ]; then
        HOST_ID=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        HOST_RELEASE=$(lsb_release -sr)
    elif [ -f /etc/system-release-cpe ]; then
        HOST_ID=$( cut -d: -f 3 < /etc/system-release-cpe)
        HOST_RELEASE=$(cut -d: -f 5 < /etc/system-release-cpe)
    fi

    HOST_TYPE=${HOST_ID}-${HOST_RELEASE}
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
    find_installed_collectd
    if [ -z "${COLLECTD}" ]; then
        echo "Unable to find a working collectd. Downloading.."
        get_sfx_collectd
    else
        outofdate=$(vercomp "$COLLECTD_VER" "$LATEST_VER")
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
    echo "Fetching latest collectd for ${HOST_ID}-${HOST_RELEASE}..."
    curl "https://dl.signalfuse.com/signalfx-collectd/${HOST_ID}/${HOST_RELEASE}/${JAVA_NAME}/signalfx-collectd-${HOST_TYPE}-${LATEST_VER}-latest-${JAVA_NAME}.tar.gz" -o /tmp/signalfx-collectd.tar.gz
    check_for_err "Success\n";
    printf "Uncompressing archive..."
    tar Cxzf /opt /tmp/signalfx-collectd.tar.gz
    check_for_err "Success\n";
    COLLECTD=/opt/signalfx-collectd/sbin/collectd
}


main() {
  figure_host_info
  find_collectd

  "${SCRIPT_DIR}/install.sh" "$@" ${COLLECTD}
}

main "$@"
