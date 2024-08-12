#!/usr/bin/env bash
PSQL_REPMGR_CONFIG_PATH=$1

repmgr -f ${PSQL_REPMGR_CONFIG_PATH} primary register
