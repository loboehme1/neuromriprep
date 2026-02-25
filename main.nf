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
    dcm2bids_merge = NEUROMRIPREP.out.dcm2bids_merge
    mriqc_part_publish = NEUROMRIPREP.out.mriqc_part_publish
    mriqc_group_publish = NEUROMRIPREP.out.mriqc_group_publish
    fmriprep_publish = NEUROMRIPREP.out.fmriprep_publish
    pydeface_publish = NEUROMRIPREP.out.pydeface_publish
    versions       = NEUROMRIPREP.out.versions
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
    merge_out          = NFCORE_NEUROMRIPREP.out.dcm2bids_merge
    mriqc_part_out     = NFCORE_NEUROMRIPREP.out.mriqc_part_publish
    mriqc_group_out    = NFCORE_NEUROMRIPREP.out.mriqc_group_publish
    fmriprep_out       = NFCORE_NEUROMRIPREP.out.fmriprep_publish
    pydeface_out       = NFCORE_NEUROMRIPREP.out.pydeface_publish
}


// output specified in correct way as in bash files

output {

  merge_out {
    path { f -> f >> f.name }
  }

  // ---- MRIQC participant: strip "mriqc_out_<sub>/" and put into derivatives/mriqc/ ----
  mriqc_part_out {
    path { f ->
      def rel = f.toString().replaceFirst(/^.*\/mriqc_out_[^\/]+\//, '')
      if( !rel ) return null
      f >> "derivatives/mriqc/${rel}"
    }
  }

  // ---- MRIQC group: strip wrapper dir and put into derivatives/mriqc/ (or mriqc_group/) ----
  mriqc_group_out {
    path { f ->
      def rel = f.toString().replaceFirst(/^.*\/mriqc_group_out\//, '')
      if( !rel ) return null
      f >> "derivatives/mriqc/${rel}"        // or: "derivatives/mriqc_group/${rel}"
    }
  }

  // ---- FMRIPREP: strip "fmriprep_out/" and put into derivatives/fmriprep/ ----
  fmriprep_out {
    path { f ->
      def rel = f.toString().replaceFirst(/^.*\/fmriprep_out\//, '')
      if( !rel ) return null
      f >> "derivatives/fmriprep/${rel}"
    }
  }

  // ---- PYDEFACE: publish into BIDS-like relative path (starting at sub-...) ----
  pydeface_out {
    path { f ->
      def rel = f.toString().replaceFirst(/^.*\/(sub-[^\/].*)$/, '$1')
      f >> rel
    }
  }
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
