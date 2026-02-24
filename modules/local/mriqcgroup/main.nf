process MRIQC_GROUP {

    tag "${meta.id}"
    label 'process_medium'

    container "${ task.ext.container ?: '/nic/sw/IRTG/sif/mriqc_25.0.0rc0.sif' }"

    input:
    tuple val(meta), path(bids_dataset, stageAs: 'input_bids'), path(participant_dirs, stageAs: 'participants/*')

    output:
    tuple val(meta), path("mriqc_group_out"), emit: mriqc_group_out
    path "mriqc_group.log", emit: log
    path "mriqc_group.errwarn.log", emit: errwarn
    path "versions.yml", emit: versions

    script:
    def args   = task.ext.args ?: ''
    def mem_gb = task.ext.mem_gb ?: 4

    def mriqc_cmd = task.ext.mriqc_bin ?: '/opt/conda/bin/mriqc'

    """
    set -euo pipefail

    echo "[INFO] mriqc_cmd=${mriqc_cmd}" | tee -a mriqc_group.log
    command -v ${mriqc_cmd} 2>&1 | tee -a mriqc_group.log || true
    ${mriqc_cmd} --version 2>&1 | tee -a mriqc_group.log

    mkdir -p mriqc_group_out work_dir

    # Merge participant outputs into the outdir 
    shopt -s nullglob dotglob
    for d in participants/*; do
      if [[ -d "\$d" ]]; then
        files=( "\$d"/* )
        if (( \${#files[@]} )); then
          cp -r "\${files[@]}" mriqc_group_out/
        fi
      fi
    done
    shopt -u nullglob dotglob

    ${mriqc_cmd} \\
      input_bids \\
      mriqc_group_out \\
      group \\
      --mem_gb ${mem_gb} \\
      --no-sub \\
      --work-dir work_dir \\
      -v \\
      ${args} \\
      2>&1 | tee -a mriqc_group.log

    grep -i -e "warning" -e "error" mriqc_group.log > mriqc_group.errwarn.log || true

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
      mriqc: \$(${mriqc_cmd} --version 2>&1 | sed 's/MRIQC v//g' || echo "unknown")
    END_VERSIONS
    """
}
