include { MRIQC_PARTICIPANT } from '../../../modules/local/mriqcparticipant/'

workflow MRIQC_PARTICIPANTS {

  take:
    ch_in
    vpn_file

  main:
    def readVpnLabels = { vpnPath ->
      if( !vpnPath ) 
        return [] as Set
      def f = file(vpnPath)
      if( !f.exists() ) 
        error "VPN file not found: ${vpnPath}"
      return f.readLines()
        .collect { it.replace('\r','').trim() }
        .findAll { it && !it.startsWith('#') }
        .collectMany { it.tokenize() }
        .collect { it.replaceFirst(/^sub-/, '') }
        .toSet()
    }

    def vpnSet = readVpnLabels(vpn_file)

    def ch_filtered = ch_in.filter { meta, bids ->
      vpnSet.isEmpty() || vpnSet.contains(meta.subject.toString())
    }
 
    def run = MRIQC_PARTICIPANT(ch_filtered)

  emit:
    mriqc_out = run.mriqc_out
    mriqc_log = run.mriqc_log 
    versions  = run.versions
}
