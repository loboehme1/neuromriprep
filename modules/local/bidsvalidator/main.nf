process BIDS_VALIDATOR {

    tag "${meta.id}"
    label 'process_low'

    container "${ task.ext.container ?: '/nic/sw/IRTG/sif/validator_1.14.13.sif' }"

    input:
    tuple val(meta), path(input_dir)

    output:
    tuple val(meta), path("${task.ext.prefix ?: meta.id}_validation_log.txt")    , emit: log
    tuple val(meta), path("${task.ext.prefix ?: meta.id}_validation_summary.txt"), emit: summary
    path "versions.yml"                                                          , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """

    : > ${prefix}_validation_log.txt

    {
        echo "[DEBUG] started: \$(date -Is)"
        echo "[DEBUG] PWD=\$(pwd)"
        echo "[DEBUG] APPTAINER_NAME=\${APPTAINER_NAME:-} SINGULARITY_NAME=\${SINGULARITY_NAME:-}"
        echo "[DEBUG] PATH=\$PATH"
        echo "[DEBUG] inside apptainer? \$( [ -d /.singularity.d ] && echo yes || echo no )"
        echo "[DEBUG] which bids-validator: \$(command -v bids-validator 2>/dev/null || echo not_found)"
    } >> ${prefix}_validation_log.txt

    set -euo pipefail

    status=0

    # Always create a log file, even if bids-validator is missing
    if command -v bids-validator >/dev/null 2>&1; then
      bids-validator \\
        ${input_dir} \\
        --verbose \\
        ${args} \\
        > ${prefix}_validation_log.txt 2>&1 || status=\$?
    else
      status=127
      echo "[BIDS_VALIDATOR] bids-validator not found in container." > ${prefix}_validation_log.txt
    fi

    # Count messages (works with typical BIDS validator output)
    errors=\$(grep -cE '^\\s*\\[ERROR\\]'   ${prefix}_validation_log.txt 2>/dev/null || true)
    warns=\$(grep -cE '^\\s*\\[(WARNING|WARN)\\]' ${prefix}_validation_log.txt 2>/dev/null || true)

    log_path="\$(pwd)/${prefix}_validation_log.txt"

    cat > ${prefix}_validation_summary.txt <<EOF
    dataset_dir=${input_dir}
    log_path=\${log_path}
    exit_code=\${status}
    errors=\${errors}
    warnings=\${warns}
    EOF

    # versions.yml (never fail)
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
      bids-validator: \$(bids-validator --version 2>/dev/null | sed 's/bids-validator v//g' || echo "unknown")
    END_VERSIONS

    # IMPORTANT: do NOT crash the pipeline even if validator found errors
    exit 0
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    cat > ${prefix}_validation_log.txt <<EOF
    [STUB] No validation run.
    EOF

    cat > ${prefix}_validation_summary.txt <<EOF
    dataset_dir=${input_dir}
    log_path=\$(pwd)/${prefix}_validation_log.txt
    exit_code=0
    errors=0
    warnings=0
    EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
      bids-validator: 1.14.13
    END_VERSIONS
    """
}
