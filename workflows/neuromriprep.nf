/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { DCM2BIDS          } from '../modules/local/dcm2bids'
include { DCM2BIDS_CONFIG   } from '../modules/local/dcm2bidsconfig'
include { DCM2BIDS_POSTPROC } from '../modules/local/dcm2bidspostprocess'
include { MERGE_BIDS_DATASET} from '../modules/local/mergebidsdataset'
include { BIDS_VALIDATOR    } from '../modules/local/bidsvalidator'
include { BIDSIGNORE        } from '../modules/local/bidsignore'
include { MRIQC_PARTICIPANT } from '../modules/local/mriqcparticipant'
include { MRIQC_GROUP       } from '../modules/local/mriqcgroup'
include { FMRIPREP          } from '../modules/local/fmriprep'
include { PYDEFACE          } from '../modules/local/pydeface'
include { MRIQC_PARTICIPANTS} from '../subworkflows/local/mriqc_participants'




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

    DCM2BIDS_POSTPROC(
        ch_bids_raw
    )


    // output

    postproc_out = DCM2BIDS_POSTPROC.out.bids_sub
    dwi_adc_sub= DCM2BIDS_POSTPROC.out.dwi_adc_sub


    ch_sub_dirs     = DCM2BIDS_POSTPROC.out.bids_sub.map { meta, subdir -> subdir }.collect()
    ch_dwi_adc_dirs = DCM2BIDS_POSTPROC.out.dwi_adc_sub.map { meta, ddir -> ddir }.collect()

    ch_logs         = DCM2BIDS.out.log.collect()


    // merge bids dataset

    MERGE_BIDS_DATASET(
        ch_sub_dirs, 
        ch_dwi_adc_dirs, 
        ch_logs
    )

    ch_bids_dataset = MERGE_BIDS_DATASET.out.bids_dataset


    ch_dataset_meta = ch_samplesheet.map { meta, _ -> meta }.first().map { meta -> meta + [ id: 'dataset' ] }


    // read in 
    ch_ignore_add    = Channel.fromPath('assets/input_pipeline/bidsignore_list.txt')
    ch_ignore_remove = Channel.fromPath('assets/input_pipeline/bidsignore_remove.txt', checkIfExists: false)



    ch_bidsignore_in = ch_dataset_meta
    .combine(ch_bids_dataset)
    .combine(ch_ignore_add)
    .combine(ch_ignore_remove)
    .map { meta, ds, addf, remf -> tuple(meta, ds, addf, remf) }

    //bidsignore

    BIDSIGNORE(ch_bidsignore_in)

    ch_bidsval_in = BIDSIGNORE.out.bids_dataset

    //bidsvalidator

    BIDS_VALIDATOR(ch_bidsval_in)



    // Print counts + log location to console -> stop so human can look at logs

    if( params.stop_bidsval) {

        log.warn "[BIDS] Stopping after BIDS validation. After resolving the issues re-run with -resume and --stop_bidsval false to continue."

    } else {

        ch_bids_dataset_after_ignore = BIDSIGNORE.out.bids_dataset
            .map { meta, outdir -> outdir }
            .first()


        // Build per-subject inputs: (meta, bids_dataset)
        ch_mriqc_in = ch_input
            .map { meta, _ -> meta }                       // meta contains subject/session
            .combine(ch_bids_dataset_after_ignore)
            .map { meta, ds -> tuple(meta, ds) }


        MRIQC_PARTICIPANTS(ch_mriqc_in, params.mriqc_vpn_file)


        ch_mriqc_part_dirs = MRIQC_PARTICIPANTS.out.mriqc_out
            .map { meta, outdir -> outdir }
            .collect()
            .map { dirs -> dirs.toSet() }   

        ch_mriqc_group_in = ch_dataset_meta
            .combine(ch_bids_dataset_after_ignore)
            .combine(ch_mriqc_part_dirs)

        MRIQC_GROUP(ch_mriqc_group_in)



        if( params.stop_mriqc) {

            log.warn "[BIDS] Stopping after BIDS validation. After resolving the issues re-run with -resume and --stop_bidsval false to continue."
        } else {
            // Dataset dir (single value)
            ch_fmriprep_ds = ch_bids_dataset_after_ignore

            // per-subject meta channel: one item per subject
            ch_fmriprep_meta = ch_input
                .map { meta, _ -> meta }
                .map { meta -> meta + [ id: "sub-${meta.subject}" ] } 

            // restrict to a VPN list file (one subject per line, allow "sub-XXX")
            if( params.fmriprep_vpn_file ) {
                def vpn_set = file(params.fmriprep_vpn_file)
                    .text
                    .readLines()
                    .collect { it.replace('\r','').trim() }
                    .findAll { it }
                    .collect { it.replaceFirst(/^sub-/, '') }
                    .toSet()

                ch_fmriprep_meta = ch_fmriprep_meta.filter { meta ->
                    vpn_set.contains(meta.subject.toString().replaceFirst(/^sub-/, ''))
                }
            }

            // BIDS filter selection: null | ses01 | ses02 | explicit json path
            def bf = params.fmriprep_bids_filter ? params.fmriprep_bids_filter.toString() : null
            def bf_path = null
            if( bf ) {
                if( bf == 'ses01' )      bf_path = '/nic/sw/IRTG/scripts/bids-filter-file/filter_ses01.json'
                else if( bf == 'ses02' ) bf_path = '/nic/sw/IRTG/scripts/bids-filter-file/filter_ses02.json'
                else                     bf_path = bf
            }

            def ch_bids_filter = bf_path \
                ? Channel.value(file(bf_path)) \
                : Channel.value(file("${projectDir}/assets/empty_bids_filter.json"))


            // FreeSurfer license
            def ch_fs_license = Channel.value( file(params.fmriprep_fs_license) )

            // Compose inputs for module
            // Common pattern: (meta, ds, fs_license, bids_filter)
            ch_fmriprep_in = ch_fmriprep_meta
                .combine(ch_fmriprep_ds)
                .combine(ch_fs_license)
                .combine(ch_bids_filter)
                .map { meta, ds, lic, filt -> [meta, ds, lic, filt] }

            // Run fMRIPrep
            FMRIPREP(ch_fmriprep_in)


            if( params.stop_fmriprep ) {

                log.warn "[BIDS] Stopping after FMRIPREP validation. After resolving the issues re-run with -resume and --stop_bidsval false to continue."
            
            } else {

                // Dataset dir (single value)
                def ch_pydeface_ds = ch_bids_dataset_after_ignore

                // Per-subject/session meta (you already have it via ch_input)
                def ch_pydeface_meta = ch_input
                    .map { meta, _ -> meta }
                    .map { meta -> meta + [ id: "sub-${meta.subject}" ] }

                // Optional restriction to VPN list file (one subject per line, allow "sub-XXX")
                if( params.pydeface_vpn_file ) {
                    def vpn_set = file(params.pydeface_vpn_file)
                        .text
                        .readLines()
                        .collect { it.replace('\r','').trim() }
                        .findAll { it }
                        .collect { it.replaceFirst(/^sub-/, '') }
                        .toSet()

                    ch_pydeface_meta = ch_pydeface_meta.filter { meta ->
                        vpn_set.contains(meta.subject.toString().replaceFirst(/^sub-/, ''))
                    }
                }

                /*
                * Enumerate anat NIfTIs per (subject, session) from the BIDS dataset.
                * Emits one task per nifti file -> parallel + resumable.
                */
                def ch_pydeface_in = ch_pydeface_meta
                    .combine(ch_pydeface_ds)
                    .flatMap { meta, ds ->
                        def anatDir = new File(ds.toString(), "sub-${meta.subject}/ses-${meta.session}/anat")
                        if( !anatDir.exists() ) return []

                        def niiFiles = anatDir
                            .listFiles()
                            ?.findAll { it.name.endsWith('.nii.gz') && !it.name.endsWith('_defaced.nii.gz') }
                            ?: []

                        return niiFiles.collect { f -> tuple(meta, ds, f.toPath()) } 
                    }


                // run pydeface
                PYDEFACE(ch_pydeface_in)

            }
        }
    }




    
    emit:
    bids_output = postproc_out
    dcm2bids_merge = ch_bids_dataset
    //derivatives = derivatives
    versions    = ch_versions
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/