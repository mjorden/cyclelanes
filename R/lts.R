#' Level of Traffic Stress
#'
#' Scores each facility 1 (comfortable for almost anyone) to 4 (strong and
#' fearless only) following the Level of Traffic Stress criteria of
#' Mekuria, Furth and Nixon (2012) as simplified in Furth's 2017 tables.
#' The score depends on the facility type and, for on-street facilities,
#' on the parent road's speed limit and number of lanes, which
#' [cl_classify()] carries as `road_maxspeed_kph` and `road_lanes`.
#'
#' Where a tag is missing the road class stands in: a `residential` or
#' `living_street` road is assumed 40 km/h with 2 lanes, a `tertiary` road
#' 48 km/h with 2 lanes, `secondary` 56 km/h with 4, `primary` or `trunk`
#' 64 km/h with 4, anything else 48 km/h with 2. `lts_basis` records which
#' rule fired and whether an assumption was used, so scores built on
#' assumptions can be told from scores built on tags. Parking-lane
#' conflicts and intersection approaches, which the full method also
#' scores, are not modelled.
#'
#' The rule table ships as `system.file("extdata", "lts_rules.csv",
#' package = "cyclelanes")` and is documented there.
#'
#' @param x An `sf` from [cl_classify()] or [cl_bike_lanes()].
#' @return `x` with integer `lts` (1-4) and character `lts_basis` columns
#'   added.
#' @references Mekuria, M. C., Furth, P. G., & Nixon, H. (2012). Low-stress
#'   bicycling and network connectivity. Mineta Transportation Institute
#'   Report 11-19. Furth, P. G. (2017). Level of Traffic Stress criteria for
#'   road segments, version 2.0.
#' @examples
#' lanes <- cl_lts(cl_classify(denver_lodo$osm, drop_none = TRUE))
#' table(lanes$lts)
#' cl_summary(lanes, by = "lts")
#' @export
cl_lts <- function(x) {
  .stop_if_not_sf(x)
  if (!"facility_type" %in% names(x)) rlang::abort("`x` has no `facility_type` column; classify it first.")
  x <- .ensure_cols(x, c("road_maxspeed_kph", "road_lanes", "highway"))
  ft <- as.character(x$facility_type)
  hw <- .norm_tag(x$highway)

  speed <- suppressWarnings(as.numeric(x$road_maxspeed_kph))
  lanes <- suppressWarnings(as.integer(x$road_lanes))
  assumed_speed <- is.na(speed)
  assumed_lanes <- is.na(lanes)
  speed[assumed_speed] <- .assumed_speed(hw[assumed_speed])
  lanes[assumed_lanes] <- .assumed_lanes(hw[assumed_lanes])

  rules <- .lts_rules()
  group <- .lts_group(ft)
  lts <- rep(NA_integer_, length(ft))
  basis <- rep(NA_character_, length(ft))
  for (i in seq_len(nrow(rules))) {
    r <- rules[i, ]
    hit <- is.na(lts) & group == r$group &
      (is.na(r$max_speed_kph) | speed <= r$max_speed_kph) &
      (is.na(r$max_lanes) | lanes <= r$max_lanes)
    lts[hit] <- as.integer(r$lts)
    basis[hit] <- r$rule
  }
  onstreet <- !group %in% c("path", "none")
  note <- ifelse(assumed_speed & assumed_lanes, " (speed and lanes assumed from road class)",
          ifelse(assumed_speed, " (speed assumed from road class)",
          ifelse(assumed_lanes, " (lanes assumed from road class)", "")))
  basis <- ifelse(onstreet, paste0(basis, note), basis)
  x$lts <- lts
  x$lts_basis <- basis
  x
}

.lts_group <- function(ft) {
  ifelse(ft %in% c("separated_path", "shared_use_path", "protected_lane"), "path",
  ifelse(ft %in% c("buffered_lane", "painted_lane"), "lane",
  ifelse(ft %in% "neighborhood_bikeway", "bikeway",
  ifelse(ft %in% "bus_bike_lane", "bus",
  ifelse(ft %in% c("shared_lane", "shoulder"), "mixed", "none")))))
}

.assumed_speed <- function(hw) {
  out <- rep(48, length(hw))
  out[hw %in% c("residential", "living_street", "service", "unclassified")] <- 40
  out[hw %in% "tertiary"] <- 48
  out[hw %in% "secondary"] <- 56
  out[hw %in% c("primary", "trunk", "motorway")] <- 64
  out
}

.assumed_lanes <- function(hw) {
  out <- rep(2L, length(hw))
  out[hw %in% c("secondary", "primary", "trunk", "motorway")] <- 4L
  out
}

.lts_rules <- function() {
  path <- system.file("extdata", "lts_rules.csv", package = "cyclelanes")
  if (!nzchar(path)) path <- "inst/extdata/lts_rules.csv"
  utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
}

#' Colours for Level of Traffic Stress
#' @return A named character vector of four colours, LTS 1 to 4.
#' @export
cl_lts_palette <- function() {
  c(`1` = "#1a9850", `2` = "#a6d96a", `3` = "#fdae61", `4` = "#d73027")
}
