#' The cyclelanes facility taxonomy
#'
#' Every facility in the package -- whether it came from OpenStreetMap or a
#' city's official inventory -- is classified into one of these levels,
#' ordered from most to least physically separated from motor traffic:
#'
#' | level | meaning | typical OSM tagging |
#' |---|---|---|
#' | `separated_path` | dedicated off-street cycleway or trail | `highway=cycleway` |
#' | `shared_use_path` | off-street path shared with pedestrians | `highway=path/footway` + `bicycle=designated`; `highway=cycleway` + `segregated=no` or `foot=designated` |
#' | `protected_lane` | on-street, physically separated (curb, bollards, parking) | `cycleway=track` |
#' | `buffered_lane` | painted lane with a painted buffer | `cycleway=lane` + `cycleway:buffer=*` |
#' | `painted_lane` | painted lane, no buffer | `cycleway=lane` |
#' | `neighborhood_bikeway` | low-traffic street designated for bikes | `bicycle_road=yes`, `cyclestreet=yes` |
#' | `bus_bike_lane` | shared bus and bike lane | `cycleway=share_busway` |
#' | `shared_lane` | sharrows / shared general-traffic lane | `cycleway=shared_lane` |
#' | `shoulder` | rideable paved shoulder | `cycleway=shoulder` |
#' | `none` | no facility | `cycleway=no`, unrecognised, or absent; sidewalks (`footway=sidewalk`) whatever their `bicycle` tag |
#'
#' @return A character vector of level names in protection order.
#' @export
cl_facility_levels <- function() {
  c("separated_path", "shared_use_path", "protected_lane", "buffered_lane",
    "painted_lane", "neighborhood_bikeway", "bus_bike_lane", "shared_lane",
    "shoulder", "none")
}

.facility_factor <- function(x) {
  factor(as.character(x), levels = cl_facility_levels())
}

# Map a cycleway=* value to a facility level. NA in -> NA out (tag absent).
# Any recognised value maps; anything unrecognised is treated as no facility.
.map_cycleway <- function(value) {
  v <- .norm_tag(value)
  lut <- c(
    track = "protected_lane",
    opposite_track = "protected_lane",
    lane = "painted_lane",
    opposite_lane = "painted_lane",
    yes = "painted_lane",
    shared_lane = "shared_lane",
    shared = "shared_lane",
    sharrow = "shared_lane",
    opposite = "shared_lane",
    share_busway = "bus_bike_lane",
    shared_busway = "bus_bike_lane",
    opposite_share_busway = "bus_bike_lane",
    shoulder = "shoulder",
    no = "none",
    none = "none",
    separate = "none",
    sidepath = "none",
    crossing = "none",
    link = "none"
  )
  out <- rep(NA_character_, length(v))
  known <- !is.na(v) & v %in% names(lut)
  out[known] <- unname(lut[v[known]])
  out[!is.na(v) & !known] <- "none"
  out
}

.contraflow_values <- c("opposite", "opposite_lane", "opposite_track",
                        "opposite_share_busway")

.classify_tag_cols <- c(
  "osm_id", "name", "highway",
  "cycleway", "cycleway:left", "cycleway:right", "cycleway:both",
  "cycleway:buffer", "cycleway:left:buffer", "cycleway:right:buffer",
  "cycleway:both:buffer",
  "bicycle", "bicycle_road", "cyclestreet", "foot", "footway", "segregated",
  "is_sidepath", "oneway", "surface"
)

# Surfaces that count as paved for `strict = TRUE`.
.paved_surfaces <- c("paved", "asphalt", "concrete", "concrete:plates",
                     "concrete:lanes", "paving_stones", "chipseal")

# Does a way's name read like a street (and not like a trail)? Used to
# recognise on-street lanes that mappers drew as their own highway=cycleway.
.street_suffixes <- c("street", "st", "avenue", "ave", "boulevard", "blvd",
                      "road", "rd", "drive", "dr", "way", "lane", "ln",
                      "parkway", "pkwy", "place", "pl", "court", "ct",
                      "highway", "hwy", "terrace", "ter", "circle", "cir")
.trail_words <- c("trail", "path", "greenway", "bikeway", "bike path",
                  "cycleway", "cycle path", "towpath", "promenade", "esplanade")

.street_like_name <- function(name) {
  n <- .norm_tag(name)
  out <- rep(FALSE, length(n))
  ok <- !is.na(n)
  if (!any(ok)) return(out)
  n <- gsub("[.,]", "", n[ok])
  # strip a trailing direction ("15th street nw") and a "bike lane" qualifier
  n <- sub("\\s+(n|s|e|w|ne|nw|se|sw|north|south|east|west)$", "", n)
  n <- sub("\\s+(bike lane|cycle track|cycle lane|bike track|protected bike lane)$", "", n)
  last <- sub("^.*\\s", "", n)
  trailish <- Reduce(`|`, lapply(.trail_words, function(w) grepl(paste0("\\b", w, "\\b"), n)))
  out[ok] <- last %in% .street_suffixes & !trailish
  out
}

.classify_out_cols <- c(
  "osm_id", "name", "highway",
  "facility_type", "facility_left", "facility_right", "n_sides",
  "contraflow", "shared_with_pedestrians", "mapped_separately",
  "oneway", "surface", "length_m"
)

#' Classify OpenStreetMap ways into the facility taxonomy
#'
#' Normalises the OSM bicycle tagging on each way into the levels of
#' [cl_facility_levels()], resolving the per-side tags so that each street
#' gets a left, a right, and an overall classification.
#'
#' The rules, in order:
#'
#' 1. `highway=cycleway` is a `separated_path` for the whole way, unless it
#'    is shared with pedestrians (`segregated=no` or `foot=designated`), in
#'    which case it is a `shared_use_path`. `highway=path`, `footway`,
#'    `pedestrian`, `track` or `bridleway` with `bicycle=designated` is a
#'    `shared_use_path`. A sidewalk (`footway=sidewalk` or `footway=crossing`)
#'    is never a facility, whatever its `bicycle` tag. Side columns are `NA`
#'    for paths.
#'    A `highway=cycleway` that is really an on-street lane drawn as its own
#'    way -- tagged `is_sidepath=yes`, or carrying `cycleway=track` /
#'    `cycleway:*=track` -- is a `protected_lane` with
#'    `mapped_separately = TRUE`, so it lines up with a city inventory that
#'    files it under protected lanes rather than trails. With
#'    `sidepath_by_name = TRUE` (the default) a `highway=cycleway` whose
#'    `name` reads like a street ("14th Street", "Lawrence St") counts too,
#'    because mappers who draw a lane as its own way usually name it after
#'    the street, while trails are named as trails. It is a heuristic; turn
#'    it off where cycleways are routinely named after streets.
#' 2. Otherwise each side starts from `cycleway=*`, is overridden by
#'    `cycleway:both=*`, and then by `cycleway:left=*` / `cycleway:right=*`.
#' 3. A `painted_lane` side with a truthy `cycleway[:side]:buffer` tag
#'    becomes `buffered_lane`.
#' 4. `bicycle_road=yes` or `cyclestreet=yes` makes any side that has no
#'    other facility a `neighborhood_bikeway`.
#' 5. `facility_type` is the more protected of the two sides.
#'
#' `cycleway=separate` / `sidepath` (the facility is mapped as its own way)
#' and `cycleway=no` both yield `none`, so nothing is double-counted.
#'
#' @param x An `sf` object from [cl_fetch_osm()], or any `sf` of ways with
#'   OSM-style tag columns. Missing tag columns are treated as absent tags.
#' @param drop_none Drop ways whose overall `facility_type` is `none`.
#' @param keep_tags Keep every input column in addition to the standard
#'   output columns. By default only `osm_id`, `name`, `highway`, `oneway`
#'   and `surface` survive from the input.
#' @param strict Also drop `shared_use_path` ways that are not
#'   `highway=cycleway` and lack a paved `surface` tag (`paved`, `asphalt`,
#'   `concrete`, `paving_stones`, ...). Park footways that a mapper tagged
#'   bike-friendly are the bulk of what this removes; use it when you want
#'   on-road-quality kilometres only.
#' @param sidepath_by_name Treat a `highway=cycleway` named like a street
#'   (a suffix such as Street, St, Avenue, Ave, Boulevard, Blvd, Road, Rd,
#'   Drive, Dr, Way, Lane, Ln, Parkway, Pkwy, Place, Pl, Court, Ct, and not
#'   Trail, Path, Greenway, Bikeway) as a separately mapped on-street lane,
#'   i.e. a `protected_lane`. See rule 1.
#' @return An `sf` with columns `osm_id`, `name`, `highway`, `facility_type`,
#'   `facility_left`, `facility_right` (factors over [cl_facility_levels()]),
#'   `n_sides` (0-2, `NA` for separated paths), `contraflow`,
#'   `shared_with_pedestrians`, `mapped_separately` (a facility drawn as its
#'   own way rather than as a tag on the road), `oneway`, `surface`,
#'   `length_m`, and geometry.
#' @examples
#' ways <- sf::st_sf(
#'   highway = c("residential", "cycleway", "primary"),
#'   cycleway = c("lane", NA, "no"),
#'   `cycleway:right:buffer` = c("yes", NA, NA),
#'   geometry = sf::st_sfc(
#'     sf::st_linestring(rbind(c(-105, 39.7), c(-104.999, 39.7))),
#'     sf::st_linestring(rbind(c(-105, 39.71), c(-104.999, 39.71))),
#'     sf::st_linestring(rbind(c(-105, 39.72), c(-104.999, 39.72))),
#'     crs = 4326
#'   ),
#'   check.names = FALSE
#' )
#' cl_classify(ways)[, c("facility_type", "facility_left", "facility_right")]
#' @export
cl_classify <- function(x, drop_none = FALSE, keep_tags = FALSE, strict = FALSE,
                        sidepath_by_name = TRUE) {
  .stop_if_not_sf(x)
  geom_col <- attr(x, "sf_column")
  x <- .ensure_cols(x, .classify_tag_cols)

  hw <- .norm_tag(x$highway)
  bicycle <- .norm_tag(x$bicycle)
  foot <- .norm_tag(x$foot)
  footway <- .norm_tag(x$footway)
  segregated <- .norm_tag(x$segregated)
  surface <- .norm_tag(x$surface)

  # 1. whole-way paths: dedicated cycleways vs paths shared with pedestrians;
  #    sidewalks are never facilities
  is_sidewalk <- footway %in% c("sidewalk", "crossing")
  is_cycleway <- hw %in% "cycleway"
  # an on-street protected lane drawn as its own way beside the road
  track_tag <- .map_cycleway(x$cycleway) %in% "protected_lane" |
    .map_cycleway(x[["cycleway:both"]]) %in% "protected_lane" |
    .map_cycleway(x[["cycleway:left"]]) %in% "protected_lane" |
    .map_cycleway(x[["cycleway:right"]]) %in% "protected_lane"
  name_says_street <- if (isTRUE(sidepath_by_name)) .street_like_name(x$name) else rep(FALSE, nrow(x))
  is_sidepath <- is_cycleway & (.tag_truthy(x$is_sidepath) | track_tag | name_says_street)
  is_mixed <- segregated %in% "no" | foot %in% "designated"
  is_dedicated_path <- is_cycleway & !is_mixed & !is_sidepath
  is_shared_path <- (is_cycleway & is_mixed & !is_sidepath) |
    (hw %in% c("path", "footway", "pedestrian", "track", "bridleway") &
       bicycle %in% "designated" & !is_sidewalk)
  if (isTRUE(strict)) {
    unpaved <- !is_cycleway & !surface %in% .paved_surfaces
    is_shared_path <- is_shared_path & !unpaved
  }
  is_path <- is_dedicated_path | is_shared_path | is_sidepath

  # 2. per-side resolution
  base  <- .map_cycleway(x$cycleway)
  both  <- .map_cycleway(x[["cycleway:both"]])
  left  <- .map_cycleway(x[["cycleway:left"]])
  right <- .map_cycleway(x[["cycleway:right"]])
  fl <- dplyr::coalesce(left, both, base)
  fr <- dplyr::coalesce(right, both, base)

  # 3. buffers
  buf_base <- .tag_truthy(x[["cycleway:buffer"]]) | .tag_truthy(x[["cycleway:both:buffer"]])
  buf_l <- .tag_truthy(x[["cycleway:left:buffer"]]) | buf_base
  buf_r <- .tag_truthy(x[["cycleway:right:buffer"]]) | buf_base
  fl[fl %in% "painted_lane" & buf_l] <- "buffered_lane"
  fr[fr %in% "painted_lane" & buf_r] <- "buffered_lane"

  # 4. neighbourhood bikeways fill sides with nothing better
  is_bikeway <- .tag_truthy(x$bicycle_road) | .tag_truthy(x$cyclestreet)
  fl[(is.na(fl) | fl %in% "none") & is_bikeway] <- "neighborhood_bikeway"
  fr[(is.na(fr) | fr %in% "none") & is_bikeway] <- "neighborhood_bikeway"
  fl[is.na(fl)] <- "none"
  fr[is.na(fr)] <- "none"

  # 5. overall = more protected side; paths override
  lv <- cl_facility_levels()
  overall <- lv[pmin(match(fl, lv), match(fr, lv))]
  overall[is_dedicated_path] <- "separated_path"
  overall[is_shared_path] <- "shared_use_path"
  overall[is_sidepath] <- "protected_lane"
  fl[is_path] <- NA_character_
  fr[is_path] <- NA_character_

  n_sides <- as.integer(!fl %in% c("none", NA)) + as.integer(!fr %in% c("none", NA))
  n_sides[is_path] <- NA_integer_

  contraflow <- .norm_tag(x$cycleway) %in% .contraflow_values |
    .norm_tag(x[["cycleway:left"]]) %in% .contraflow_values |
    .norm_tag(x[["cycleway:right"]]) %in% .contraflow_values |
    .norm_tag(x[["cycleway:both"]]) %in% .contraflow_values

  shared_peds <- is_shared_path | (is_dedicated_path & foot %in% "yes")

  out <- x
  out$facility_type <- .facility_factor(overall)
  out$facility_left <- .facility_factor(fl)
  out$facility_right <- .facility_factor(fr)
  out$n_sides <- n_sides
  out$contraflow <- contraflow
  out$shared_with_pedestrians <- shared_peds
  out$mapped_separately <- is_sidepath
  out$length_m <- .length_m(out)

  keep <- .classify_out_cols
  if (keep_tags) {
    keep <- c(keep, setdiff(names(x), c(keep, geom_col)))
  }
  out <- out[, keep]
  if (drop_none) {
    out <- out[out$facility_type != "none", ]
  }
  rownames(out) <- NULL
  out
}
