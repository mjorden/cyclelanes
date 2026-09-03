# Crash sources ----------------------------------------------------------------

.cl_crash_registry <- new.env(parent = emptyenv())

.crash_severity_levels <- c("fatal", "serious", "minor", "none", "unknown")

.builtin_crash_sources <- function() {
  list(
    denver = list(
      city = "denver",
      label = "Denver, Colorado",
      type = "arcgis",
      # Denver Police NIBRS-based traffic accidents, 2013 to present; the
      # "5YR" in the name is historical.
      url = paste0("https://services1.arcgis.com/zdB7qR0BtYrg0Xpl/ArcGIS/rest/services/",
                   "ODC_CRIME_TRAFFICACCIDENTS5YR_P/FeatureServer/325"),
      fields = list(
        id = "incident_id",
        date = "first_occurrence_date",
        bicycle = "bicycle_ind",
        pedestrian = "pedestrian_ind",
        n_fatal = "FATALITIES",
        n_serious = "SERIOUSLY_INJURED",
        injured_mode = c("FATALITY_MODE_1", "FATALITY_MODE_2",
                         "SERIOUSLY_INJURED_MODE_1", "SERIOUSLY_INJURED_MODE_2"),
        location_type = "ROAD_DESCRIPTION",
        light = "LIGHT_CONDITION",
        road_condition = "ROAD_CONDITION",
        address = "incident_address",
        severity_text = "top_traffic_accident_offense",
        lon = "geo_lon",
        lat = "geo_lat"
      ),
      bike_where = "bicycle_ind = 1",
      attribution = paste("Denver Police Department, Traffic Accidents (NIBRS),",
                          "via the Denver Open Data Catalog. Revised continuously;",
                          "the fetch date is part of the result."),
      homepage = "https://opendata-geospatialdenver.hub.arcgis.com/"
    )
  )
}

.all_crash_sources <- function() {
  reg <- mget(ls(.cl_crash_registry), envir = .cl_crash_registry)
  builtin <- .builtin_crash_sources()
  c(reg, builtin[setdiff(names(builtin), names(reg))])
}

.get_crash_source <- function(city) {
  city <- tolower(trimws(city))
  src <- .all_crash_sources()[[city]]
  if (is.null(src)) {
    rlang::abort(sprintf(
      "No crash source registered for \"%s\". Known: %s. See cl_register_crash_source().",
      city, paste(names(.all_crash_sources()), collapse = ", ")
    ))
  }
  src
}

#' Registered crash data sources
#'
#' @return A data frame with one row per city: `city`, `label`, `type`,
#'   `homepage`, `attribution`.
#' @examples
#' cl_crash_sources()
#' @export
cl_crash_sources <- function() {
  s <- .all_crash_sources()
  data.frame(
    city = vapply(s, `[[`, character(1), "city"),
    label = vapply(s, function(z) z$label %||% z$city, character(1)),
    type = vapply(s, `[[`, character(1), "type"),
    homepage = vapply(s, function(z) z$homepage %||% NA_character_, character(1)),
    attribution = vapply(s, function(z) z$attribution %||% NA_character_, character(1)),
    row.names = NULL, stringsAsFactors = FALSE
  )
}

#' Register a crash data source for a city
#'
#' Adds (or replaces) a source so that [cl_fetch_crashes(city)][cl_fetch_crashes]
#' works for it. `fields` names the source's attributes for each standard
#' column; every entry is optional except `date`, and missing ones come
#' through as `NA`.
#'
#' @param city Short lower-case key.
#' @param url An ArcGIS REST layer endpoint, or anything [sf::st_read()]
#'   can open.
#' @param fields A named list mapping standard names to source attribute
#'   names: `id`, `date` (a date, epoch milliseconds, or ISO string),
#'   `bicycle` and `pedestrian` (flags: `1`, `Y`, `yes`, `TRUE`),
#'   `n_fatal`, `n_serious` (counts), `injured_mode` (one or more fields
#'   naming the mode of the people hurt: values containing `BIC`, `PED`),
#'   `location_type` (values containing `INTERSECTION` are intersections),
#'   `light`, `road_condition`, `address`, `severity_text` (a free-text
#'   offense or severity in which `INJUR` means at least a minor injury),
#'   and `lon`/`lat` for sources whose geometry can be empty.
#' @param type `"arcgis"` or `"file"`.
#' @param bike_where For ArcGIS sources, an SQL where clause selecting
#'   bicycle-involved crashes server-side; for file sources the `bicycle`
#'   flag is used instead.
#' @param label,attribution,homepage Provenance strings.
#' @return The source definition, invisibly.
#' @export
cl_register_crash_source <- function(city, url, fields, type = c("arcgis", "file"),
                                     bike_where = NULL, label = city,
                                     attribution = NULL, homepage = NULL) {
  type <- match.arg(type)
  city <- tolower(trimws(city))
  if (!nzchar(city)) rlang::abort("`city` must be a non-empty string.")
  if (!is.list(fields) || is.null(fields$date)) rlang::abort("`fields` must be a list with at least a `date` entry.")
  src <- list(city = city, label = label, type = type, url = url, fields = fields,
              bike_where = bike_where, attribution = attribution, homepage = homepage)
  assign(city, src, envir = .cl_crash_registry)
  invisible(src)
}

# Fetching ---------------------------------------------------------------------

#' Fetch reported crashes for a city
#'
#' Reads a registered crash source (see [cl_crash_sources()]) and returns
#' the crashes as points with a standard set of columns, so
#' [cl_crash_join()] and [cl_crash_rates()] work on any city.
#'
#' Police crash data miss roughly half of bicycle injury crashes and
#' almost all crashes with no motor vehicle involved; what comes back is
#' *reported* crashes. Sources are revised continuously, so the fetch time
#' in `attr(x, "cl_fetched")` is part of the result.
#'
#' @param city A key from [cl_crash_sources()], default `"denver"`, or a
#'   place name with no registered source, in which case the crashes come
#'   from NHTSA's FARS through [cl_fetch_fars()] -- fatalities only, and
#'   `years` is then required.
#' @param years Optional integer vector of years to keep, e.g. `2019:2025`.
#' @param bike_only Keep bicycle-involved crashes only (default). `FALSE`
#'   returns every crash, which for a city is hundreds of thousands.
#' @param bbox Optional area (anything [cl_bbox()] accepts, or an `sf`
#'   polygon, which also clips).
#' @param keep_raw Keep the source's own columns alongside the standard ones.
#' @return An `sf` of `POINT`s in WGS84 with columns `source_id`, `date`,
#'   `year`, `severity` (factor `fatal` > `serious` > `minor` > `none` >
#'   `unknown`), `bicycle`, `pedestrian`, `n_fatal`, `n_serious`,
#'   `injured_mode` (`bicycle`, `pedestrian`, `motor_vehicle`, `unknown`:
#'   who was hurt, as distinct from who was involved), `location_type`
#'   (`intersection`, `mid_block`, `unknown`), `light`, `road_condition`,
#'   `address`. Attributes `cl_source`, `cl_attribution`, `cl_fetched`.
#' @examples
#' \dontrun{
#' crashes <- cl_fetch_crashes("denver", years = 2019:2025)
#' table(crashes$severity, crashes$location_type)
#' }
#' @export
cl_fetch_crashes <- function(city = "denver", years = NULL, bike_only = TRUE, bbox = NULL,
                             keep_raw = FALSE) {
  key <- tolower(trimws(city))
  if (!key %in% names(.all_crash_sources())) {
    if (is.null(years)) {
      rlang::abort(c(sprintf("No crash source is registered for \"%s\".", city),
                     i = "Pass `years` to fall back to NHTSA FARS (fatal crashes only) for that place, or register a source with cl_register_crash_source()."))
    }
    rlang::inform(sprintf("No crash source registered for \"%s\"; using NHTSA FARS (fatal crashes only).", city))
    area <- if (!is.null(bbox)) bbox else tryCatch(cl_boundary(city), error = function(e) cl_bbox(city))
    return(cl_fetch_fars(years, bbox = area, bike_only = bike_only))
  }
  src <- .get_crash_source(city)
  if (!is.null(years) && (!is.numeric(years) || any(years < 1900 | years > 2100))) {
    rlang::abort("`years` must be a vector of calendar years.")
  }
  polygon <- NULL
  if (inherits(bbox, c("sf", "sfc")) &&
      all(sf::st_geometry_type(bbox) %in% c("POLYGON", "MULTIPOLYGON"))) {
    polygon <- cl_boundary(bbox)
  }
  bb <- if (!is.null(bbox)) cl_bbox(bbox) else NULL

  raw <- switch(
    src$type,
    arcgis = {
      clauses <- character()
      if (bike_only && !is.null(src$bike_where)) clauses <- c(clauses, src$bike_where)
      if (!is.null(years)) {
        clauses <- c(clauses, sprintf("%s >= DATE '%d-01-01' AND %s < DATE '%d-01-01'",
                                      src$fields$date, min(years), src$fields$date, max(years) + 1L))
      }
      where <- if (length(clauses)) paste(sprintf("(%s)", clauses), collapse = " AND ") else "1=1"
      .arcgis_read(src$url, where = where, bbox = bb)
    },
    file = {
      z <- sf::st_read(src$url, quiet = TRUE)
      if (is.na(sf::st_crs(z))) sf::st_crs(z) <- 4326
      z <- sf::st_transform(z, 4326)
      if (!is.null(bb)) {
        hit <- lengths(sf::st_intersects(z, sf::st_as_sfc(sf::st_bbox(
          c(xmin = bb[["xmin"]], ymin = bb[["ymin"]], xmax = bb[["xmax"]], ymax = bb[["ymax"]]),
          crs = sf::st_crs(4326))))) > 0
        z <- z[hit, ]
      }
      z
    },
    rlang::abort(sprintf("Unknown source type \"%s\".", src$type))
  )

  out <- .standardise_crashes(raw, src, keep_raw = keep_raw)
  if (bike_only) out <- out[out$bicycle %in% TRUE, ]
  if (!is.null(years)) out <- out[!is.na(out$year) & out$year %in% years, ]
  if (!is.null(polygon) && nrow(out)) {
    inside <- lengths(sf::st_intersects(out, sf::st_geometry(polygon))) > 0
    out <- out[inside, ]
  }
  rownames(out) <- NULL
  attr(out, "cl_source") <- src$city
  attr(out, "cl_attribution") <- src$attribution
  attr(out, "cl_fetched") <- Sys.time()
  out
}

.standardise_crashes <- function(raw, src, keep_raw = FALSE) {
  .stop_if_not_sf(raw, "raw")
  f <- src$fields
  n <- nrow(raw)
  d <- sf::st_drop_geometry(raw)
  get <- function(field) {
    if (is.null(field) || !all(field %in% names(d))) return(rep(NA, n))
    d[[field[1]]]
  }
  date <- .parse_crash_date(get(f$date))
  n_fatal <- suppressWarnings(as.integer(get(f$n_fatal)))
  n_serious <- suppressWarnings(as.integer(get(f$n_serious)))
  n_fatal[is.na(n_fatal)] <- 0L
  n_serious[is.na(n_serious)] <- 0L
  sev_text <- toupper(trimws(as.character(get(f$severity_text))))
  severity <- ifelse(n_fatal > 0, "fatal",
              ifelse(n_serious > 0, "serious",
              ifelse(!is.na(sev_text) & grepl("INJUR", sev_text), "minor",
              ifelse(!is.na(sev_text), "none", "unknown"))))

  modes <- if (!is.null(f$injured_mode)) {
    cols <- intersect(f$injured_mode, names(d))
    if (length(cols)) toupper(trimws(do.call(paste, c(d[cols], sep = "|")))) else rep(NA_character_, n)
  } else rep(NA_character_, n)
  injured_mode <- ifelse(is.na(modes), "unknown",
                  ifelse(grepl("BIC|BIKE|CYCL", modes), "bicycle",
                  ifelse(grepl("PED", modes), "pedestrian",
                  ifelse(grepl("[A-Z]", gsub("OTHER|NA|\\|", "", modes)), "motor_vehicle", "unknown"))))
  injured_mode[severity %in% c("none", "unknown") & injured_mode == "unknown"] <- "unknown"

  loc <- toupper(trimws(as.character(get(f$location_type))))
  location_type <- ifelse(is.na(loc) | !nzchar(loc), "unknown",
                   ifelse(grepl("NON.?INTERSECTION|NOT AT|MID.?BLOCK", loc), "mid_block",
                   ifelse(grepl("INTERSECTION", loc), "intersection", "mid_block")))

  out <- data.frame(
    source_id = if (is.null(f$id)) as.character(seq_len(n)) else as.character(get(f$id)),
    date = date,
    year = as.integer(format(date, "%Y")),
    severity = factor(severity, levels = .crash_severity_levels),
    bicycle = .flag(get(f$bicycle)),
    pedestrian = .flag(get(f$pedestrian)),
    n_fatal = n_fatal,
    n_serious = n_serious,
    injured_mode = injured_mode,
    location_type = location_type,
    light = trimws(as.character(get(f$light))),
    road_condition = trimws(as.character(get(f$road_condition))),
    address = trimws(as.character(get(f$address))),
    stringsAsFactors = FALSE
  )
  if (keep_raw) out <- cbind(out, d[, setdiff(names(d), names(out)), drop = FALSE])

  geom <- sf::st_geometry(raw)
  if (is.na(sf::st_crs(geom))) sf::st_crs(geom) <- 4326
  geom <- sf::st_transform(geom, 4326)
  empty <- sf::st_is_empty(geom)
  if (any(empty) && !is.null(f$lon) && !is.null(f$lat) && all(c(f$lon, f$lat) %in% names(d))) {
    lon <- suppressWarnings(as.numeric(d[[f$lon]]))
    lat <- suppressWarnings(as.numeric(d[[f$lat]]))
    fix <- empty & is.finite(lon) & is.finite(lat)
    if (any(fix)) {
      pts <- sf::st_sfc(lapply(which(fix), function(i) sf::st_point(c(lon[i], lat[i]))), crs = 4326)
      geom[fix] <- pts
      empty <- sf::st_is_empty(geom)
    }
  }
  if (any(empty)) {
    rlang::inform(sprintf("%d crash%s with no location dropped.", sum(empty), if (sum(empty) == 1) "" else "es"))
  }
  res <- sf::st_sf(out, geometry = geom)[!empty, ]
  rownames(res) <- NULL
  res
}

.flag <- function(v) {
  if (all(is.na(v))) return(rep(NA, length(v)))
  s <- toupper(trimws(as.character(v)))
  out <- s %in% c("1", "Y", "YES", "TRUE", "T")
  out[is.na(s)] <- NA
  out
}

# Epoch milliseconds, epoch seconds, Date, POSIXct, or an ISO-ish string.
.parse_crash_date <- function(v) {
  if (inherits(v, "Date")) return(v)
  if (inherits(v, "POSIXct")) return(as.Date(v, tz = "UTC"))
  if (is.numeric(v)) {
    secs <- ifelse(abs(v) > 1e11, v / 1000, v)
    return(as.Date(as.POSIXct(secs, origin = "1970-01-01", tz = "UTC")))
  }
  s <- trimws(as.character(v))
  d <- suppressWarnings(as.Date(substr(s, 1, 10), format = "%Y-%m-%d"))
  alt <- suppressWarnings(as.Date(substr(s, 1, 10), format = "%m/%d/%Y"))
  d[is.na(d)] <- alt[is.na(d)]
  d
}
