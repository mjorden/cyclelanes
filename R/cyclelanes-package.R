#' cyclelanes: bicycle infrastructure from OpenStreetMap and city open data
#'
#' Fetch every bicycle-related way for a place from OpenStreetMap, normalise
#' the tagging into one facility taxonomy (see [cl_facility_levels()]), and
#' optionally pull a city's official bike-facility inventory through the same
#' taxonomy so the two can be summarised and compared.
#'
#' The main entry points are:
#'
#' * [cl_bike_lanes()] -- fetch + classify OSM for a place name or bounding box
#' * [cl_fetch_official()] -- a city's official inventory, via [cl_sources()]
#' * [cl_summary()] -- length by facility type
#' * [cl_compare()] -- how well the two layers agree
#' * [cl_plot()] -- a quick map
#'
#' @keywords internal
#' @importFrom rlang .data
"_PACKAGE"
