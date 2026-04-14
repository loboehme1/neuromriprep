process DEFACE_DETECTOR {
    tag "${meta.id}"
    label 'process_single'


    input:
    tuple val(meta), path(nii)

    output:
    tuple val(meta), path("${prefix}.deface_qc.json"), emit: qc_json
    tuple val(meta), path("${prefix}.deface_qc_pass.txt"), emit: qc_pass

    script:
    prefix = nii.name.replaceFirst(/\.nii(\.gz)?$/, '')

    """
    node ${projectDir}/assets/scripts/mri_deface_detector.mjs \
      --in "${nii}" \
      --model-dir "${projectDir}/assets/mri-deface-detector/model_js" \
      --threshold 0.5 \
      --out-json "${prefix}.deface_qc.json" \
      --out-pass "${prefix}.deface_qc_pass.txt"
    """
}
