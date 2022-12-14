# Tricking Nextflow's Caching System

## Introduction

An unfortunate, but necessary aspect of bioinformatics is policing storage usage. This is due to both relatively large file sizes and the sheer number of files associated with potentially thousands of samples worth of data. It is easy to allow this usage to get out of hand in cases where strict controls are not in place. I am, unfortunately, guilty as charged when it comes to the sin of excess storage usage and I attribute most of this usage to Nextflow's picky caching system. This problem is not specific to me and my colleagues. In fact, a GitHub issues thread (link) regarding this topic recently celebrated its fifth birthday and Ben Sherman has, as of the writing of this post, started laying the ground work to allow Nextflow to utilize temporary intermediate files.

Our lab has been tackling the storage issue since deciding to use Nextflow DSL2 way back in November 2019. Despite our best efforts, we were unable to "trick" Nextflow into caching near-zero sized files. Luckily, Stephen Flickin and colleages, authors of GEMmaker, have developed a clever solution to this problem. This blog post is to show example explaining utility of this approach, to provide a syntactical tutorial showing implementation examples, and to describe some considerations and pitfalls I encountered while implementing it.

Before we discuss the technical aspects of intermediate file cleaning, let's further elaborate on the need for this functionality.

##Why?

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


