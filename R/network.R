#' Build a routable network from classified facilities
#'
#' Turns the line layer into an undirected `sfnetworks` graph whose edges
#' carry `facility_type`, `length_m` and, if present, `lts`. Endpoints
#' within `tolerance` metres of each other are snapped to one node so
#' facilities that meet at an intersection connect even when their ends
#' do not coincide exactly. Requires `sfnetworks`.
#'
#' @param x An `sf` from [cl_classify()], [cl_bike_lanes()],
#'   [cl_fetch_official()] or [cl_lts()].
#' @param tolerance Snap distance in metres.
#' @return An `sfnetwork` in a projected (UTM) CRS.
#' @examples
#' if (requireNamespace("sfnetworks", quietly = TRUE)) {
#'   net <- cl_as_sfnetwork(cl_classify(denver_lodo$osm, drop_none = TRUE))
#'   net
#' }
#' @export
cl_as_sfnetwork <- function(x, tolerance = 5) {
  rlang::check_installed("sfnetworks", reason = "for cl_as_sfnetwork()")
  .stop_if_not_sf(x)
  if (nrow(x) == 0L) rlang::abort("`x` has no features.")
  crs <- .utm_crs(x)
  y <- sf::st_transform(x, crs)
  y <- suppressWarnings(sf::st_cast(sf::st_cast(y, "MULTILINESTRING"), "LINESTRING"))
  # snap endpoints to a grid of `tolerance` metres so near-misses share a node
  g <- sf::st_geometry(y)
  g <- sf::st_as_sfc(sf::st_as_binary(sf::st_set_precision(g, 1 / tolerance)), crs = crs)
  sf::st_geometry(y) <- g
  y <- y[!sf::st_is_empty(y), ]
  y$length_m <- .length_m(y)
  sfnetworks::as_sfnetwork(y, directed = FALSE)
}

#' Connected components of the low-stress network
#'
#' How fragmented is the network a given kind of rider can use? Keeps the
#' facilities at or below `max_lts` (all of them when `NULL`), builds the
#' network with [cl_as_sfnetwork()], and labels each segment with the
#' connected component it belongs to, numbered from the longest. The
#' component table in `attr(x, "components")` gives the number of segments
#' and kilometres in each, so "the largest low-stress island is 12 km out
#' of 260" is one call.
#'
#' @inheritParams cl_as_sfnetwork
#' @param max_lts Keep segments with `lts` at or below this (1-4), running
#'   [cl_lts()] first if needed. `NULL` keeps everything.
#' @return The kept segments as an `sf` (WGS84) with an integer `component`
#'   column, plus `attr(x, "components")`: a data frame of `component`,
#'   `n_segments`, `length_km`, `share`.
#' @examples
#' if (requireNamespace("sfnetworks", quietly = TRUE)) {
#'   lanes <- cl_classify(denver_lodo$osm, drop_none = TRUE)
#'   low <- cl_components(lanes, max_lts = 2)
#'   head(attr(low, "components"))
#' }
#' @export
cl_components <- function(x, max_lts = NULL, tolerance = 5) {
  rlang::check_installed("sfnetworks", reason = "for cl_components()")
  .stop_if_not_sf(x)
  if (!is.null(max_lts)) {
    if (!is.numeric(max_lts) || length(max_lts) != 1L || !max_lts %in% 1:4) {
      rlang::abort("`max_lts` must be NULL or a single value 1-4.")
    }
    if (!"lts" %in% names(x)) x <- cl_lts(x)
    x <- x[!is.na(x$lts) & x$lts <= max_lts, ]
  }
  if (nrow(x) == 0L) {
    out <- x
    out$component <- integer()
    attr(out, "components") <- data.frame(component = integer(), n_segments = integer(),
                                          length_km = numeric(), share = numeric())
    return(out)
  }
  x$.row <- seq_len(nrow(x))
  net <- cl_as_sfnetwork(x, tolerance = tolerance)
  edges <- sf::st_as_sf(net, "edges")
  membership <- igraph::components(net)$membership
  # an edge belongs to the component of its endpoints
  edge_comp <- membership[edges$from]
  # several edges can come from one input row (multilinestrings); take the first
  comp_by_row <- tapply(edge_comp, edges$.row, function(v) v[1])
  comp <- as.integer(comp_by_row[as.character(x$.row)])

  len <- .length_m(x)
  tab <- data.frame(component = comp, len = len)
  tab <- tab[!is.na(tab$component), ]
  agg <- stats::aggregate(len ~ component, data = tab, FUN = sum)
  cnt <- stats::aggregate(len ~ component, data = tab, FUN = length)
  agg <- agg[order(-agg$len), ]
  rank <- stats::setNames(seq_len(nrow(agg)), agg$component)
  comp_ranked <- as.integer(rank[as.character(comp)])

  out <- x
  out$.row <- NULL
  out$component <- comp_ranked
  out <- sf::st_transform(out, 4326)
  components <- data.frame(
    component = seq_len(nrow(agg)),
    n_segments = as.integer(cnt$len[match(agg$component, cnt$component)]),
    length_km = agg$len / 1000,
    stringsAsFactors = FALSE
  )
  components$share <- components$length_km / sum(components$length_km)
  attr(out, "components") <- components
  out
}
