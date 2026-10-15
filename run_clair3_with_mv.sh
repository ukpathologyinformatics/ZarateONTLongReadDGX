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
if [[ -n "${CLAIR3_SQFS_FILE}" && -f "${IMAGES_DIRECTORY}/${CLAIR3_SQFS_FILE}" ]]; then
	CONTAINER_IMAGE="${IMAGES_DIRECTORY}/${CLAIR3_SQFS_FILE}"
else
	CONTAINER_IMAGE="${CLAIR3_IMAGE}"
fi

# Get sample data
SAMPLE=$(awk -v ArrayTaskID=$SLURM_ARRAY_TASK_ID '$1==ArrayTaskID {print $2}' $SLURM_ARRAY_FILE)
SAMPLE_RESULTS_DIRECTORY=${RESULTS_DIRECTORY}/${SAMPLE}

# Run the container
srun -N${SLURM_NNODES} --ntasks=${SLURM_NPROCS} --gpus-per-task=${SLURM_GPUS_PER_TASK} --gpu-bind=none \
	--cpus-per-gpu=${SLURM_CPUS_PER_GPU} --output=${SAMPLE_RESULTS_DIRECTORY}/logs/clair3_%a_%A.out \
	--container-writable --container-image=${CONTAINER_IMAGE} --container-mounts=${CONTAINER_MOUNTS} \
		bash -c "mkdir -p ${SAMPLE_RESULTS_DIRECTORY}/clair3 && /opt/bin/run_clair3.sh \
    		--bam_fn=${SAMPLE_RESULTS_DIRECTORY}/${RESULT_FILE_PREFIX}${SAMPLE}.aligned.sorted.bam \
    		--ref_fn=${REFERENCE_GENOME_FILE} \
    		--threads=${SLURM_CPUS_PER_GPU} \
    		--platform=ont \
    		--enable_dwell_time \
    		--model_path=/opt/models/${CLAIR3_MODEL} \
    		--output=${SAMPLE_RESULTS_DIRECTORY}/clair3 \
    		--use_gpu \
    		--use_whatshap_for_final_output_phasing"
