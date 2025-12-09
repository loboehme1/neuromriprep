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
    tag "sub-${subject}_ses-${session_id}"
    label 'process_single'

    // Use public dcm2bids container with option for local override via task.ext.container
    // change to own container
    APPTAINER_IMG = "/nic/sw/IRTG/sif/dcm2bids_3.2.0.sif"

    if( !file(APPTAINER_IMG).exists() ) {
        exit 1, "ERROR: $APPTAINER_IMG not found!"
    }

    container "${ task.ext.container ?: APPTAINER_IMG }"


    input:
    val  subject              // Subject identifier (e.g., "001")
    val  session_id           // Session label (e.g., "01")
    path dicom_dir            // DICOM directory for this subject/session
    path config_file          // Session-specific dcm2bids config JSON
    val  force_reprocessing   // Boolean flag for --force_dcm2bids

    output:
    path "bids_output/sub-${subject}/ses-${session_id}", emit: bids_output
    path "*.log"                                       , emit: log
    path "versions.yml"                                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def force_flag = force_reprocessing ? '--force_dcm2bids' : ''
    def prefix = "sub-${subject}_ses-${session_id}"

    """
    # Debug: List files to verify staging
    ls -la

    # Create output directory
    mkdir -p bids_output

    # Run dcm2bids
    dcm2bids \\
        -p ${subject} \\
        -s ${session_id} \\
        -c ${config_file.name} \\
        -d ${dicom_dir.name} \\
        -o bids_output \\
        ${force_flag} ${args} 2>&1 | tee ${prefix}_dcm2bids.log

    # Post-processing: Remove AcquisitionDuration from BOLD JSON files
    # This ensures BIDS compliance by eliminating conflicts with RepetitionTime/SliceTiming
    bold_jsons=\$(find bids_output/sub-${subject}/ses-${session_id} -name "*_bold.json" 2>/dev/null || true)

    if [ -n "\${bold_jsons}" ]; then
        for json_file in \${bold_jsons}; do
            if [ -f "\${json_file}" ]; then
                # Remove AcquisitionDuration field using Python (more portable than jq)
                python3 <<EOF

import json
import sys

try:
    with open("\${json_file}", 'r') as f:
        data = json.load(f)

    # Remove AcquisitionDuration if present
    if 'AcquisitionDuration' in data:
        del data['AcquisitionDuration']
        with open("\${json_file}", 'w') as f:
            json.dump(data, f, indent=2)
        print(f"Removed AcquisitionDuration from \${json_file}", file=sys.stderr)
except Exception as e:
    print(f"Warning: Failed to process \${json_file}: {e}", file=sys.stderr)
EOF
            fi
        done
    fi

    # Clean up temporary dcm2bids directory
    rm -rf bids_output/tmp_dcm2bids

    # Generate versions file
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dcm2bids: \$(dcm2bids --version 2>&1 | grep -oP 'dcm2bids \\K[0-9.]+' || echo "unknown")
    END_VERSIONS
    """

    stub:
    def prefix = "sub-${subject}_ses-${session}"
    """
    mkdir -p bids_output/sub-${subject}/ses-${session}/anat
    mkdir -p bids_output/sub-${subject}/ses-${session}/func
    mkdir -p bids_output/sub-${subject}/ses-${session}/fmap

    touch bids_output/sub-${subject}/ses-${session}/anat/sub-${subject}_ses-${session}_T1w.nii.gz
    touch bids_output/sub-${subject}/ses-${session}/func/sub-${subject}_ses-${session}_task-rest_bold.nii.gz
    touch ${prefix}_dcm2bids.log

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dcm2bids: 3.2.0
    END_VERSIONS
    """
}