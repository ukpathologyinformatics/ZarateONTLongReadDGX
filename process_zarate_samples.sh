#!/bin/bash

#	UKHC Bioinformatics - DGX Cluster Processing of Nanopore Long Read Sequencing Data
#	Copyright (C) 2026 Caylin Hickey and Dr. Justin Miller
#
#	This script launches a pipeline to process long read sequencing data from the Nanopore
#	Sequencing Platform that process SNP/SNV, STR, SV, and Methylation results

usage() {
	echo "Usage: $0 -s <sample_id(s)> -p <[snp|snv|sv|str|cnv|methyl|all]> -o <output_folder>"
}

show_help() {
	echo "$0 : Run Nanopore Long Read Sequencing Data Processing Pipeline" 1>&2
	echo "Required Parameters:" 1>&2
	echo "	-s <sample_id(s)> : Comma-separated sample IDs (will be used as names for output folders)" 1>&2
	echo "	-p <task[,task...]> : Comma-separated task list (available: snp/snv, sv, str, cnv, methyl, all)" 1>&2
	#echo "Optional Parameters:" 1>&2
	#echo "	-o <output_folder> : Overrides the root output folder for processing results" 1>&2
}

check_args() {
	if [[ -z "${SAMPLE_IDS}" ]]; then
		printf "ERROR: you must supply comma-separated sample id(s) to process (-s <id>,<id>)\n"
		usage
		exit 1
	fi
	if [[ "${PROCESS_SNP}" == 0 && "${PROCESS_SV}" == 0 && "${PROCESS_STR}" == 0 && "${PROCESS_CNV}" == 0 && "${PROCESS_METHYL}" == 0 ]]; then
		printf "ERROR: you must select at least one process (-p}\n"
		usage
		exit 1
	fi
}

check_sample() {
	RUNS_DIR="/project/cdhick2_dgxzarate25/nanopore_runs"
	POD5_SUB_DIR=$(grep $1 zarate_samples.txt | awk '{ print $3 }')
	if [[ -z "${POD5_SUB_DIR}" ]]; then
		printf "ERROR: sample ${1} not found in records.\n"
		exit 1
	fi
	POD5_DIR="${RUNS_DIR}/${POD5_SUB_DIR}"
	if [[ ! -d $POD5_DIR ]]; then
		printf "ERROR: sample ${1} pod5 folder [${POD5_DIR}] does not exist.\n"
		exit 1
	fi
}

submit_slurm_job() {
	local SCRIPT="$1"
	local SAMPLES="$2"
	local PARTITIONS="--partition=$3"
	DEPENDENCIES=""
	for DEPENDENCY in "${@:4}"; do
		if [[ -z "${DEPENDENCIES}" ]]; then
			DEPENDENCIES+="--dependency aftercorr:${DEPENDENCY}"
		else
			DEPENDENCIES+=",aftercorr:${DEPENDENCY}"
		fi
	done
	ACCOUNT=""
	if [[ -n "${SLURM_ACCOUNT}" ]]; then
		ACCOUNT="--account=${SLURM_ACCOUNT}"
	fi
	OUTPUT="--output=${SLURM_LOGS_DIRECTORY}/slurm-%A_%a.out"
	export SCRIPT_DIRECTORY
	EXPORTS="--export=SCRIPT_DIRECTORY"
	# printf "sbatch --array ${SAMPLES} ${PARTITIONS} ${ACCOUNT} ${DEPENDENCIES} ${EXPORTS} ${OUTPUT} ${SCRIPT}\n" >&2
	echo $(sbatch --array ${SAMPLES} ${PARTITIONS} ${ACCOUNT} ${DEPENDENCIES} ${EXPORTS} ${OUTPUT} ${SCRIPT} | awk '{ print $4 }')
}

ORIGINAL_SAMPLE_IDS=""
SAMPLE_IDS=""
PROCESS_SNP=0
PROCESS_SV=0
PROCESS_STR=0
PROCESS_CNV=0
PROCESS_METHYL=0
OUTPUT_DIR=""

while getopts ":s:p:o:h" o; do
	case "${o}" in
		s)
			ORIGINAL_SAMPLE_IDS=$OPTARG
			IFS=',' read -ra IDS <<< "$OPTARG"
			for ID in "${IDS[@]}"; do
				check_sample $ID
				if [[ -z "${SAMPLE_IDS}" ]]; then
					SAMPLE_IDS+=$((10#$ID))
				else
					SAMPLE_IDS+=","
					SAMPLE_IDS+=$((10#$ID))
				fi
			done
		;;
		p)
			IFS=',' read -ra PROCESSES <<< "$OPTARG"
			for TO_PROCESS in "${PROCESSES[@]}"; do
				if [[ "${TO_PROCESS,,}" != "snv" && "${TO_PROCESS,,}" != "snp" && "${TO_PROCESS,,}" != "sv" && "${TO_PROCESS,,}" != "str" && "${TO_PROCESS,,}" != "cnv" && "${TO_PROCESS,,}" != "methyl" && "${TO_PROCESS,,}" != "all" ]]; then
					printf "ERROR: Invalid process supplied: ${TO_PROCESS}\n"
					usage
					exit 1
				fi
				if [[ "${TO_PROCESS,,}" == "snv" ]]; then
					PROCESS_SNP=1
				fi
				if [[ "${TO_PROCESS,,}" == "snp" ]]; then
					PROCESS_SNP=1
				fi
				if [[ "${TO_PROCESS,,}" == "sv" ]]; then
					PROCESS_SV=1
				fi
				if [[ "${TO_PROCESS,,}" == "str" ]]; then
					PROCESS_STR=1
				fi
				if [[ "${TO_PROCESS,,}" == "cnv" ]]; then
					PROCESS_CNV=1
				fi
				if [[ "${TO_PROCESS,,}" == "methyl" ]]; then
					PROCESS_METHYL=1
				fi
				if [[ "${TO_PROCESS,,}" == "all" ]]; then
					PROCESS_SNP=1
					PROCESS_SV=1
					PROCESS_STR=1
					PROCESS_CNV=1
					PROCESS_METHYL=1
				fi
			done
		;;
		o) OUTPUT_DIR="${OPTARG}" ;;
		h)
            show_help
            exit 1
	esac
done
shift $((OPTIND-1))

check_args

source .env

# Creating results output directories for sample(s)
IFS=',' read -ra SAMPLES <<< "$ORIGINAL_SAMPLE_IDS"
for SAMPLE in "${SAMPLES[@]}"; do
	echo "Creating output directories for sample: ${SAMPLE}"
	mkdir -p ${RESULTS_DIRECTORY}/${SAMPLE}/logs
done

SAMPLE_INDEX_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/${RESULT_FILE_PREFIX}${SAMPLE}.aligned.sorted.bam.bai"
SAMPLE_SORTED_BAM_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/${RESULT_FILE_PREFIX}${SAMPLE}.aligned.sorted.bam"
SAMPLE_ALIGNED_BAM_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/${RESULT_FILE_PREFIX}${SAMPLE}.aligned.bam"
SAMPLE_CLAIR3_PHASED_SNP_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/clair3/phased_merge_output.vcf.gz"

ALIGNMENT_JOB_ID=""
SORT_JOB_ID=""
INDEX_JOB_ID=""
CLAIR_JOB_ID=""

# Align .pod5 files, sort, and align (required by all sub-tasks)
if [[ ! -s "${SAMPLE_INDEX_FILE}" ]]; then
	echo "Index file not properly generated"
	if [[ ! -s "${SAMPLE_SORTED_BAM_FILE}" ]]; then
		echo "Sorted .bam file not properly generated"
		if [[ ! -s "${SAMPLE_ALIGNED_BAM_FILE}" ]]; then
			echo "Aligned .bam file not properly generated"
			echo "Run Dorado Basecaller alignment job"
			ALIGNMENT_JOB_ID=$(submit_slurm_job $DORADO_SCRIPT $SAMPLE_IDS $SLURM_GPU_PARTITIONS)
			echo "Run Samtools sort job"
			SORT_JOB_ID=$(submit_slurm_job $SAMTOOLS_SORT_SCRIPT $SAMPLE_IDS $SLURM_PARTITIONS $ALIGNMENT_JOB_ID)
			echo "Run Samtools index job"
			INDEX_JOB_ID=$(submit_slurm_job $SAMTOOLS_INDEX_SCRIPT $SAMPLE_IDS $SLURM_PARTITIONS $SORT_JOB_ID)
		else
			echo "Run Samtools sort job"
			SORT_JOB_ID=$(submit_slurm_job $SAMTOOLS_SORT_SCRIPT $SAMPLE_IDS $SLURM_PARTITIONS $ALIGNMENT_JOB_ID)
			echo "Run Samtools index job"
			INDEX_JOB_ID=$(submit_slurm_job $SAMTOOLS_INDEX_SCRIPT $SAMPLE_IDS $SLURM_PARTITIONS $SORT_JOB_ID)
		fi
	else
		echo "Run Samtools index job"
			INDEX_JOB_ID=$(submit_slurm_job $SAMTOOLS_INDEX_SCRIPT $SAMPLE_IDS $SLURM_PARTITIONS $SORT_JOB_ID)
	fi
fi

# SNPs are required by SNP, STR, and CNV pipelines
if [[ "${PROCESS_SNP}" == 1 || "${PROCESS_STR}" == 1 || "${PROCESS_CNV}" == 1 ]]; then
	if [[ ! -s "${SAMPLE_CLAIR3_PHASED_SNP_FILE}" ]]; then
		echo "Run Clair3 variant caller && phasing job"
		CLAIR_JOB_ID=$(submit_slurm_job $CLAIR3_SCRIPT $SAMPLE_IDS $SLURM_GPU_PARTITIONS $INDEX_JOB_ID)
	fi
	if [[ "${PROCESS_STR}" == 1 ]]; then
		echo "Run WhatsHap haplotag job"
		WHATSHAP_JOB_ID=$(submit_slurm_job $WHATSHAP_SCRIPT $SAMPLE_IDS $SLURM_GPU_PARTITIONS $CLAIR_JOB_ID)
		echo "Run Samtools haplotagged index job"
		HAPLOTAGGED_INDEX_JOB_ID=$(submit_slurm_job $SAMTOOLS_INDEX_HAPLOTAGGED_SCRIPT $SAMPLE_IDS $SLURM_PARTITIONS $WHATSHAP_JOB_ID)
		echo "Run Mahi Mahi job"
		MAHI_MAHI_JOB_ID=$(submit_slurm_job $MAHIMAHI_SCRIPT $SAMPLE_IDS $SLURM_PARTITIONS $HAPLOTAGGED_INDEX_JOB_ID)
	fi
	if [[ "${PROCESS_CNV}" == 1 ]]; then
		echo "Run MosDepth job"
		MOSDEPTH_JOB_ID=$(submit_slurm_job $MOSDEPTH_SCRIPT $SAMPLE_IDS $SLURM_PARTITIONS $INDEX_JOB_ID)
		echo "Run Spectre job"
		SPECTRE_JOB_ID=$(submit_slurm_job $SPECTRE_SCRIPT $SAMPLE_IDS $SLURM_PARTITIONS $CLAIR_JOB_ID $MOSDEPTH_JOB_ID)
	fi
fi
if [[ "${PROCESS_SV}" == 1 ]]; then
	echo "Run Sniffles job"
	SNIFFLES_JOB_ID=$(submit_slurm_job $SNIFFLES_SCRIPT $SAMPLE_IDS $SLURM_PARTITIONS $INDEX_JOB_ID)
	echo "Run needLR job"
	NEEDLR_JOB_ID=$(submit_slurm_job $NEEDLR_SCRIPT $SAMPLE_IDS $SLURM_LONG_PARTITIONS $SNIFFLES_JOB_ID)
fi
if [[ "${PROCESS_METHYL}" == 1 ]]; then
	echo "Run ModKit pileup job"
	MODKIT_JOB_ID=$(submit_slurm_job $MODKIT_PILEUP_SCRIPT $SAMPLE_IDS $SLURM_PARTITIONS $INDEX_JOB_ID)
fi