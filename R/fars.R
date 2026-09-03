#' Fatal crashes anywhere in the US from NHTSA's FARS
#'
#' Every fatal crash on a US public road since 1975 is in the Fatality
#' Analysis Reporting System, with coordinates from 2001 on. This reads
#' the yearly national CSV release, keeps crashes inside `bbox`, and
#' returns them in the same shape as [cl_fetch_crashes()], so a city with
#' no crash source of its own still gets a fatalities-only layer.
#'
#' Each year's release is a 20-40 MB zip, downloaded once into
#' `cache_dir`. FARS final data lag about two years. Coordinates recorded
#' as unknown (`77.7777`, `88.8888`, `99.9999` and their longitude
#' counterparts) are dropped, not plotted.
#'
#' @param years Integer vector of years, 2001 or later.
#' @param bbox Area to keep (anything [cl_bbox()] accepts, or an `sf`
#'   polygon, which also clips).
#' @param bike_only Keep crashes in which a bicyclist was involved.
#' @param cache_dir Where the yearly zips are kept.
#' @return An `sf` of `POINT`s in WGS84 with the [cl_fetch_crashes()]
#'   columns. `severity` is always `fatal`; `n_serious` is `NA` because
#'   FARS records deaths only. `injured_mode` is the mode of the person who
#'   died. `location_type` comes from the relation-to-junction code.
#' @examples
#' \dontrun{
#' den <- cl_fetch_fars(2021:2022, bbox = cl_boundary("Denver, Colorado"))
#' table(den$injured_mode)
#' }
#' @export
cl_fetch_fars <- function(years, bbox, bike_only = TRUE,
                          cache_dir = file.path(cl_cache_dir(), "fars")) {
  years <- sort(unique(as.integer(years)))
  if (!length(years) || any(is.na(years)) || any(years < 2001)) {
    rlang::abort("`years` must be integers from 2001 on (earlier FARS years have no coordinates).")
  }
  polygon <- NULL
  if (inherits(bbox, c("sf", "sfc")) &&
      all(sf::st_geometry_type(bbox) %in% c("POLYGON", "MULTIPOLYGON"))) {
    polygon <- cl_boundary(bbox)
  }
  bb <- cl_bbox(bbox)
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

  parts <- lapply(years, function(y) {
    tabs <- .fars_download(y, cache_dir)
    .fars_standardise(tabs$accident, tabs$person, y, bb)
  })
  out <- do.call(rbind, parts)
  if (bike_only) out <- out[out$bicycle %in% TRUE, ]
  if (!is.null(polygon) && nrow(out)) {
    inside <- lengths(sf::st_intersects(out, sf::st_geometry(polygon))) > 0
    out <- out[inside, ]
  }
  rownames(out) <- NULL
  attr(out, "cl_source") <- "fars"
  attr(out, "cl_attribution") <- paste("NHTSA Fatality Analysis Reporting System (FARS),",
                                       paste(range(years), collapse = "-"), "national CSV release.")
  attr(out, "cl_fetched") <- Sys.time()
  out
}

.fars_url <- function(year) {
  sprintf("https://static.nhtsa.gov/nhtsa/downloads/FARS/%d/National/FARS%dNationalCSV.zip", year, year)
}

# Download (once) and read the accident and person tables for one year.
# Mocked in tests.
.fars_download <- function(year, cache_dir) {
  zip <- file.path(cache_dir, sprintf("FARS%dNationalCSV.zip", year))
  if (!file.exists(zip)) {
    old <- options(timeout = max(3600, getOption("timeout", 60)))
    on.exit(options(old), add = TRUE)
    rlang::inform(sprintf("Downloading FARS %d national CSV (20-40 MB)...", year))
    status <- tryCatch(utils::download.file(.fars_url(year), zip, mode = "wb", quiet = TRUE),
                       error = function(e) conditionMessage(e))
    if (!identical(as.integer(status), 0L)) {
      unlink(zip)
      rlang::abort(c(sprintf("Could not download FARS %d.", year), i = as.character(status)))
    }
  }
  files <- utils::unzip(zip, list = TRUE)$Name
  pick <- function(name) {
    f <- files[tolower(basename(files)) == paste0(name, ".csv")]
    if (!length(f)) rlang::abort(sprintf("FARS %d zip has no %s.csv.", year, name))
    con <- unz(zip, f[1])
    on.exit(close(con), add = TRUE)
    utils::read.csv(con, stringsAsFactors = FALSE, fileEncoding = "latin1", check.names = FALSE)
  }
  list(accident = pick("accident"), person = pick("person"))
}

.fars_col <- function(d, ...) {
  for (nm in c(...)) if (nm %in% names(d)) return(d[[nm]])
  rep(NA, nrow(d))
}

.fars_standardise <- function(acc, per, year, bb) {
  names(acc) <- toupper(names(acc))
  names(per) <- toupper(names(per))
  lat <- suppressWarnings(as.numeric(.fars_col(acc, "LATITUDE")))
  lon <- suppressWarnings(as.numeric(.fars_col(acc, "LONGITUD", "LONGITUDE")))
  bad <- is.na(lat) | is.na(lon) | lat %in% c(77.7777, 88.8888, 99.9999) |
    lon %in% c(777.7777, 888.8888, 999.9999) | abs(lat) > 90 | abs(lon) > 180
  keep <- !bad & lon >= bb[["xmin"]] & lon <= bb[["xmax"]] & lat >= bb[["ymin"]] & lat <= bb[["ymax"]]
  acc <- acc[keep, , drop = FALSE]
  lat <- lat[keep]; lon <- lon[keep]
  n <- nrow(acc)

  case <- as.character(.fars_col(acc, "ST_CASE"))
  per_case <- as.character(.fars_col(per, "ST_CASE"))
  per <- per[per_case %in% case, , drop = FALSE]
  per_case <- per_case[per_case %in% case]
  ptype <- suppressWarnings(as.integer(.fars_col(per, "PER_TYP")))
  inj <- suppressWarnings(as.integer(.fars_col(per, "INJ_SEV")))
  cyclist <- ptype %in% c(6L, 7L)
  ped <- ptype %in% 5L
  died <- inj %in% 4L

  by_case <- function(flag) {
    hit <- tapply(flag, factor(per_case, levels = case), any)
    v <- as.logical(hit); v[is.na(v)] <- FALSE; v
  }
  bicycle <- by_case(cyclist)
  pedestrian <- by_case(ped)
  cyclist_died <- by_case(cyclist & died)
  ped_died <- by_case(ped & died)

  month <- suppressWarnings(as.integer(.fars_col(acc, "MONTH")))
  day <- suppressWarnings(as.integer(.fars_col(acc, "DAY")))
  day[is.na(day) | day < 1 | day > 31] <- NA
  month[is.na(month) | month < 1 | month > 12] <- NA
  date <- suppressWarnings(as.Date(sprintf("%d-%02d-%02d", year, month, day)))

  rel <- .fars_col(acc, "RELJCT2NAME", "RELJCT2")
  rel_s <- toupper(trimws(as.character(rel)))
  location_type <- ifelse(is.na(rel_s) | !nzchar(rel_s), "unknown",
                   ifelse(grepl("NON.?JUNCTION|^1$", rel_s), "mid_block",
                   ifelse(grepl("INTERSECTION|^[23]$", rel_s), "intersection", "mid_block")))
  light <- trimws(as.character(.fars_col(acc, "LGT_CONDNAME", "LGT_COND")))

  out <- data.frame(
    source_id = paste0(year, "-", case),
    date = date,
    year = rep(year, n),
    severity = factor(rep("fatal", n), levels = .crash_severity_levels),
    bicycle = bicycle,
    pedestrian = pedestrian,
    n_fatal = suppressWarnings(as.integer(.fars_col(acc, "FATALS"))),
    n_serious = rep(NA_integer_, n),
    injured_mode = ifelse(cyclist_died, "bicycle", ifelse(ped_died, "pedestrian", "motor_vehicle")),
    location_type = location_type,
    light = light,
    road_condition = rep(NA_character_, n),
    address = rep(NA_character_, n),
    stringsAsFactors = FALSE
  )
  geom <- sf::st_sfc(lapply(seq_len(n), function(i) sf::st_point(c(lon[i], lat[i]))), crs = 4326)
  sf::st_sf(out, geometry = geom)
}
