process MERGE_BIDS_DATASET {


    label 'process_single'

    container "${ task.ext.container ?: '/home/loboehme/Documents/container/docker-curl-jq.sif' }"

    input:
    path sub_dirs,          stageAs: 'in_subjects/*'
    path dwi_adc_sub_dirs,  stageAs: 'in_adc/*'
    path log_files,         stageAs: 'in_logs/*'

    //output folder and contents to get structured outputs
    output:
    path "bids_dataset"   , emit: bids_dataset
    path "bids_dataset/*" , emit: bids_dataset_items



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
      dest="bids_dataset/\$(basename "\$s")"         
      mkdir -p "\$dest"                               
      cp -aL "\$s/." "\$dest/"                        
    done

    # Merge ADC derivatives (FOLLOW symlinks + copy contents)
    for d in ${dwi_adc_sub_dirs}; do
      [ -d "\$d" ] || continue
      dest="bids_dataset/derivatives/dwi_ADC/\$(basename "\$d")"   
      mkdir -p "\$dest"                                            
      cp -aL "\$d/." "\$dest/"                                     
    done

    # Collect logs
    for lf in ${log_files}; do
      [ -f "\$lf" ] || continue
      cp -a "\$lf" "bids_dataset/logs_dcm2bids/"      
    done

    ls -la bids_dataset

    find bids_dataset -type l -print || true                        
    """
}
