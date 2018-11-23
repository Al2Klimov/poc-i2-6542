#!/bin/bash

set -exo pipefail

perl -pi -e 'if (m~^//const NodeName\b~) { s~//~~; s/\blocalhost\b/$ENV{"NodeName"}/e }' /etc/icinga2/constants.conf

icinga2 daemon -C
icinga2 api setup

perl -pi -e 'if (/accept/) { s~//~~; s/false/true/ }' /etc/icinga2/features-available/api.conf

rm -vf /var/run/icinga2/icinga2.pid
exec icinga2 daemon
