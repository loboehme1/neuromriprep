// TODO nf-core: If in doubt look at other nf-core/modules to see how we are doing things! :)
//               https://github.com/nf-core/modules/tree/master/modules/nf-core/
//               You can also ask for help via your pull request or on the #modules channel on the nf-core Slack workspace:
//               https://nf-co.re/join
// TODO nf-core: A module file SHOULD only define input and output files as command-line parameters.
//               All other parameters MUST be provided using the "task.ext" directive, see here:
//               https://www.nextflow.io/docs/latest/process.html#ext
//               where "task.ext" is a string.
//               Any parameters that need to be evaluated in the context of a particular sample
//               e.g. single-end/paired-end data MUST also be defined and evaluated appropriately.
// TODO nf-core: Software that can be piped together SHOULD be added to separate module files
//               unless there is a run-time, storage advantage in implementing in this way
//               e.g. it's ok to have a single module for bwa to output BAM instead of SAM:
//                 bwa mem | samtools view -B -T ref.fasta
// TODO nf-core: Optional inputs are not currently supported by Nextflow. However, using an empty
//               list (`[]`) instead of a file can be used to work around this issue.



process DCM2BIDS {
    //tag { "sub-${meta.subject}_ses-${meta.session}" }
    label 'process_single'

    // Use public dcm2bids container with option for local override via task.ext.container
    // change to own container
    container "${ task.ext.container ?: '/nic/sw/IRTG/sif/dcm2bids_3.2.0.sif' }"

    
  //if( !file(APPTAINER_IMG).exists() ) {
    //  exit 1, "ERROR: $APPTAINER_IMG not found!"
  //}

  //container "${ task.ext.container ?: APPTAINER_IMG }"

/*
    input:
    val  subject              // Subject identifier (e.g., "001")
    val  session_id           // Session label (e.g., "01")
    path dicom_dir            // DICOM directory for this subject/session
    path config_file          // Session-specific dcm2bids config JSON
    val  force_reprocessing   // Boolean flag for --force_dcm2bids
    */

    input:
    tuple val(meta), path(dicom_dir)
    path config_file
    val force_reprocessing

    output:
    path "sub-${meta.subject}/ses-${meta.session}", emit: bids_output
    path "derivatives/dwi_ADC/sub-${meta.subject}/ses-${meta.session}", emit: derivatives
    path "*.log"                                       , emit: log
    path "versions.yml"                                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def force_flag = force_reprocessing ? '--force_dcm2bids' : ''
    def subject = meta.subject
    def session = meta.session
    def project = meta.project
    def prefix = "sub-${subject}_ses-${session}"

    """
    # Debug: List files to verify staging
    echo "processing ${project}"
    echo "subject ${subject}, session ${session}"
    ls -la

    # Create modified config for this session
    # Add session suffix to B0FieldIdentifier and B0FieldSource
    jq '.descriptions |= map(
        if .sidecar_changes?.B0FieldIdentifier? != null and (.sidecar_changes.B0FieldIdentifier | type == "string") and (.sidecar_changes.B0FieldIdentifier | test("_fmap"))
        then .sidecar_changes.B0FieldIdentifier += "_ses-${meta.session}"
        else . end |
        if .sidecar_changes?.B0FieldSource? != null and (.sidecar_changes.B0FieldSource | type == "string") and (.sidecar_changes.B0FieldSource | test("_fmap"))
        then .sidecar_changes.B0FieldSource += "_ses-${meta.session}"
        elif .sidecar_changes?.B0FieldSource? != null and (.sidecar_changes.B0FieldSource | type == "array") and (.sidecar_changes.B0FieldSource | all(. | type == "string"))
        then .sidecar_changes.B0FieldSource |= map(if . | test("_fmap") then . + "_ses-${meta.session}" else . end)
        else . end
    )' ${config_file} > modified_config.json

    # Verify modified config was created successfully
    if [ ! -s modified_config.json ]; then
        echo "Error: Failed to create modified config file"
        exit 1
    fi

    echo "Modified config created for ses-${meta.session}"

    # Create output directory
    # mkdir -p bids_output

    # Run dcm2bids
    dcm2bids \\
        -p ${meta.subject} \\
        -s ses-${meta.session} \\
        -c modified_config.json \\
        -d ${dicom_dir} \\
        -o . \\
        ${force_flag} ${args} 2>&1 | tee ${prefix}_dcm2bids.log

    # Post-processing: Remove AcquisitionDuration from BOLD JSON files
    # This ensures BIDS compliance by eliminating conflicts with RepetitionTime/SliceTiming
    bold_jsons=\$(find sub-${meta.subject}/ses-${meta.session} -name "*_bold.json" 2>/dev/null || true)

    if [ -n "\${bold_jsons}" ]; then
        for json_file in \${bold_jsons}; do
            if [ -f "\${json_file}" ]; then
                if jq "del(.Acquisitionduration)" "\${json_file}" > "\${json_file}.tmp" && mv "\${json_file}.tmp" "\${json_file}"; then
                    echo "post processing: removed ac..."
        
                else
                    echo "Warning: failed"
                fi
            fi
        done

    else
        echo "Warning: No _bold.json files found"
    fi

    # 2. Handle DWI derivatives and cleanup
    fmap_dir="sub-${meta.subject}/ses-${meta.session}/fmap"
    dwi_dir="sub-${meta.subject}/ses-${meta.session}/dwi"
    derivatives_dwi_adc="derivatives/dwi_ADC/sub-${meta.subject}/ses-${meta.session}"

    # Move ADC files to derivatives
    mkdir -p "\${derivatives_dwi_adc}"

    adc_files=\$(find "\${fmap_dir}" "\${dwi_dir}" -type f -name "*ADC*" 2>/dev/null || true)
    if [ -n "\${adc_files}" ]; then
        if mv \${adc_files} "\${derivatives_dwi_adc}" 2>/dev/null; then
            echo "Post-processing: Moved ADC files to derivatives"
        else
            echo "Warning: No ADC files found or failed to move"
        fi
    fi

    # Remove sbref.bval and sbref.bvec files
    sbref_files=\$(find "\${dwi_dir}" -type f \\( -name "*sbref.bval" -o -name "*sbref.bvec" \\) 2>/dev/null || true)
    if [ -n "\${sbref_files}" ]; then
        if rm \${sbref_files} 2>/dev/null; then
            echo "Post-processing: Deleted sbref.bval and sbref.bvec files"
        else
            echo "Warning: No sbref files found or failed to delete"
        fi
    fi

    # Clean up temporary dcm2bids directory
    rm -rf tmp_dcm2bids

    echo "post precess compl for ${prefix}"

    # Generate versions file
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dcm2bids: \$(dcm2bids --version 2>&1 | grep -oP 'dcm2bids \\K[0-9.]+' || echo "unknown")
        jq: \$(jq --version 2>&1 | grep -oP 'jq-\\K[0-9.]+' || echo "unknowm")
    END_VERSIONS
    """

    stub:
    def prefix = "sub-${meta.subject}_ses-${meta.session}"
    """
    mkdir -p sub-${meta.subject}/ses-${meta.session}/anat
    mkdir -p sub-${meta.subject}/ses-${meta.session}/func
    mkdir -p sub-${meta.subject}/ses-${meta.session}/fmap

    touch sub-${meta.subject}/ses-${meta.session}/anat/sub-${meta.subject}_ses-${meta.ession}_T1w.nii.gz
    touch sub-${meta.subject}/ses-${meta.session}/func/sub-${meta.subject}_ses-${meta.session}_task-rest_bold.nii.gz
    touch ${prefix}_dcm2bids.log

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dcm2bids: 3.2.0
        jq: 1.6
    END_VERSIONS
    """
}