#!/bin/bash

set -e

function sleep_forever() {
    while [ 1 ]; do
        sleep 60
    done
}

CMD=${1:-install}

pwd
find . -type f

if [ "$CMD" == 'install' ]; then
    echo "Installing Gestalt platform... ('install' container argument specified)"

    SECONDS=0
    log=./install.log

    # Get a config map from the current namespace and write contents to local file
    kubectl get configmap install-data -ojsonpath='{.data.b64data}' | base64 -D > ./install-data.tar.gz

    # TODO: Test the file size, or check if the configmap didn't exist

    # If an install-data package was placed, overwrite the install directories on this image with them
    if [ -f ./install-data.tar.gz ]; then
        mkdir ./tmp
        tar xfzv ./install-data.tar.gz -C ./tmp 
        for d in scripts resource_templates gestalt-helm-chart ; do
            if [ -d ./tmp/$d ] ; then
                echo "Overwriting ./install/$d ..."
                rm -r ./install/$d
                cp -r ./tmp/$d ./install
                chmod +x ./install/$d/*.sh
            fi
        done
    fi

    echo "Initiating Gestalt platform installation at `date`" | tee -a $log

    ./install/scripts/install.sh $2 2>&1 | tee -a $log

    echo "Total elapsed time: $SECONDS seconds." | tee -a $log

    if [ "$2" == "debug" ]; then 
        echo "Debug was enabled, sleeping forever so container stays running..."
        sleep_forever
    fi
elif [ "$1" == 'sleep' ]; then
    echo "Sleep command asserted, sleeping forever so container stays running..."
    sleep_forever 
else
  echo "Skipping Gestalt installation ('install' container argument not specified)."
fi
