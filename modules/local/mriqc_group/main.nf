process MRIQC_GROUP {
    label 'process_medium'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker://nipreps/mriqc:25.0.0rc0':
        'nipreps/mriqc:25.0.0rc0' }"

    input:
    path input_dir
    path mriqc_results

    output:
    path "results/reports/group_T1w.html", emit: group_t1w_html, optional: true
    path "results/reports/group_T2w.html", emit: group_t2w_html, optional: true
    path "results/reports/group_bold.html", emit: group_bold_html, optional: true
    path "results/group_*.tsv"           , emit: group_tsv, optional: true
    path "versions.yml"                  , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def mem_gb = task.memory.toGiga()
    """
    mkdir -p results
    
    # Copy or symlink staged results to the results folder so mriqc finds them
    # mriqc_results is a list of files/dirs.
    # We copy them to 'results/' because mriqc group expects them in the output directory.
    # We use cp -n to avoid overwriting if duplicates (shouldn't be) and to dereference.
    
    cp -rn $mriqc_results results/ || echo "Warning: Some files could not be copied"

    mriqc \\
        $input_dir \\
        results \\
        group \\
        --no-sub \\
        --mem_gb $mem_gb \\
        --nprocs $task.cpus \\
        --omp-nthreads $task.cpus \\
        -v \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mriqc: \$(mriqc --version 2>&1 | sed 's/mriqc, version //g')
    END_VERSIONS
    """
}
