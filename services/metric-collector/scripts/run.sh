#!/bin/bash

python -m gunicorn main:prometheus -w 1 -k uvicorn.workers.UvicornWorker --timeout 0 --log-level=debug
