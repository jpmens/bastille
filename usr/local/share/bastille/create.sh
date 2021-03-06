#!/bin/sh
# 
# Copyright (c) 2018-2019, Christer Edwards <christer.edwards@gmail.com>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

. /usr/local/share/bastille/colors.pre.sh
. /usr/local/etc/bastille/bastille.conf

usage() {
    echo -e "${COLOR_RED}Usage: bastille create name release ip | interface.${COLOR_RESET}"
    exit 1
}

running_jail() {
    jls name | grep -E "(^|\b)${NAME}($|\b)"
}

validate_ip() {
    local IFS
    ip=${IP}
    if expr "$ip" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
      IFS=.
      set $ip
      for quad in 1 2 3 4; do
        if eval [ \$$quad -gt 255 ]; then
          echo "fail ($ip)"
          exit 1
        fi
      done
      echo -e "${COLOR_GREEN}Valid: ($ip).${COLOR_RESET}"
    else
      echo -e "${COLOR_RED}Invalid: ($ip).${COLOR_RESET}"
      exit 1
    fi
}

validate_netif() {
    local LIST_INTERFACES=$(ifconfig -l)
    interface=${INTERFACE}
    if echo "${LIST_INTERFACES}" | grep -qwo "${INTERFACE}"; then
        echo -e "${COLOR_GREEN}Valid: ($interface).${COLOR_RESET}"
    else
        echo -e "${COLOR_RED}Invalid: ($interface).${COLOR_RESET}"
        exit 1
    fi
}

create_jail() {
    bastille_jail_base="${bastille_jailsdir}/${NAME}/root/.bastille"  ## dir
    bastille_jail_template="${bastille_jailsdir}/${NAME}/root/.template"  ## dir
    bastille_jail_path="${bastille_jailsdir}/${NAME}/root"  ## dir
    bastille_jail_fstab="${bastille_jailsdir}/${NAME}/fstab"  ## file
    bastille_jail_conf="${bastille_jailsdir}/${NAME}/jail.conf"  ## file
    bastille_jail_log="${bastille_logsdir}/${NAME}_console.log"  ## file
    bastille_jail_rc_conf="${bastille_jailsdir}/${NAME}/root/etc/rc.conf" ## file
    bastille_jail_resolv_conf="${bastille_jailsdir}/${NAME}/root/etc/resolv.conf" ## file

    if [ ! -d "${bastille_jailsdir}/${NAME}" ]; then
        if [ "${bastille_zfs_enable}" = "YES" ]; then
            if [ ! -z "${bastille_zfs_zpool}" ]; then
                ## create required zfs datasets
                zfs create ${bastille_zfs_options} ${bastille_zfs_zpool}/${bastille_zfs_prefix}/jails/${NAME}
                zfs create ${bastille_zfs_options} -o mountpoint=${bastille_jailsdir}/${NAME}/root ${bastille_zfs_zpool}/${bastille_zfs_prefix}/jails/${NAME}/root
            fi
        else
            mkdir -p "${bastille_jailsdir}/${NAME}"
        fi
    fi

    if [ ! -d "${bastille_jail_base}" ]; then
        mkdir -p "${bastille_jail_base}"
        mkdir -p "${bastille_jail_path}/usr/home"
        mkdir -p "${bastille_jail_path}/usr/local"
    fi

    if [ ! -d "${bastille_jail_template}" ]; then
        mkdir -p "${bastille_jail_template}"
    fi

    if [ ! -f "${bastille_jail_fstab}" ]; then
        echo -e "${bastille_releasesdir}/${RELEASE} ${bastille_jail_base} nullfs ro 0 0" > ${bastille_jail_fstab}
    fi

    if [ ! -f "${bastille_jail_conf}" ]; then
        if [ -z ${bastille_jail_loopback} ] && [ ! -z ${bastille_jail_external} ]; then
            local bastille_jail_conf_interface=${bastille_jail_external}
        fi
        if [ ! -z ${bastille_jail_loopback} ] && [ -z ${bastille_jail_external} ]; then
            local bastille_jail_conf_interface=${bastille_jail_interface}
        fi
        if [ ! -z  ${INTERFACE} ]; then
            local bastille_jail_conf_interface=${INTERFACE}
        fi
echo -e "interface = ${bastille_jail_conf_interface};\nhost.hostname = ${NAME};\nexec.consolelog = \
${bastille_jail_log};\npath = ${bastille_jail_path};\nip6 = \
disable;\nsecurelevel = 2;\ndevfs_ruleset = 4;\nenforce_statfs = \
2;\nexec.start = '/bin/sh /etc/rc';\nexec.stop = '/bin/sh \
/etc/rc.shutdown';\nexec.clean;\nmount.devfs;\nmount.fstab = \
${bastille_jail_fstab};\n\n${NAME} {\n\tip4.addr = ${IP};\n}" > \
${bastille_jail_conf}
fi

    ## using relative paths here
    ## MAKE SURE WE'RE IN THE RIGHT PLACE
    cd "${bastille_jail_path}"
    echo
    echo -e "${COLOR_GREEN}NAME: ${NAME}.${COLOR_RESET}"
    echo -e "${COLOR_GREEN}IP: ${IP}.${COLOR_RESET}"
    if [ ! -z  ${INTERFACE} ]; then
        echo -e "${COLOR_GREEN}INTERFACE: ${INTERFACE}.${COLOR_RESET}"
    fi
    echo -e "${COLOR_GREEN}RELEASE: ${RELEASE}.${COLOR_RESET}"
    echo

    for _link in bin boot lib libexec rescue sbin usr/bin usr/include usr/lib usr/lib32 usr/libdata usr/libexec usr/sbin usr/share usr/src; do
        ln -sf /.bastille/${_link} ${_link}
    done

    ## link home properly
    ln -s usr/home home

    ## rw
    cp -a "${bastille_releasesdir}/${RELEASE}/.cshrc" "${bastille_jail_path}"
    cp -a "${bastille_releasesdir}/${RELEASE}/.profile" "${bastille_jail_path}"
    cp -a "${bastille_releasesdir}/${RELEASE}/COPYRIGHT" "${bastille_jail_path}"
    cp -a "${bastille_releasesdir}/${RELEASE}/dev" "${bastille_jail_path}"
    cp -a "${bastille_releasesdir}/${RELEASE}/etc" "${bastille_jail_path}"
    cp -a "${bastille_releasesdir}/${RELEASE}/media" "${bastille_jail_path}"
    cp -a "${bastille_releasesdir}/${RELEASE}/mnt" "${bastille_jail_path}"
    if [ "${RELEASE}" == "11.2-RELEASE" ]; then cp -a "${bastille_releasesdir}/${RELEASE}/net" "${bastille_jail_path}"; fi
    cp -a "${bastille_releasesdir}/${RELEASE}/proc" "${bastille_jail_path}"
    cp -a "${bastille_releasesdir}/${RELEASE}/root" "${bastille_jail_path}"
    cp -a "${bastille_releasesdir}/${RELEASE}/tmp" "${bastille_jail_path}"
    cp -a "${bastille_releasesdir}/${RELEASE}/var" "${bastille_jail_path}"
    cp -a "${bastille_releasesdir}/${RELEASE}/usr/obj" "${bastille_jail_path}"
    if [ "${RELEASE}" == "11.2-RELEASE" ]; then cp -a "${bastille_releasesdir}/${RELEASE}/usr/tests" "${bastille_jail_path}"; fi

    ## rc.conf
    ##  + syslogd_flags="-ss"
    ##  + sendmail_none="NONE"
    ##  + cron_flags="-J 60" ## cedwards 20181118
    if [ ! -f "${bastille_jail_rc_conf}" ]; then
        touch "${bastille_jail_rc_conf}"
        /usr/sbin/sysrc -f "${bastille_jail_rc_conf}" syslogd_flags=-ss
        /usr/sbin/sysrc -f "${bastille_jail_rc_conf}" sendmail_enable=NONE
        /usr/sbin/sysrc -f "${bastille_jail_rc_conf}" cron_flags='-J 60'
        echo
    fi

    ## resolv.conf (default: copy from host)
    if [ ! -f "${bastille_jail_resolv_conf}" ]; then
        cp -L ${bastille_resolv_conf} ${bastille_jail_resolv_conf}
    fi

    ## TZ: configurable (default: etc/UTC)
    ln -s /usr/share/zoneinfo/${bastille_tzdata} etc/localtime
}

# Handle special-case commands first.
case "$1" in
help|-h|--help)
    usage
    ;;
esac

if [ $# -gt 4 ] || [ $# -lt 3 ]; then
    usage
fi

if [ $(echo $3 | grep '@' ) ]; then
    BASTILLE_JAIL_IP=$(echo $3 | awk -F@ '{print $2}')
    BASTILLE_JAIL_INTERFACES=$( echo $3 | awk -F@ '{print $1}')
fi

NAME="$1"
RELEASE="$2"
IP="$3"
INTERFACE="$4"

## verify release
case "${RELEASE}" in
*-RELEASE|*-release|*-RC1|*-rc1|*-RC2|*-rc2)
## check for FreeBSD releases name
NAME_VERIFY=$(echo "${RELEASE}" | grep -iwE '^([1-9]{2,2})\.[0-9](-RELEASE|-RC[1-2])$' | tr '[:lower:]' '[:upper:]')
if [ -n "${NAME_VERIFY}" ]; then
    RELEASE="${NAME_VERIFY}"
else
    usage
fi
    ;;
*-stable-LAST|*-STABLE-last|*-stable-last|*-STABLE-LAST)
## check for HardenedBSD releases name
NAME_VERIFY=$(echo "${RELEASE}" | grep -iwE '^([1-9]{2,2})(-stable-LAST|-STABLE-last|-stable-last|-STABLE-LAST)$' | sed 's/STABLE/stable/g' | sed 's/last/LAST/g')
if [ -n "${NAME_VERIFY}" ]; then
    RELEASE="${NAME_VERIFY}"
else
    usage
fi
    ;;
*)
    echo -e "${COLOR_RED}Unknown Release.${COLOR_RESET}"
    usage
    ;;
esac

## check for name/root/.bastille
if [ -d "${bastille_jailsdir}/${NAME}/root/.bastille" ]; then
    echo -e "${COLOR_RED}Jail: ${NAME} already created. ${NAME}/root/.bastille exists.${COLOR_RESET}"
    exit 1
fi

## check for required release
if [ ! -d "${bastille_releasesdir}/${RELEASE}" ]; then
    echo -e "${COLOR_RED}Release must be bootstrapped first; see `bastille bootstrap`.${COLOR_RESET}"
    exit 1
fi

## check if a running jail matches name
if running_jail ${NAME}; then
    echo -e "${COLOR_RED}A running jail matches name.${COLOR_RESET}"
    echo -e "${COLOR_RED}Jails must be stopped before they are destroyed.${COLOR_RESET}"
    exit 1
fi

## check if ip address is valid
if [ ! -z ${IP} ]; then
    validate_ip
else
    usage
fi

## check if interface is valid
if [ ! -z  ${INTERFACE} ]; then
    validate_netif
fi

create_jail ${NAME} ${RELEASE} ${IP} ${INTERFACE}
