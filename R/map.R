#' Interactive map of classified bike lanes
#'
#' A `leaflet` map coloured by `facility_type` (or by `lts`), with a popup
#' per segment that links to the way on openstreetmap.org so a mapper can
#' fix a tag straight from the map. Given a [cl_compare()] result, draws
#' the OSM and official layers as toggleable groups and highlights the
#' segments the other layer lacks. Requires `leaflet`.
#'
#' @param x An `sf` from [cl_classify()], [cl_bike_lanes()],
#'   [cl_fetch_official()] or [cl_lts()], or a `cl_comparison`.
#' @param colour `"facility_type"` (default) or `"lts"`.
#' @param unmatched_below For a comparison, segments with `matched_frac`
#'   below this are drawn in a separate "not in the other layer" group.
#' @param weight Line weight in pixels.
#' @return A `leaflet` htmlwidget.
#' @examples
#' if (requireNamespace("leaflet", quietly = TRUE)) {
#'   cl_map(cl_classify(denver_lodo$osm, drop_none = TRUE))
#' }
#' @export
cl_map <- function(x, colour = c("facility_type", "lts"), unmatched_below = 0.5, weight = 3) {
  rlang::check_installed("leaflet", reason = "for cl_map()")
  colour <- match.arg(colour)
  if (inherits(x, "cl_comparison")) return(.map_comparison(x, colour, unmatched_below, weight))
  .stop_if_not_sf(x)
  if (!colour %in% names(x)) {
    rlang::abort(sprintf("`x` has no `%s` column; run %s first.", colour,
                         if (colour == "lts") "cl_lts()" else "cl_classify()"))
  }
  m <- leaflet::leaflet() |>
    leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron)
  m <- .add_lane_layer(m, x, colour, group = NULL, weight = weight)
  .add_lane_legend(m, colour)
}

.map_comparison <- function(cmp, colour, unmatched_below, weight) {
  osm <- cmp$osm
  off <- cmp$official
  m <- leaflet::leaflet() |>
    leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron)
  m <- .add_lane_layer(m, osm, colour, group = "OpenStreetMap", weight = weight)
  m <- .add_lane_layer(m, off, colour, group = "Official", weight = weight, dashed = TRUE)
  gap_off <- off[!is.na(off$matched_frac) & off$matched_frac < unmatched_below, ]
  gap_osm <- osm[!is.na(osm$matched_frac) & osm$matched_frac < unmatched_below, ]
  if (nrow(gap_off)) {
    m <- leaflet::addPolylines(m, data = sf::st_transform(gap_off, 4326), color = "#d73027",
                               weight = weight + 2, opacity = 0.9, group = "Official, not in OSM",
                               popup = .lane_popup(gap_off, colour))
  }
  if (nrow(gap_osm)) {
    m <- leaflet::addPolylines(m, data = sf::st_transform(gap_osm, 4326), color = "#7b3294",
                               weight = weight + 2, opacity = 0.9, group = "OSM, not in official",
                               popup = .lane_popup(gap_osm, colour))
  }
  m <- leaflet::addLayersControl(
    m, overlayGroups = c("OpenStreetMap", "Official", "Official, not in OSM", "OSM, not in official"),
    options = leaflet::layersControlOptions(collapsed = FALSE))
  .add_lane_legend(m, colour)
}

.lane_colours <- function(x, colour) {
  if (colour == "lts") {
    pal <- cl_lts_palette()
    unname(pal[as.character(x$lts)])
  } else {
    pal <- cl_palette()
    unname(pal[as.character(x$facility_type)])
  }
}

.add_lane_layer <- function(m, x, colour, group, weight, dashed = FALSE) {
  if (nrow(x) == 0L) return(m)
  x <- sf::st_transform(x, 4326)
  cols <- .lane_colours(x, colour)
  cols[is.na(cols)] <- "#999999"
  leaflet::addPolylines(
    m, data = x, color = cols, weight = weight, opacity = 0.85,
    dashArray = if (dashed) "6,6" else NULL,
    group = group, popup = .lane_popup(x, colour)
  )
}

# Popup HTML per segment. Every string that came from the data is escaped.
.lane_popup <- function(x, colour) {
  esc <- function(v) htmltools::htmlEscape(ifelse(is.na(v), "", as.character(v)))
  d <- sf::st_drop_geometry(x)
  n <- nrow(d)
  get <- function(col) if (col %in% names(d)) d[[col]] else rep(NA, n)
  name <- esc(get("name"))
  type <- esc(get("facility_type"))
  len <- ifelse(is.na(get("length_m")), "", sprintf("%.0f m", get("length_m")))
  extra <- if (colour == "lts" && "lts" %in% names(d)) {
    sprintf("<br>LTS %s <small>(%s)</small>", esc(get("lts")), esc(get("lts_basis")))
  } else rep("", n)
  official <- if ("official_class" %in% names(d)) {
    sprintf("<br>City class: %s%s", esc(get("official_class")),
            ifelse(is.na(get("status")), "", paste0(" &middot; ", esc(get("status")))))
  } else rep("", n)
  osm <- if ("osm_id" %in% names(d) && !"official_class" %in% names(d)) {
    id <- esc(get("osm_id"))
    ifelse(nzchar(id),
           sprintf("<br><a href=\"https://www.openstreetmap.org/way/%s\" target=\"_blank\" rel=\"noopener\">way %s on openstreetmap.org</a>", id, id),
           "")
  } else rep("", n)
  match <- if ("matched_frac" %in% names(d)) {
    sprintf("<br>Matched: %s%%", ifelse(is.na(get("matched_frac")), "?", round(100 * get("matched_frac"))))
  } else rep("", n)
  sides <- if (all(c("facility_left", "facility_right") %in% names(d))) {
    l <- get("facility_left"); r <- get("facility_right")
    ifelse(is.na(l) & is.na(r), "", sprintf("<br>Left: %s &middot; Right: %s", esc(l), esc(r)))
  } else rep("", n)
  paste0("<b>", ifelse(nzchar(name), name, "(unnamed)"), "</b><br>", type, " &middot; ", len,
         sides, extra, official, match, osm)
}

.add_lane_legend <- function(m, colour) {
  if (colour == "lts") {
    leaflet::addLegend(m, position = "bottomright", colors = unname(cl_lts_palette()),
                       labels = paste("LTS", names(cl_lts_palette())), title = "Traffic stress", opacity = 0.9)
  } else {
    pal <- cl_palette()
    pal <- pal[names(pal) != "none"]
    leaflet::addLegend(m, position = "bottomright", colors = unname(pal), labels = names(pal),
                       title = "Facility", opacity = 0.9)
  }
}
