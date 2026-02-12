process MERGE_BIDS_DATASET {

    label 'process_single'
    container "${ task.ext.container ?: '/home/loboehme/Documents/container/docker-curl-jq.sif' }"

    input:
    path sub_dirs,          stageAs: 'in_subjects/*'
    path dwi_adc_sub_dirs,  stageAs: 'in_adc/*'
    path log_files,         stageAs: 'in_logs/*'

    output:
    path "bids_dataset", emit: bids_dataset

    script:
    """
    set -euo pipefail

    mkdir -p bids_dataset
    mkdir -p bids_dataset/derivatives/dwi_ADC
    mkdir -p bids_dataset/logs_dcm2bids

    cat > bids_dataset/dataset_description.json <<'EOF'
{
  "Name": "neuromriprep_dataset",
  "BIDSVersion": "1.9.0"
}
EOF

    # Merge subjects (FOLLOW symlinks + copy contents)
    for s in ${sub_dirs}; do
      [ -d "\$s" ] || continue
      dest="bids_dataset/\$(basename "\$s")"          # <-- NEW
      mkdir -p "\$dest"                               # <-- NEW
      cp -aL "\$s/." "\$dest/"                        # <-- CHANGED (was: cp -a "\$s/" ...)
    done

    # Merge ADC derivatives (FOLLOW symlinks + copy contents)
    for d in ${dwi_adc_sub_dirs}; do
      [ -d "\$d" ] || continue
      dest="bids_dataset/derivatives/dwi_ADC/\$(basename "\$d")"   # <-- NEW
      mkdir -p "\$dest"                                            # <-- NEW
      cp -aL "\$d/." "\$dest/"                                     # <-- CHANGED
    done

    # Collect logs
    for lf in ${log_files}; do
      [ -f "\$lf" ] || continue
      cp -a "\$lf" "bids_dataset/logs_dcm2bids/"      # <-- tiny improvement: cp -a
    done

    echo "[DEBUG] merged dataset top level:"
    ls -la bids_dataset

    echo "[DEBUG] symlinks inside bids_dataset (should be empty):"  # <-- NEW
    find bids_dataset -type l -print || true                        # <-- NEW
    """
}
