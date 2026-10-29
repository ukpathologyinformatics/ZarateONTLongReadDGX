#!/bin/bash

#	UKHC Bioinformatics - DGX Cluster Processing of Nanopore Long Read Sequencing Data
#	Copyright (C) 2026 Caylin Hickey and Dr. Justin Miller
#
#	This script launches a pipeline to process long read sequencing data from the Nanopore
#	Sequencing Platform that process SNP/SNV, STR, SV, CNV, and Methylation results

# Pull in configuration environment variables
source .env

usage() {
	echo "Usage: $0 [-n] [-v] -s <sample_id(s)> -p <[snp|snv|sv|str|cnv|methyl|all]>"
}

show_help() {
	echo "$0 : Run Nanopore Long Read Sequencing Data Processing Pipeline" 1>&2
	echo "Required Parameters:" 1>&2
	echo "	-s <sample_id(s)> : Comma-separated sample IDs (will be used as names for output folders)" 1>&2
	echo "	-p <task[,task...]> : Comma-separated task list (available: snp/snv, sv, str, cnv, methyl, all)" 1>&2
	echo "Optional Parameters:" 1>&2
	echo "	-n : Perform a dry run of the script to see what changes and jobs will be run" 1>&2
	echo "  -f : Allow fastq_pass to be used if pod5 directory does not exist" 1>&2
	echo "	-v : Run with verbose logging" 1>&2
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
	DATA_SUB_DIRECTORY=$(grep $1 $SLURM_ARRAY_FILE | awk '{ print $3 }')
	POD5_DIRECTORY="${RUNS_DIRECTORY}/${DATA_SUB_DIRECTORY}/pod5"
	FASTQ_DIRECTORY="${RUNS_DIRECTORY}/${DATA_SUB_DIRECTORY}/fastq_pass"
	if [[ -z "${POD5_DIRECTORY}" && -z "${FASTQ_DIRECTORY}" ]]; then
		printf "WARNING: sample ${1} not found in records, skipping.\n" >&2
		echo ""
	else
		if [[ ! -d $POD5_DIRECTORY ]]; then
			if [[ $ALLOW_FASTQ == 1 ]]; then
				printf "INFO: sample ${1} pod5 directory [${POD5_DIRECTORY}] does not exist, using fastq_pass directory [${FASTQ_DIRECTORY}] instead.\n" >&2 
				echo $FASTQ_DIRECTORY
			else
				printf "WARNING: sample ${1} pod5 directory [${POD5_DIRECTORY}] does not exist, skipping.\n" >&2
				echo ""
			fi
		else
			echo $POD5_DIRECTORY
		fi
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
	if [[ $VERBOSE == 1 ]]; then
		printf "SBATCH Command: sbatch --array ${SAMPLES} ${PARTITIONS} ${ACCOUNT} ${DEPENDENCIES} ${EXPORTS} ${OUTPUT} ${SCRIPT}\n" >&2
	fi
	echo $(sbatch --array ${SAMPLES} ${PARTITIONS} ${ACCOUNT} ${DEPENDENCIES} ${EXPORTS} ${OUTPUT} ${SCRIPT} | awk '{ print $4 }')
}

ORIGINAL_SAMPLE_IDS=""
SAMPLE_IDS=""
PROCESS_SNP=0
PROCESS_SV=0
PROCESS_STR=0
PROCESS_CNV=0
PROCESS_METHYL=0
ALLOW_FASTQ=0
DRYRUN=0
VERBOSE=0

while getopts ":s:p:o:fhnv" o; do
	case "${o}" in
		s)
			ORIGINAL_SAMPLE_IDS=$OPTARG
			IFS=',' read -ra IDS <<< "$OPTARG"
			for ID in "${IDS[@]}"; do
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
		f) ALLOW_FASTQ=1 ;;
		n) DRYRUN=1 ;;
		v) VERBOSE=1 ;;
		h)
            show_help
            exit 1
	esac
done
shift $((OPTIND-1))

check_args

if [[ $DRYRUN == 1 ]]; then
	echo "Performing a dry run, no changes will be made or Slurm jobs run."
fi

if [[ $VERBOSE == 1 ]]; then
	echo "PROCESS_SNP = ${PROCESS_SNP}"
	echo "PROCESS_SV = ${PROCESS_SV}"
	echo "PROCESS_STR = ${PROCESS_STR}"
	echo "PROCESS_CNV = ${PROCESS_CNV}"
	echo "PROCESS_METHYL = ${PROCESS_METHYL}"
fi

POD5_ALIGNMENT_JOB_SAMPLES=""
FASTQ_ALIGNMENT_JOB_SAMPLES=""
SORT_JOB_SAMPLES=""
INDEX_JOB_SAMPLES=""

CLAIR3_MV_JOB_SAMPLES=""
CLAIR3_JOB_SAMPLES=""

WHATSHAP_JOB_SAMPLES=""
HAPLOTAGGED_INDEX_JOB_SAMPLES=""
MAHI_MAHI_JOB_SAMPLES=""

MOSDEPTH_JOB_SAMPLES=""
SPECTRE_JOB_SAMPLES=""

SNIFFLES_JOB_SAMPLES=""
NEEDLR_JOB_SAMPLES=""

MODKIT_PILEUP_JOB_SAMPLES=""

# Discovering per-sample needed tasks
IFS=',' read -ra SAMPLES <<< "$ORIGINAL_SAMPLE_IDS"
IFS=',' read -ra ARRAY_IDS <<< "$SAMPLE_IDS"
for i in "${!SAMPLES[@]}"; do
	SAMPLE="${SAMPLES[$i]}"
	SAMPLE_DATA_FILES=$(check_sample $SAMPLE)
	if [[ -z $SAMPLE_DATA_FILES ]]; then
		continue
	fi
	ARRAY_ID="${ARRAY_IDS[$i]}"
	# Creating output directories
	if [[ ! -d "${RESULTS_DIRECTORY}/${SAMPLE}" ]]; then
		echo "Creating output directories for sample [${SAMPLE}]: ${RESULTS_DIRECTORY}/${SAMPLE} and ${RESULTS_DIRECTORY}/${SAMPLE}/logs"
		if [[ $DRYRUN == 0 ]]; then
			mkdir -p ${RESULTS_DIRECTORY}/${SAMPLE}/logs
		fi
	fi
	# Checking if sample needs secondary analysis
	SAMPLE_ALIGNED_BAM_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/${RESULT_FILE_PREFIX}${SAMPLE}.aligned.bam"
	SAMPLE_SORTED_BAM_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/${RESULT_FILE_PREFIX}${SAMPLE}.aligned.sorted.bam"
	SAMPLE_INDEX_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/${RESULT_FILE_PREFIX}${SAMPLE}.aligned.sorted.bam.bai"
	if [[ ! -s "${SAMPLE_INDEX_FILE}" ]]; then
		# Sorted .bai index does not exist
		if [[ ! -s "${SAMPLE_SORTED_BAM_FILE}" ]]; then
			# Sorted .bam file does not exist
			if [[ ! -s "${SAMPLE_ALIGNED_BAM_FILE}" ]]; then
				# Aligned .bam file does not exist
				if [[ "${SAMPLE_DATA_FILES}" == *pod5 ]]; then
					if [[ -n "${POD5_ALIGNMENT_JOB_SAMPLES}" ]]; then
						POD5_ALIGNMENT_JOB_SAMPLES+=","
					fi
					POD5_ALIGNMENT_JOB_SAMPLES+="${ARRAY_ID}"
				else
					if [[ -n "${FASTQ_ALIGNMENT_JOB_SAMPLES}" ]]; then
						FASTQ_ALIGNMENT_JOB_SAMPLES+=","
					fi
					FASTQ_ALIGNMENT_JOB_SAMPLES+="${ARRAY_ID}"
				fi
				if [[ -n "${SORT_JOB_SAMPLES}" ]]; then
					SORT_JOB_SAMPLES+=","
				fi
				SORT_JOB_SAMPLES+="${ARRAY_ID}"
				if [[ -n "${INDEX_JOB_SAMPLES}" ]]; then
					INDEX_JOB_SAMPLES+=","
				fi
				INDEX_JOB_SAMPLES+="${ARRAY_ID}"
			else
				# Aligned .bam file exists
				if [[ -n "${SORT_JOB_SAMPLES}" ]]; then
					SORT_JOB_SAMPLES+=","
				fi
				SORT_JOB_SAMPLES+="${ARRAY_ID}"
				if [[ -n "${INDEX_JOB_SAMPLES}" ]]; then
					INDEX_JOB_SAMPLES+=","
				fi
				INDEX_JOB_SAMPLES+="${ARRAY_ID}"
			fi
		else
			# Sorted .bam file exists
			if [[ -n "${INDEX_JOB_SAMPLES}" ]]; then
				INDEX_JOB_SAMPLES+=","
			fi
			INDEX_JOB_SAMPLES+="${ARRAY_ID}"
		fi
	fi
	# Checking if pipeline needs Clair3 step
	if [[ "${PROCESS_SNP}" == 1 || "${PROCESS_STR}" == 1 || "${PROCESS_CNV}" == 1 ]]; then
		SAMPLE_CLAIR3_PHASED_SNP_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/clair3/phased_merge_output.vcf.gz"
		if [[ ! -s "${SAMPLE_CLAIR3_PHASED_SNP_FILE}" ]]; then
			# Clair3 SNP file does not exist
			if [[ "${SAMPLE_DATA_FILES}" == *pod5 ]]; then
				if [[ -n "${CLAIR3_MV_JOB_SAMPLES}" ]]; then
					CLAIR3_MV_JOB_SAMPLES+=","
				fi
				CLAIR3_MV_JOB_SAMPLES+="${ARRAY_ID}"
			else
				if [[ -n "${CLAIR3_JOB_SAMPLES}" ]]; then
					CLAIR3_JOB_SAMPLES+=","
				fi
				CLAIR3_JOB_SAMPLES+="${ARRAY_ID}"
			fi
		fi
		if [[ "${PROCESS_STR}" == 1 ]]; then
			SAMPLE_WHATSHAP_HAPLOTAGGED_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/${RESULT_FILE_PREFIX}${SAMPLE}.haplotagged.bam"
			SAMPLE_HAPLOTAGGED_INDEX_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/${RESULT_FILE_PREFIX}${SAMPLE}.haplotagged.bam.bai"
			SAMPLE_MAHI_MAHI_STR_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/mahi-mahi/${RESULT_FILE_PREFIX}${SAMPLE}.tsv"
			if [[ ! -s "${SAMPLE_MAHI_MAHI_STR_FILE}" ]]; then
				# Mahi Mahi .tsv does not exist
				if [[ ! -s "${SAMPLE_HAPLOTAGGED_INDEX_FILE}" ]]; then
					# .haplotagged.bam.bai file does not exist
					if [[ ! -s "${SAMPLE_WHATSHAP_HAPLOTAGGED_FILE}" ]]; then
						# .haplotagged.bam file does not exist
						if [[ -n "${WHATSHAP_JOB_SAMPLES}" ]]; then
							WHATSHAP_JOB_SAMPLES+=","
						fi
						WHATSHAP_JOB_SAMPLES+="${ARRAY_ID}"
						if [[ -n "${HAPLOTAGGED_INDEX_JOB_SAMPLES}" ]]; then
							HAPLOTAGGED_INDEX_JOB_SAMPLES+=","
						fi
						HAPLOTAGGED_INDEX_JOB_SAMPLES+="${ARRAY_ID}"
						if [[ -n "${MAHI_MAHI_JOB_SAMPLES}" ]]; then
							MAHI_MAHI_JOB_SAMPLES+=","
						fi
						MAHI_MAHI_JOB_SAMPLES+="${ARRAY_ID}"
					else
						# .haplotagged.bam file exists
						if [[ -n "${HAPLOTAGGED_INDEX_JOB_SAMPLES}" ]]; then
							HAPLOTAGGED_INDEX_JOB_SAMPLES+=","
						fi
						HAPLOTAGGED_INDEX_JOB_SAMPLES+="${ARRAY_ID}"
						if [[ -n "${MAHI_MAHI_JOB_SAMPLES}" ]]; then
							MAHI_MAHI_JOB_SAMPLES+=","
						fi
						MAHI_MAHI_JOB_SAMPLES+="${ARRAY_ID}"
					fi
				else
					# Mahi Mahi .tsv file file
					if [[ -n "${MAHI_MAHI_JOB_SAMPLES}" ]]; then
						MAHI_MAHI_JOB_SAMPLES+=","
					fi
					MAHI_MAHI_JOB_SAMPLES+="${ARRAY_ID}"
				fi
			fi
		fi
		if [[ "${PROCESS_CNV}" == 1 ]]; then
			SAMPLE_MOSDEPTH_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/mosdepth/${RESULT_FILE_PREFIX}${SAMPLE}.regions.bed.gz"
			SAMPLE_SPECTRE_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/spectre/${SAMPLE}_cnv.bed"
			if [[ ! -s "${SAMPLE_SPECTRE_FILE}" ]]; then
				# Spectre CNV file does not exist
				if [[ ! -s "${SAMPLE_MOSDEPTH_FILE}" ]]; then
					# MosDepth regions file does not exist
					if [[ -n "${MOSDEPTH_JOB_SAMPLES}" ]]; then
						MOSDEPTH_JOB_SAMPLES+=","
					fi
					MOSDEPTH_JOB_SAMPLES+="${ARRAY_ID}"
					if [[ -n "${SPECTRE_JOB_SAMPLES}" ]]; then
						SPECTRE_JOB_SAMPLES+=","
					fi
					SPECTRE_JOB_SAMPLES+="${ARRAY_ID}"
				else
					# MosDepth regions file exists
					if [[ -n "${SPECTRE_JOB_SAMPLES}" ]]; then
						SPECTRE_JOB_SAMPLES+=","
					fi
					SPECTRE_JOB_SAMPLES+="${ARRAY_ID}"
				fi
			fi
		fi
	fi
	if [[ "${PROCESS_SV}" == 1 ]]; then
		SAMPLE_SNIFFLES_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/${RESULT_FILE_PREFIX}${SAMPLE}.sniffles.vcf.gz"
		SAMPLE_NEEDLR_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/needLR/${RESULT_FILE_PREFIX}${SAMPLE}.sniffles_needLR_1kg_v4.0/${RESULT_FILE_PREFIX}${SAMPLE}.sniffles.needLR.4.0_RESULTS.tsv"
		if [[ ! -s "${SAMPLE_NEEDLR_FILE}" ]]; then
			# needLR SV file does not exist
			if [[ ! -s "${SAMPLE_SNIFFLES_FILE}" ]]; then
				# sniffles file does not exist
				if [[ -n "${SNIFFLES_JOB_SAMPLES}" ]]; then
					SNIFFLES_JOB_SAMPLES+=","
				fi
				SNIFFLES_JOB_SAMPLES+="${ARRAY_ID}"
				if [[ -n "${NEEDLR_JOB_SAMPLES}" ]]; then
					NEEDLR_JOB_SAMPLES+=","
				fi
				NEEDLR_JOB_SAMPLES+="${ARRAY_ID}"
			else
				# sniffles file exists
				if [[ -n "${NEEDLR_JOB_SAMPLES}" ]]; then
					NEEDLR_JOB_SAMPLES+=","
				fi
				NEEDLR_JOB_SAMPLES+="${ARRAY_ID}"
			fi
		fi
	fi
	if [[ "${PROCESS_METHYL}" == 1 ]]; then
		SAMPLE_MODKIT_PILEUP_FILE="${RESULTS_DIRECTORY}/${SAMPLE}/${RESULT_FILE_PREFIX}${SAMPLE}.pileup.methyl.bed.gz"
		if [[ ! -s "${SAMPLE_MODKIT_PILEUP_FILE}" ]]; then
			# Modkit pileup file does not exist
			if [[ "${SAMPLE_DATA_FILES}" == *pod5 ]]; then
				if [[ -n "${MODKIT_PILEUP_JOB_SAMPLES}" ]]; then
					MODKIT_PILEUP_JOB_SAMPLES+=","
				fi
				MODKIT_PILEUP_JOB_SAMPLES+="${ARRAY_ID}"
			else
				printf "WARNING: sample ${SAMPLE} only has .fastq.gz files which may not contain 'mv' tags, skipping methylation.\n" >&2
			fi
		fi
	fi
done

if [[ $VERBOSE == 1 ]]; then
	echo "POD5_ALIGNMENT_JOB_SAMPLES = ${POD5_ALIGNMENT_JOB_SAMPLES}"
	echo "FASTQ_ALIGNMENT_JOB_SAMPLES = ${FASTQ_ALIGNMENT_JOB_SAMPLES}"
	echo "SORT_JOB_SAMPLES = ${SORT_JOB_SAMPLES}"
	echo "INDEX_JOB_SAMPLES = ${INDEX_JOB_SAMPLES}"
	if [[ "${PROCESS_SNP}" == 1 || "${PROCESS_STR}" == 1 || "${PROCESS_CNV}" == 1 ]]; then
		echo "CLAIR3_MV_JOB_SAMPLES = ${CLAIR3_MV_JOB_SAMPLES}"
		echo "CLAIR3_JOB_SAMPLES = ${CLAIR3_JOB_SAMPLES}"
		if [[ "${PROCESS_STR}" == 1 ]]; then
			echo "WHATSHAP_JOB_SAMPLES = ${WHATSHAP_JOB_SAMPLES}"
			echo "HAPLOTAGGED_INDEX_JOB_SAMPLES = ${HAPLOTAGGED_INDEX_JOB_SAMPLES}"
			echo "MAHI_MAHI_JOB_SAMPLES = ${MAHI_MAHI_JOB_SAMPLES}"
		fi
		if [[ "${PROCESS_CNV}" == 1 ]]; then
			echo "MOSDEPTH_JOB_SAMPLES = ${MOSDEPTH_JOB_SAMPLES}"
			echo "SPECTRE_JOB_SAMPLES = ${SPECTRE_JOB_SAMPLES}"
		fi
	fi
	if [[ "${PROCESS_SV}" == 1 ]]; then
		echo "SNIFFLES_JOB_SAMPLES = ${SNIFFLES_JOB_SAMPLES}"
		echo "NEEDLR_JOB_SAMPLES = ${NEEDLR_JOB_SAMPLES}"
	fi
	if [[ "${PROCESS_METHYL}" == 1 ]]; then
		echo "MODKIT_PILEUP_JOB_SAMPLES = ${MODKIT_PILEUP_JOB_SAMPLES}"
	fi
fi

POD5_ALIGNMENT_JOB_ID=""
FASTQ_ALIGNMENT_JOB_ID=""
VIEW_JOB_ID=""
SORT_JOB_ID=""
INDEX_JOB_ID=""
CLAIR3_MV_JOB_ID=""
CLAIR3_JOB_ID=""
WHATSHAP_JOB_ID=""
HAPLOTAGGED_INDEX_JOB_ID=""
MAHI_MAHI_JOB_ID=""
MOSDEPTH_JOB_ID=""
SPECTRE_JOB_ID=""
SNIFFLES_JOB_ID=""
NEEDLR_JOB_ID=""
MODKIT_JOB_ID=""

if [[ -n "${POD5_ALIGNMENT_JOB_SAMPLES}" ]]; then
	echo "Running Dorado basecaller alignment job on sample array indices: ${POD5_ALIGNMENT_JOB_SAMPLES}"
	if [[ $DRYRUN == 0 ]]; then
		POD5_ALIGNMENT_JOB_ID=$(submit_slurm_job $DORADO_SCRIPT $POD5_ALIGNMENT_JOB_SAMPLES $SLURM_GPU_PARTITIONS)
	else
		echo "POD5_ALIGNMENT_JOB_ID=\$(submit_slurm_job $DORADO_SCRIPT $POD5_ALIGNMENT_JOB_SAMPLES $SLURM_GPU_PARTITIONS)"
	fi
fi
if [[ -n "${FASTQ_ALIGNMENT_JOB_SAMPLES}" ]]; then
	echo "Running Minimap2 alignment and Samtools view jobs on sample array indices: ${FASTQ_ALIGNMENT_JOB_SAMPLES}"
	if [[ $DRYRUN == 0 ]]; then
		FASTQ_ALIGNMENT_JOB_ID=$(submit_slurm_job $MINIMAP2_SCRIPT $FASTQ_ALIGNMENT_JOB_SAMPLES $SLURM_PARTITIONS)
		VIEW_JOB_ID=$(submit_slurm_job $SAMTOOLS_VIEW_SCRIPT $FASTQ_ALIGNMENT_JOB_SAMPLES $SLURM_PARTITIONS $FASTQ_ALIGNMENT_JOB_ID)
	else
		echo "FASTQ_ALIGNMENT_JOB_ID=\$(submit_slurm_job $MINIMAP2_SCRIPT $FASTQ_ALIGNMENT_JOB_SAMPLES $SLURM_PARTITIONS)"
		echo "VIEW_JOB_ID=\$(submit_slurm_job $SAMTOOLS_VIEW_SCRIPT $FASTQ_ALIGNMENT_JOB_SAMPLES $SLURM_PARTITIONS $FASTQ_ALIGNMENT_JOB_ID)"
	fi
fi
if [[ -n "${SORT_JOB_SAMPLES}" ]]; then
	echo "Running samtools sort job on sample array indices: ${SORT_JOB_SAMPLES}"
	if [[ $DRYRUN == 0 ]]; then
		SORT_JOB_ID=$(submit_slurm_job $SAMTOOLS_SORT_SCRIPT $SORT_JOB_SAMPLES $SLURM_PARTITIONS $POD5_ALIGNMENT_JOB_ID $VIEW_JOB_ID)
	else
		echo "SORT_JOB_ID=\$(submit_slurm_job $SAMTOOLS_SORT_SCRIPT $SORT_JOB_SAMPLES $SLURM_PARTITIONS $ALIGNMENT_JOB_ID)"
	fi
fi
if [[ -n "${INDEX_JOB_SAMPLES}" ]]; then
	echo "Running samtools index job on sample array indices: ${INDEX_JOB_SAMPLES}"
	if [[ $DRYRUN == 0 ]]; then
		INDEX_JOB_ID=$(submit_slurm_job $SAMTOOLS_INDEX_SCRIPT $INDEX_JOB_SAMPLES $SLURM_PARTITIONS $SORT_JOB_ID)
	else
		echo "INDEX_JOB_ID=\$(submit_slurm_job $SAMTOOLS_INDEX_SCRIPT $INDEX_JOB_SAMPLES $SLURM_PARTITIONS $SORT_JOB_ID)"
	fi
fi
if [[ -n "${CLAIR3_JOB_SAMPLES}" ]]; then
	echo "Running Clair3 SNP calling job on sample array indices: ${CLAIR3_JOB_SAMPLES}"
	if [[ $DRYRUN == 0 ]]; then
		CLAIR3_JOB_ID=$(submit_slurm_job $CLAIR3_SCRIPT $CLAIR3_JOB_SAMPLES $SLURM_GPU_PARTITIONS $INDEX_JOB_ID)
	else
		echo "CLAIR3_JOB_ID=\$(submit_slurm_job $CLAIR3_SCRIPT $CLAIR3_JOB_SAMPLES $SLURM_GPU_PARTITIONS $INDEX_JOB_ID)"
	fi
fi
if [[ -n "${CLAIR3_MV_JOB_SAMPLES}" ]]; then
	echo "Running Clair3 SNP (with mv) calling job on sample array indices: ${CLAIR3_MV_JOB_SAMPLES}"
	if [[ $DRYRUN == 0 ]]; then
		CLAIR3_MV_JOB_ID=$(submit_slurm_job $CLAIR3_MV_SCRIPT $CLAIR3_MV_JOB_SAMPLES $SLURM_GPU_PARTITIONS $INDEX_JOB_ID)
	else
		echo "CLAIR3_MV_JOB_ID=\$(submit_slurm_job $CLAIR3_MV_SCRIPT $CLAIR3_MV_JOB_SAMPLES $SLURM_GPU_PARTITIONS $INDEX_JOB_ID)"
	fi
fi
if [[ -n "${WHATSHAP_JOB_SAMPLES}" ]]; then
	echo "Running WhatsHap haplotagging job on sample array indices: ${WHATSHAP_JOB_SAMPLES}"
	if [[ $DRYRUN == 0 ]]; then
		WHATSHAP_JOB_ID=$(submit_slurm_job $WHATSHAP_SCRIPT $WHATSHAP_JOB_SAMPLES $SLURM_GPU_PARTITIONS $CLAIR_JOB_ID $CLAIR3_MV_JOB_ID)
	else
		echo "WHATSHAP_JOB_ID=\$(submit_slurm_job $WHATSHAP_SCRIPT $WHATSHAP_JOB_SAMPLES $SLURM_GPU_PARTITIONS $CLAIR_JOB_ID $CLAIR3_MV_JOB_ID)"
	fi
fi
if [[ -n "${HAPLOTAGGED_INDEX_JOB_SAMPLES}" ]]; then
	echo "Running haplotagged bam indexing job on sample array indices: ${HAPLOTAGGED_INDEX_JOB_SAMPLES}"
	if [[ $DRYRUN == 0 ]]; then
		HAPLOTAGGED_INDEX_JOB_ID=$(submit_slurm_job $SAMTOOLS_INDEX_HAPLOTAGGED_SCRIPT $HAPLOTAGGED_INDEX_JOB_SAMPLES $SLURM_PARTITIONS $WHATSHAP_JOB_ID)
	else
		echo "HAPLOTAGGED_INDEX_JOB_ID=\$(submit_slurm_job $SAMTOOLS_INDEX_HAPLOTAGGED_SCRIPT $HAPLOTAGGED_INDEX_JOB_SAMPLES $SLURM_PARTITIONS $WHATSHAP_JOB_ID)"
	fi
fi
if [[ -n "${MAHI_MAHI_JOB_SAMPLES}" ]]; then
	echo "Running Mahi Mahi STR job on sample array indices: ${MAHI_MAHI_JOB_SAMPLES}"
	if [[ $DRYRUN == 0 ]]; then
		MAHI_MAHI_JOB_ID=$(submit_slurm_job $MAHIMAHI_SCRIPT $MAHI_MAHI_JOB_SAMPLES $SLURM_PARTITIONS $HAPLOTAGGED_INDEX_JOB_ID)
	else
		echo "MAHI_MAHI_JOB_ID=\$(submit_slurm_job $MAHIMAHI_SCRIPT $MAHI_MAHI_JOB_SAMPLES $SLURM_PARTITIONS $HAPLOTAGGED_INDEX_JOB_ID)"
	fi
fi
if [[ -n "${MOSDEPTH_JOB_SAMPLES}" ]]; then
	echo "Running MosDepth job on sample array indices: ${MOSDEPTH_JOB_SAMPLES}"
	if [[ $DRYRUN == 0 ]]; then
		MOSDEPTH_JOB_ID=$(submit_slurm_job $MOSDEPTH_SCRIPT $MOSDEPTH_JOB_SAMPLES $SLURM_PARTITIONS $INDEX_JOB_ID)
	else
		echo "MOSDEPTH_JOB_ID=\$(submit_slurm_job $MOSDEPTH_SCRIPT $MOSDEPTH_JOB_SAMPLES $SLURM_PARTITIONS $INDEX_JOB_ID)"
	fi
fi
if [[ -n "${SPECTRE_JOB_SAMPLES}" ]]; then
	echo "Running Spectre job on sample array indices: ${SPECTRE_JOB_SAMPLES}"
	if [[ $DRYRUN == 0 ]]; then
		SPECTRE_JOB_ID=$(submit_slurm_job $SPECTRE_SCRIPT $SPECTRE_JOB_SAMPLES $SLURM_PARTITIONS $CLAIR_JOB_ID $CLAIR3_MV_JOB_ID $MOSDEPTH_JOB_ID)
	else
		echo "SPECTRE_JOB_ID=\$(submit_slurm_job $SPECTRE_SCRIPT $SPECTRE_JOB_SAMPLES $SLURM_PARTITIONS $CLAIR_JOB_ID $CLAIR3_MV_JOB_ID $MOSDEPTH_JOB_ID)"
	fi
fi
if [[ -n "${SNIFFLES_JOB_SAMPLES}" ]]; then
	echo "Running sniffles job on sample array indices: ${SNIFFLES_JOB_SAMPLES}"
	if [[ $DRYRUN == 0 ]]; then
		SNIFFLES_JOB_ID=$(submit_slurm_job $SNIFFLES_SCRIPT $SNIFFLES_JOB_SAMPLES $SLURM_PARTITIONS $INDEX_JOB_ID)
	else
		echo "SNIFFLES_JOB_ID=\$(submit_slurm_job $SNIFFLES_SCRIPT $SNIFFLES_JOB_SAMPLES $SLURM_PARTITIONS $INDEX_JOB_ID)"
	fi
fi
if [[ -n "${NEEDLR_JOB_SAMPLES}" ]]; then
	echo "Running needLR job on sample array indices: ${NEEDLR_JOB_SAMPLES}"
	if [[ $DRYRUN == 0 ]]; then
		NEEDLR_JOB_ID=$(submit_slurm_job $NEEDLR_SCRIPT $NEEDLR_JOB_SAMPLES $SLURM_LONG_PARTITIONS $SNIFFLES_JOB_ID)
	else
		echo "NEEDLR_JOB_ID=\$(submit_slurm_job $NEEDLR_SCRIPT $NEEDLR_JOB_SAMPLES $SLURM_LONG_PARTITIONS $SNIFFLES_JOB_ID)"
	fi
fi
if [[ -n "${MODKIT_PILEUP_JOB_SAMPLES}" ]]; then
	echo "Running Modkit pileup job on sample array indices: ${MODKIT_PILEUP_JOB_SAMPLES}"
	if [[ $DRYRUN == 0 ]]; then
		MODKIT_JOB_ID=$(submit_slurm_job $MODKIT_PILEUP_SCRIPT $MODKIT_PILEUP_JOB_SAMPLES $SLURM_PARTITIONS $INDEX_JOB_ID)
	else
		echo "MODKIT_JOB_ID=\$(submit_slurm_job $MODKIT_PILEUP_SCRIPT $MODKIT_PILEUP_JOB_SAMPLES $SLURM_PARTITIONS $INDEX_JOB_ID)"
	fi
fi