#!/bin/bash

#SBATCH --ntasks=1
#SBATCH --gpus-per-task=1
#SBATCH --cpus-per-gpu=32

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
export PROJECT_MOUNT=${PROJECT_DIRECTORY}:${PROJECT_DIRECTORY}

# Setup container info
export CONTAINER_MOUNTS=${PROJECT_MOUNT}
if [[ -n "${DORADO_SQFS_FILE}" && -f "${IMAGES_DIRECTORY}/${DORADO_SQFS_FILE}" ]]; then
	CONTAINER_IMAGE="${IMAGES_DIRECTORY}/${DORADO_SQFS_FILE}"
else
	CONTAINER_IMAGE="${DORADO_IMAGE}"
fi

# Get sample data
SAMPLE=$(awk -v ArrayTaskID=$SLURM_ARRAY_TASK_ID '$1==ArrayTaskID {print $2}' $SLURM_ARRAY_FILE)
SAMPLE_POD5=$(awk -v ArrayTaskID=$SLURM_ARRAY_TASK_ID '$1==ArrayTaskID {print $3}' $SLURM_ARRAY_FILE)
SAMPLE_POD5_DIRECTORY=${RUNS_DIRECTORY}/${SAMPLE_POD5}/pod5
SAMPLE_RESULTS_DIRECTORY=${RESULTS_DIRECTORY}/${SAMPLE}

# Run the container
srun -N${SLURM_NNODES} --ntasks=${SLURM_NPROCS} --gpus-per-task=${SLURM_GPUS_PER_TASK} --gpu-bind=none \
	--cpus-per-gpu=${SLURM_CPUS_PER_GPU} --output=${SAMPLE_RESULTS_DIRECTORY}/logs/dorado_basecaller_%a_%A.out \
	--container-writable --container-image=${CONTAINER_IMAGE} --container-mounts=${CONTAINER_MOUNTS} \
		bash -c "mkdir -p ${SAMPLE_RESULTS_DIRECTORY} && /usr/bin/dorado basecaller -v --emit-moves \
			hac,5mCG_5hmCG ${SAMPLE_POD5_DIRECTORY} \
			--reference ${REFERENCE_GENOME_FILE} \
			--models-directory ${SCRIPT_DIRECTORY}/models \
				> ${SAMPLE_RESULTS_DIRECTORY}/${RESULT_FILE_PREFIX}${SAMPLE}.aligned.bam"
