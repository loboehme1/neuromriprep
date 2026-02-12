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

process BIDSIGNORE {

  tag "${meta.id}"
  label 'process_low'

  // Key: make Nextflow stage inputs as a real copy in the work dir
  stageInMode 'copy'

  container "${ task.ext.container ?: '/home/loboehme/Documents/container/docker-curl-jq.sif' }"

  input:
  tuple val(meta),
        path(dataset_dir, stageAs: 'bids_dataset'),   // staged folder name
        path(ignore_add),
        path(ignore_remove)

  output:
  tuple val(meta), path("bids_dataset"), emit: bids_dataset
  path "*.log", emit: log
  path "versions.yml", emit: versions

  script:
  def prefix = task.ext.prefix ?: "${meta.id}"
  """
  set -euo pipefail

  INPUT_DIR="bids_dataset"
  LOGFILE="${prefix}_bidsignore.log"

  echo "\$(date +"%Y-%m-%d %H:%M:%S") - Dataset root: \$(pwd)/\$INPUT_DIR" | tee -a "\$LOGFILE"

  # Ensure .bidsignore exists
  if [ ! -f "\$INPUT_DIR/.bidsignore" ]; then
    echo "\$(date +"%Y-%m-%d %H:%M:%S") - Creating .bidsignore" | tee -a "\$LOGFILE"
    : > "\$INPUT_DIR/.bidsignore"
  fi

  echo "\$(date +"%Y-%m-%d %H:%M:%S") - Initial .bidsignore:" | tee -a "\$LOGFILE"
  cat "\$INPUT_DIR/.bidsignore" | tee -a "\$LOGFILE" || true
  echo | tee -a "\$LOGFILE"

  # Add entries
  while IFS= read -r ITEM; do
    [ -z "\$ITEM" ] && continue
    case "\$ITEM" in \\#*) continue ;; esac
    if ! grep -Fxq "\$ITEM" "\$INPUT_DIR/.bidsignore"; then
      echo "\$(date +"%Y-%m-%d %H:%M:%S") - Adding '\$ITEM'" | tee -a "\$LOGFILE"
      echo "\$ITEM" >> "\$INPUT_DIR/.bidsignore"
    fi
  done < "${ignore_add}"

  # Remove entries
  if [ -s "${ignore_remove}" ]; then
    while IFS= read -r ITEM; do
      [ -z "\$ITEM" ] && continue
      case "\$ITEM" in \\#*) continue ;; esac
      if grep -Fxq "\$ITEM" "\$INPUT_DIR/.bidsignore"; then
        echo "\$(date +"%Y-%m-%d %H:%M:%S") - Removing '\$ITEM'" | tee -a "\$LOGFILE"
        grep -Fxv "\$ITEM" "\$INPUT_DIR/.bidsignore" > "\$INPUT_DIR/.bidsignore.tmp"
        mv "\$INPUT_DIR/.bidsignore.tmp" "\$INPUT_DIR/.bidsignore"
      fi
    done < "${ignore_remove}"
  fi

  echo "\$(date +"%Y-%m-%d %H:%M:%S") - Final .bidsignore:" | tee -a "\$LOGFILE"
  cat "\$INPUT_DIR/.bidsignore" | tee -a "\$LOGFILE" || true
  echo | tee -a "\$LOGFILE"

  cat <<-END_VERSIONS > versions.yml
  "${task.process}":
    tool: "shell"
  END_VERSIONS
  """
}

