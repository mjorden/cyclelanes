# cl_fetch_fars() with the download mocked.

fake_fars <- function(year, cache_dir) {
  acc <- data.frame(
    ST_CASE = c(80001, 80002, 80003, 80004, 80005),
    STATE = 8, YEAR = year, MONTH = c(3, 7, 12, 1, 99), DAY = c(14, 4, 25, 99, 1),
    LATITUDE = c(39.74, 39.75, 77.7777, 39.76, 45.5),
    LONGITUD = c(-104.99, -104.98, -104.97, -104.96, -122.6),
    FATALS = c(1, 2, 1, 1, 1),
    LGT_CONDNAME = c("Daylight", "Dark - Lighted", "Daylight", "Dawn", "Daylight"),
    RELJCT2NAME = c("Intersection", "Non-Junction", "Intersection", "Intersection-Related", "Non-Junction")
  )
  per <- data.frame(
    ST_CASE = c(80001, 80001, 80002, 80002, 80003, 80004, 80005),
    PER_TYP = c(6, 1, 5, 1, 6, 1, 6),
    INJ_SEV = c(4, 0, 4, 0, 4, 4, 4)
  )
  list(accident = acc, person = per)
}

denver_box <- c(-105.1, 39.6, -104.6, 39.9)

test_that("FARS accidents become standard crash points with cyclist involvement", {
  testthat::local_mocked_bindings(.fars_download = fake_fars, .package = "cyclelanes")
  withr::local_envvar(CYCLELANES_CACHE_DIR = withr::local_tempdir())
  x <- cl_fetch_fars(2022, bbox = denver_box, bike_only = FALSE)
  expect_s3_class(x, "sf")
  # the sentinel-coordinate crash and the Portland one are gone
  expect_equal(x$source_id, c("2022-80001", "2022-80002", "2022-80004"))
  expect_equal(as.character(x$severity), rep("fatal", 3))
  expect_equal(x$bicycle, c(TRUE, FALSE, FALSE))
  expect_equal(x$pedestrian, c(FALSE, TRUE, FALSE))
  expect_equal(x$injured_mode, c("bicycle", "pedestrian", "motor_vehicle"))
  expect_equal(x$location_type, c("intersection", "mid_block", "intersection"))
  expect_equal(x$n_fatal, c(1L, 2L, 1L))
  expect_true(all(is.na(x$n_serious)))
  expect_equal(x$date[1:2], as.Date(c("2022-03-14", "2022-07-04")))
  expect_true(is.na(x$date[3]))   # day 99 = unknown
  expect_equal(x$light[2], "Dark - Lighted")
  expect_equal(attr(x, "cl_source"), "fars")

  bikes <- cl_fetch_fars(2022, bbox = denver_box)
  expect_equal(bikes$source_id, "2022-80001")

  two <- cl_fetch_fars(2021:2022, bbox = denver_box, bike_only = FALSE)
  expect_equal(nrow(two), 6L)
  expect_setequal(unique(two$year), 2021:2022)
})

test_that("cl_fetch_fars validates years and clips to a polygon", {
  expect_error(cl_fetch_fars(1999, bbox = denver_box), "2001")
  testthat::local_mocked_bindings(.fars_download = fake_fars, .package = "cyclelanes")
  withr::local_envvar(CYCLELANES_CACHE_DIR = withr::local_tempdir())
  sq <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(rbind(
    c(-105.0, 39.735), c(-104.985, 39.735), c(-104.985, 39.745), c(-105.0, 39.745), c(-105.0, 39.735)
  ))), crs = 4326))
  x <- cl_fetch_fars(2022, bbox = sq, bike_only = FALSE)
  expect_equal(x$source_id, "2022-80001")
})

test_that("cl_fetch_crashes falls through to FARS for an unregistered place", {
  testthat::local_mocked_bindings(.fars_download = fake_fars, .package = "cyclelanes")
  withr::local_envvar(CYCLELANES_CACHE_DIR = withr::local_tempdir())
  expect_error(cl_fetch_crashes("Nowhere, Colorado"), "Pass `years`")
  expect_message(
    x <- cl_fetch_crashes("Nowhere, Colorado", years = 2022, bbox = denver_box, bike_only = FALSE),
    "FARS"
  )
  expect_equal(nrow(x), 3L)
  expect_equal(attr(x, "cl_source"), "fars")
})

test_that("the FARS URL follows NHTSA's layout", {
  expect_equal(cyclelanes:::.fars_url(2022),
               "https://static.nhtsa.gov/nhtsa/downloads/FARS/2022/National/FARS2022NationalCSV.zip")
})
