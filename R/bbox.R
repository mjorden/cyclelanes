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

.nominatim_url <- function(place, base = "https://nominatim.openstreetmap.org") {
  paste0(base, "/search?", .query_string(list(q = place, format = "json", limit = 10)))
}

.geocode_bbox <- function(place) {
  url <- .nominatim_url(place)
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)
  ua <- sprintf("cyclelanes/%s (R package; https://github.com/mjorden/cyclelanes)",
                as.character(utils::packageVersion("cyclelanes")))
  status <- tryCatch(
    utils::download.file(url, tmp, quiet = TRUE, mode = "wb", headers = c(`User-Agent` = ua)),
    error = function(e) conditionMessage(e)
  )
  if (!identical(as.integer(status), 0L)) {
    rlang::abort(c(sprintf("Could not geocode place name \"%s\": Nominatim request failed.", place),
                   i = as.character(status)))
  }
  bb <- .parse_nominatim(readLines(tmp, warn = FALSE, encoding = "UTF-8"))
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
  score <- vapply(res, function(r) {
    cls <- r$class %||% ""
    typ <- r$type %||% ""
    if (cls == "boundary" && typ == "administrative") 3
    else if (cls == "place") 2
    else 1
  }, numeric(1))
  best <- res[[which.max(score)]]
  bb <- suppressWarnings(as.numeric(unlist(best$boundingbox)))
  if (length(bb) != 4L || anyNA(bb)) return(NULL)
  # Nominatim order is south, north, west, east
  c(xmin = bb[3], ymin = bb[1], xmax = bb[4], ymax = bb[2])
}
