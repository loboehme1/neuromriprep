process MRI_DEFACE {

    tag "${meta.subject}_${meta.session}_${nifti.name}"

    container { task.ext.container ?: '/home/loboehme/Documents/container/ownconts/mri_deface.sif' }

    cpus   { (params.mri_deface_cpus ?: 8) as Integer }
    memory {  params.mri_deface_mem  ?: '8 GB' }
    time   {  params.mri_deface_time ?: '2h' }

    input:
    tuple val(meta), path(bids_dir), path(nifti)

    output:
    tuple val(meta), path("sub-${meta.subject}/ses-${meta.session}/anat/*_defaced.nii.gz"), emit: defaced
    path("sub-${meta.subject}/ses-${meta.session}/anat/*_defaced.nii.gz"),                  emit: defaced_publish
    path("logs/*.log"), emit: logs

    shell:
    '''
    set -euo pipefail

    export OMP_NUM_THREADS="!{task.cpus}"
    export OMP_THREADS="!{task.cpus}"

    sub="sub-!{meta.subject}"
    ses="ses-!{meta.session}"

    mkdir -p "$sub/$ses/anat" logs

    fname="$(basename "!{nifti}")"
    base="${fname%.nii.gz}"
    if [[ "$base" == "$fname" ]]; then
      base="${fname%.nii}"
    fi

    out_file="$sub/$ses/anat/${base}_defaced.nii.gz"

    log_prefix="sub-!{meta.subject}_ses-!{meta.session}_${base}"
    out_log="logs/${log_prefix}_out.log"
    err_log="logs/${log_prefix}_err.log"

    mri_deface_bin="!{params.mri_deface_bin ?: 'mri_deface'}"
    brain_tmpl="!{params.mri_deface_brain_template ?: '/opt/mri_deface/talairach_mixed_with_skull.gca'}"
    face_tmpl="!{params.mri_deface_face_template ?: '/opt/mri_deface/face.gca'}"

    {
      echo "=== MRI_DEFACE ==="
      echo "BIDS_DIR:      !{bids_dir}"
      echo "INPUT:         !{nifti}"
      echo "OUTPUT:        $out_file"
      echo "BINARY:        $mri_deface_bin"
      echo "BRAIN_TMPL:    $brain_tmpl"
      echo "FACE_TMPL:     $face_tmpl"
      echo "CPUS:          !{task.cpus}"
      echo "OMP_THREADS:   $OMP_THREADS"
      echo "DATE:          $(date -Is)"
      echo "=================="
      echo
    } | tee -a "$out_log"

    # Skip if input already looks defaced, but still create declared output
    if [[ "$base" == *"_defaced" ]] || [[ "$base" == *"_deface" ]]; then
      echo "[SKIP] Input already looks defaced: $base" | tee -a "$out_log"
      cp "!{nifti}" "$out_file"
      : >> "$err_log"
      exit 0
    fi

    if [[ "$mri_deface_bin" != "mri_deface" ]]; then
      [[ -x "$mri_deface_bin" ]] || { echo "ERROR: mri_deface binary not executable: $mri_deface_bin" | tee -a "$err_log" >&2; exit 127; }
    else
      command -v mri_deface >/dev/null 2>&1 || { echo "ERROR: mri_deface not found in PATH" | tee -a "$err_log" >&2; exit 127; }
    fi

    [[ -f "$brain_tmpl" ]] || { echo "ERROR: Missing brain template: $brain_tmpl" | tee -a "$err_log" >&2; exit 1; }
    [[ -f "$face_tmpl"  ]] || { echo "ERROR: Missing face template: $face_tmpl"  | tee -a "$err_log" >&2; exit 1; }

    "$mri_deface_bin" "!{nifti}" "$brain_tmpl" "$face_tmpl" "$out_file" \
      1> >(tee -a "$out_log") \
      2> >(tee >(grep -i -e "warning" -e "error" >> "$err_log") >&2)

    [[ -f "$out_file" ]] || { echo "ERROR: Expected output not created: $out_file" | tee -a "$err_log" >&2; exit 1; }

    : >> "$err_log"
    '''
}
