include { PYDEFACE     } from '../../../modules/local/pydeface'
include { MRI_DEFACE   } from '../../../modules/local/mrideface'
include { FSL_DEFACE   } from '../../../modules/local/fsldeface'
include { AFNI_REFACER } from '../../../modules/local/afnirefacer'

workflow DEFACING {

    take:
    ch_input
    ch_bids_dataset

    main:

    def ch_deface_meta = ch_input
        .map { meta, ignored -> meta }
        .map { meta -> meta + [ id: "sub-${meta.subject}" ] }

    // Optional subject filter, currently named pydeface_vpn_file.
    // You may want to rename this later to params.deface_vpn_file because it now applies to all defacers.
    if( params.pydeface_vpn_file ) {
        def vpn_set = file(params.pydeface_vpn_file)
            .text
            .readLines()
            .collect { it.replace('\r','').trim() }
            .findAll { it }
            .collect { it.replaceFirst(/^sub-/, '') }
            .toSet()

        ch_deface_meta = ch_deface_meta.filter { meta ->
            vpn_set.contains(meta.subject.toString().replaceFirst(/^sub-/, ''))
        }
    }

    def ch_deface_in = ch_deface_meta
        .combine(ch_bids_dataset)
        .flatMap { meta, ds ->
            def anatDir = new File(ds.toString(), "sub-${meta.subject}/ses-${meta.session}/anat")
            if( !anatDir.exists() ) return []

            def niiFiles = anatDir
                .listFiles()
                ?.findAll { it.name.endsWith('.nii.gz') && !it.name.endsWith('_defaced.nii.gz') }
                ?: []

            niiFiles.collect { f -> tuple(meta, ds, f.toPath()) }
        }

    def ch_defaced = Channel.empty()
    def ch_deface_publish = Channel.empty()

    if( params.deface_tool == 'mri_deface' ) {

        MRI_DEFACE(ch_deface_in)
        ch_defaced = MRI_DEFACE.out.defaced
        ch_deface_publish = MRI_DEFACE.out.defaced_publish

    } else if( params.deface_tool == 'pydeface' ) {

        PYDEFACE(ch_deface_in)
        ch_defaced = PYDEFACE.out.defaced
        ch_deface_publish = PYDEFACE.out.defaced_publish

    } else if( params.deface_tool == 'fsl_deface' ) {

        FSL_DEFACE(ch_deface_in)
        ch_defaced = FSL_DEFACE.out.defaced
        ch_deface_publish = FSL_DEFACE.out.defaced_publish

    } else if( params.deface_tool == 'afni_refacer' ) {

        AFNI_REFACER(ch_deface_in)
        ch_defaced = AFNI_REFACER.out.defaced
        ch_deface_publish = AFNI_REFACER.out.defaced_publish

    /*
    } else if( params.deface_tool == 'deepdefacer' ) {

        DEEPDEFACER(ch_deface_in)
        ch_defaced = DEEPDEFACER.out.defaced
        ch_deface_publish = DEEPDEFACER.out.defaced_publish
    */

    } else {
        error "Unsupported params.deface_tool: ${params.deface_tool}"
    }

    ch_deface_publish_mapped = ch_deface_publish
        .flatten()
        .map { p ->
            def s = p.toString()
            def parts = s.split(/[\\\/]+/)
            def i = parts.findIndexOf { it.startsWith('sub-') }
            if( i < 0 ) error "Could not derive rel path from: ${s}"
            def rel = parts[i..-1].join('/')
            [ file: p, rel: rel ]
        }

    ch_defaced_files = ch_defaced
        .map { meta, files -> files }
        .flatten()
        .collect()

    emit:
    defaced        = ch_defaced
    defaced_files  = ch_defaced_files
    deface_publish = ch_deface_publish_mapped
}
