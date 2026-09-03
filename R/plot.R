#' Colours for the facility taxonomy
#'
#' Greens for off-street, blues for on-street separated or marked lanes,
#' oranges for shared facilities, greys for the rest.
#'
#' @return A named character vector of hex colours over [cl_facility_levels()].
#' @export
cl_palette <- function() {
  c(
    separated_path       = "#1b7837",
    protected_lane       = "#2166ac",
    buffered_lane        = "#4393c3",
    painted_lane         = "#92c5de",
    neighborhood_bikeway = "#9e9ac8",
    bus_bike_lane        = "#e08214",
    shared_lane          = "#fdb863",
    shoulder             = "#bababa",
    none                 = "#e6e6e6"
  )
}

#' Quick map of classified bike lanes
#'
#' A `ggplot2` map coloured by `facility_type`. Requires `ggplot2`.
#'
#' @param x An `sf` with a `facility_type` column.
#' @param title Optional plot title.
#' @param linewidth Line width passed to [ggplot2::geom_sf()].
#' @return A `ggplot` object.
#' @examples
#' \dontrun{
#' cl_plot(cl_bike_lanes("Denver, Colorado"), title = "Denver bike facilities (OSM)")
#' }
#' @export
cl_plot <- function(x, title = NULL, linewidth = 0.6) {
  rlang::check_installed("ggplot2", reason = "for cl_plot()")
  .stop_if_not_sf(x)
  if (!"facility_type" %in% names(x)) {
    rlang::abort("`x` has no `facility_type` column; classify it first.")
  }
  x$facility_type <- .facility_factor(x$facility_type)
  ggplot2::ggplot(x) +
    ggplot2::geom_sf(ggplot2::aes(colour = .data$facility_type), linewidth = linewidth) +
    ggplot2::scale_colour_manual(values = cl_palette(), drop = TRUE, name = "Facility") +
    ggplot2::labs(title = title) +
    ggplot2::theme_minimal() +
    ggplot2::theme(panel.grid = ggplot2::element_blank(),
                   axis.text = ggplot2::element_blank())
}
