#!/usr/bin/env nextflow

process clean_work_dirs {

    tuple val(directory)

    output:
    val(1), emit: IS_CLEAN

    script:
    """
    for dir in ${directory}; do
      if [ -e \$dir ]; then
        echo "Cleaning: \$dir"
        files=`find \$dir -type  f `
        echo "Files to delete: \$files"
        clean_work_files.sh "\$files" "null"
      fi
    done
    """
}

process clean_work_files {
    cache 'lenient'

    input:
    val(file)

    output:
    val(1), emit: IS_CLEAN

    script:
    """
    clean_work_files.sh "${file}"
    """
}
