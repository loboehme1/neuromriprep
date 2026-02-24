#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    nf-core/neuromriprep
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/nf-core/neuromriprep
    Website: https://nf-co.re/neuromriprep
    Slack  : https://nfcore.slack.com/channels/neuromriprep
----------------------------------------------------------------------------------------
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { NEUROMRIPREP            } from './workflows/neuromriprep'
//include { PIPELINE_INITIALISATION } from './subworkflows/local/utils_nfcore_neuromriprep_pipeline'
//include { PIPELINE_COMPLETION     } from './subworkflows/local/utils_nfcore_neuromriprep_pipeline'
//include { samplesheetToList       } from 'plugin/nf-schema'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    GENOME PARAMETER VALUES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOWS FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// WORKFLOW: Run main analysis pipeline depending on type of input
//
workflow NFCORE_NEUROMRIPREP {


    main:

    ch_samplesheet = Channel
        .fromPath(params.input)
        .splitCsv(header: true)
        .map { row -> 
            def meta = [
                id: row.project,
                project: row.project
            ]
            [ meta, file(row.dicom_dir) ]
        }
        .view()

    ch_config = Channel.fromPath(params.dcm2bids_config, checkIfExists: true)

    //
    // WORKFLOW: Run pipeline
    //
    NEUROMRIPREP (
        ch_samplesheet,
        ch_config
    )

    //NEUROMRIPREP.out.copied_dicoms.view { it }

    emit:
    //copied_dicoms  = NEUROMRIPREP.out.copied_dicoms
    bids_output    = NEUROMRIPREP.out.bids_output
    dcm2bids_merge = NEUROMRIPREP.out.dcm2bids_merge
    //derivatives    = NEUROMRIPREP.out.derivatives
    //log            = NEUROMRIPREP.out.log
    versions       = NEUROMRIPREP.out.versions
    //multiqc_report = NEUROMRIPREP.out.multiqc_report
    multiqc_report = Channel.empty() //PLACEHOLDER
}
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {

    main:
    //
    // SUBWORKFLOW: Run initialisation tasks
    //
    /*
    PIPELINE_INITIALISATION (
        params.version,
        params.validate_params,
        params.monochrome_logs,
        args,
        params.outdir,
        params.input,
        params.help,
        params.help_full,
        params.show_hidden
    )
    */
    //
    // WORKFLOW: Run main workflow
    //
    NFCORE_NEUROMRIPREP ()
    //
    // SUBWORKFLOW: Run completion tasks
    //
    /*
    PIPELINE_COMPLETION (
        params.email,
        params.email_on_fail,
        params.plaintext_email,
        params.outdir,
        params.monochrome_logs,
        params.hook_url,
        NFCORE_NEUROMRIPREP.out.multiqc_report
    )
    */

    publish:
    merge_out = NFCORE_NEUROMRIPREP.out.dcm2bids_merge
}

output {
    merge_out {
        path 'merge_out'
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
