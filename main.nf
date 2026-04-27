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
include { DEFACE_BENCHMARK        } from './workflows/deface_benchmark'
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
        //.view() # uncomment to print every samplesheet entry for debugging

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
    dcm2bids_merge      = NEUROMRIPREP.out.dcm2bids_merge
    bidsgate_report     = NEUROMRIPREP.out.bidsgate_report
    bidsval_report      = NEUROMRIPREP.out.bidsval_report
    bidsignore_file     = NEUROMRIPREP.out.bidsignore_file
    mriqc_part_publish  = NEUROMRIPREP.out.mriqc_part_publish
    mriqc_group_publish = NEUROMRIPREP.out.mriqc_group_publish
    fmriprep_publish    = NEUROMRIPREP.out.fmriprep_publish
    deface_publish      = NEUROMRIPREP.out.deface_publish
    versions            = NEUROMRIPREP.out.versions
    multiqc_report      = Channel.empty() //PLACEHOLDER
}



workflow NFCORE_DEFACE_BENCHMARK {

    main:

    ch_samplesheet = Channel
        .fromPath(params.input)
        .splitCsv(header: true)
        .map { row ->
            def meta = [
                id     : row.project,
                project: row.project
            ]
            [ meta, file(row.dicom_dir) ]
        }

    ch_config = Channel.fromPath(params.dcm2bids_config, checkIfExists: true)

    DEFACE_BENCHMARK(
        ch_samplesheet,
        ch_config
    )

    emit:
    benchmark_defaced  = DEFACE_BENCHMARK.out.benchmark_defaced
    benchmark_qc       = DEFACE_BENCHMARK.out.benchmark_qc
    benchmark_metrics  = DEFACE_BENCHMARK.out.benchmark_metrics
    benchmark_summary  = DEFACE_BENCHMARK.out.benchmark_summary
    benchmark_defacedet= DEFACE_BENCHMARK.out.benchmark_defacedet
    versions           = DEFACE_BENCHMARK.out.versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

params.mode = params.mode ?: 'production'

//workflow {

    //main:
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
    //NFCORE_NEUROMRIPREP ()

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

workflow {

    main:

    // initialize everything as empty
    merge_out             = Channel.empty()
    bidsqc_out            = Channel.empty()
    bidsignore_out        = Channel.empty()
    bidsval_out           = Channel.empty()
    mriqc_part_out        = Channel.empty()
    mriqc_group_out       = Channel.empty()
    fmriprep_out          = Channel.empty()
    deface_out            = Channel.empty()

    benchmark_metrics_out   = Channel.empty()
    benchmark_qc_out        = Channel.empty()
    benchmark_files_out     = Channel.empty()  
    benchmark_summary_out   = Channel.empty()
    benchmark_defacedet_out = Channel.empty()


    if( params.mode == 'production' ) {
        NFCORE_NEUROMRIPREP()

        merge_out      = NFCORE_NEUROMRIPREP.out.dcm2bids_merge
        bidsqc_out     = NFCORE_NEUROMRIPREP.out.bidsgate_report
        bidsval_out    = NFCORE_NEUROMRIPREP.out.bidsval_report
        bidsignore_out = NFCORE_NEUROMRIPREP.out.bidsignore_file
        mriqc_part_out = NFCORE_NEUROMRIPREP.out.mriqc_part_publish
        mriqc_group_out= NFCORE_NEUROMRIPREP.out.mriqc_group_publish
        fmriprep_out   = NFCORE_NEUROMRIPREP.out.fmriprep_publish
        deface_out     = NFCORE_NEUROMRIPREP.out.deface_publish
    }
    else if( params.mode == 'benchmark_defacing' ) {
        NFCORE_DEFACE_BENCHMARK()

        benchmark_metrics_out     = NFCORE_DEFACE_BENCHMARK.out.benchmark_metrics
        benchmark_qc_out          = NFCORE_DEFACE_BENCHMARK.out.benchmark_qc
        benchmark_files_out       = NFCORE_DEFACE_BENCHMARK.out.benchmark_defaced
        benchmark_summary_out     = NFCORE_DEFACE_BENCHMARK.out.benchmark_summary
        benchmark_defacedet_out   = NFCORE_DEFACE_BENCHMARK.out.benchmark_defacedet
    }
    else {
        error "Unknown --mode '${params.mode}'. Use 'production' or 'benchmark_defacing'."
    }

    publish:
    merge_out             = merge_out
    bidsqc_out            = bidsqc_out
    bidsval_out           = bidsval_out
    bidsignore_out        = bidsignore_out
    mriqc_part_out        = mriqc_part_out
    mriqc_group_out       = mriqc_group_out
    fmriprep_out          = fmriprep_out
    deface_out            = deface_out


    benchmark_metrics_out = benchmark_metrics_out
    benchmark_qc_out      = benchmark_qc_out
    benchmark_files_out   = benchmark_files_out
    benchmark_summary_out = benchmark_summary_out
    benchmark_defacedet_out=benchmark_defacedet_out

}


// output specified in correct way as in bash files

output {

    // BIDS output
    merge_out {
        path { f -> f >> f.name }
    }

    // BIDSGATE
    bidsqc_out {
        path {f -> f >> f.name }
    }
    
    // BIDSVALIDATOR
    bidsval_out {
        path { meta, f -> f >> f.name }
    }

    bidsignore_out {
        path { meta, f -> f >> f.name }
    }

    // MRIQC participant output --> derivatives/mriqc
    mriqc_part_out {
        path { x ->
            x.file >> "derivatives/mriqc/${x.rel}"   
        }
    }


    // MRIQC group output --> derivatives/mriqc
    mriqc_group_out {
        path { x ->
            x.file >> "derivatives/mriqc/${x.rel}"  
        }
    }


    // FMRIPREP output -->
    fmriprep_out {
        path { x ->
            x.file >> "derivatives/fmriprep/${x.rel}"   
        }
    }

    // DEFACE output -->
    deface_out {
        path { x ->
            x.file >> "derivatives/defaces/${x.rel}"   
        }
    }

    benchmark_metrics_out {
        path { f -> f >> "benchmark_defacing/metrics/${f.name}" }
    }

    benchmark_qc_out {
        path { f ->
            f >> "benchmark_defacing/qc/${f.name}"
        }
    }

    benchmark_summary_out {
        path { f -> f >> "benchmark_defacing/summary/${f.name}" }
    }

    benchmark_files_out {
        path 'benchmark_defacing/defaced'
    }

    benchmark_defacedet_out {
        path { meta, qc_json, qc_pass ->
            def method = meta.deface_method ?: "unknown"
            qc_json >> "benchmark_defacedet/defacedet/${method}/${qc_json.name}"
            qc_pass >> "benchmark_defacedet/defacedet/${method}/${qc_pass.name}"
        }
    }
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
