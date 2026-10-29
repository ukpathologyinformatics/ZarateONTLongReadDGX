# ONT Long Read Sequencing Processing for Dr. Zarate on the DGX GPU Cluster

## Table of Contents
1. [Introduction](#introduction)
2. [Pipeline Flow](#pipeline-flow)
3. [Usage](#usage)
	- [Setup](#setup)
	- [Running](#running)
4. [Current Versions](#current-versions)

## Introduction
This Slurm-based processing pipeline leverages the UKIT DGX GPU Compute Cluster to process Nanopore ONT Long Read Sequencing data (originating from .pod5 files) through the following:
* Phasing
* Haplotagging
* Single Nucleotide Variant (SNV) or Single Nucleotride Polymorphisms (SNP)
* Structural Variants (SV)
* Short Tandem Repeats (STR)
* Copy Number Variants (CNV)
* Methylation

The following tools are employed in this analysis:
* [Nanopore Dorado](https://github.com/nanoporetech/dorado/)
* [Minimap2](https://github.com/lh3/minimap2)
* [samtools](https://github.com/samtools/samtools)
* [Clair3](https://github.com/HKU-BAL/clair3)
* [WhatsHap](https://github.com/whatshap/whatshap)
* [Nanopore Mahi-mahi](https://github.com/nanoporetech/mahi-mahi)
* [Sniffles](https://github.com/fritzsedlazeck/sniffles)
* [needLR](https://github.com/millerlaboratory/needLR)
* [mosdepth](https://github.com/brentp/mosdepth)
* [Nanopore Spectre (fork)](https://github.com/nanoporetech/ont-spectre)
* [Nanopore Modkit](https://github.com/nanoporetech/modkit)

## Pipeline Flow
                      ONT Sequencing (.pod5) | ONT Sequencing (.fastq.gz)
                                |                       |
                         Dorado basecaller           Minimap2
                                 |						|
								 |  			  samtools view
								  \____________________/
									        |
		               ------------samtools sort/index-------------
		              |             |              |               |
		           clair3        sniffles       mosdepth         modkit
		         <phase,SNP>        |              |         <Methylation>
		              |           needLR        spectre
		           whatshap        <SV>          <CNV>
		  	      <haplotag>
		              |
		  	    samtools index
		    	      |
		          mahi-mahi
		            <STR>

## Usage

### Setup

#### .env

There are some environmental variables required to establish paths and Slurm parameters. Please copy `.env.example` to `.env` and fill in the required variables.

#### images/

To more efficiently run jobs in the pipeline, the scripts are currently written to use `.sqfs` images files saved on the DGX. These can be downloaded using a helper script ([images/download-image-to-sqfs.sh](images/download-image-to-sqfs.sh)) in the `images/` directory, which is where the scripts expect the files to be located.

#### models/

Dorado basecaller requires model files to align .pod5 files to a reference genome. To download these models you can use `sbatch run_dorado_models_download.sh` &mdash; pointed to the correct directory &mdash; to download the required models. In this example setup, the target directory is `models/`.

#### references/

This is the directory to use for you genome reference files.

#### sniffles/

Sniffles requires a short tandem repeat `.bed` file. `needLR` suggests a file provided by PacBio ([human_GRCh38_no_alt_analysis_set.trf.bed](https://github.com/PacificBiosciences/pbsv/blob/master/annotations/human_GRCh38_no_alt_analysis_set.trf.bed)). This file should be saved in the `sniffles/` directory.

### Running

Running the pipeline for a sample is initiated using the `process_zarate_samples.sh` script:

	process_zarate_samples.sh : Run Nanopore Long Read Sequencing Data Processing Pipeline
	Required Parameters:
		-s <sample_id(s)> : Comma-separated sample IDs (will be used as names for output folders)
		-p <task[,task...]> : Comma-separated task list (available: snp/snv, sv, str, cnv, methyl, all)
	Optional Parameters:
		-n : Perform a dry run of the script to see what changes and jobs will be run
		-v : Run with verbose logging
	
	e.g. ./process_zarate_samples.sh -s 0002 -p snp,cnv,methyl

This script will naively attempt to determine which steps a sample actually needs and establish a dependency tree of Slurm jobs to process all pipeline tasks as efficiently as possible.

#### Manually using the scripts

The various task SBATCH scripts can be run manually from the directory with your `.env` file, but you may need to provide some parameters. An example of manually running a job:

	sbatch --array <sample.txt_index_#> [--account <slurm_account>] [--partition <slurm_partition(s)>] run_modkit_pileup.sh

## Current Versions
* Dorado - v2.1.1
* Minimap2 - v2.31
* samtools - v1.24
* Clair3 - v2.0.4
* WhatsHap - v2.8
* Mahi-mahi - v1.0.0
* sniffles - v2.8.0
* needLR - v4.1
* mosdepth - v0.3.14
* Spectre - v0.3.2
* ModKit - v0.6.3

## To Do List
* Migrate program parameters (at least the static ones) to the .env file to allow a single source of record of a pipeline setup (e.g. `MAHI_MAHI_PARAMS="--set generate_motif_plots=true --loci hg38"`)