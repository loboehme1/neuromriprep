// TODO nf-core: If in doubt look at other nf-core/modules to see how we are doing things! :)
//               https://github.com/nf-core/modules/tree/master/modules/nf-core/
//               You can also ask for help via your pull request or on the #modules channel on the nf-core Slack workspace:
//               https://nf-co.re/join
// TODO nf-core: A module file SHOULD only define input and output files as command-line parameters.
//               All other parameters MUST be provided using the "task.ext" directive, see here:
//               https://www.nextflow.io/docs/latest/process.html#ext
//               where "task.ext" is a string.
//               Any parameters that need to be evaluated in the context of a particular sample
//               e.g. single-end/paired-end data MUST also be defined and evaluated appropriately.
// TODO nf-core: Software that can be piped together SHOULD be added to separate module files
//               unless there is a run-time, storage advantage in implementing in this way
//               e.g. it's ok to have a single module for bwa to output BAM instead of SAM:
//                 bwa mem | samtools view -B -T ref.fasta
// TODO nf-core: Optional inputs are not currently supported by Nextflow. However, using an empty
//               list (`[]`) instead of a file can be used to work around this issue.

process MRIQC_PARTICIPANT {

    tag "${meta.subject}"
    label 'process_medium'

    container "${ task.ext.container ?: '/nic/sw/IRTG/sif/mriqc_25.0.0rc0.sif' }"

    input:
    tuple val(meta), path(bids_dataset, stageAs: 'input_bids')

    output:
    tuple val(meta), path("mriqc_out"), emit: mriqc_out
    path "mriqc_participant.log", emit: log
    path "versions.yml", emit: versions

    script:
    def args      = task.ext.args ?: ''
    def mem_gb    = task.ext.mem_gb ?: 16
    def nprocs    = task.ext.nprocs ?: (task.cpus ?: 16)
    def threads   = task.ext.omp_threads ?: 4
    def participant = meta.subject.toString()

    // Prefer absolute path in this container (we verified it exists)
    def mriqc_cmd = task.ext.mriqc_bin ?: '/opt/conda/bin/mriqc'

    """
    set -euo pipefail

    echo "[CANARY] started \$(date)" > mriqc_participant.log
    echo "[DEBUG] inside container? APPTAINER_NAME=\${APPTAINER_NAME:-} SINGULARITY_NAME=\${SINGULARITY_NAME:-}" | tee -a mriqc_participant.log
    echo "[DEBUG] PATH=\$PATH" | tee -a mriqc_participant.log

    echo "[INFO] mriqc_cmd=${mriqc_cmd}" | tee -a mriqc_participant.log
    command -v ${mriqc_cmd} 2>&1 | tee -a mriqc_participant.log || true
    ${mriqc_cmd} --version 2>&1 | tee -a mriqc_participant.log

    mkdir -p mriqc_out

    ${mriqc_cmd} \\
      input_bids \\
      mriqc_out \\
      participant \\
      --participant-label ${participant} \\
      --nprocs ${nprocs} \\
      --omp-nthreads ${threads} \\
      --mem_gb ${mem_gb} \\
      --no-sub \\
      -v \\
      --verbose-reports \\
      ${args} \\
      2>&1 | tee -a mriqc_participant.log

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
      mriqc: \$(${mriqc_cmd} --version 2>&1 | sed 's/MRIQC v//g' || echo "unknown")
    END_VERSIONS
    """
}


