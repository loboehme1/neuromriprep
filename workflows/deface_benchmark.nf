include { DCM2BIDS           } from '../modules/local/dcm2bids'
include { DCM2BIDS_CONFIG    } from '../modules/local/dcm2bidsconfig'
include { DCM2BIDS_POSTPROC  } from '../modules/local/dcm2bidspostprocess'
include { MERGE_BIDS_DATASET } from '../modules/local/mergebidsdataset'
include { BIDSIGNORE         } from '../modules/local/bidsignore'
include { BIDS_VALIDATOR     } from '../modules/local/bidsvalidator'

include { PYDEFACE           } from '../modules/local/pydeface'

/*
include { MRI_DEFACE         } from '../modules/local/mri_deface'
include { FSL_DEFACE         } from '../modules/local/fsl_deface'
include { AFNI_REFACER       } from '../modules/local/afni_refacer'
include { QUICKSHEAR         } from '../modules/local/quickshear'
include { DEEPDEFACER        } from '../modules/local/deepdefacer'

include { DEFACE_QC_RENDER   } from '../modules/local/deface_qc_render'
include { DEFACE_METRICS     } from '../modules/local/deface_metrics'
include { MERGE_BENCHMARK    } from '../modules/local/merge_benchmark'
*/



workflow DEFACE_BENCHMARK {

    take:
    ch_samplesheet
    ch_config

    main:

    // exactly like in other workflow
    ch_input = ch_samplesheet
        .map { meta, dicom_dir ->
            def folder_name = dicom_dir.name
            def parts       = folder_name.split('_')
            def subject     = parts.size() > 1 ? parts[1] : "unknown"
            def sesStr      = parts.size() > 2 ? parts[2] : ""
            def ses_match   = sesStr =~ /S(\d+)/
            def ses         = ses_match ? ses_match[0][1] : "01"
            def session     = ses.padLeft(2, '0')

            def new_meta = meta + [
                subject: subject,
                session: session,
                project: meta.project
            ]
            tuple(new_meta, dicom_dir)
        }

    ch_cfg_in = ch_input
        .combine(ch_config)
        .map { meta, dicom_dir, config_file ->
            tuple(meta, config_file)
        }

    DCM2BIDS_CONFIG(ch_cfg_in)

    ch_run_in = ch_input
        .join(DCM2BIDS_CONFIG.out.config)
        .map { row ->
            def meta            = row[0]
            def dicom_dir       = row[1]
            def modified_config = row[2]
            tuple(meta, dicom_dir, modified_config)
        }

    ch_force = Channel.value(params.force_dcm2bids ?: false)

    DCM2BIDS(ch_run_in, ch_force)
    DCM2BIDS_POSTPROC(DCM2BIDS.out.bids_output)

    ch_sub_dirs     = DCM2BIDS_POSTPROC.out.bids_sub.map { meta, subdir -> subdir }.collect()
    ch_dwi_adc_dirs = DCM2BIDS_POSTPROC.out.dwi_adc_sub.map { meta, ddir -> ddir }.collect()
    ch_logs         = DCM2BIDS.out.log.collect()

    MERGE_BIDS_DATASET(ch_sub_dirs, ch_dwi_adc_dirs, ch_logs)

    ch_bids_dataset = MERGE_BIDS_DATASET.out.bids_dataset

    ch_dataset_meta = ch_samplesheet
        .map { meta, _ -> meta }
        .first()
        .map { meta -> meta + [ id: 'dataset' ] }

    ch_ignore_add    = Channel.fromPath('assets/input_pipeline/bidsignore_list.txt')
    ch_ignore_remove = Channel.fromPath('assets/input_pipeline/bidsignore_remove.txt', checkIfExists: false)

    ch_bidsignore_in = ch_dataset_meta
        .combine(ch_bids_dataset)
        .combine(ch_ignore_add)
        .combine(ch_ignore_remove)
        .map { meta, ds, addf, remf -> tuple(meta, ds, addf, remf) }

    BIDSIGNORE(ch_bidsignore_in)
    BIDS_VALIDATOR(BIDSIGNORE.out.bids_dataset)

    ch_bids_dataset_after_ignore = BIDSIGNORE.out.bids_dataset
        .map { meta, outdir -> outdir }
        .first()


    //after bidsvalidation, do defacing benchmarking


    // collect original anat nifti inputs
    ch_benchmark_in = ch_input
        .map { meta, _ -> meta }
        .combine(ch_bids_dataset_after_ignore)
        .flatMap { meta, ds ->
            def anatDir = new File(ds.toString(), "sub-${meta.subject}/ses-${meta.session}/anat")
            if( !anatDir.exists() ) return []

            def niiFiles = anatDir
                .listFiles()
                ?.findAll { it.name.endsWith('.nii.gz') && !it.name.contains('_defaced') }
                ?: []

            niiFiles.collect { f -> tuple(meta, ds, f.toPath()) }
        }

    // fan out
    PYDEFACE(ch_benchmark_in)

    /*
    MRI_DEFACE(ch_benchmark_in)
    FSL_DEFACE(ch_benchmark_in)
    AFNI_REFACER(ch_benchmark_in)
    QUICKSHEAR(ch_benchmark_in)
    DEEPDEFACER(ch_benchmark_in)

    ch_all_defaced = Channel
        .empty()
        .mix(PYDEFACE.out.defaced)
        .mix(MRI_DEFACE.out.defaced)
        .mix(FSL_DEFACE.out.defaced)
        .mix(AFNI_REFACER.out.defaced)
        .mix(QUICKSHEAR.out.defaced)
        .mix(DEEPDEFACER.out.defaced)

    */

    DEFACE_QC_RENDER(ch_all_defaced)
    DEFACE_METRICS(ch_all_defaced)

    ch_summary_in = DEFACE_METRICS.out.metrics
        .mix(DEFACE_QC_RENDER.out.qc_summary)

    MERGE_BENCHMARK(ch_summary_in)

    emit:
    benchmark_defaced = ch_all_defaced
    benchmark_qc      = DEFACE_QC_RENDER.out.qc_publish
    benchmark_summary = MERGE_BENCHMARK.out.summary
    versions          = DCM2BIDS.out.versions
}