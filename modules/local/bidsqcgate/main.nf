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


  container "${ task.ext.container ?: (params.bids_qc_container ?: 'python:3.11-slim') }"

  input:
  path bids_log

  output:
  path "bids_qc_summary.txt", emit: summary
  path "bids_qc_report.json", emit: report

  errorStrategy 'terminate'

  script:
  def policy  = params.bids_qc_policy ?: 'nfcore'   
  def failW   = (params.bids_qc_fail_warnings  ?: []).join(',')
  def ignoreW = (params.bids_qc_ignore_warnings ?: []).join(',')

  """
  set -euo pipefail

  python3 ${projectDir}/bin/bids_gate.py \
    --log ${bids_log} \
    --allow-warnings ${warnings_ok_file} \
    --helpers ${help_file} \
    --summary-out bids_qc_summary.txt \
    --json-out bids_qc_report.json

  """
}
