#' Snap crashes to the nearest facility
#'
#' Attaches each crash to the nearest facility within `tolerance` metres,
#' or to `facility_type = "none"` when nothing is that close, and counts
#' crashes per facility. Intersection crashes are coded to the
#' intersection point and will attach to whichever facility passes through
#' it; keep `location_type` in every summary rather than merging it away.
#'
#' @param lanes An `sf` of facilities from [cl_classify()],
#'   [cl_bike_lanes()] or [cl_fetch_official()].
#' @param crashes An `sf` of points from [cl_fetch_crashes()].
#' @param tolerance Snap distance in metres.
#' @return A list of class `cl_crash_join`: `crashes` (WGS84, with
#'   `facility_row`, `facility_type`, `snap_dist_m` added), `facilities`
#'   (WGS84, with `n_crashes`, `n_serious`, `n_fatal` added), and
#'   `tolerance`.
#' @examples
#' \dontrun{
#' lanes <- cl_fetch_official("denver")
#' crashes <- cl_fetch_crashes("denver", years = 2019:2025)
#' j <- cl_crash_join(lanes, crashes)
#' cl_crash_rates(j)
#' }
#' @export
cl_crash_join <- function(lanes, crashes, tolerance = 25) {
  .stop_if_not_sf(lanes, "lanes")
  .stop_if_not_sf(crashes, "crashes")
  if (!"facility_type" %in% names(lanes)) rlang::abort("`lanes` has no `facility_type` column; classify it first.")
  if (!is.numeric(tolerance) || length(tolerance) != 1L || tolerance <= 0) {
    rlang::abort("`tolerance` must be a single positive number of metres.")
  }
  lanes$facility_type <- .facility_factor(lanes$facility_type)
  if (nrow(crashes) == 0L || nrow(lanes) == 0L) {
    crashes$facility_row <- integer(nrow(crashes))
    crashes$facility_type <- .facility_factor(rep("none", nrow(crashes)))
    crashes$snap_dist_m <- rep(NA_real_, nrow(crashes))
    lanes$n_crashes <- integer(nrow(lanes)); lanes$n_serious <- integer(nrow(lanes)); lanes$n_fatal <- integer(nrow(lanes))
    return(structure(list(crashes = crashes, facilities = lanes, tolerance = tolerance), class = "cl_crash_join"))
  }
  crs <- .utm_crs(lanes)
  l <- sf::st_transform(lanes, crs)
  c <- sf::st_transform(crashes, crs)
  idx <- sf::st_nearest_feature(c, l)
  dist <- as.numeric(sf::st_distance(c, l[idx, ], by_element = TRUE))
  near <- is.finite(dist) & dist <= tolerance
  facility_row <- ifelse(near, idx, NA_integer_)
  ftype <- as.character(l$facility_type)[idx]
  ftype[!near] <- "none"

  crashes$facility_row <- as.integer(facility_row)
  crashes$facility_type <- .facility_factor(ftype)
  crashes$snap_dist_m <- ifelse(near, dist, NA_real_)

  n_fatal <- if ("n_fatal" %in% names(crashes)) crashes$n_fatal else rep(0L, nrow(crashes))
  n_serious <- if ("n_serious" %in% names(crashes)) crashes$n_serious else rep(0L, nrow(crashes))
  sev <- if ("severity" %in% names(crashes)) as.character(crashes$severity) else rep("unknown", nrow(crashes))
  rows <- factor(facility_row[near], levels = seq_len(nrow(lanes)))
  lanes$n_crashes <- as.integer(table(rows))
  lanes$n_serious <- as.integer(tapply(sev[near] == "serious", rows, sum, default = 0L))
  lanes$n_fatal <- as.integer(tapply(sev[near] == "fatal", rows, sum, default = 0L))
  lanes$n_serious[is.na(lanes$n_serious)] <- 0L
  lanes$n_fatal[is.na(lanes$n_fatal)] <- 0L

  structure(list(crashes = crashes, facilities = lanes, tolerance = tolerance),
            class = "cl_crash_join")
}

#' Reported crashes per kilometre-year by facility type
#'
#' Turns a [cl_crash_join()] into rates that can be compared across
#' facility types. The denominator is **kilometre-years**: facility
#' kilometres times the years the crash data span (or, when the facilities
#' carry an `install_year`, only the years after each was installed).
#' Intersection and mid-block crashes are reported on separate rows and
#' never merged: intersection crashes attach to whichever facility passes
#' through the intersection.
#'
#' Crashes per kilometre-year is not crashes per rider. A busy protected
#' lane carries many times the riders of a quiet sharrow, so a raw
#' per-kilometre rate flatters low-use facilities. When the facilities
#' carry an `exposure` column (average daily bicycle volume) the output
#' also gives crashes per million bicycle-kilometres. Police data miss
#' roughly half of bicycle injury crashes; these are reported crashes.
#'
#' @param joined A `cl_crash_join`.
#' @param years The calendar years the crash data cover, e.g. `2019:2025`.
#'   Taken from the crash dates when `NULL`.
#' @param by Facility column(s) to group by. Default `"facility_type"`.
#' @return A data frame with one row per group and `location_type`:
#'   `length_km`, `km_years`, `n_crashes`, `n_serious_fatal`,
#'   `crashes_per_km_year`, `serious_fatal_per_km_year`, and, when
#'   `exposure` is present, `crashes_per_million_bike_km`. Crashes not
#'   within tolerance of any facility appear under `facility_type = "none"`
#'   with no denominator.
#' @export
cl_crash_rates <- function(joined, years = NULL, by = "facility_type") {
  if (!inherits(joined, "cl_crash_join")) rlang::abort("`joined` must come from cl_crash_join().")
  cr <- joined$crashes
  fa <- joined$facilities
  if (is.null(years)) {
    yrs <- if ("year" %in% names(cr)) cr$year[!is.na(cr$year)] else integer()
    if (!length(yrs)) rlang::abort("`years` is needed: the crashes carry no `year` column.")
    years <- seq(min(yrs), max(yrs))
  }
  years <- sort(unique(as.integer(years)))
  n_years <- length(years)
  missing <- setdiff(by, names(fa))
  if (length(missing)) rlang::abort(sprintf("Column(s) not in the facilities: %s", paste(missing, collapse = ", ")))

  # facility-side denominators
  fd <- sf::st_drop_geometry(fa)
  fd$.km <- .length_m(fa) / 1000
  fd$.km_years <- if ("install_year" %in% names(fd)) {
    iy <- suppressWarnings(as.integer(fd$install_year))
    active <- ifelse(is.na(iy), n_years, pmax(0L, max(years) - pmax(iy, min(years)) + 1L))
    fd$.km * active
  } else fd$.km * n_years
  fd$.bike_km <- if ("exposure" %in% names(fd)) {
    fd$.km * suppressWarnings(as.numeric(fd$exposure)) * 365 * n_years
  } else NA_real_
  denom <- fd |>
    dplyr::group_by(dplyr::across(dplyr::all_of(by))) |>
    dplyr::summarise(length_km = sum(.data$.km), km_years = sum(.data$.km_years),
                     bike_km = sum(.data$.bike_km), .groups = "drop")

  # crash-side numerators, by the facility's grouping columns
  cd <- sf::st_drop_geometry(cr)
  for (col in by) {
    if (col == "facility_type") next
    cd[[col]] <- ifelse(is.na(cd$facility_row), NA, fd[[col]][cd$facility_row])
  }
  cd$location_type <- if ("location_type" %in% names(cd)) cd$location_type else "unknown"
  sev <- if ("severity" %in% names(cd)) as.character(cd$severity) else rep("unknown", nrow(cd))
  cd$.sf <- sev %in% c("serious", "fatal")
  num <- cd |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(by, "location_type")))) |>
    dplyr::summarise(n_crashes = dplyr::n(), n_serious_fatal = sum(.data$.sf), .groups = "drop")

  out <- dplyr::full_join(num, denom, by = by)
  out$n_crashes[is.na(out$n_crashes)] <- 0L
  out$n_serious_fatal[is.na(out$n_serious_fatal)] <- 0L
  out$location_type[is.na(out$location_type)] <- "none"
  out$crashes_per_km_year <- ifelse(out$km_years > 0, out$n_crashes / out$km_years, NA_real_)
  out$serious_fatal_per_km_year <- ifelse(out$km_years > 0, out$n_serious_fatal / out$km_years, NA_real_)
  if ("exposure" %in% names(fd)) {
    out$crashes_per_million_bike_km <- ifelse(out$bike_km > 0, out$n_crashes / (out$bike_km / 1e6), NA_real_)
  }
  out$bike_km <- NULL
  out <- out[order(match(out$location_type, c("intersection", "mid_block", "unknown", "none"))), ]
  out <- out[do.call(order, c(lapply(by, function(col) out[[col]]), list(out$location_type))), ]
  out <- as.data.frame(out)
  rownames(out) <- NULL
  attr(out, "years") <- years
  out
}

#' @export
print.cl_crash_join <- function(x, ...) {
  cr <- x$crashes
  near <- !is.na(cr$facility_row)
  cat(sprintf("<cl_crash_join> %d crashes, %d within %g m of a facility (%.0f%%), %d facilities\n",
              nrow(cr), sum(near), x$tolerance, 100 * mean(near), nrow(x$facilities)))
  if ("location_type" %in% names(cr)) print(table(location = cr$location_type, facility = cr$facility_type))
  invisible(x)
}
