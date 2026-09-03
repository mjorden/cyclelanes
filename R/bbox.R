#' Resolve a place into a WGS84 bounding box
#'
#' Accepts the same `place` argument as every fetch function in the package
#' and returns a bounding box in longitude/latitude degrees.
#'
#' @param place One of:
#'   * a place name geocoded through Nominatim, e.g. `"Denver, Colorado"`
#'     (see [osmdata::getbb()]; respect the Nominatim usage policy -- one
#'     request per second, no bulk geocoding);
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
    m <- tryCatch(osmdata::getbb(place, format_out = "matrix"),
                  error = function(e) NULL)
    if (is.null(m) || !is.matrix(m) || anyNA(m)) {
      rlang::abort(sprintf("Could not geocode place name \"%s\".", place))
    }
    return(.validate_bbox(c(m[1, 1], m[2, 1], m[1, 2], m[2, 2])))
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
