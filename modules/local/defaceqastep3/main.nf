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

process DEFACEQA_STEP3 {
    tag "${meta.subject}_${meta.session}_${method}_${orig_nifti.name}"
    label 'process_single'

    container { task.ext.container ?: (params.defaceqa_step3_container ?: '/home/loboehme/Documents/container/ownconts/deface_benchmark.sif') }

    input:
    tuple val(meta), val(method), path(step3script), path(orig_nifti), path(brainmask_nifti), path(defaced_nifti)

    output:
    tuple val(meta), val(method), path("defaceqa_step3/*.tsv"), emit: features
    path("defaceqa_step3/*.tsv"), emit: features_publish
    path("defaceqa_step3/*.json"), emit: json_publish

    script:
    """
    set -euo pipefail

    mkdir -p defaceqa_step3

    python3 "${step3script}" \
        --orig "${orig_nifti}" \
        --brainmask "${brainmask_nifti}" \
        --defaced "${defaced_nifti}" \
        --method "${method}" \
        --project "${meta.project ?: ''}" \
        --subject "${meta.subject ?: ''}" \
        --session "${meta.session ?: ''}" \
        --outdir defaceqa_step3
    """
}
