#!/bin/bash

#SBATCH --partition=h200
#SBATCH --account=cdhick2_dgxzarate25
#SBATCH --ntasks=1

# Setup directory path shortcuts
export PROJECT_DIR=/project/cdhick2_dgxzarate25
export REFERENCES_DIR=${PROJECT_DIR}/nanopore_references
export RUNS_DIR=${PROJECT_DIR}/nanopore_runs
export RESULTS_DIR=${PROJECT_DIR}/nanopore_dgx_processing
export NSLURM_DIR=${PROJECT_DIR}/nanopore_scripts
export SQFS_IMAGES=${NSLURM_DIR}/images

# Setup container mounts
export PROJECT_MOUNT=${PROJECT_DIR}:${PROJECT_DIR}

# Setup container info
#export CONTAINER_IMAGE=nanoporetech/dorado
export CONTAINER_IMAGE=${SQFS_IMAGES}/nanoporetech_dorado-2.1.1.sqfs
export CONTAINER_MOUNTS=${PROJECT_MOUNT}

#srun -N${SLURM_NNODES} --ntasks=${SLURM_NPROCS} --gpus-per-task=${SLURM_GPUS_PER_TASK} --gpu-bind=none --cpus-per-gpu=${SLURM_CPUS_PER_GPU} \
srun -N${SLURM_NNODES} --ntasks=${SLURM_NPROCS} \
	--container-image=${CONTAINER_IMAGE} --container-mounts=${CONTAINER_MOUNTS} \
	/usr/bin/dorado download -v --model all --models-directory ${NSLURM_DIR}/models 
