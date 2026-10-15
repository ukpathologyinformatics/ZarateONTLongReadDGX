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
export PROJECT_MOUNT=${PROJECT_DIRECTORY}:${PROJECT_DIRECTORY}

# Setup container info
export CONTAINER_MOUNTS=${PROJECT_MOUNT}
if [[ -n "${SPECTRE_SQFS_FILE}" && -f "${IMAGES_DIRECTORY}/${SPECTRE_SQFS_FILE}" ]]; then
	CONTAINER_IMAGE="${IMAGES_DIRECTORY}/${SPECTRE_SQFS_FILE}"
else
	CONTAINER_IMAGE="${SPECTRE_IMAGE}"
fi

# Get sample data
SAMPLE=$(awk -v ArrayTaskID=$SLURM_ARRAY_TASK_ID '$1==ArrayTaskID {print $2}' $SLURM_ARRAY_FILE)
SAMPLE_RESULTS_DIRECTORY=${RESULTS_DIRECTORY}/${SAMPLE}

# Run the container
srun -N${SLURM_NNODES} --ntasks=${SLURM_NPROCS} --cpus-per-task=${SLURM_CPUS_PER_TASK} \
	--output=${SAMPLE_RESULTS_DIRECTORY}/logs/spectre_%a_%A.out \
    --container-writable --container-image=${CONTAINER_IMAGE} --container-mounts=${CONTAINER_MOUNTS} \
        bash -c "mkdir -p ${SAMPLE_RESULTS_DIRECTORY}/spectre && \
			/opt/custflow/epi2meuser/conda/bin/spectre CNVCaller \
				--bin-size ${BIN_SIZE} \
				--coverage ${SAMPLE_RESULTS_DIRECTORY}/mosdepth \
				--sample-id ${SAMPLE} \
				--output-dir ${SAMPLE_RESULTS_DIRECTORY}/spectre \
				--reference ${REFERENCE_GENOME_FILE} \
				--sn ${SAMPLE_RESULTS_DIRECTORY}/clair3/phased_merge_output.vcf.gz"