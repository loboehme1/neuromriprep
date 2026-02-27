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

process BIDS_QC_GATE {

  tag "bids-qc"

  label 'process_single'

  stageInMode 'copy'


  container { task.ext.container ?: '/home/loboehme/Documents/container/ownconts/python_3.11.14-trixie.sif' }

  input:
  tuple val(meta), path(bids_log), path(gate_py), path(warnings_ok), path(helpers)

  output:
  path("bids_qc_summary.txt"), emit: summary
  path("bids_qc_report.json"), emit: report
  tuple val(meta), path("check_passed.txt")   , emit: passed
  path "versions.yml"                         , emit: versions


script:
  def extra_args = task.ext.args ?: ''

  def helpers_arg = ''
  if( helpers instanceof List ) {
    if( helpers ) helpers_arg = "--helpers ${helpers[0]}"
  } else if( helpers ) {
    helpers_arg = "--helpers ${helpers}"
  }

  """
  set -euo pipefail

  python3 ${gate_py} \
    --log ${bids_log} \
    --allow-warnings ${warnings_ok} \
    ${helpers_arg} \
    --summary-out bids_qc_summary.txt \
    --json-out bids_qc_report.json \
    ${extra_args}

  python3 - <<'PY' > check_passed.txt
  import json
  with open("bids_qc_report.json") as f:
      print(str(json.load(f)["check_passed"]).lower())
  PY


  cat <<-END_VERSIONS > versions.yml
  "${task.process}":
    python: "\$(python3 --version 2>&1 | awk '{print \$2}')"
  END_VERSIONS
  """
}