#!/bin/bash

pushd ${ARTIFACTS_DIR}
wget -O astool.tgz https://dl.aerospike.com/artifacts/aerospike-tools/11.2.2/aerospike-tools_11.2.2_ubuntu24.04_x86_64.tgz
tar xvf astool.tgz
pushd aerospike-tools_11.2.2_ubuntu24.04_x86_64 && ./asinstall
