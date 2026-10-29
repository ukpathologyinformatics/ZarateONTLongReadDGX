#!/bin/bash

#SBATCH --ntasks=1
#SBATCH --cpus-per-task=64

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
if [[ -n "${MINIMAP2_SQFS_FILE}" && -f "${IMAGES_DIRECTORY}/${MINIMAP2_SQFS_FILE}" ]]; then
	CONTAINER_IMAGE="${IMAGES_DIRECTORY}/${MINIMAP2_SQFS_FILE}"
else
	CONTAINER_IMAGE="${MINIMAP2_IMAGE}"
fi

# Get sample data
SAMPLE=$(awk -v ArrayTaskID=$SLURM_ARRAY_TASK_ID '$1==ArrayTaskID {print $2}' $SLURM_ARRAY_FILE)
SAMPLE_DATA_DIRECTORY=$(awk -v ArrayTaskID=$SLURM_ARRAY_TASK_ID '$1==ArrayTaskID {print $3}' $SLURM_ARRAY_FILE)
SAMPLE_FASTQ_DIRECTORY=${RUNS_DIRECTORY}/${SAMPLE_DATA_DIRECTORY}/fastq_pass
SAMPLE_RESULTS_DIRECTORY=${RESULTS_DIRECTORY}/${SAMPLE}

# Run the container
srun -N${SLURM_NNODES} --ntasks=${SLURM_NPROCS} --cpus-per-task=${SLURM_CPUS_PER_TASK} \
	--output=${SAMPLE_RESULTS_DIRECTORY}/logs/minimap2_%a_%A.out \
	--container-writable --container-image=${CONTAINER_IMAGE} --container-mounts=${CONTAINER_MOUNTS} \
		bash -c "cat ${SAMPLE_FASTQ_DIRECTORY}/* | /usr/local/bin/minimap2 \
			-t ${SLURM_CPUS_PER_TASK} \
			-ax map-ont \
			-y \
			--cap-kalloc 100m \
			--cap-sw-mem 50m \
			${REFERENCE_GENOME_MMI_FILE} - \
				> ${SAMPLE_RESULTS_DIRECTORY}/${RESULT_FILE_PREFIX}${SAMPLE}.aligned.sam"

#		bash -c "apt update && apt install -y curl build-essential libbz2-dev liblzma-dev zlib1g-dev &&  \
#		curl -OL https://github.com/samtools/htslib/releases/download/${HTSLIB_VERSION}/htslib-${HTSLIB_VERSION}.tar.bz2 && \
#		tar -xf htslib-${HTSLIB_VERSION}.tar.bz2 && mv htslib-${HTSLIB_VERSION} htslib && \
#		curl -OL https://github.com/samtools/samtools/releases/download/${SAMTOOLS_VERSION}/samtools-${SAMTOOLS_VERSION}.tar.bz2 && \
#		tar -xf samtools-${SAMTOOLS_VERSION}.tar.bz2 && cd samtools-${SAMTOOLS_VERSION} && \
#		./configure --without-curses && make && make install && \
#			cat ${SAMPLE_FASTQ_DIRECTORY}/* | /usr/local/bin/minimap2 \
#				-t ${SLURM_CPUS_PER_TASK} \
#				-ax map-ont \
#				-y \
#				--cap-kalloc 100m \
#				--cap-sw-mem 50m \
#				${REFERENCE_GENOME_MMI_FILE} - | \
#					/usr/local/bin/samtools sort --write-index --threads ${SLURM_CPUS_PER_TASK} -o ${SAMPLE_RESULTS_DIRECTORY}/${RESULT_FILE_PREFIX}${SAMPLE}.aligned.bam - \
#						-o ${SAMPLE_RESULTS_DIRECTORY}/${RESULT_FILE_PREFIX}${SAMPLE}.aligned.bam"