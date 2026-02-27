process FMRIPREP {

    tag "${meta.subject}"
    label 'process_high'

    container "${ task.ext.container ?: '/nic/sw/IRTG/sif/fmriprep_24.1.1.sif' }"

    // Mimic your bash: clean environment + bind templateflow repo into container
    containerOptions {
        def tf_host = task.ext.templateflow_host ?: (System.getenv('TEMPLATEFLOW_HOME') ?: '/nic/sw/IRTG/templateflow')
        def tf_cont = task.ext.templateflow_cont ?: '/templateflow'
        return "--cleanenv -B ${tf_host}:${tf_cont}"
    }

    /*
    publishDir {
        params.fmriprep_outdir ?: "${params.outdir}/derivatives/fmriprep"
    }, mode: 'copy', overwrite: true
    */

    input:
    tuple val(meta), 
    path(bids_dataset, stageAs: 'input_bids'),
    path(fs_license, stageAs: 'fs_license.txt'),
    path(bids_filter, stageAs: 'bids_filter.json')


    output:
    tuple val(meta), path("fmriprep_out_sub-${meta.subject}"), emit: out
    path("fmriprep_out_sub-${meta.subject}/**"),               emit: fmriprep_publish
    path "versions_sub-${meta.subject}.yml", emit: versions
    path "logs/sub-${meta.subject}_out.log", emit: log_out
    path "logs/sub-${meta.subject}_err.log", emit: log_err


    script:
    def participant      = meta.subject.toString()
    def omp_threads      = task.ext.omp_threads ?: (task.cpus ?: 16)
    def random_seed      = task.ext.random_seed ?: 13
    def longitudinal     = task.ext.longitudinal ? '--longitudinal' : ''
    def extra_spaces     = (task.ext.extra_output_spaces ?: '').toString().trim()
    def outdir      = "fmriprep_out_sub-${participant}"
    def wdir        = "work_dir_sub-${participant}"

    def base_spaces      = task.ext.base_output_spaces ?: 'MNI152NLin2009cAsym MNI152NLin6Asym'
    def all_spaces       = extra_spaces ? "${base_spaces} ${extra_spaces}".trim() : base_spaces

    // If no filter is provided [] is passed and args skipped
    def filter_arg = '[[ -f bids_filter.json ]] && echo "--bids-filter-file bids_filter.json" || true'

    """
    set -euo pipefail

    mkdir -p fmriprep_out logs work_dir

    echo "[CANARY] started \$(date)" > logs/sub-${participant}_out.log
    echo "[DEBUG] inside container? APPTAINER_NAME=\${APPTAINER_NAME:-} SINGULARITY_NAME=\${SINGULARITY_NAME:-}" | tee -a logs/sub-${participant}_out.log

    # Hard fail if it looks like we're not in apptainer/singularity (prevents accidental host execution)
    if [[ -z "\${APPTAINER_NAME:-}" && -z "\${SINGULARITY_NAME:-}" ]]; then
      echo "[ERROR] Not running inside Apptainer/Singularity (APPTAINER_NAME/SINGULARITY_NAME empty)." | tee -a logs/sub-${participant}_out.log
      exit 99
    fi

    # Ensure templateflow is used from the bind mount
    export TEMPLATEFLOW_HOME=/templateflow
    echo "[INFO] TEMPLATEFLOW_HOME=\$TEMPLATEFLOW_HOME" | tee -a logs/sub-${participant}_out.log
    ls -la "\$TEMPLATEFLOW_HOME" | head -n 20 | tee -a logs/sub-${participant}_out.log || true

    echo "[INFO] fmriprep version:" | tee -a logs/sub-${participant}_out.log
    fmriprep --version 2>&1 | tee -a logs/sub-${participant}_out.log

    FILTER_ARG=\$(${filter_arg})

    echo "[INFO] participant=${participant}" | tee -a logs/sub-${participant}_out.log
    echo "[INFO] omp_threads=${omp_threads}" | tee -a logs/sub-${participant}_out.log
    echo "[INFO] longitudinal=${longitudinal}" | tee -a logs/sub-${participant}_out.log
    echo "[INFO] output_spaces=${all_spaces}" | tee -a logs/sub-${participant}_out.log
    echo "[INFO] filter_arg=\${FILTER_ARG:-<none>}" | tee -a logs/sub-${participant}_out.log

    # Run fMRIPrep
    fmriprep \\
      input_bids \\
      "${outdir}" \\
      participant \\
      --notrack \\
      --participant-label ${participant} \\
      --fs-license-file fs_license.txt \\
      --skip_bids_validation \\
      --omp-nthreads ${omp_threads} \\
      --random-seed ${random_seed} \\
      --skull-strip-fixed-seed \\
      --output-spaces ${all_spaces} \\
      --work-dir "${wdir}" \\
      2>&1 | tee -a logs/sub-${participant}_out.log

    grep -i -e "warning" -e "error" logs/sub-${participant}_out.log > logs/sub-${participant}_err.log || true

    cat <<-END_VERSIONS > versions_sub-${participant}.yml
    "${task.process}":
      fmriprep: "\$(fmriprep --version 2>/dev/null | tr -d '\\n' || echo unknown)"
    END_VERSIONS
    """
}
