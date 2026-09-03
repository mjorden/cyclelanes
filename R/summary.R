#' Summarise facility length by type
#'
#' Works on either layer: the OpenStreetMap output of [cl_bike_lanes()] or
#' the official output of [cl_fetch_official()].
#'
#' @param x An `sf` with a `facility_type` column (or whatever `by` names).
#' @param by Column(s) to group on. Default `"facility_type"`; for the
#'   official Denver layer `c("facility_type", "status")` is informative.
#' @return A data frame with `n_segments`, `length_km`, `length_mi`, and
#'   `share` (fraction of total length) per group. Empty groups of a factor
#'   are omitted.
#' @examples
#' cl_summary(cl_classify(denver_lodo$osm, drop_none = TRUE))
#' cl_summary(denver_lodo$official, by = c("facility_type", "status"))
#' \dontrun{
#' cl_summary(cl_bike_lanes("Boulder, Colorado"))
#' }
#' @export
cl_summary <- function(x, by = "facility_type") {
  .stop_if_not_sf(x)
  missing <- setdiff(by, names(x))
  if (length(missing)) {
    rlang::abort(sprintf("Column(s) not found in `x`: %s", paste(missing, collapse = ", ")))
  }
  d <- sf::st_drop_geometry(x)
  d$.len <- .length_m(x)
  out <- d |>
    dplyr::group_by(dplyr::across(dplyr::all_of(by))) |>
    dplyr::summarise(
      n_segments = dplyr::n(),
      length_km = sum(.data$.len, na.rm = TRUE) / 1000,
      .groups = "drop"
    ) |>
    dplyr::mutate(
      length_mi = .data$length_km * 0.621371,
      share = if (sum(.data$length_km) > 0) .data$length_km / sum(.data$length_km) else NA_real_
    ) |>
    dplyr::arrange(dplyr::across(dplyr::all_of(by)))
  as.data.frame(out)
}
