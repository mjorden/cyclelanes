#' Where cached Overpass results live
#'
#' `cl_cache_dir()` returns the directory [cl_fetch_osm()] uses when
#' `cache = TRUE`: the `CYCLELANES_CACHE_DIR` environment variable if set,
#' otherwise the per-user cache directory from [tools::R_user_dir()].
#' `cl_cache_clear()` deletes every cached result in it.
#'
#' @param cache_dir Directory to clear.
#' @return `cl_cache_dir()`: a path. `cl_cache_clear()`: the number of files
#'   removed, invisibly.
#' @examples
#' cl_cache_dir()
#' @export
cl_cache_dir <- function() {
  env <- Sys.getenv("CYCLELANES_CACHE_DIR", unset = "")
  if (nzchar(env)) return(env)
  tools::R_user_dir("cyclelanes", which = "cache")
}

#' @rdname cl_cache_dir
#' @export
cl_cache_clear <- function(cache_dir = cl_cache_dir()) {
  files <- list.files(cache_dir, pattern = "^overpass-.*\\.rds$", full.names = TRUE)
  if (length(files)) unlink(files)
  invisible(length(files))
}

.overpass_cache_key <- function(bb, tile = NULL, backend = "overpass") {
  rlang::hash(list(bbox = round(unname(bb), 6), features = .cl_osm_features,
                   tile = tile, backend = backend, version = 1L))
}

.cache_path <- function(key, cache_dir) {
  file.path(cache_dir, paste0("overpass-", key, ".rds"))
}

.cache_read <- function(key, cache_dir, max_age_days) {
  path <- .cache_path(key, cache_dir)
  if (!file.exists(path)) return(NULL)
  hit <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(hit) || !inherits(hit$lines, "sf") || is.null(hit$fetched)) return(NULL)
  age <- as.numeric(difftime(Sys.time(), hit$fetched, units = "days"))
  if (age > max_age_days) return(NULL)
  hit
}

.cache_write <- function(key, cache_dir, value) {
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(value, .cache_path(key, cache_dir))
  invisible(TRUE)
}
