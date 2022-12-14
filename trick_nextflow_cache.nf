nextflow.enable.dsl=2

include { clean_work_files } from './utilities.nf'

params.delete_intermediates = ''

process make_a_large_file {

  cache 'lenient'

  output:
  tuple val("foo"), path("1G_file"), emit: a_large_file

  script:
  """
  dd if=/dev/zero of=1G_file bs=1G count=1
  """
}

process inspect_large_file {

  cache 'lenient'

  input:
  tuple val(samp), path(required_input_file)

  output:
  tuple val(samp), path("file_stats"), emit: file_stats

  script:
  """
  ls -ldhrt ${required_input_file} > file_stats
  """
}

workflow {
  make_a_large_file()
  make_a_large_file.out.a_large_file.view()
  inspect_large_file(
    make_a_large_file.out.a_large_file)
  inspect_large_file.out.file_stats.view()
  make_a_large_file.out.a_large_file                                                                
    .join(inspect_large_file.out.file_stats, by: [0])                                               
    .flatten()                                                                                      
    .filter{ it =~ /_file$/}                                                                        
    .set{ large_file_done_signal }                                                                  
  large_file_done_signal.view() 
  if( params.delete_intermediates ) {
    clean_work_files(
      large_file_done_signal)
  }
}
