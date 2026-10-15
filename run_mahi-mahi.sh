#!/bin/bash

#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32

# Pull in environment variables
if [[ -n "${SCRIPT_DIRECTORY}" && -f "${SCRIPT_DIRECTORY}/.env" ]]; then
	echo "Pulling in environment variables from ${SCRIPT_DIRECTORY}/.env"
	source ${SCRIPT_DIRECTORY}/.env
else
	if [[ -f "${PWD}/.env" ]]; then
		echo "Pulling in environment variables from working directory ${PWD}/.env"
		source ${PWD}/.env
	else
		echo "WARNING: .env is missing from working directory, please generate it."
	fi
fi

# Setup container mounts
PROJECT_MOUNT=${PROJECT_DIRECTORY}:${PROJECT_DIRECTORY}

# Setup container info
CONTAINER_MOUNTS=${PROJECT_MOUNT}
if [[ -n "${MAHIMAHI_SQFS_FILE}" && -f "${IMAGES_DIRECTORY}/${MAHIMAHI_SQFS_FILE}" ]]; then
	CONTAINER_IMAGE="${IMAGES_DIRECTORY}/${MAHIMAHI_SQFS_FILE}"
else
	CONTAINER_IMAGE="${MAHIMAHI_IMAGE}"
fi

# Get sample data
SAMPLE=$(awk -v ArrayTaskID=$SLURM_ARRAY_TASK_ID '$1==ArrayTaskID {print $2}' $SLURM_ARRAY_FILE)
SAMPLE_SEX=$(awk -v ArrayTaskID=$SLURM_ARRAY_TASK_ID '$1==ArrayTaskID {print $4}' $SLURM_ARRAY_FILE)
SAMPLE_RESULTS_DIRECTORY=${RESULTS_DIRECTORY}/${SAMPLE}

MAHI_MAHI_WHL=${SQFS_IMAGES}/mahi_mahi-0.6.0-py3-none-any.whl

# Run the container
srun -N${SLURM_NNODES} --ntasks=${SLURM_NPROCS} --cpus-per-task=${SLURM_CPUS_PER_TASK} \
	--output=${SAMPLE_RESULTS_DIR}/logs/mahi-mahi_%a_%A.out \
	--container-writable --container-image=${CONTAINER_IMAGE} --container-mounts=${CONTAINER_MOUNTS} \
		bash -c "pip install -v ${MAHI_MAHI_WHL} && \
			/usr/local/bin/mahi-mahi \
        		--bam ${SAMPLE_RESULTS_DIRECTORY}/${RESULT_FILE_PREFIX}${SAMPLE}.haplotagged.bam \
        		--ref ${REFERENCE_GENOME_FILE} \
        		--sex ${SAMPLE_SEX} \
        		--loci hg38 \
        		--sample ${RESULT_FILE_PREFIX}${SAMPLE} \
        		--out-dir ${SAMPLE_RESULTS_DIRECTORY}/mahi-mahi"
