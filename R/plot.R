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
    shared_use_path      = "#7fbc41",
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
#' @param colour Column to colour by: `"facility_type"` (default, using
#'   [cl_palette()]) or `"type_match"` from a [cl_compare()] layer, which
#'   draws agreeing segments green, disagreeing red, and unmatched grey.
#' @return A `ggplot` object.
#' @examples
#' if (requireNamespace("ggplot2", quietly = TRUE)) {
#'   cl_plot(cl_classify(denver_lodo$osm, drop_none = TRUE), title = "Downtown Denver (OSM)")
#' }
#' \dontrun{
#' cl_plot(cl_bike_lanes("Denver, Colorado"), title = "Denver bike facilities (OSM)")
#' }
#' @export
cl_plot <- function(x, title = NULL, linewidth = 0.6,
                    colour = c("facility_type", "type_match")) {
  rlang::check_installed("ggplot2", reason = "for cl_plot()")
  .stop_if_not_sf(x)
  colour <- match.arg(colour)
  if (!colour %in% names(x)) {
    rlang::abort(sprintf("`x` has no `%s` column; %s first.", colour,
                         if (colour == "facility_type") "classify it" else "run cl_compare()"))
  }
  base <- ggplot2::ggplot(x) +
    ggplot2::labs(title = title) +
    ggplot2::theme_minimal() +
    ggplot2::theme(panel.grid = ggplot2::element_blank(),
                   axis.text = ggplot2::element_blank())
  if (colour == "facility_type") {
    x$facility_type <- .facility_factor(x$facility_type)
    base$data <- x
    return(base +
      ggplot2::geom_sf(ggplot2::aes(colour = .data$facility_type), linewidth = linewidth) +
      ggplot2::scale_colour_manual(values = cl_palette(), drop = TRUE, name = "Facility"))
  }
  x$agreement <- factor(
    ifelse(is.na(x$type_match), "unmatched", ifelse(x$type_match, "same type", "different type")),
    levels = c("same type", "different type", "unmatched")
  )
  base$data <- x
  base +
    ggplot2::geom_sf(ggplot2::aes(colour = .data$agreement), linewidth = linewidth) +
    ggplot2::scale_colour_manual(
      values = c(`same type` = "#1a9850", `different type` = "#d73027", unmatched = "#bdbdbd"),
      drop = TRUE, name = "Agreement"
    )
}
