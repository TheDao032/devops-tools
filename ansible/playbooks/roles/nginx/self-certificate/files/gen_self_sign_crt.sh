#!/usr/bin/env bash

set -e
SELF_SIGN_CRT_KEY_PATH=$1
SELF_SIGN_CRT_PATH=$2

CRT_SUBJECT="/C=VN/ST=Ho Chi Minh/L=Ho Chi Minh/O=Local Inc./CN=k3s.local.com"
CRT_VALID_DAYS=3650
NUMBITS=2048
# ALGORITHMS="-aes256"

sudo openssl genrsa -out ${SELF_SIGN_CRT_KEY_PATH} ${NUMBITS}
sudo openssl req -x509 -key ${SELF_SIGN_CRT_KEY_PATH} --subj "${CRT_SUBJECT}" -days ${CRT_VALID_DAYS} -out ${SELF_SIGN_CRT_PATH}

exit 0
