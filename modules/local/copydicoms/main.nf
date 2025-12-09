process COPYDICOMS {
    tag "$meta.id"
    label 'process_single'

    // TODO nf-core: See section in main README for further information regarding finding and adding container addresses to the section below.
    conda "${moduleDir}/environment.yml"
    // TODO CONTAINER IMPORTANT
    //container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        //'https://depot.galaxyproject.org/singularity/YOUR-TOOL-HERE':
        //'biocontainers/YOUR-TOOL-HERE' }"


    input:
    // meta carries sample context (id / subject / session / etc.)
    tuple val(meta), path(dicom_src)

    output:
    // Emit the copied directory as a single path (no file extensions needed)
    tuple val(meta), path("dicoms"), emit: dicoms
    path "versions.yml", emit: versions

    shell:
    """
    set -euo pipefail
    echo "COPYDICOMS for !{meta.id} from !{dicom_src}" >&2 ##

    # read ext.args from modules.config
    SEARCH_PATTERNS_CSV=""; INCLUDE_PATTERNS_CSV=""; EXCLUDE_PATTERNS_CSV=""
    set -o noglob    # <-- prevent * from expanding to files
    set -- !{ task.ext.args ?: '' }
    set +o noglob
    while [[ \$# -gt 0 ]]; do
    case "\$1" in
        --search)  SEARCH_PATTERNS_CSV="\$2"; shift 2 ;;
        --include) INCLUDE_PATTERNS_CSV="\$2"; shift 2 ;;
        --exclude) EXCLUDE_PATTERNS_CSV="\$2"; shift 2 ;;
        *) shift ;;
    esac
    done

    IFS=',' read -r -a SEARCH_PATTERNS  <<< "\${SEARCH_PATTERNS_CSV}"
    IFS=',' read -r -a INCLUDE_PATTERNS <<< "\${INCLUDE_PATTERNS_CSV}"
    IFS=',' read -r -a EXCLUDE_PATTERNS <<< "\${EXCLUDE_PATTERNS_CSV}"
    [[ \${#SEARCH_PATTERNS[@]} -eq 0 || -z "\${SEARCH_PATTERNS[0]:-}" ]] && SEARCH_PATTERNS=('*')



    # Default search patterns if none provided (match your bash script)
    if [[ \${#SEARCH_PATTERNS[@]} -eq 0 || -z "\${SEARCH_PATTERNS[0]:-}" ]]; then
        SEARCH_PATTERNS=('*') ## (NoOwner IRIS)
    fi

    # sanity checks for testing - remove later
    echo "SEARCH=\${SEARCH_PATTERNS[@]} INCLUDE=\${INCLUDE_PATTERNS[@]} EXCLUDE=\${EXCLUDE_PATTERNS[@]}" >&2

    echo "PWD=\$(pwd)"; ls -la
    echo "dicom_src type: \$(stat -c '%F' !{dicom_src} || true)"
    #find "!{dicom_src}" -maxdepth 1 -type d -print >&2

    mapfile -t parents < <(find -L "!{dicom_src}" -mindepth 1 -maxdepth 1 -type d)


    echo "parents: \${parents[@]}" >&2

    should_skip() {
      local folder="\$1"
      for pattern in "\${EXCLUDE_PATTERNS[@]}"; do
        [[ -z "\$pattern" ]] && continue
        if [[ "\$folder" == \$pattern ]]; then
          return 0
        fi
      done
      return 1
    }

    should_include() {
      local folder="\$1"
      # If no include patterns set, include everything
      local have_inc=0
      for pattern in "\${INCLUDE_PATTERNS[@]}"; do
        [[ -n "\$pattern" ]] && { have_inc=1; break; }
      done
      if [[ \$have_inc -eq 0 ]]; then
        return 0
      fi
      for pattern in "\${INCLUDE_PATTERNS[@]}"; do
        [[ -z "\$pattern" ]] && continue
        if [[ "\$folder" == \$pattern ]]; then
          return 0
        fi
      done
      return 1
    }

    # make target directory
    mkdir -p dicoms

    # Keep only those whose names match any SEARCH_PATTERNS
    for parent in "\${parents[@]}"; do
        dir_name="\$(basename "\$parent")"
        match=0
        for pat in "\${SEARCH_PATTERNS[@]}"; do
        [[ -z "\$pat" ]] && continue
        if [[ "\$dir_name" == \$pat ]]; then
            match=1
            break
        fi
        done
        [[ \$match -eq 0 ]] && continue


        # Subjects one level below each matched parent
        found=0
        parent_dest="dicoms/\$dir_name"
        mkdir -p "\$parent_dest"
        while IFS= read -r -d '' sub; do
            found=1
            folder_name="\$(basename "\$sub")"

            should_include "\$folder_name" || continue
            if should_skip "\$folder_name"; then
            echo "Skipping \$folder_name: excluded" >&2
            continue
            fi

            dest="\$parent_dest/\$folder_name"
            if [[ -d "\$dest" ]]; then
                echo "  skip (exists): \$dest" >&2
            else
                echo "  cp -a '\$sub' -> '\$parent_dest/'" >&2
                cp -a "\$sub" "\$parent_dest/"
            fi
        done < <(find -L "\$parent" -mindepth 1 -maxdepth 1 -type d -print0)
        
        # fallback: if no child dirs, copy the parent itself
        if [[ \$found -eq 0 ]]; then
            echo "  no children; copying parent '\$dir_name' -> dicoms/" >&2
            cp -a "\$parent" "dicoms/"
        fi
    done


    # versions file
    cat > versions.yml <<YML
    COPYDICOMS:
      tool: copydicoms
      params:
        search_patterns: "\${SEARCH_PATTERNS_CSV}"
        include_patterns: "\${INCLUDE_PATTERNS_CSV}"
        exclude_patterns: "\${EXCLUDE_PATTERNS_CSV}"
    YML
    """

}

