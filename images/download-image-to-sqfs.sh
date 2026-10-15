#!/bin/bash

usage() {
	echo "Usage: $0 -i <image_name> -o <output_sqfs_file>"
}

show_help() {
	echo "$0 : Download Docker image to SquashFS file foruse in Nanopore Long Read Sequencing Data Processing Pipeline" 1>&2
	echo "Required Parameters:" 1>&2
	echo "	-i <image_name> : Name of the image to download" 1>&2
	echo "	-o <output_sqfs_file> : Path to save .sqfs image file" 1>&2
}

check_args() {
	if [[ -z "${IMAGE_TO_DOWNLOAD}" ]]; then
		printf "ERROR: you must provide a Docker image to download (-i <image_name>)\n"
		usage
		exit 1
	fi
	check_image_name
	if [[ -z "${PATH_TO_SQFS_FILE}" ]]; then
		printf "ERROR: you must provide a path to save the .sqfs file (-o <output_sqfs_file>)\n"
		usage
		exit 1
	fi
	check_download_path
}

check_image_name() {
	ORIGINAL_IMAGE_NAME="${IMAGE_TO_DOWNLOAD}"
	separator="/"
	remaining="${IMAGE_TO_DOWNLOAD//[^$separator]}"
	count="${#remaining}"
	if [[ "${count}" == 2 ]]; then
		IMAGE_TO_DOWNLOAD="${IMAGE_TO_DOWNLOAD/\//\\#}"
	fi
}

check_download_path() {
	if [[ ! "${PATH_TO_SQFS_FILE}" == *.sqfs ]]; then
		PATH_TO_SQFS_FILE+=".sqfs"
	fi
	PATH_TO_SQFS_FILE=$(realpath "${PATH_TO_SQFS_FILE}")
}

submit_slurm_image_save_job() {
	PARTITIONS="--partition=${SLURM_PARTITIONS}"
	ACCOUNT="--account=${SLURM_ACCOUNT}"
	SAVE_SCRIPT="${SLURM_IMAGE_SAVE_SCRIPT}"
	EXPORTS="--export=IMAGE_TO_DOWNLOAD,PATH_TO_SQFS_FILE"
	echo "sbatch ${PARTITIONS} ${ACCOUNT} ${EXPORTS} ${SAVE_SCRIPT}"
	sbatch ${PARTITIONS} ${ACCOUNT} ${EXPORTS} ${SAVE_SCRIPT}
}

while getopts ":i:o:h" o; do
	case "${o}" in
		i) IMAGE_TO_DOWNLOAD="${OPTARG}" ;;
		o) PATH_TO_SQFS_FILE="${OPTARG}" ;;
		h)
			show_help
			exit 1
	esac
done
shift $((OPTIND-1))

check_args

source ../.env

export IMAGE_TO_DOWNLOAD
export PATH_TO_SQFS_FILE

echo "Downloading [${ORIGINAL_IMAGE_NAME}] to [${PATH_TO_SQFS_FILE}]"

submit_slurm_image_save_job