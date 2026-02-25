process PYDEFACE {

    tag "${meta.subject}_${meta.session}_${nifti.name}"

    // use your new container
    container { task.ext.container ?: '/home/loboehme/Documents/container/ownconts/pydeface.sif' }

    cpus   { (params.pydeface_cpus ?: 8) as Integer }
    memory {  params.pydeface_mem  ?: '8 GB' }
    time   {  params.pydeface_time ?: '2h' }

    /*
    publishDir {
        params.pydeface_outdir ?: "${params.outdir}/derivatives/pydeface"
    }, mode: 'copy', overwrite: true
    */

    input:
    tuple val(meta), path(bids_dir), path(nifti)

    output:
    tuple val(meta), path("sub-${meta.subject}/ses-${meta.session}/anat/*_defaced.nii.gz"), emit: defaced
    path("logs/*.log"), emit: logs

    shell:
    '''
    set -euo pipefail

    export OMP_NUM_THREADS="!{task.cpus}"
    export OMP_THREADS="!{task.cpus}"

    sub="sub-!{meta.subject}"
    ses="ses-!{meta.session}"

    mkdir -p "$sub/$ses/anat" logs

    base="$(basename "!{nifti}" .nii.gz)"
    out_file="$sub/$ses/anat/${base}_defaced.nii.gz"

    log_prefix="sub-!{meta.subject}_ses-!{meta.session}_${base}"
    out_log="logs/${log_prefix}_out.log"
    err_log="logs/${log_prefix}_err.log"

    {
      echo "=== PYDEFACE ==="
      echo "BIDS_DIR:      !{bids_dir}"
      echo "INPUT:         !{nifti}"
      echo "OUTPUT:        $out_file"
      echo "CPUS:          !{task.cpus}"
      echo "OMP_THREADS:   $OMP_THREADS"
      echo "DATE:          $(date -Is)"
      echo "==============="
      echo
    } | tee -a "$out_log"

    # Skip if input already looks defaced --> does this work?
    if [[ "$base" == *"_defaced" ]]; then
      echo "[SKIP] Input already looks defaced: $base" | tee -a "$out_log"
      : >> "$err_log"
      exit 0
    fi


    if command -v pydeface >/dev/null 2>&1; then
      pydeface "!{nifti}" --outfile "$out_file" \
        1> >(tee -a "$out_log") \
        2> >(tee >(grep -i -e "warning" -e "error" >> "$err_log") >&2)
    elif command -v python3 >/dev/null 2>&1; then
      python3 -m pydeface "!{nifti}" --outfile "$out_file" \
        1> >(tee -a "$out_log") \
        2> >(tee >(grep -i -e "warning" -e "error" >> "$err_log") >&2)
    else
      echo "ERROR: Neither pydeface nor python3 available in container" >&2
      exit 127
    fi

    : >> "$err_log"
    '''
}
