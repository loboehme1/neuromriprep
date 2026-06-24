process MAKE_DEFACED_BIDS {

    tag "${meta.id}"

    input:
    tuple val(meta), path(bids_dir), path(defaced_files, stageAs: 'defaced/*')

    output:
    tuple val(meta), path("bids_defaced"), emit: bids_dataset

    script:
    """
    set -euo pipefail

    mkdir -p bids_defaced
    cp -aL "${bids_dir}/." bids_defaced/

    # Defensive cleanup in case the source dataset already contained old defaced files
    find bids_defaced -type f -name "*_defaced.nii.gz" -delete

    shopt -s nullglob
    defaced=(defaced/*_defaced.nii.gz)

    if [[ \${#defaced[@]} -eq 0 ]]; then
        echo "No defaced files were provided to MAKE_DEFACED_BIDS" >&2
        exit 1
    fi

    for f in "\${defaced[@]}"; do
        base="\$(basename "\$f")"
        orig="\${base/_defaced.nii.gz/.nii.gz}"

        mapfile -t targets < <(find bids_defaced -type f -path "*/anat/\$orig")

        if [[ \${#targets[@]} -eq 0 ]]; then
            echo "Could not find original anatomical file for defaced file: \$base" >&2
            echo "Expected original basename: \$orig" >&2
            exit 1
        fi

        if [[ \${#targets[@]} -gt 1 ]]; then
            echo "Ambiguous original anatomical file for defaced file: \$base" >&2
            printf '%s\n' "\${targets[@]}" >&2
            exit 1
        fi

        cp -f "\$f" "\${targets[0]}"
    done
    """
}
