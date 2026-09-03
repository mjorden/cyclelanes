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
#' @param n_components How many components to colour when
#'   `colour = "component"`.
#' @param crashes Optional `sf` of points from [cl_fetch_crashes()] to draw
#'   over the facilities, sized by severity.
#' @param colour Column to colour by: `"facility_type"` (default, using
#'   [cl_palette()]); `"type_match"` from a [cl_compare()] layer, which
#'   draws agreeing segments green, disagreeing red, and unmatched grey; or
#'   `"lts"` from [cl_lts()], green to red for stress levels 1 to 4; or
#'   `"component"` from [cl_components()], the largest `n_components`
#'   coloured and the rest grey.
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
                    colour = c("facility_type", "type_match", "lts", "component"),
                    n_components = 8, crashes = NULL) {
  rlang::check_installed("ggplot2", reason = "for cl_plot()")
  .stop_if_not_sf(x)
  colour <- match.arg(colour)
  if (!colour %in% names(x)) {
    rlang::abort(sprintf("`x` has no `%s` column; %s first.", colour,
                         switch(colour, facility_type = "classify it",
                                type_match = "run cl_compare()", lts = "run cl_lts()",
                                component = "run cl_components()")))
  }
  base <- ggplot2::ggplot(x) +
    ggplot2::labs(title = title) +
    ggplot2::theme_minimal() +
    ggplot2::theme(panel.grid = ggplot2::element_blank(),
                   axis.text = ggplot2::element_blank())
  if (!is.null(crashes)) {
    .stop_if_not_sf(crashes, "crashes")
    cr <- sf::st_transform(crashes, sf::st_crs(x))
    sev <- if ("severity" %in% names(cr)) as.character(cr$severity) else rep("unknown", nrow(cr))
    cr$crash_size <- ifelse(sev == "fatal", 3, ifelse(sev == "serious", 2, 1))
    base <- base +
      ggplot2::geom_sf(data = cr, ggplot2::aes(size = .data$crash_size),
                       colour = "#000000", alpha = 0.45, shape = 16, inherit.aes = FALSE) +
      ggplot2::scale_size_identity()
  }
  if (colour == "facility_type") {
    x$facility_type <- .facility_factor(x$facility_type)
    base$data <- x
    return(base +
      ggplot2::geom_sf(ggplot2::aes(colour = .data$facility_type), linewidth = linewidth, key_glyph = "path") +
      ggplot2::scale_colour_manual(values = cl_palette(), drop = TRUE, name = "Facility"))
  }
  if (colour == "component") {
    top <- seq_len(min(n_components, max(x$component, na.rm = TRUE)))
    x$component_group <- factor(ifelse(x$component %in% top, as.character(x$component), "other"),
                                levels = c(as.character(top), "other"))
    pal <- c(grDevices::hcl.colors(length(top), "Dark 3"), "#d9d9d9")
    names(pal) <- levels(x$component_group)
    base$data <- x
    return(base +
      ggplot2::geom_sf(ggplot2::aes(colour = .data$component_group), linewidth = linewidth, key_glyph = "path") +
      ggplot2::scale_colour_manual(values = pal, drop = FALSE, name = "Component"))
  }
  if (colour == "lts") {
    x$lts <- factor(as.character(x$lts), levels = c("1", "2", "3", "4"))
    base$data <- x
    return(base +
      ggplot2::geom_sf(ggplot2::aes(colour = .data$lts), linewidth = linewidth, key_glyph = "path") +
      ggplot2::scale_colour_manual(values = cl_lts_palette(), drop = FALSE,
                                   name = "Level of Traffic Stress"))
  }
  x$agreement <- factor(
    ifelse(is.na(x$type_match), "unmatched", ifelse(x$type_match, "same type", "different type")),
    levels = c("same type", "different type", "unmatched")
  )
  base$data <- x
  base +
    ggplot2::geom_sf(ggplot2::aes(colour = .data$agreement), linewidth = linewidth, key_glyph = "path") +
    ggplot2::scale_colour_manual(
      values = c(`same type` = "#1a9850", `different type` = "#d73027", unmatched = "#bdbdbd"),
      drop = TRUE, name = "Agreement"
    )
}
