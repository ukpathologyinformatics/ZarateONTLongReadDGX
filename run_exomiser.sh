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
if [[ -n "${EXOMISER_SQFS_FILE}" && -f "${IMAGES_DIRECTORY}/${EXOMISER_SQFS_FILE}" ]]; then
	CONTAINER_IMAGE="${IMAGES_DIRECTORY}/${EXOMISER_SQFS_FILE}"
else
	CONTAINER_IMAGE="${EXOMISER_IMAGE}"
fi

# Get sample data
SAMPLE=$(awk -v ArrayTaskID=$SLURM_ARRAY_TASK_ID '$1==ArrayTaskID {print $2}' $SLURM_ARRAY_FILE)
SAMPLE_SEX=$(awk -v ArrayTaskID=$SLURM_ARRAY_TASK_ID '$1==ArrayTaskID {print $4}' $SLURM_ARRAY_FILE)
SAMPLE_SEX_STRING="F"
if [[ "$SAMPLE_SEX" -eq "XY" ]]; then
	SAMPLE_SEX_STRING="M"
fi
SAMPLE_HPO_TERMS=$(awk -v ArrayTaskID=$SLURM_ARRAY_TASK_ID '$1==ArrayTaskID {print $5}' $SLURM_ARRAY_FILE)
SAMPLE_RESULTS_DIRECTORY=${RESULTS_DIRECTORY}/${SAMPLE}

# Run the container
srun -N${SLURM_NNODES} --ntasks=${SLURM_NPROCS} --cpus-per-task=${SLURM_CPUS_PER_TASK} \
	--output=${SAMPLE_RESULTS_DIRECTORY}/logs/exomiser_%a_%A.out \
    --container-writable --container-image=${CONTAINER_IMAGE} --container-mounts=${CONTAINER_MOUNTS} \
        bash -c "mkdir -p ${SAMPLE_RESULTS_DIRECTORY}/exomiser && \
			python3 ${EXOMISER_YAML_GEN_SCRIPT} \
				-s ${SAMPLE} \
				-v ${SAMPLE_RESULTS_DIRECTORY}/clair3/phased_merge_output.vcf.gz \
				-o ${SAMPLE_RESULTS_DIRECTORY}/exomiser -h ${SAMPLE_HPO_TERMS} && \
			/usr/local/openjdk-28/bin/java -Dspring.config.location=${EXOMISER_RUN_DIR}/application.properties \
				-jar ${EXOMISER_RUN_DIR}/${EXOMISER_JAR_FILE} analyse \
					--analysis ${SAMPLE_RESULTS_DIRECTORY}/exomiser/exomiser.yml && \
		    /usr/local/openjdk-28/bin/java -Dspring.config.location=${EXOMISER_RUN_DIR}/application.properties \
				-jar ${EXOMISER_RUN_DIR}/${EXOMISER_JAR_FILE} analyse \
					--analysis ${SAMPLE_RESULTS_DIRECTORY}/exomiser/genomiser.yml"