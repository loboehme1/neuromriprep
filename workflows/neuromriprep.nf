/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//params.input       = params.input ?: ''      // e.g. "/data/dicoms/*/"
//params.outdir_copy = params.outdir_copy ?: null

include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_neuromriprep_pipeline'
include { MULTIQC                } from '../modules/nf-core/multiqc'
include { COPYDICOMS             } from '../modules/local/copydicoms'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow NEUROMRIPREP {

    /*
    take:
    ch_input_dirs // channel: [ val(meta), path(input_dir) ]
    ch_config     // channel: path(config_file)
    */
    


    main:

    ch_versions = Channel.empty()
    ch_input_dirs = Channel.fromPath(params.input, type: 'dir')
        .map { dir ->
            def meta = [id: dir.name]
            [meta, dir]
        }

    //ch_config = params.config ? Channel.fromPath(params.config) : Channel.empty()
    //ch_fs_license = Channel.fromPath(params.fs_license)

    //
    // MODULE: copydicoms
    //

    COPYDICOMS (
        ch_input_dirs
    )

    ch_multiqc_files = Channel.empty()
    multiqc_report = Channel.empty()

    
    
    


    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_'  +  'neuromriprep_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }


    //
    // MODULE: MultiQC
    //
    /*
    ch_multiqc_config        = Channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        Channel.fromPath(params.multiqc_config, checkIfExists: true) :
        Channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        Channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        Channel.empty()

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )
    */
    // (optional) versions into MultiQC bundle later
    ch_versions = ch_versions.mix( COPYDICOMS.out.versions )

    // --- MultiQC scaffold (kept minimal for now) ---
    ch_multiqc_config        = Channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = Channel.empty()
    ch_multiqc_logo          = Channel.empty()

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:
    copied_dicoms  = COPYDICOMS.out.dicoms          // <- directory you want
    versions       = COPYDICOMS.out.versions        // <- if you keep versions.yml
    multiqc_report = MULTIQC.out.report.toList()
    /*
    emit:
    multiqc_report  = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions        = ch_versions                 // channel: [ path(versions.yml) ]
    bids_files      = params.run_dcm2bids || params.run_complete ? DCM2BIDS.out.bids_files : Channel.empty()
    defaced_images  = params.run_pydeface || params.run_complete ? PYDEFACE.out.defaced_image : Channel.empty()
    mriqc_output    = params.run_mriqc || params.run_complete ? MRIQC.out.mriqc_output : Channel.empty()
    fmriprep_output = params.run_fmriprep || params.run_complete ? FMRIPREP.out.fmriprep_output : Channel.empty()
    */
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
