// TODO nf-core: If in doubt look at other nf-core/modules to see how we are doing things! :)
//               https://github.com/nf-core/modules/tree/master/modules/nf-core/
//               You can also ask for help via your pull request or on the #modules channel on the nf-core Slack workspace:
//               https://nf-co.re/join
// TODO nf-core: A module file SHOULD only define input and output files as command-line parameters.
//               All other parameters MUST be provided using the "task.ext" directive, see here:
//               https://www.nextflow.io/docs/latest/process.html#ext
//               where "task.ext" is a string.
//               Any parameters that need to be evaluated in the context of a particular sample
//               e.g. single-end/paired-end data MUST also be defined and evaluated appropriately.
// TODO nf-core: Software that can be piped together SHOULD be added to separate module files
//               unless there is a run-time, storage advantage in implementing in this way
//               e.g. it's ok to have a single module for bwa to output BAM instead of SAM:
//                 bwa mem | samtools view -B -T ref.fasta
// TODO nf-core: Optional inputs are not currently supported by Nextflow. However, using an empty
//               list (`[]`) instead of a file can be used to work around this issue.

process DCM2BIDS_POSTPROC {

    label 'process_single'

    //container "${ task.ext.container ?: '/nic/sw/IRTG/sif/dcm2bids_3.2.0.sif' }"

    input:
    tuple val(meta), path(bids_dir)

    output:
    tuple val(meta), path("sub-${meta.subject}/ses-${meta.session}"), emit: bids_post
    path "derivatives/dwi_ADC/sub-${meta.subject}/ses-${meta.session}", emit: derivatives

    script:
    // Groovy-side helpers
    def subject  = meta.subject
    def session  = meta.session
    def bidsName = bids_dir.getName()   // staged dir name, e.g. "ses-01"

    """
    # ------------------------------------------------------------------
    # 0) Ensure final BIDS folder structure: sub-<subject>/ses-<session>
    # ------------------------------------------------------------------
    final_bids_dir="sub-${subject}/ses-${session}"
    orig_bids_dir="${bidsName}"

    mkdir -p "sub-${subject}"

    if [ "\${orig_bids_dir}" != "\${final_bids_dir}" ]; then
        mv "\${orig_bids_dir}" "\${final_bids_dir}"
    fi

    # ------------------------------------------------------------------
    # 1) Remove Acquisitionduration from all *_bold.json
    # ------------------------------------------------------------------
    bold_jsons=\$(find "\${final_bids_dir}" -type f -name "*_bold.json" 2>/dev/null || true)

    if [ -n "\${bold_jsons}" ]; then
        for json_file in \${bold_jsons}; do
            if [ -f "\${json_file}" ]; then
                if jq "del(.Acquisitionduration)" "\${json_file}" > "\${json_file}.tmp" && mv "\${json_file}.tmp" "\${json_file}"; then
                    :
                else
                    echo "Warning: failed to update \${json_file}" >&2
                fi
            fi
        done
    fi

    # ------------------------------------------------------------------
    # 2) Handle ADC derivatives (anat, dwi, fmap, func)
    # ------------------------------------------------------------------
    derivatives_dwi_adc="derivatives/dwi_ADC/sub-${subject}/ses-${session}"
    mkdir -p "\${derivatives_dwi_adc}"

    # build list of search roots explicitly
    search_dirs=""
    for d in anat dwi fmap func; do
        if [ -d "\${final_bids_dir}/\${d}" ]; then
            search_dirs="\${search_dirs} \${final_bids_dir}/\${d}"
        fi
    done

    adc_files=\$(
        for root in \${search_dirs}; do
            if [ -d "\${root}" ]; then
                find "\${root}" -type f -iname "*adc*" -print 2>/dev/null || true
            fi
        done
    )

    if [ -n "\${adc_files}" ]; then
        while IFS= read -r f; do
            [ -f "\${f}" ] || continue
            mv "\${f}" "\${derivatives_dwi_adc}/"
        done << EOF
\${adc_files}
EOF
    fi

    # ------------------------------------------------------------------
    # 3) Remove sbref.bval / sbref.bvec (only in dwi/)
    # ------------------------------------------------------------------
    dwi_dir=\$(find "\${final_bids_dir}/dwi" -type d -name "dwi" | head -n1 || true)

    if [ -n "\${dwi_dir}" ]; then
        sbref_files=\$(find "\${dwi_dir}" -type f \\( -name "*sbref.bval" -o -name "*sbref.bvec" \\) -print 2>/dev/null || true)
        if [ -n "\${sbref_files}" ]; then
            rm \${sbref_files} 2>/dev/null || true
        fi
    fi

    # ------------------------------------------------------------------
    # 4) Remove tmp_dcm2bids if present
    # ------------------------------------------------------------------
    rm -rf tmp_dcm2bids || true
    """

    stub:
    """
    mkdir -p "sub-${meta.subject}/ses-${meta.session}"
    mkdir -p "derivatives/dwi_ADC/sub-${meta.subject}/ses-${meta.session}"
    """
}


