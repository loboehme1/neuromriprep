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

process NONDEFACED_DETECTOR {
    tag "${meta.subject}_${meta.session}_${method}_${defaced_nifti.name}"
    label 'process_single'

    // Use your own pinned SIF path in config for strict reproducibility
    container { task.ext.container ?: (params.deface_qc_container ?: '/home/loboehme/Documents/container/ownconts/nondefaced-detector_latest-cpu.sif') } 

    input:
    tuple val(meta), val(method), path(defaced_nifti), path(model_dir)

    output:
    tuple val(meta), val(method), path("nondefaced_detector/*.json"), emit: json
    tuple val(meta), val(method), path("nondefaced_detector/*.tsv"),  emit: tsv
    path("nondefaced_detector/*.json"), emit: json_publish
    path("nondefaced_detector/*.tsv"),  emit: tsv_publish
    path("nondefaced_detector/*.log"),  emit: logs

    script:
    def base = defaced_nifti.getName()
        .replaceFirst(/\.nii\.gz$/, '')
        .replaceFirst(/\.nii$/, '')

    """
    set -euo pipefail

    mkdir -p nondefaced_detector tmp_preproc

    run_nondefaced_detector.py \
        --input "${defaced_nifti}" \
        --model-path "${model_dir}" \
        --method "${method}" \
        --project "${meta.project ?: ''}" \
        --subject "${meta.subject ?: ''}" \
        --session "${meta.session ?: ''}" \
        --threshold "${params.nondefaced_detector_threshold ?: 0.5}" \
        --preprocess-path tmp_preproc \
        --out-json "nondefaced_detector/${base}_${method}_nondefaced_detector.json" \
        --out-tsv  "nondefaced_detector/${base}_${method}_nondefaced_detector.tsv" \
        --out-log  "nondefaced_detector/${base}_${method}_nondefaced_detector.log"
    """
}
