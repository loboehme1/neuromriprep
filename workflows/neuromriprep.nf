/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { DCM2BIDS               } from '../modules/local/dcm2bids'
/*
include { BIDSVALIDATOR          } from '../modules/local/bidsvalidator'
include { MRIQC                  } from '../modules/local/mriqc'
include { FMRIPREP               } from '../modules/local/fmriprep'
include { PYDEFACE               } from '../modules/local/pydeface'
//include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_neuromriprep_pipeline'
include { MULTIQC                } from '../modules/nf-core/multiqc'
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow NEUROMRIPREP {


    take:
    ch_samplesheet  // channel: [ val(meta), path(dicom_dir) ]
    ch_config       // channel: path(config_file)

    main:


    // Extract subject and session from DICOM folder basename
    // Expected format: IRTGXX_SYY where XX is subject and YY is session
    ch_input = ch_samplesheet
        .map { meta, dicom_dir ->

            // DEBUG at the start of map
            log.info "[DEBUG] map(): incoming meta=${meta}, dicom_dir=${dicom_dir} name=${dicom_dir?.name}"

            def folder_name = dicom_dir.name
            def parts       = folder_name.split('_')

            // Extract subject (e.g. "01" from "IRTG01_001001")
            def subject = parts.size() > 1 ? parts[1] : "unknown"

            // Extract session (e.g. from "..._S01")
            def sesStr    = parts.size() > 2 ? parts[2] : ""
            def ses_match = sesStr =~ /S(\d+)/
            def ses       = ses_match ? ses_match[0][1] : "01"
            def session   = ses.padLeft(2, '0')

            def new_meta = meta + [
                subject: subject,
                session: session,
                project: meta.project
            ]

            // DEBUG after transformation
            log.info "[DEBUG] ch_input emit: new_meta=${new_meta}, dicom_dir_name=${dicom_dir.name}"

            // IMPORTANT: emit a TUPLE, not a plain list
            tuple(new_meta, dicom_dir)
        }

    // Now this .view will work because channel items are tuples
    ch_input.view { meta, dicom_dir ->
        log.info "[DEBUG] ch_input.view: meta=${meta}, dicom_dir=${dicom_dir} name=${dicom_dir?.name}"
    }

    //
    // Call DCM2BIDS module
    //
    DCM2BIDS(
        ch_input,
        ch_config,
        params.force_dcm2bids ?: false
    )

    //
    // Versions (optional)
    //
    ch_versions = DCM2BIDS.out.versions

    emit:
    bids_output = DCM2BIDS.out.bids_output
    derivatives = DCM2BIDS.out.derivatives
    //log         = DCM2BIDS.out.log
    versions    = ch_versions
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/