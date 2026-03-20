include { DCM2BIDS           } from '../modules/local/dcm2bids'
include { DCM2BIDS_CONFIG    } from '../modules/local/dcm2bidsconfig'
include { DCM2BIDS_POSTPROC  } from '../modules/local/dcm2bidspostprocess'
include { MERGE_BIDS_DATASET } from '../modules/local/mergebidsdataset'
include { BIDSIGNORE         } from '../modules/local/bidsignore'
include { BIDS_VALIDATOR     } from '../modules/local/bidsvalidator'

include { PYDEFACE           } from '../modules/local/pydeface'

include { DEFACE_QC_RENDER   } from '../modules/local/defaceqcrender'
include { DEFACE_METRICS     } from '../modules/local/defacemetrics'
include { DEFACEQA_STEP3     } from '../modules/local/defaceqastep3'
include { MERGE_DEFACEQA_STEP3} from '../modules/local/mergedefaceqastep3'
include { SUMMARIZE_DEFACEQA_STEP3 } from '../modules/local/summarizedefaceqastep3'

/*
include { MRI_DEFACE         } from '../modules/local/mri_deface'
include { FSL_DEFACE         } from '../modules/local/fsl_deface'
include { AFNI_REFACER       } from '../modules/local/afni_refacer'
include { QUICKSHEAR         } from '../modules/local/quickshear'
include { DEEPDEFACER        } from '../modules/local/deepdefacer'

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

    // run pydeface
    PYDEFACE(ch_benchmark_in)

    // helper scripts paths
    qc_script = file("${projectDir}/assets/scripts/deface_qc_render.py")
    metrics_script = file("${projectDir}/assets/scripts/deface_metrics.py")

    def stripNii = { f ->
        def n = f.getName()
        n = n.replaceFirst(/\.nii\.gz$/, '')
        n = n.replaceFirst(/\.nii$/, '')
        return n
    }

    ch_orig_keyed = ch_benchmark_in
        .map { meta, ds, orig_nifti ->
            def key = "${meta.subject}|${meta.session}|${stripNii(orig_nifti)}"
            tuple(key, meta, orig_nifti)
        }

    ch_pydeface_keyed = PYDEFACE.out.defaced
        .map { meta, defaced_nifti ->
            def base = stripNii(defaced_nifti).replaceFirst(/_defaced$/, '')
            def key  = "${meta.subject}|${meta.session}|${base}"
            tuple(key, meta, defaced_nifti)
        }

    ch_deface_qc_in = ch_orig_keyed
        .join(ch_pydeface_keyed)
        .map { key, meta_orig, orig_nifti, meta_def, defaced_nifti ->
            tuple(meta_orig, 'pydeface', qc_script, orig_nifti, defaced_nifti)
        }

    DEFACE_QC_RENDER(ch_deface_qc_in)

    pydeface_defaced = PYDEFACE.out.defaced_publish

    ch_deface_metrics_in = ch_orig_keyed
        .join(ch_pydeface_keyed)
        .map { key, meta_orig, orig_nifti, meta_def, defaced_nifti ->
            tuple(meta_orig, 'pydeface', metrics_script, orig_nifti, defaced_nifti)
        }

    DEFACE_METRICS(ch_deface_metrics_in)

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

    //brainmask channel
    def ch_fmriprep_brainmasks = Channel
        .fromPath("${params.fmriprep_brainmask_dir}/sub-*/ses-*/anat/sub-??????_ses-??_desc-brain_mask.nii.gz", checkIfExists: true)
        .map { mask ->
            def m = mask.name =~ /^sub-([^_]+)_ses-([^_]+)_desc-brain_mask\.nii\.gz$/
            if( !m.matches() ) {
                error "Unexpected fMRIPrep brainmask filename: ${mask.name}"
            }

            def subject = m[0][1]
            def session = m[0][2]
            def key = "${subject}|${session}"

            tuple(key, [subject: subject, session: session], mask)
        }

    ch_orig_t1w_keyed = ch_benchmark_in
        .filter { meta, ds, orig_nifti ->
            orig_nifti.name.contains('_T1w')
        }
        .map { meta, ds, orig_nifti ->
            def key = "${meta.subject}|${meta.session}"
            tuple(key, meta, orig_nifti)
        }

    ch_pydeface_t1w_keyed = PYDEFACE.out.defaced
        .filter { meta, defaced_nifti ->
            defaced_nifti.name.contains('_T1w')
        }
        .map { meta, defaced_nifti ->
            def key = "${meta.subject}|${meta.session}"
            tuple(key, meta, defaced_nifti)
        }

    def step3_script = file("${projectDir}/assets/scripts/defaceqa_step3_generic.py")

    ch_defaceqa_step3_in = ch_orig_t1w_keyed
        .join(ch_fmriprep_brainmasks)
        .join(ch_pydeface_t1w_keyed)
        .map { key, meta_orig, orig_nifti, meta_mask, brainmask_nifti, meta_def, defaced_nifti ->
            tuple(meta_orig, 'pydeface', step3_script, orig_nifti, brainmask_nifti, defaced_nifti)
        }




    DEFACEQA_STEP3(ch_defaceqa_step3_in)

    ch_defaceqa_step3_tsvs = DEFACEQA_STEP3.out.features_publish.collect()

    MERGE_DEFACEQA_STEP3(ch_defaceqa_step3_tsvs)

    ch_defaceqc_step3_merged = MERGE_DEFACEQA_STEP3.out.merged

    SUMMARIZE_DEFACEQA_STEP3(ch_defaceqc_step3_merged)


    emit:
    //benchmark_defaced = ch_all_defaced
    benchmark_defaced = pydeface_defaced
    benchmark_qc      = DEFACE_QC_RENDER.out.qc_publish
    benchmark_metrics = DEFACE_METRICS.out.metrics_publish
    benchmark_defaceqa= ch_defaceqc_step3_merged
    benchmark_defaceqa_sum = SUMMARIZE_DEFACEQA_STEP3.out.summary_tsv
    versions          = DCM2BIDS.out.versions
}