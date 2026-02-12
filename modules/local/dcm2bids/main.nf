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

    label 'process_single'

    container "${ task.ext.container ?: '/nic/sw/IRTG/sif/dcm2bids_3.2.0.sif' }"

    input:
    // meta + dicom + modified config + force flag
    tuple val(meta), path(dicom_dir), path(modified_config)
    val  force_reprocessing

    output:
    tuple val(meta), path("sub-${meta.subject}/ses-${meta.session}") , emit: bids_output
    path "logs_dcm2bids/*.log"                                       , emit: log
    path "versions.yml"                                              , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args       = task.ext.args ?: ''
    def force_flag = force_reprocessing ? '--force_dcm2bids' : ''
    def prefix     = "sub-${meta.subject}_ses-${meta.session}"

    """
    echo "Running dcm2bids for project ${meta.project}"
    echo "subject ${meta.subject}, session ${meta.session}"
    ls -la


    mkdir -p logs_dcm2bids

    dcm2bids \\
        -p ${meta.subject} \\
        -s ses-${meta.session} \\
        -c ${modified_config} \\
        -d ${dicom_dir} \\
        -o . \\
        ${force_flag} ${args} 2>&1 | tee logs_dcm2bids/${prefix}_dcm2bids.log

    # Generate versions file
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dcm2bids: \$(dcm2bids --version 2>&1 | grep -oP 'dcm2bids \\K[0-9.]+' || echo "unknown")
        jq: \$(jq --version 2>&1 | grep -oP 'jq-\\K[0-9.]+' || echo "unknown")
    END_VERSIONS
    """

    stub:
    def prefix = "sub-${meta.subject}_ses-${meta.session}"
    """
    mkdir -p sub-${meta.subject}/ses-${meta.session}/anat
    mkdir -p sub-${meta.subject}/ses-${meta.session}/func
    mkdir -p sub-${meta.subject}/ses-${meta.session}/fmap

    touch sub-${meta.subject}/ses-${meta.session}/anat/sub-${meta.subject}_ses-${meta.session}_T1w.nii.gz
    touch sub-${meta.subject}/ses-${meta.session}/func/sub-${meta.subject}_ses-${meta.session}_task-rest_bold.nii.gz

    mkdir -p logs_dcm2bids

    touch logs_dcm2bids/${prefix}_dcm2bids.log

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dcm2bids: 3.2.0
        jq: 1.6
    END_VERSIONS
    """
}
