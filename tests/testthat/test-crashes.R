# cl_fetch_crashes() through a file source, and the Denver definition.

crash_file <- function() {
  pts <- function(lon, lat) sf::st_point(c(lon, lat))
  raw <- sf::st_sf(
    INC = c("a", "b", "c", "d", "e", "f"),
    WHEN = c(1704067200000, 1706745600000, 1735689600000, 1704067200000, 1704067200000, NA),  # ms: 2024-01-01, 2024-02-01, 2025-01-01, ...
    BIKE = c(1, 1, 0, 1, 1, 1),
    PED = c(0, 0, 1, 0, 0, 0),
    KILLED = c(0, 1, 0, 0, 0, 0),
    HURT = c(1, 0, 0, 0, 0, 0),
    MODE1 = c("BICYCLE", "OTHER", "PEDESTRIAN", NA, NA, NA),
    MODE2 = c("OTHER", "BICYCLE", "OTHER", NA, NA, NA),
    WHERE = c("AT INTERSECTION", "NON-INTERSECTION", "INTERSECTION RELATED", NA, "NON-INTERSECTION", NA),
    OFFENSE = c("TRAF - ACCIDENT - SBI", "TRAF - ACCIDENT - FATAL", "TRAF - ACCIDENT", "TRAF - ACCIDENT - INJURY", NA, "TRAF - ACCIDENT"),
    LIGHT = c("DAYLIGHT", "DARK", "DAWN OR DUSK", NA, NA, NA),
    geometry = sf::st_sfc(pts(-105.00, 39.75), pts(-104.99, 39.75), pts(-104.98, 39.75),
                          pts(-104.97, 39.75), pts(-104.96, 39.75), pts(-104.95, 39.75), crs = 4326)
  )
  path <- withr::local_tempfile(fileext = ".geojson", .local_envir = parent.frame())
  sf::st_write(raw, path, quiet = TRUE)
  path
}

register_crash_file <- function(path) {
  cl_register_crash_source(
    "crashtown", url = path, type = "file", label = "Crashtown",
    fields = list(id = "INC", date = "WHEN", bicycle = "BIKE", pedestrian = "PED",
                  n_fatal = "KILLED", n_serious = "HURT", injured_mode = c("MODE1", "MODE2"),
                  location_type = "WHERE", light = "LIGHT", severity_text = "OFFENSE"),
    attribution = "test"
  )
}

test_that("a file crash source is standardised: severity, who was hurt, where", {
  withr::defer(rm(list = ls(cyclelanes:::.cl_crash_registry), envir = cyclelanes:::.cl_crash_registry))
  path <- crash_file()
  register_crash_file(path)
  expect_true("crashtown" %in% cl_crash_sources()$city)

  x <- cl_fetch_crashes("crashtown", bike_only = FALSE)
  expect_s3_class(x, "sf")
  expect_equal(nrow(x), 6L)
  expect_true(all(sf::st_geometry_type(x) == "POINT"))
  expect_equal(x$source_id, c("a", "b", "c", "d", "e", "f"))
  expect_equal(x$date[1:3], as.Date(c("2024-01-01", "2024-02-01", "2025-01-01")))
  expect_true(is.na(x$date[6]))
  expect_equal(as.character(x$severity), c("serious", "fatal", "none", "minor", "unknown", "none"))
  expect_equal(x$injured_mode, c("bicycle", "bicycle", "pedestrian", "unknown", "unknown", "unknown"))
  expect_equal(x$location_type, c("intersection", "mid_block", "intersection", "unknown", "mid_block", "unknown"))
  expect_equal(x$bicycle, c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE))
  expect_equal(x$n_fatal, c(0L, 1L, 0L, 0L, 0L, 0L))
  expect_equal(attr(x, "cl_source"), "crashtown")
  expect_equal(attr(x, "cl_attribution"), "test")

  bikes <- cl_fetch_crashes("crashtown")
  expect_equal(nrow(bikes), 5L)
  y24 <- cl_fetch_crashes("crashtown", years = 2024)
  expect_equal(y24$source_id, c("a", "b", "d", "e"))
  box <- cl_fetch_crashes("crashtown", bbox = c(-105.005, 39.74, -104.985, 39.76))
  expect_equal(box$source_id, c("a", "b"))
  s <- cl_summary(bikes, by = "severity")
  expect_true(all(c("n", "share") %in% names(s)))
  expect_equal(sum(s$n), 5L)
})

test_that("cl_fetch_crashes validates", {
  expect_error(cl_fetch_crashes("atlantis"), "No crash source")
  expect_error(cl_fetch_crashes("denver", years = 12), "calendar years")
  expect_error(cl_register_crash_source("x", "u", fields = list()), "date")
})

test_that("the Denver crash source is defined against the police layer", {
  src <- cyclelanes:::.get_crash_source("denver")
  expect_match(src$url, "ODC_CRIME_TRAFFICACCIDENTS5YR_P/FeatureServer/325", fixed = TRUE)
  expect_equal(src$fields$date, "first_occurrence_date")
  expect_equal(src$bike_where, "bicycle_ind = 1")
  expect_true(all(c("FATALITIES", "SERIOUSLY_INJURED") %in% unlist(src$fields)))
})

test_that("crash dates parse from milliseconds, seconds, strings and Dates", {
  p <- cyclelanes:::.parse_crash_date
  expect_equal(p(1704067200000), as.Date("2024-01-01"))
  expect_equal(p(1704067200), as.Date("2024-01-01"))
  expect_equal(p("2024-01-01T05:00:00Z"), as.Date("2024-01-01"))
  expect_equal(p(as.Date("2024-01-01")), as.Date("2024-01-01"))
  expect_true(is.na(p("not a date")))
})
