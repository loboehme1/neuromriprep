process BIDS_VALIDATOR {

    tag "${meta.id}"
    label 'process_low'

    container "${ task.ext.container ?: '/home/loboehme/Documents/container/ownconts/bidsvalidator_bash.sif' }"

    input:
    tuple val(meta), path(input_dir), path(bidsignore_file, stageAs: 'incoming_bidsignore.txt')

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

    set -euo pipefail

    status=0
    TARGET_BIDSIGNORE="${input_dir}/.bidsignore"

    {
        echo "================================================================"
        echo "[DIAG] BIDS_VALIDATOR started: \$(date -Is)"
        echo "================================================================"
        echo "[DIAG] PWD=\$(pwd)"
        echo "[DIAG] input_dir=${input_dir}"
        echo "[DIAG] staged bidsignore_file=${bidsignore_file}"
        echo "[DIAG] TARGET_BIDSIGNORE=\${TARGET_BIDSIGNORE}"
        echo "[DIAG] APPTAINER_NAME=\${APPTAINER_NAME:-}"
        echo "[DIAG] SINGULARITY_NAME=\${SINGULARITY_NAME:-}"
        echo "[DIAG] PATH=\$PATH"
        echo "[DIAG] inside apptainer? \$( [ -d /.singularity.d ] && echo yes || echo no )"
        echo "[DIAG] which bids-validator: \$(command -v bids-validator 2>/dev/null || echo not_found)"
        echo "[DIAG] bids-validator version: \$(bids-validator --version 2>/dev/null || echo unknown)"
        echo

        echo "================================================================"
        echo "[DIAG] Workdir listing BEFORE copy/check"
        echo "================================================================"
        ls -la .
        echo

        echo "================================================================"
        echo "[DIAG] Dataset root listing BEFORE copy/check"
        echo "================================================================"
        ls -la "${input_dir}" || true
        echo

        echo "================================================================"
        echo "[DIAG] Incoming bidsignore file BEFORE copy/check"
        echo "================================================================"
        if [ -f "${bidsignore_file}" ]; then
            echo "[DIAG] FOUND incoming file: ${bidsignore_file}"
            echo "[DIAG] incoming realpath: \$(readlink -f "${bidsignore_file}" || true)"
            echo "[DIAG] incoming inode: \$(stat -c '%d:%i' "${bidsignore_file}" 2>/dev/null || true)"
            echo "[DIAG] incoming sha256: \$(sha256sum "${bidsignore_file}" 2>/dev/null || true)"
            echo "[DIAG] incoming content using sed:"
            sed -n '1,200p' "${bidsignore_file}" || true
            echo
            echo "[DIAG] incoming content using cat -A:"
            cat -A "${bidsignore_file}" || true
        else
            echo "[DIAG][ERROR] incoming bidsignore file is missing: ${bidsignore_file}"
        fi
        echo

        echo "================================================================"
        echo "[DIAG] Target dataset .bidsignore BEFORE copy/check"
        echo "================================================================"
        if [ -f "\${TARGET_BIDSIGNORE}" ]; then
            echo "[DIAG] FOUND target file before copy/check: \${TARGET_BIDSIGNORE}"
            echo "[DIAG] target realpath before copy/check: \$(readlink -f "\${TARGET_BIDSIGNORE}" || true)"
            echo "[DIAG] target inode before copy/check: \$(stat -c '%d:%i' "\${TARGET_BIDSIGNORE}" 2>/dev/null || true)"
            echo "[DIAG] target sha256 before copy/check: \$(sha256sum "\${TARGET_BIDSIGNORE}" 2>/dev/null || true)"
            echo "[DIAG] target content before copy/check:"
            sed -n '1,200p' "\${TARGET_BIDSIGNORE}" || true
            echo
            echo "[DIAG] target content before copy/check using cat -A:"
            cat -A "\${TARGET_BIDSIGNORE}" || true
        else
            echo "[DIAG] target file missing before copy/check: \${TARGET_BIDSIGNORE}"
        fi
        echo
    } >> ${prefix}_validation_log.txt 2>&1

    # -------------------------------------------------------------------------
    # Ensure .bidsignore is present exactly where bids-validator expects it:
    # ${input_dir}/.bidsignore
    #
    # Important:
    # Nextflow may stage the same file twice:
    #   incoming_bidsignore.txt
    #   ${input_dir}/.bidsignore
    # Therefore we must not blindly cp, because cp can fail if both paths are
    # the same inode.
    # -------------------------------------------------------------------------

    if [ ! -f "${bidsignore_file}" ]; then
        echo "[DIAG][ERROR] Cannot copy missing bidsignore file: ${bidsignore_file}" >> ${prefix}_validation_log.txt

    elif [ -f "\${TARGET_BIDSIGNORE}" ]; then
        SRC_ID="\$(stat -c '%d:%i' "${bidsignore_file}" 2>/dev/null || echo src_unknown)"
        DST_ID="\$(stat -c '%d:%i' "\${TARGET_BIDSIGNORE}" 2>/dev/null || echo dst_unknown)"

        if [ "\${SRC_ID}" = "\${DST_ID}" ]; then
            echo "[DIAG] incoming bidsignore and dataset .bidsignore are the same file/inode; no copy needed." >> ${prefix}_validation_log.txt
        elif cmp -s "${bidsignore_file}" "\${TARGET_BIDSIGNORE}"; then
            echo "[DIAG] incoming bidsignore and dataset .bidsignore have identical content; no copy needed." >> ${prefix}_validation_log.txt
        else
            echo "[DIAG] Updating existing dataset .bidsignore from incoming file." >> ${prefix}_validation_log.txt
            cp -f "${bidsignore_file}" "\${TARGET_BIDSIGNORE}"
        fi

    else
        echo "[DIAG] Creating dataset .bidsignore from incoming file." >> ${prefix}_validation_log.txt
        cp -f "${bidsignore_file}" "\${TARGET_BIDSIGNORE}"
    fi

    {
        echo
        echo "================================================================"
        echo "[DIAG] Dataset root listing IMMEDIATELY BEFORE validator"
        echo "================================================================"
        ls -la "${input_dir}" || true
        echo

        echo "================================================================"
        echo "[DIAG] Target dataset .bidsignore IMMEDIATELY BEFORE validator"
        echo "================================================================"
        if [ -f "\${TARGET_BIDSIGNORE}" ]; then
            echo "[DIAG] FOUND target file: \${TARGET_BIDSIGNORE}"
            echo "[DIAG] target realpath: \$(readlink -f "\${TARGET_BIDSIGNORE}" || true)"
            echo "[DIAG] target inode: \$(stat -c '%d:%i' "\${TARGET_BIDSIGNORE}" 2>/dev/null || true)"
            echo "[DIAG] target sha256: \$(sha256sum "\${TARGET_BIDSIGNORE}" 2>/dev/null || true)"
            echo "[DIAG] target content using sed:"
            sed -n '1,200p' "\${TARGET_BIDSIGNORE}" || true
            echo
            echo "[DIAG] target content using cat -A:"
            cat -A "\${TARGET_BIDSIGNORE}" || true
        else
            echo "[DIAG][ERROR] target file missing: \${TARGET_BIDSIGNORE}"
        fi
        echo

        echo "================================================================"
        echo "[DIAG] Check specific ignored paths immediately before validator"
        echo "================================================================"

        echo "[DIAG] logs_dcm2bids:"
        if [ -e "${input_dir}/logs_dcm2bids" ]; then
            ls -ld "${input_dir}/logs_dcm2bids" || true
            find "${input_dir}/logs_dcm2bids" -maxdepth 3 -print 2>/dev/null | sed -n '1,120p' || true
        else
            echo "[DIAG] ${input_dir}/logs_dcm2bids does not exist"
        fi
        echo

        echo "[DIAG] tmp_dcm2bids:"
        if [ -e "${input_dir}/tmp_dcm2bids" ]; then
            ls -ld "${input_dir}/tmp_dcm2bids" || true
            find "${input_dir}/tmp_dcm2bids" -maxdepth 3 -print 2>/dev/null | sed -n '1,120p' || true
        else
            echo "[DIAG] ${input_dir}/tmp_dcm2bids does not exist"
        fi
        echo

        echo "[DIAG] sourcedata:"
        if [ -e "${input_dir}/sourcedata" ]; then
            ls -ld "${input_dir}/sourcedata" || true
            find "${input_dir}/sourcedata" -maxdepth 3 -print 2>/dev/null | sed -n '1,120p' || true
        else
            echo "[DIAG] ${input_dir}/sourcedata does not exist"
        fi
        echo

        echo "================================================================"
        echo "[DIAG] Exact command that will be executed now"
        echo "================================================================"
        echo "bids-validator ${input_dir} --verbose ${args}"
        echo
    } >> ${prefix}_validation_log.txt 2>&1

    # -------------------------------------------------------------------------
    # Run validator. Capture its exit code, but do not crash the pipeline.
    # -------------------------------------------------------------------------

    if command -v bids-validator >/dev/null 2>&1; then
        bids-validator \\
            "${input_dir}" \\
            --verbose \\
            ${args} \\
            >> ${prefix}_validation_log.txt 2>&1 || status=\$?
    else
        status=127
        echo "[BIDS_VALIDATOR] bids-validator not found in container." >> ${prefix}_validation_log.txt
    fi

    {
        echo
        echo "================================================================"
        echo "[DIAG] Validator finished"
        echo "================================================================"
        echo "[DIAG] validator_exit_code=\${status}"
        echo "[DIAG] finished: \$(date -Is)"
    } >> ${prefix}_validation_log.txt 2>&1

    errors=\$(grep -cE '^\\s*\\[ERROR\\]' ${prefix}_validation_log.txt 2>/dev/null || true)
    warns=\$(grep -cE '^\\s*\\[(WARNING|WARN)\\]' ${prefix}_validation_log.txt 2>/dev/null || true)

    log_path="\$(pwd)/${prefix}_validation_log.txt"

    cat > ${prefix}_validation_summary.txt <<EOF
dataset_dir=${input_dir}
log_path=\${log_path}
exit_code=\${status}
errors=\${errors}
warnings=\${warns}
EOF

    cat <<-END_VERSIONS > versions.yml
"${task.process}":
  bids-validator: \$(bids-validator --version 2>/dev/null | sed 's/bids-validator v//g' || echo "unknown")
END_VERSIONS

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