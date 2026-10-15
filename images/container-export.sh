#!/bin/bash

srun --container-image=${IMAGE_TO_DOWNLOAD} --container-save=${PATH_TO_SQFS_FILE} \
    echo "[${IMAGE_TO_DOWNLOAD}] downloaded to [${PATH_TO_SQFS_FILE}] successfully."