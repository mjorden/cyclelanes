#' Resolve a place into a WGS84 bounding box
#'
#' Accepts the same `place` argument as every fetch function in the package
#' and returns a bounding box in longitude/latitude degrees.
#'
#' @param place One of:
#'   * a place name geocoded through Nominatim, e.g. `"Denver, Colorado"`
#'     (respect the Nominatim usage policy: at most one request per second,
#'     no bulk geocoding);
#'   * a numeric vector `c(xmin, ymin, xmax, ymax)` in WGS84 degrees;
#'   * an `sf`, `sfc`, or `bbox` object in any CRS;
#'   * the 2 x 2 matrix returned by [osmdata::getbb()].
#' @return A named numeric vector `c(xmin, ymin, xmax, ymax)`.
#' @examples
#' cl_bbox(c(-105.02, 39.73, -104.97, 39.76))
#' \dontrun{
#' cl_bbox("Denver, Colorado")
#' }
#' @export
cl_bbox <- function(place) {
  if (inherits(place, c("sf", "sfc"))) {
    bb <- sf::st_bbox(sf::st_transform(place, 4326))
    return(.validate_bbox(as.numeric(bb)))
  }
  if (inherits(place, "bbox")) {
    bb <- sf::st_bbox(sf::st_transform(sf::st_as_sfc(place), 4326))
    return(.validate_bbox(as.numeric(bb)))
  }
  if (is.matrix(place) && all(dim(place) == c(2L, 2L))) {
    return(.validate_bbox(c(place[1, 1], place[2, 1], place[1, 2], place[2, 2])))
  }
  if (is.numeric(place) && length(place) == 4L) {
    return(.validate_bbox(as.numeric(place)))
  }
  if (is.character(place) && length(place) == 1L) {
    return(.geocode_bbox(place))
  }
  rlang::abort(paste(
    "`place` must be a place name, a numeric c(xmin, ymin, xmax, ymax),",
    "an sf/sfc/bbox object, or a 2x2 getbb() matrix."
  ))
}

.validate_bbox <- function(bb) {
  bb <- as.numeric(bb)
  names(bb) <- c("xmin", "ymin", "xmax", "ymax")
  ok <- all(is.finite(bb)) &&
    bb[["xmin"]] < bb[["xmax"]] && bb[["ymin"]] < bb[["ymax"]] &&
    all(bb[c("xmin", "xmax")] >= -180) && all(bb[c("xmin", "xmax")] <= 180) &&
    all(bb[c("ymin", "ymax")] >= -90) && all(bb[c("ymin", "ymax")] <= 90)
  if (!ok) {
    rlang::abort("Bounding box must be finite WGS84 degrees with xmin < xmax and ymin < ymax.")
  }
  bb
}

# Geocoding ---------------------------------------------------------------------
#
# Nominatim is called directly with download.file() rather than through
# osmdata::getbb(), which goes via httr2 and needs a recent 'curl' package
# that older R installs cannot get as a binary.

.nominatim_url <- function(place, base = "https://nominatim.openstreetmap.org",
                           polygon = FALSE) {
  params <- list(q = place, format = "json", limit = 10)
  if (polygon) params$polygon_geojson <- 1
  paste0(base, "/search?", .query_string(params))
}

.nominatim_fetch <- function(url, place) {
  tmp <- tempfile(fileext = ".json")
  ua <- sprintf("cyclelanes/%s (R package; https://github.com/mjorden/cyclelanes)",
                as.character(utils::packageVersion("cyclelanes")))
  status <- tryCatch(
    utils::download.file(url, tmp, quiet = TRUE, mode = "wb", headers = c(`User-Agent` = ua)),
    error = function(e) conditionMessage(e)
  )
  if (!identical(as.integer(status), 0L)) {
    unlink(tmp)
    rlang::abort(c(sprintf("Could not geocode place name \"%s\": Nominatim request failed.", place),
                   i = as.character(status)))
  }
  on.exit(unlink(tmp), add = TRUE)
  readLines(tmp, warn = FALSE, encoding = "UTF-8")
}

# Score a Nominatim result: administrative boundaries first, then populated
# places, then anything else (a street of the same name, say).
.nominatim_score <- function(r) {
  cls <- r$class %||% ""
  typ <- r$type %||% ""
  if (cls == "boundary" && typ == "administrative") 3
  else if (cls == "place") 2
  else 1
}

#' Administrative boundary polygon for a place
#'
#' Geocodes `place` through Nominatim with `polygon_geojson=1` and returns
#' the matching boundary as an `sf` polygon. Used by [cl_fetch_osm()] and
#' [cl_bike_lanes()] to clip a bounding-box query to the place itself, so
#' that "Denver, Colorado" does not include Lakewood and Aurora.
#'
#' @param place A place name, or an `sf`/`sfc` polygon which is returned
#'   as-is (unioned, in WGS84) so callers can supply their own boundary.
#' @return An `sf` with one row: `name` (Nominatim's display name), `osm_type`,
#'   `osm_id`, and a `POLYGON`/`MULTIPOLYGON` geometry in EPSG:4326.
#' @examples
#' \dontrun{
#' den <- cl_boundary("Denver, Colorado")
#' plot(sf::st_geometry(den))
#' }
#' @export
cl_boundary <- function(place) {
  if (inherits(place, c("sf", "sfc"))) {
    g <- sf::st_geometry(place)
    if (is.na(sf::st_crs(g))) rlang::abort("`place` polygon has no CRS.")
    g <- sf::st_union(sf::st_transform(g, 4326))
    if (!all(sf::st_geometry_type(g) %in% c("POLYGON", "MULTIPOLYGON"))) {
      rlang::abort("`place` must be a polygon to be used as a boundary.")
    }
    return(sf::st_sf(name = NA_character_, osm_type = NA_character_,
                     osm_id = NA_character_, geometry = g))
  }
  if (!is.character(place) || length(place) != 1L) {
    rlang::abort("`place` must be a place name or an sf/sfc polygon.")
  }
  json <- .nominatim_fetch(.nominatim_url(place, polygon = TRUE), place)
  out <- .parse_nominatim_geojson(json)
  if (is.null(out)) {
    rlang::abort(sprintf("Nominatim returned no polygon boundary for \"%s\".", place))
  }
  out
}

# Best polygonal result of a polygon_geojson=1 response as a one-row sf,
# or NULL when nothing usable came back.
.parse_nominatim_geojson <- function(json) {
  res <- tryCatch(jsonlite::fromJSON(paste(json, collapse = "\n"), simplifyVector = FALSE),
                  error = function(e) NULL)
  if (!length(res)) return(NULL)
  poly <- vapply(res, function(r) {
    isTRUE((r$geojson$type %||% "") %in% c("Polygon", "MultiPolygon"))
  }, logical(1))
  res <- res[poly]
  if (!length(res)) return(NULL)
  best <- res[[which.max(vapply(res, .nominatim_score, numeric(1)))]]

  feature <- list(type = "Feature", properties = list(), geometry = best$geojson)
  tmp <- tempfile(fileext = ".geojson")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(jsonlite::toJSON(feature, auto_unbox = TRUE, digits = NA), tmp)
  g <- tryCatch(sf::st_geometry(sf::st_read(tmp, quiet = TRUE)), error = function(e) NULL)
  if (is.null(g) || length(g) != 1L) return(NULL)
  sf::st_crs(g) <- 4326
  sf::st_sf(
    name = as.character(best$display_name %||% NA_character_),
    osm_type = as.character(best$osm_type %||% NA_character_),
    osm_id = as.character(best$osm_id %||% NA_character_),
    geometry = g
  )
}

.geocode_bbox <- function(place) {
  json <- .nominatim_fetch(.nominatim_url(place), place)
  bb <- .parse_nominatim(json)
  if (is.null(bb)) {
    rlang::abort(sprintf("Could not geocode place name \"%s\": Nominatim returned no results.", place))
  }
  .validate_bbox(bb)
}

# Turn a Nominatim JSON response into c(xmin, ymin, xmax, ymax), preferring an
# administrative boundary or populated place over e.g. a street of the same
# name. NULL when there are no usable results.
.parse_nominatim <- function(json) {
  res <- tryCatch(jsonlite::fromJSON(paste(json, collapse = "\n"), simplifyVector = FALSE),
                  error = function(e) NULL)
  if (!length(res)) return(NULL)
  best <- res[[which.max(vapply(res, .nominatim_score, numeric(1)))]]
  bb <- suppressWarnings(as.numeric(unlist(best$boundingbox)))
  if (length(bb) != 4L || anyNA(bb)) return(NULL)
  # Nominatim order is south, north, west, east
  c(xmin = bb[3], ymin = bb[1], xmax = bb[4], ymax = bb[2])
}
