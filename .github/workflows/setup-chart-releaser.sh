#!/bin/bash
#
# Setup chart releaser
# use latest version
#

BASURL="https://github.com/helm/chart-releaser/releases" &&
VER=$(curl -i "$BASURL/latest/download" |
    sed -n "s#^location: $BASURL/download/v\([^[:space:]]*\).*\$#\1#p"
    ) &&
[ ! -z "$VER" ] &&
curl -L $BASURL/download/v$VER/chart-releaser_${VER}_linux_amd64.tar.gz |
tar xvz cr &&
mv cr /usr/local/bin/cr &&
true || exit 1

exit 0
