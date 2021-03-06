#' @title Create cluster functions for SLURM-based systems.
#'
#' @description
#' Job files are created based on the brew template
#' \code{template.file}. This file is processed with brew and then
#' submitted to the queue using the \code{sbatch} command. Jobs are
#' killed using the \code{scancel} command and the list of running jobs
#' is retrieved using \code{squeue}. The user must have the
#' appropriate privileges to submit, delete and list jobs on the
#' cluster (this is usually the case).
#'
#' The template file can access all arguments passed to the
#' \code{submitJob} function, see here \code{\link{ClusterFunctions}}.
#' It is the template file's job to choose a queue for the job
#' and handle the desired resource allocations.
#' Examples can be found on
#' \url{https://github.com/tudo-r/BatchJobs/tree/master/examples/cfSLURM}.
#'
#' @template arg_template
#' @template arg_list_jobs_cmd
#' @template ret_cf
#' @param list.job.line.skip [\code{integer(1)}]\cr
#'    Change how many lines of the job list should be skipped. Can be useful if \code{squeue} is giving
#'    additional output.
#' @param cluster.name [\code{character(1)}]\cr
#'    If an additional cluster name has to be specified for listing or deleting jobs it can be 
#'    supplied with this argument. it will be added as \code{--clusters=cluster.name} for SLURM.
#' @family clusterFunctions
#' @export
makeClusterFunctionsSLURM = function(template.file, list.jobs.cmd = c("squeue", "-h", "-o %i", "-u $USER"),
                                     list.job.line.skip = 0L, cluster.name = NULL) {
  
  if (!is.null(cluster.name)) {
    assertString(cluster.name)
    list.jobs.cmd = append(list.jobs.cmd, paste0("--clusters=", cluster.name))
  }
  assertCharacter(list.jobs.cmd, min.len = 1L, any.missing = FALSE)
  assertCount(list.job.line.skip)
  template = cfReadBrewTemplate(template.file)

  submitJob = function(conf, reg, job.name, rscript, log.file, job.dir, resources, arrayjobs) {
    outfile = cfBrewTemplate(conf, template, rscript, "sb")
    res = runOSCommandLinux("sbatch", outfile, stop.on.exit.code = FALSE)

    max.jobs.msg = "sbatch: error: Batch job submission failed: Job violates accounting policy (job submit limit, user's size and/or time limits)"
    temp.error = "Socket timed out on send/recv operation"
    output = collapse(res$output, sep = "\n")
    if (grepl(max.jobs.msg, output, fixed = TRUE)) {
      makeSubmitJobResult(status = 1L, batch.job.id = NA_character_, msg = max.jobs.msg)
    } else if (grepl(temp.error, output, fixed = TRUE)) {
      # another temp error we want to catch
      makeSubmitJobResult(status = 2L, batch.job.id = NA_character_, msg = temp.error)
    } else if (res$exit.code > 0L) {
      cfHandleUnknownSubmitError("sbatch", res$exit.code, res$output)
    } else {
      makeSubmitJobResult(status = 0L, batch.job.id = stri_trim_both(stri_split_fixed(output, " ")[[1L]][4L]))
    }
  }

  killJob = function(conf, reg, batch.job.id) {

    
    if (!is.null(cluster.name)) {
      cfKillBatchJob("scancel",paste0("--clusters=", cluster.name, " ", batch.job.id))
    }
    cfKillBatchJob("scancel", batch.job.id)
  }

  listJobs = function(conf, reg) {
    # Result is lines of fully quantified batch.job.ids
    jids = runOSCommandLinux(list.jobs.cmd[1L], list.jobs.cmd[-1L])$output
    # if squeue returns additional information (like cluster name), one or more
    # lines can be omitted
    if (list.job.line.skip > 0L) {
      jids = jids[-seq_len(list.job.line.skip)]
    }
    stri_extract_first_regex(jids, "[0-9]+")
  }

  getArrayEnvirName = function() "SLURM_ARRAY_TASK_ID"

  makeClusterFunctions(name = "SLURM", submitJob = submitJob, killJob = killJob,
                       listJobs = listJobs, getArrayEnvirName = getArrayEnvirName)
}
