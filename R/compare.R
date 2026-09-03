#' Compare OpenStreetMap bike lanes against an official inventory
#'
#' Measures how much of each layer lies within `tolerance` metres of the
#' other, and whether the two agree on the *kind* of facility where they
#' overlap.
#'
#' A segment's *matched fraction* is the share of its length inside a
#' buffer around the other layer, so it is 1 where both sources agree a
#' facility exists and 0 where one source has something the other lacks.
#' For matched segments, `other_type` is the facility type of the other
#' layer that covers most of the segment, `type_match` says whether it
#' equals the segment's own type, and `type_adjacent` whether it is one
#' step away in [cl_facility_levels()] (painted vs buffered lane, say),
#' which is often a tagging choice rather than a real difference.
#'
#' @param osm An `sf` from [cl_bike_lanes()] or [cl_classify()].
#' @param official An `sf` from [cl_fetch_official()].
#' @param tolerance Match distance in metres. Fifteen metres absorbs the
#'   usual centreline-vs-curb offset between sources without bridging
#'   parallel streets.
#' @return A list of class `cl_comparison`:
#'   * `summary`: one row per layer with `length_km`, `matched_km`,
#'     `matched_frac`, `type_agreement` (share of matched length whose
#'     types agree) and `type_adjacent` (share that agrees within one level);
#'   * `by_type`: the same broken down by `facility_type` within each layer;
#'   * `confusion`: a matrix of kilometres, official facility type by OSM
#'     facility type, with an `unmatched` column for official length OSM
#'     has nothing near;
#'   * `osm`, `official`: the inputs (WGS84) with `matched_frac`,
#'     `other_type`, `type_match` and `type_adjacent` columns added, so
#'     disagreements can be mapped;
#'   * `tolerance`.
#' @examples
#' \dontrun{
#' osm <- cl_bike_lanes("Denver, Colorado")
#' den <- cl_fetch_official("denver", bbox = attr(osm, "cl_boundary"))
#' cmp <- cl_compare(osm, den)
#' cmp
#' cmp$confusion
#' cl_plot(cmp$official, colour = "type_match",
#'         title = "Where the city and OSM disagree on the facility type")
#' }
#' @export
cl_compare <- function(osm, official, tolerance = 15) {
  .stop_if_not_sf(osm, "osm")
  .stop_if_not_sf(official, "official")
  if (nrow(osm) == 0L || nrow(official) == 0L) {
    rlang::abort("Both `osm` and `official` must have at least one feature.")
  }
  if (!is.numeric(tolerance) || length(tolerance) != 1L || tolerance <= 0) {
    rlang::abort("`tolerance` must be a single positive number of metres.")
  }
  for (nm in c("osm", "official")) {
    if (!"facility_type" %in% names(get(nm))) {
      rlang::abort(sprintf("`%s` has no `facility_type` column; classify it first.", nm))
    }
  }

  # Lengths are geodesic on the inputs so they agree with `length_m`;
  # the buffer/intersection runs in a projected CRS.
  o_len <- .length_m(osm)
  f_len <- .length_m(official)
  crs <- .utm_crs(osm)
  o <- sf::st_transform(osm, crs)
  f <- sf::st_transform(official, crs)
  o$facility_type <- .facility_factor(o$facility_type)
  f$facility_type <- .facility_factor(f$facility_type)

  o$matched_frac <- .covered_frac(o, f, tolerance)
  f$matched_frac <- .covered_frac(f, o, tolerance)
  o <- .add_other_type(o, f, tolerance)
  f <- .add_other_type(f, o, tolerance)

  summary <- rbind(.layer_summary(o, o_len, "osm"),
                   .layer_summary(f, f_len, "official"))
  by_type <- rbind(.matched_by_type(o, o_len, "osm"),
                   .matched_by_type(f, f_len, "official"))
  confusion <- .confusion_km(f, f_len)

  structure(
    list(
      summary = summary,
      by_type = by_type,
      confusion = confusion,
      osm = sf::st_transform(o, 4326),
      official = sf::st_transform(f, 4326),
      tolerance = tolerance
    ),
    class = "cl_comparison"
  )
}

# Fraction of each feature in x lying within `tolerance` of any feature in y.
# Both must share a projected CRS in metres.
.covered_frac <- function(x, y, tolerance) {
  geom <- sf::st_geometry(x)
  total <- .length_m(geom)
  covered <- .covered_len(geom, sf::st_geometry(y), tolerance)
  ifelse(total > 0, pmin(covered / total, 1), 0)
}

# Length of each geometry in `geom` inside a `tolerance` buffer around `ygeom`.
.covered_len <- function(geom, ygeom, tolerance) {
  covered <- numeric(length(geom))
  if (!length(ygeom)) return(covered)
  buf <- sf::st_union(sf::st_buffer(ygeom, tolerance))
  ids <- sf::st_sf(.id = seq_along(geom), geometry = geom)
  sf::st_agr(ids) <- "constant"
  hit <- lengths(sf::st_intersects(ids, buf)) > 0
  if (!any(hit)) return(covered)
  inter <- suppressWarnings(sf::st_intersection(ids[hit, ], buf))
  if (nrow(inter) > 0L) {
    lens <- .length_m(inter)
    sums <- tapply(lens, factor(inter$.id, levels = seq_along(geom)), sum)
    covered <- as.numeric(sums)
    covered[is.na(covered)] <- 0
  }
  covered
}

# For each feature of x, the facility type of y that covers the most of it
# within `tolerance`, plus whether that agrees with x's own type.
.add_other_type <- function(x, y, tolerance) {
  lv <- cl_facility_levels()
  types <- lv[lv %in% unique(as.character(y$facility_type))]
  geom <- sf::st_geometry(x)
  cov <- matrix(0, nrow = length(geom), ncol = length(types),
                dimnames = list(NULL, types))
  for (t in types) {
    cov[, t] <- .covered_len(geom, sf::st_geometry(y)[y$facility_type == t], tolerance)
  }
  best <- if (length(types)) types[max.col(cov, ties.method = "first")] else rep(NA_character_, length(geom))
  best[rowSums(cov) <= 0] <- NA_character_
  own <- as.character(x$facility_type)
  x$other_type <- .facility_factor(best)
  x$type_match <- ifelse(is.na(best), NA, best == own)
  x$type_adjacent <- ifelse(is.na(best), NA, abs(match(best, lv) - match(own, lv)) <= 1)
  x
}

.layer_summary <- function(x, len, layer) {
  matched <- len * x$matched_frac
  m <- !is.na(x$type_match)
  data.frame(
    layer = layer,
    n_segments = nrow(x),
    length_km = sum(len) / 1000,
    matched_km = sum(matched) / 1000,
    matched_frac = if (sum(len) > 0) sum(matched) / sum(len) else NA_real_,
    type_agreement = .share(matched[m], x$type_match[m]),
    type_adjacent = .share(matched[m], x$type_adjacent[m]),
    stringsAsFactors = FALSE
  )
}

.share <- function(w, flag) {
  if (!length(w) || sum(w) <= 0) return(NA_real_)
  sum(w[flag %in% TRUE]) / sum(w)
}

.matched_by_type <- function(x, len, layer) {
  d <- data.frame(
    facility_type = x$facility_type,
    len = len,
    matched = len * x$matched_frac,
    type_match = x$type_match,
    type_adjacent = x$type_adjacent
  )
  out <- d |>
    dplyr::group_by(.data$facility_type) |>
    dplyr::summarise(
      n_segments = dplyr::n(),
      length_km = sum(.data$len) / 1000,
      matched_frac = ifelse(sum(.data$len) > 0, sum(.data$matched) / sum(.data$len), NA_real_),
      type_agreement = .share(.data$matched[!is.na(.data$type_match)],
                              .data$type_match[!is.na(.data$type_match)]),
      type_adjacent = .share(.data$matched[!is.na(.data$type_adjacent)],
                             .data$type_adjacent[!is.na(.data$type_adjacent)]),
      .groups = "drop"
    ) |>
    dplyr::arrange(.data$facility_type)
  out <- as.data.frame(out)
  cbind(layer = layer, out, stringsAsFactors = FALSE)
}

# Official type (rows) by OSM type (columns), kilometres; unmatched official
# length gets its own column.
.confusion_km <- function(f, f_len) {
  lv <- cl_facility_levels()
  other <- as.character(f$other_type)
  other[is.na(other)] <- "unmatched"
  m <- stats::xtabs(f_len ~ factor(as.character(f$facility_type), levels = lv) +
                      factor(other, levels = c(lv, "unmatched")))
  m <- unclass(m) / 1000
  dimnames(m) <- list(official = lv, osm = c(lv, "unmatched"))
  keep_r <- rowSums(m) > 0
  keep_c <- colSums(m) > 0
  m[keep_r, keep_c, drop = FALSE]
}

#' @export
print.cl_comparison <- function(x, ...) {
  cat(sprintf("<cl_comparison> tolerance = %g m\n\n", x$tolerance))
  s <- x$summary
  for (col in c("length_km", "matched_km")) s[[col]] <- round(s[[col]], 1)
  for (col in c("matched_frac", "type_agreement", "type_adjacent")) s[[col]] <- round(s[[col]], 3)
  print(s, row.names = FALSE)
  cat("\nBy facility type:\n")
  b <- x$by_type
  b$length_km <- round(b$length_km, 1)
  for (col in c("matched_frac", "type_agreement", "type_adjacent")) b[[col]] <- round(b[[col]], 3)
  print(b, row.names = FALSE)
  cat("\nOfficial type (rows) vs OSM type (columns), km:\n")
  print(round(x$confusion, 1))
  invisible(x)
}
