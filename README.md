# Tricking Nextflow's Caching System

## Introduction

An unfortunate, but necessary aspect of bioinformatics is policing storage usage. This is due to both relatively large file sizes and the sheer number of files associated with potentially thousands of samples worth of data. It is easy to allow this usage to get out of hand in cases where strict controls are not in place. I am, unfortunately, guilty as charged when it comes to the sin of excess storage usage and I attribute most of this usage to Nextflow's picky caching system. This problem is not specific to me and my colleagues. In fact, a GitHub issues thread (link) regarding this topic recently celebrated its fifth birthday and Ben Sherman has, as of the writing of this post, started laying the ground work to allow Nextflow to utilize temporary intermediate files.

Our lab has been tackling the storage issue since deciding to use Nextflow DSL2 way back in November 2019. Despite our best efforts, we were unable to "trick" Nextflow into caching near-zero sized files. Luckily, Stephen Flickin and colleages, authors of GEMmaker, have developed a clever solution to this problem. This blog post is to show example explaining utility of this approach, to provide a syntactical tutorial showing implementation examples, and to describe some considerations and pitfalls I encountered while implementing it.

Before we discuss the technical aspects of intermediate file cleaning, let's further elaborate on the need for this functionality.

## Why?

Consider the following workflow and its associated files:

IMAGE HERE

In this case, we are only required to retain the first (raw FASTQs) and last (fully processed BAMs) files for the purposes of reproducibility and to satisfy downstream workflow inputs, respectively. Nevertheless, Nextflow in its current form requires the four intermediate files (which are only used as input and output once) to be available on the filesystem for workflow caching to perform as expected.

Now consider the following workflows and its associated files.

IMAGE HERE

Allowing for intermediates to be deleted results in a 75% reduction in storage requirements for the same eventual workflow outcome. This allows for more samples to be processed using the same storage with less downtime resulting from storage maintenance. This optimization can be taken to the extreme by having the fully processed BAM deleted once your workflow generates its final outputs (e.g. transcript counts, VCFs, etc.). There, of course, are trade-offs to this strategy which we'll discuss in the Limitations and Pitfalls section.

## How?
In a nutshell, the GEMmaker strategy works by creating a near zero sized file that resembles the original file closely enough that Nextflow cannot tell the difference. The bash script which performs this action can be found here: https://github.com/SystemsGenetics/GEMmaker/blob/master/bin/clean_work_files.sh. Briefly, the script `stat`s the file, records its findings, creates a sparse file(link) and modifies the sparse file's logical size, modification time, and access time to reflect those of the original file. The result is an indistinguishable (by Nextflow, anyways) file to serve as a placeholder for your previously large intermediate file.

## When?
Hopefully by this point one can appreciate the value of the modified sparse file when it comes to running large scale Nextflow workflows. It may be tempting to want to apply this hammer to all of the nails in your workflows. Unfortunately, every rose has its thorns and that saying applies in this scenario as well. Specifically, the timing of this cleaning process is relatively delicate as any downstream processes or workflows that utilize the cleanable intermediate files must have completed. If your workflows do not account for this and prematurely deletes the intermediate files, then your downstream processes will fail and you will be stuck re-running a portion of your workflow after debugging the cause. 
IMAGE HERE

The next aspect of "when?" is more philosophical -- is it better to delete as soon as possible or is it better to delete at the end of the workflow when all of your endpoint files are available? Should deletion occur within your top-level workflow (as in GEMmaker) or within subworkflows? We'll discuss the pros and cons as well as considerations to these questions in the Limitations and Pitfalls sections.

## An example

The GEMmaker implementation has been suggested as a potential workaround to commentors in Nextflow's GitHub Issue [#452](https://github.com/nextflow-io/nextflow/issues/452). I decided to attempt to implement this strategy at the strong (but understandable) insistence by our sysadmins to use less storage. I initially found the logic a bit hard to follow (the code is clear, but I am a mere geneticist, not a software engineer), so I wanted to create a verbose yet minimal example to explain the core logic. The code (`trick_nextflow_cache.nf`, `clean_work_dirs.sh`, and `utilities.nf`) can be found on GitHub: https://github.com/pirl-unc/tricking_nextflow_cache

First, we'll demonstrate the functionality and then walk through the script.

We begin with an empty work directory and run our Nextflow script for the first time:

```
[spvensko@c6145-2-9 tricking_nextflow_cache_example]$ du -hscL work/
4.0K    work
4.0K    total
```

```
[spvensko@c6145-2-9 tricking_nextflow_cache_example]$ nextflow trick_nextflow_cache.nf -resume
N E X T F L O W  ~  version 21.10.6
Launching `trick_nextflow_cache.nf` [romantic_fourier] - revision: 22b984aca2
executor >  slurm (2)
[22/0f9755] process > make_a_large_file  [100%] 1 of 1 ✔
[b1/d1cc88] process > inspect_large_file [100%] 1 of 1 ✔
```

Checking the work directories sizes revealed a ~1 Gb intermediate file generate by `make_a_large_file`:

```
[spvensko@c6145-2-9 tricking_nextflow_cache_example]$ du -hscL work/
1.1G    work/
1.1G    total
```

Now we will run the Nextflow script again and indicate that we'd like intermediate files to be deleted:

```
[spvensko@c6145-2-9 tricking_nextflow_cache_example]$ nextflow trick_nextflow_cache.nf -resume --delete_intermediates True
N E X T F L O W  ~  version 21.10.6
Launching `trick_nextflow_cache.nf` [exotic_jennings] - revision: 22b984aca2
executor >  slurm (1)
[22/0f9755] process > make_a_large_file    [100%] 1 of 1, cached: 1 ✔
[b1/d1cc88] process > inspect_large_file   [100%] 1 of 1, cached: 1 ✔
[16/f99612] process > clean_work_files (1) [100%] 1 of 1 ✔
```

Note the process `clean_work_files` ran this time.

Checking the work directories again revealed a reduction from ***1.1G to 60K***!

```
[spvensko@c6145-2-9 tricking_nextflow_cache_example]$ du -hscL work/*
24K     work/16
20K     work/22
16K     work/b1
60K     total
```

This in itself is not too impressive -- anyone can delete or replace a file in a work directory. The magical part happens when we re-run the workflow again:

```
[spvensko@c6145-2-9 tricking_nextflow_cache_example]$ nextflow trick_nextflow_cache.nf -resume --delete_intermediates True
N E X T F L O W  ~  version 21.10.6
Launching `trick_nextflow_cache.nf` [mighty_albattani] - revision: 22b984aca2
[22/0f9755] process > make_a_large_file    [100%] 1 of 1, cached: 1 ✔
[b1/d1cc88] process > inspect_large_file   [100%] 1 of 1, cached: 1 ✔
[16/f99612] process > clean_work_files (1) [100%] 1 of 1, cached: 1 ✔
```

Nextflow pulled the `make_a_large_file` process from cache despite file emitted by `make_a_large_file.out.a_large_file` being a 20K sparse file!

Next, let's go file-by-file and explain what's happening behind the scenes.

### `utilities.nf`

```
#!/usr/bin/env nextflow
process clean_work_dirs {
  input:
  tuple val(directory)

  output:
  val(1), emit: IS_CLEAN

  script:
  """
  for dir in ${directory}; do
  if [ -e \$dir ]; then
    echo "Cleaning: \$dir"
    files=`find \$dir -type f `
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
```

`utilities.nf` consists of two process -- `clean_work_dirs` and `clean_work_files`. `clean_work_dirs` appears to exhaustively delete the contents of a work directory while `clean_work_files` targets specific files for deletion. Personally, I have only been using `clean_work_files` within our workflows. I have included these processes into their own module to allow for easy aliasing when including the process into `main.nf`. For example, consider our current example in which we're running a single cleaning process. Defining the cleaning process within `main.nf` wouldn’t be the worst idea in the world. However, once you start cleaning multiple outputs files from multiple processes, having multiple cleaning processes defined in `main.nf` (as opposed to using aliasing while making `include` statements (see below)) get messy fast.

```
include { clean_work_files as clean_trimmed_fastqs } from '../utilities/utilities.nf'
include { clean_work_files as clean_sorted_bams } from '../utilities/utilities.nf'
...
```

