#!/bin/sh

set +x
. /etc/sysconfig/heat-params
set -x

ssh_cmd="ssh -F /srv/magnum/.ssh/config root@localhost"


if [ -n "$INFRA_DNS_ZONE" ]; then
   $ssh_cmd sed -i "s/^search/search\ ${INFRA_DNS_ZONE}/g" /etc/resolv.conf
   $ssh_cmd echo DOMAIN=\"${INFRA_DNS_ZONE}\" >> /etc/sysconfig/network-scripts/ifcfg-eth0
fi

