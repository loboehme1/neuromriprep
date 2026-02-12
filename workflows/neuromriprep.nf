/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { DCM2BIDS               } from '../modules/local/dcm2bids'
include { DCM2BIDS_CONFIG   } from '../modules/local/dcm2bidsconfig'
include { DCM2BIDS_POSTPROC } from '../modules/local/dcm2bidspostprocess'
include { MRIQC             } from '../modules/local/mriqc'
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
    // Expected format: IRTGXX_SYY: XX is subject and YY is session
    ch_input = ch_samplesheet
        .map { meta, dicom_dir ->

            def folder_name = dicom_dir.name
            def parts       = folder_name.split('_')

            // Extract subject
            def subject = parts.size() > 1 ? parts[1] : "unknown"

            // Extract session 
            def sesStr    = parts.size() > 2 ? parts[2] : ""
            def ses_match = sesStr =~ /S(\d+)/
            def ses       = ses_match ? ses_match[0][1] : "01"
            def session   = ses.padLeft(2, '0')

            def new_meta = meta + [
                subject: subject,
                session: session,
                project: meta.project
            ]

            // emit tuple with meta + directory
            tuple(new_meta, dicom_dir)
        }


    // prepare config input for DCM2BIDS_CONFIG
    ch_cfg_in = ch_input
        .combine(ch_config)
        .map { meta, dicom_dir, config_file ->
            tuple(meta, config_file)
        }


    // Call dcm2bids_config

    DCM2BIDS_CONFIG(ch_cfg_in)

    // output
    ch_modified_cfg = DCM2BIDS_CONFIG.out.config



    // Prepare input for DCM2BIDS

    ch_run_in = ch_input
        .join(ch_modified_cfg)
        .map { row ->
            // row is [meta, dicom_dir, meta2, modified_config]
            def meta            = row[0]
            def dicom_dir       = row[1]
            def modified_config = row[2]

            tuple(meta, dicom_dir, modified_config)
        }

    ch_force = Channel.value( params.force_dcm2bids ?: false )


    // call dcm2bids

    DCM2BIDS(
        ch_run_in,
        ch_force
    )

    // output
    ch_bids_raw = DCM2BIDS.out.bids_output
    ch_versions = DCM2BIDS.out.versions

    ch_bids_raw.view { bids_dir ->
        log.info "[DEBUG] ch_bids_raw item: ${bids_dir} (name=${bids_dir.name})"
        // or just: "[DEBUG] ch_bids_raw: ${bids_dir}"
    }


    // postprocessing

    DCM2BIDS_POSTPROC(ch_bids_raw)


    // output

    postproc_out = DCM2BIDS_POSTPROC.out.bids_sub
    derivatives = DCM2BIDS_POSTPROC.out.derivatives


    // transfor channel entries to list
    //ch_root_paths = ch_bids_roots.map { meta, root -> root }
    //ch_root_list = ch_root_paths.collect()


    //bidsvalidator

    //bidsvalidator()


    // mriqc





    emit:
    bids_output = postproc_out
    derivatives = derivatives
    versions    = ch_versions
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/