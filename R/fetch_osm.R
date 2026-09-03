# Overpass feature filters. Any way carrying one of these is a candidate for
# bicycle infrastructure; cl_classify() decides what it actually is.
.cl_osm_features <- c(
  '"highway"="cycleway"',
  '"cycleway"',
  '"cycleway:left"',
  '"cycleway:right"',
  '"cycleway:both"',
  '"bicycle"="designated"',
  '"bicycle_road"="yes"',
  '"cyclestreet"="yes"'
)

#' Fetch raw bicycle-related ways from OpenStreetMap
#'
#' Queries the Overpass API for every way inside `place` that carries a tag
#' which can denote bicycle infrastructure: `highway=cycleway`, any
#' `cycleway`, `cycleway:left`, `cycleway:right` or `cycleway:both` tag,
#' `bicycle=designated`, `bicycle_road=yes`, or `cyclestreet=yes`. The result
#' is *unclassified*: many of these ways (a footway with `bicycle=designated`,
#' a road tagged `cycleway=no`) are not facilities. Pass it to
#' [cl_classify()] or use [cl_bike_lanes()] which does both.
#'
#' Overpass is a shared public service that answers `HTTP 429` when an
#' address queries too often and `504` when it is overloaded. Those are
#' retried with exponential backoff (`retries`), a mirror can be used for
#' one call (`overpass_url`), large areas can be split into tiles (`tile`),
#' and results can be cached on disk (`cache`) so a re-run of a script does
#' not hit the server at all.
#'
#' @inheritParams cl_bbox
#' @param timeout Overpass server timeout in seconds. City-scale queries can
#'   take a minute or more; the public Overpass instance rejects long-running
#'   queries, so keep `place` to a metro area or smaller.
#' @param clip Overpass only takes a bounding box, and the box around a city
#'   usually spills into its neighbours. `TRUE` (the default) clips the result
#'   to the place's administrative boundary from [cl_boundary()] when `place`
#'   is a name; ways crossing the boundary are cut at it. Pass an `sf`/`sfc`
#'   polygon to clip to your own boundary with any kind of `place`, or
#'   `FALSE` to keep the whole box. Ignored for bbox and `sf` inputs unless a
#'   polygon is supplied.
#' @param overpass_url Overpass endpoint for this call only, e.g.
#'   `"https://overpass.private.coffee/api/interpreter"`. Must end in
#'   `/interpreter`. The session-wide default set with
#'   [osmdata::set_overpass_url()] is restored afterwards.
#' @param retries How many times to retry a transient failure (429, 502,
#'   503, 504, timeout) before giving up. Waits start at 30 s and double,
#'   with jitter, capped at 5 minutes.
#' @param tile Split the bounding box into tiles of at most this many
#'   degrees on a side and query each, de-duplicating ways by `osm_id`.
#'   `NULL` (default) sends one query. Use around `0.25` for areas that
#'   time out; note each tile is a separate request against the server's
#'   per-address rate limit.
#' @param cache Store the raw Overpass result under `cache_dir` and reuse it
#'   for the same bounding box within `cache_max_age` days.
#' @param cache_dir Directory for cached results; see [cl_cache_dir()].
#' @param cache_max_age Maximum age in days of a cached result to reuse.
#' @param backend `"overpass"` (default) queries the Overpass API for the
#'   bounding box. `"extract"` downloads the smallest Geofabrik extract
#'   covering the box through the `osmextract` package, converts it once,
#'   and reads the ways from there: no Overpass request at all, so no rate
#'   limit, and the second place in the same region is instant. The first
#'   download of a US state is 50-300 MB and the conversion takes a few
#'   minutes; extracts lag OSM by about a day. Right for a city or a batch
#'   of cities; Overpass is right for a neighbourhood.
#' @param extract_dir Where `osmextract` keeps downloaded extracts. Defaults
#'   to [osmextract::oe_download_directory()], which honours the
#'   `OSMEXT_DOWNLOAD_DIRECTORY` environment variable.
#' @return An `sf` object of `LINESTRING`s in WGS84 (EPSG:4326) with the raw
#'   OSM tag columns present in the area. A zero-row `sf` if nothing matched.
#'   The WGS84 bounding box queried is stored in `attr(x, "cl_bbox")`, the
#'   clipping polygon (if any) in `attr(x, "cl_boundary")`, and the fetch
#'   time in `attr(x, "cl_fetched")` (the original fetch time for a cache hit).
#' @examples
#' \dontrun{
#' raw <- cl_fetch_osm(c(-105.00, 39.74, -104.98, 39.75))
#' nrow(raw)
#'
#' # a mirror, with caching so the next run is instant
#' raw <- cl_fetch_osm("Boulder, Colorado", cache = TRUE,
#'                     overpass_url = "https://overpass.private.coffee/api/interpreter")
#' }
#' @export
cl_fetch_osm <- function(place, timeout = 180, clip = TRUE, overpass_url = NULL,
                         retries = 3, tile = NULL, cache = FALSE,
                         cache_dir = cl_cache_dir(), cache_max_age = 30,
                         backend = c("overpass", "extract"), extract_dir = NULL) {
  backend <- match.arg(backend)
  bb <- cl_bbox(place)
  boundary <- .resolve_clip(place, clip)
  if (!is.null(overpass_url)) {
    if (!is.character(overpass_url) || length(overpass_url) != 1L ||
        !grepl("/interpreter/?$", overpass_url)) {
      rlang::abort("`overpass_url` must be a single URL ending in /interpreter.")
    }
    old <- options(osmdata.base_url = overpass_url)
    on.exit(options(old), add = TRUE)
  }
  if (!is.null(tile) && (!is.numeric(tile) || length(tile) != 1L || tile <= 0)) {
    rlang::abort("`tile` must be NULL or a single positive number of degrees.")
  }

  key <- .overpass_cache_key(bb, tile, backend)
  hit <- if (isTRUE(cache)) .cache_read(key, cache_dir, cache_max_age) else NULL
  if (!is.null(hit)) {
    rlang::inform(sprintf("Using cached %s result fetched %s.",
                          if (backend == "extract") "extract" else "Overpass",
                          format(hit$fetched, "%Y-%m-%d %H:%M")))
    lines <- hit$lines
    fetched <- hit$fetched
  } else if (backend == "extract") {
    lines <- .extract_lines(bb, extract_dir)
    fetched <- Sys.time()
    if (isTRUE(cache)) .cache_write(key, cache_dir, list(lines = lines, fetched = fetched, bbox = bb))
  } else {
    boxes <- .tile_bbox(bb, tile)
    parts <- lapply(boxes, function(b) .overpass_lines(b, timeout, retries))
    lines <- .bind_osm_lines(parts)
    fetched <- Sys.time()
    if (isTRUE(cache)) .cache_write(key, cache_dir, list(lines = lines, fetched = fetched, bbox = bb))
  }

  if (nrow(lines) == 0L) {
    rlang::warn("Overpass returned no bicycle-tagged ways for this area.")
    lines <- .empty_osm_sf()
  } else {
    lines <- sf::st_transform(lines, 4326)
    rownames(lines) <- NULL
    if (!is.null(boundary)) lines <- .clip_lines(lines, boundary)
  }
  attr(lines, "cl_bbox") <- bb
  attr(lines, "cl_boundary") <- boundary
  attr(lines, "cl_fetched") <- fetched
  attr(lines, "cl_backend") <- backend
  lines
}

# Work out the clipping polygon (or NULL) from `place` and `clip`.
.resolve_clip <- function(place, clip) {
  if (inherits(clip, c("sf", "sfc"))) return(cl_boundary(clip))
  if (!is.logical(clip) || length(clip) != 1L || is.na(clip)) {
    rlang::abort("`clip` must be TRUE, FALSE, or an sf/sfc polygon.")
  }
  if (!clip || !is.character(place)) return(NULL)
  tryCatch(cl_boundary(place), error = function(e) {
    rlang::warn(c("Could not fetch a boundary polygon; returning the whole bounding box.",
                  i = conditionMessage(e)))
    NULL
  })
}

.empty_osm_sf <- function() {
  sf::st_sf(
    osm_id = character(),
    geometry = sf::st_sfc(crs = 4326)
  )
}

# Overpass query with retries --------------------------------------------------

# One Overpass query for one bbox; NULL when it returned no lines.
.overpass_lines <- function(bb, timeout, retries) {
  q <- osmdata::opq(bbox = bb, timeout = timeout)
  q <- osmdata::add_osm_features(q, features = .cl_osm_features)
  res <- .with_retries(function() .overpass_query(q), retries = retries)
  lines <- res$osm_lines
  if (is.null(lines) || nrow(lines) == 0L) return(NULL)
  sf::st_as_sf(lines)
}

# The actual network call. Mocked in tests.
.overpass_query <- function(q) {
  osmdata::osmdata_sf(q)
}

# Mocked in tests so retries do not actually wait.
.backoff_sleep <- function(seconds) {
  Sys.sleep(seconds)
}

.transient_classes <- c("httr2_http_429", "httr2_http_502", "httr2_http_503", "httr2_http_504")

.is_transient <- function(e) {
  inherits(e, .transient_classes) ||
    grepl("\\b(429|502|503|504)\\b|timed? ?out|gateway|too many requests|overloaded",
          conditionMessage(e), ignore.case = TRUE)
}

.http_code <- function(e) {
  cls <- grep("^httr2_http_[0-9]+$", class(e), value = TRUE)
  if (length(cls)) return(sub("httr2_http_", "HTTP ", cls[1]))
  m <- regmatches(conditionMessage(e), regexpr("\\b(429|502|503|504)\\b", conditionMessage(e)))
  if (length(m)) paste("HTTP", m) else "a transient error"
}

.with_retries <- function(fn, retries = 3, base_wait = 30, max_wait = 300) {
  attempt <- 0L
  repeat {
    attempt <- attempt + 1L
    res <- tryCatch(list(ok = TRUE, value = fn()),
                    error = function(e) list(ok = FALSE, error = e))
    if (res$ok) return(res$value)
    e <- res$error
    if (!.is_transient(e) || attempt > retries) {
      server <- tryCatch(osmdata::get_overpass_url(), error = function(err) "the Overpass server")
      rlang::abort(c(
        sprintf("Overpass query failed after %d attempt%s.", attempt, if (attempt == 1L) "" else "s"),
        x = conditionMessage(e),
        i = sprintf("Server: %s. Wait a few minutes, pass `overpass_url` for a mirror, or use `cache = TRUE` to avoid re-fetching.", server)
      ), parent = e)
    }
    wait <- min(max_wait, base_wait * 2^(attempt - 1L) * stats::runif(1, 0.8, 1.2))
    rlang::inform(sprintf("Overpass answered %s; retry %d of %d in %.0f s.",
                          .http_code(e), attempt, retries, wait))
    .backoff_sleep(wait)
  }
}

# Tiling -----------------------------------------------------------------------

.tile_bbox <- function(bb, tile = NULL) {
  if (is.null(tile)) return(list(bb))
  nx <- max(1L, ceiling((bb[["xmax"]] - bb[["xmin"]]) / tile))
  ny <- max(1L, ceiling((bb[["ymax"]] - bb[["ymin"]]) / tile))
  xs <- seq(bb[["xmin"]], bb[["xmax"]], length.out = nx + 1L)
  ys <- seq(bb[["ymin"]], bb[["ymax"]], length.out = ny + 1L)
  out <- list()
  for (i in seq_len(nx)) {
    for (j in seq_len(ny)) {
      out[[length(out) + 1L]] <- c(xmin = xs[i], ymin = ys[j], xmax = xs[i + 1L], ymax = ys[j + 1L])
    }
  }
  out
}

# Combine per-tile results, dropping ways that fell in more than one tile.
.bind_osm_lines <- function(parts) {
  parts <- Filter(Negate(is.null), parts)
  if (!length(parts)) return(.empty_osm_sf())
  if (length(parts) == 1L) return(parts[[1]])
  out <- do.call(dplyr::bind_rows, parts)
  out <- sf::st_as_sf(out)
  if ("osm_id" %in% names(out)) out <- out[!duplicated(out$osm_id), ]
  out
}

# Extract backend --------------------------------------------------------------

# Every tag cl_classify() reads, plus the ones the Overpass filter keys on,
# requested as columns from the extract's lines layer.
.cl_extract_tags <- c(
  "name", "cycleway", "cycleway:left", "cycleway:right", "cycleway:both",
  "cycleway:buffer", "cycleway:left:buffer", "cycleway:right:buffer",
  "cycleway:both:buffer", "bicycle", "bicycle_road", "cyclestreet", "foot",
  "footway", "segregated", "is_sidepath", "oneway", "surface", "lit", "width"
)

# Bicycle-relevant ways from a Geofabrik extract covering `bb`, in the same
# shape as an Overpass result (osm_id, highway, tag columns, geometry).
.extract_lines <- function(bb, extract_dir = NULL) {
  rlang::check_installed("osmextract", reason = "for backend = \"extract\"")
  poly <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = bb[["xmin"]], ymin = bb[["ymin"]], xmax = bb[["xmax"]], ymax = bb[["ymax"]]),
    crs = sf::st_crs(4326)))
  raw <- .extract_query(poly, extract_dir)
  if (is.null(raw) || nrow(raw) == 0L) return(.empty_osm_sf())
  raw <- .ensure_cols(raw, c("osm_id", "highway", .cl_extract_tags))
  keep <- !is.na(raw$highway) & (
    .norm_tag(raw$highway) %in% "cycleway" |
      !is.na(raw$cycleway) | !is.na(raw[["cycleway:left"]]) |
      !is.na(raw[["cycleway:right"]]) | !is.na(raw[["cycleway:both"]]) |
      .norm_tag(raw$bicycle) %in% "designated" |
      .tag_truthy(raw$bicycle_road) | .tag_truthy(raw$cyclestreet)
  )
  out <- raw[keep, ]
  out <- out[, setdiff(names(out), c("z_order", "other_tags"))]
  out$osm_id <- as.character(out$osm_id)
  out <- sf::st_transform(out, 4326)
  rownames(out) <- NULL
  out
}

# The actual osmextract call. Mocked in tests.
.extract_query <- function(poly, extract_dir = NULL) {
  args <- list(
    place = poly, layer = "lines", provider = "geofabrik",
    extra_tags = .cl_extract_tags,
    boundary = poly, boundary_type = "clipsrc",
    max_file_size = Inf, quiet = TRUE
  )
  if (!is.null(extract_dir)) args$download_directory <- extract_dir
  do.call(osmextract::oe_get, args)
}
