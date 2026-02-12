process MRIQC {
    tag "$meta.id"
    label 'process_medium'

    container "${ task.ext.container ?: '/nic/sw/IRTG/sif/mriqc_25.0.0rc0.sif' }"


    input:
    tuple val(meta), path(input_dir)
    tuple val(meta), path(bids_dir)


    output:
    tuple val(meta), path("results/*")    , emit: mriqc_output
    path "versions.yml"                   , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def mem_gb = 16
    def cpus = 16
    def threads = 4
    """

    mkdir -p \$PWD/results
    results="\$PWD/results"

    mriqc \\
        $input_dir \\
        \$results \\
        participant \\
        --participant-label $prefix \\
        --nprocs $cpus \\
        --omp-nthreads $threads \\
        --mem_gb $mem_gb \\
        --no-sub \\
        -v\\
        --verbose-reports \\
        $args



    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mriqc: \$(mriqc --version 2>&1 | sed 's/mriqc, version //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p \$PWD/results/sub-${prefix}
    touch \$PWD/results/sub-${prefix}/sub-${prefix}_T1w.html
    touch \$PWD/results/sub-${prefix}/sub-${prefix}_T1w.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mriqc: 24.0.2
    END_VERSIONS
    """
}
