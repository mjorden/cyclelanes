#' Downtown Denver bike facilities, frozen
#'
#' A small, fixed sample of both data sources for a box over downtown
#' Denver (Cherry Creek trail, the 15th and 16th Street lanes, Union
#' Station), so examples, tests and vignettes run without touching Overpass
#' or the city's ArcGIS service. Regenerate with `data-raw/denver_lodo.R`.
#'
#' @format A list with six elements:
#' \describe{
#'   \item{`osm`}{An `sf` of raw OpenStreetMap ways as returned by
#'     [cl_fetch_osm()], cut at the box edge: one row per way with the OSM
#'     tag columns present in the area (tags that are `NA` for every way are
#'     dropped). Unclassified; pass it to [cl_classify()].}
#'   \item{`official`}{An `sf` from [cl_fetch_official("denver")][cl_fetch_official]
#'     cut to the same box, already in the package taxonomy.}
#'   \item{`bbox`}{The WGS84 bounding box, `c(xmin, ymin, xmax, ymax)`.}
#'   \item{`fetched`}{The `Date` both layers were fetched.}
#'   \item{`crashes`}{An `sf` of reported bicycle-involved crashes in the
#'     box, 2019-2025, from [cl_fetch_crashes("denver")][cl_fetch_crashes];
#'     `crash_years` gives the span and `crashes_fetched` the date.}
#' }
#' @source OpenStreetMap contributors (ODbL) via the Overpass API; City and
#'   County of Denver, Denver Moves: Bikes 2025 bikeway inventory and Denver
#'   Police Department traffic accidents (NIBRS), via the Denver Open Data
#'   Catalog.
#' @examples
#' lanes <- cl_classify(denver_lodo$osm, drop_none = TRUE)
#' cl_summary(lanes)
#' cl_compare(lanes, denver_lodo$official)
#' j <- cl_crash_join(denver_lodo$official, denver_lodo$crashes)
#' cl_crash_rates(j, years = denver_lodo$crash_years)
"denver_lodo"
