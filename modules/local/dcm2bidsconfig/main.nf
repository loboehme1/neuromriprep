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



process DCM2BIDS_CONFIG{

    label 'process_single'

    // ubuntu jq container
    container "${ task.ext.container ?: '/home/loboehme/Documents/container/docker-curl-jq.sif' }"

    input:
    tuple val(meta), path(config_file)

    output:
    // Emit meta again so we can join later
    tuple val(meta), path("modified_config.json"), emit: config

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    echo "Creating modified config for project ${meta.project}"
    echo "subject ${meta.subject}, session ${meta.session}"
    ls -la

    jq '.descriptions |= map(
        if .sidecar_changes?.B0FieldIdentifier? != null
           and (.sidecar_changes.B0FieldIdentifier | type == "string")
           and (.sidecar_changes.B0FieldIdentifier | test("_fmap"))
        then .sidecar_changes.B0FieldIdentifier += "_ses-${meta.session}"
        else . end |
        if .sidecar_changes?.B0FieldSource? != null
           and (.sidecar_changes.B0FieldSource | type == "string")
           and (.sidecar_changes.B0FieldSource | test("_fmap"))
        then .sidecar_changes.B0FieldSource += "_ses-${meta.session}"
        elif .sidecar_changes?.B0FieldSource? != null
           and (.sidecar_changes.B0FieldSource | type == "array")
           and (.sidecar_changes.B0FieldSource | all(. | type == "string"))
        then .sidecar_changes.B0FieldSource |= map(
            if . | test("_fmap")
            then . + "_ses-${meta.session}"
            else . end
        )
        else . end
    )' ${config_file} > modified_config.json

    if [ ! -s modified_config.json ]; then
        echo "Error: Failed to create modified config file"
        exit 1
    fi

    echo "Modified config created for ses-${meta.session}"
    """

    stub:
    """
    echo "STUB: creating dummy modified_config.json for sub-${meta.subject} ses-${meta.session}"
    echo '{}' > modified_config.json
    """
}
