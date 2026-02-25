process MRIQC_PARTICIPANT {

    tag "${meta.subject}"
    label 'process_high'

    container "${ task.ext.container ?: '/nic/sw/IRTG/sif/mriqc_25.0.0rc0.sif' }"

    /*
    publishDir {
        params.mriqc_part_outdir ?: "${params.outdir}/derivatives/mriqc"
    }, mode: 'copy', overwrite: true
    */

    input:
    tuple val(meta), path(bids_dataset, stageAs: 'input_bids')

    output:
    tuple val(meta), path("mriqc_out_${meta.subject}/"), emit: mriqc_out
    path("mriqc_out_${meta.subject}/**")               , emit: mriqc_publish  // for publishing
    path "mriqc_participant.log"                      , emit: mriqc_log
    path "versions.yml"                               , emit: versions

    script:
    def args        = task.ext.args ?: ''
    def mem_gb      = task.ext.mem_gb ?: 16
    def nprocs      = task.ext.nprocs ?: (task.cpus ?: 16)
    def threads     = task.ext.omp_threads ?: 4
    def participant = meta.subject.toString()
    def outdir      = "mriqc_out_${participant}"

    def mriqc_cmd = task.ext.mriqc_bin ?: '/opt/conda/bin/mriqc'

    """
    set -euo pipefail

    command -v ${mriqc_cmd} 2>&1 | tee -a mriqc_participant.log || true
    ${mriqc_cmd} --version 2>&1 | tee -a mriqc_participant.log

    mkdir -p ${outdir}

    ${mriqc_cmd} \\
      input_bids \\
      ${outdir} \\
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
