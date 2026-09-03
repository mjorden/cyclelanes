# The extract backend with osmextract mocked out.

extract_result <- function() {
  mk <- function(i, y) sf::st_linestring(rbind(c(-105 + i * 0.001, y), c(-105 + i * 0.001 + 0.0005, y)))
  sf::st_sf(
    osm_id = c(1, 2, 3, 4, 5, 6, 7),
    highway = c("cycleway", "residential", "primary", "footway", "residential", NA, "tertiary"),
    waterway = c(NA, NA, NA, NA, NA, "river", NA),
    cycleway = c(NA, "lane", NA, NA, NA, NA, NA),
    `cycleway:right` = c(NA, NA, "track", NA, NA, NA, NA),
    bicycle = c(NA, NA, NA, "designated", NA, "yes", NA),
    bicycle_road = c(NA, NA, NA, NA, "yes", NA, NA),
    name = c("Trail", "A St", "B Ave", "Park path", "C St", "Creek", "Plain road"),
    z_order = 0L,
    other_tags = NA_character_,
    geometry = sf::st_sfc(lapply(1:7, function(i) mk(i, 39.7 + i * 0.001)), crs = 4326),
    check.names = FALSE
  )
}

box <- c(-105.01, 39.70, -104.99, 39.72)

# `fn(url, poly, extract_dir)` stands in for download + read; the match is a
# fixed small extract unless `match` is given.
with_mock_extract <- function(fn, code, match = list(url = "https://download.geofabrik.de/north-america/us/district-of-columbia-latest.osm.pbf", file_size = 2e7)) {
  testthat::local_mocked_bindings(
    .extract_query = function(url, poly, extract_dir) fn(poly, extract_dir),
    .extract_match = function(geom) match,
    .package = "cyclelanes"
  )
  force(code)
}

test_that("the extract backend keeps bicycle-relevant ways and drops the rest", {
  withr::local_envvar(CYCLELANES_CACHE_DIR = withr::local_tempdir())
  seen <- list()
  fn <- function(poly, extract_dir) { seen$poly <<- poly; seen$dir <<- extract_dir; extract_result() }
  out <- suppressMessages(with_mock_extract(fn, cl_fetch_osm(box, backend = "extract", clip = FALSE)))
  expect_s3_class(out, "sf")
  # cycleway, lane, track, designated footway, bicycle road; not the plain
  # road, not the waterway (no highway)
  expect_equal(sort(out$osm_id), c("1", "2", "3", "4", "5"))
  expect_false(any(c("z_order", "other_tags") %in% names(out)))
  expect_equal(attr(out, "cl_backend"), "extract")
  expect_equal(attr(out, "cl_bbox"), cl_bbox(box))
  expect_s3_class(seen$poly, "sfc")
  expect_equal(as.numeric(sf::st_bbox(seen$poly)), unname(cl_bbox(box)))
  expect_equal(seen$dir, file.path(cl_cache_dir(), "extracts"))
  expect_true(dir.exists(seen$dir))

  lanes <- cl_classify(out, drop_none = TRUE)
  expect_setequal(as.character(lanes$facility_type),
                  c("separated_path", "painted_lane", "protected_lane", "shared_use_path", "neighborhood_bikeway"))
})

test_that("extract_dir is passed through and an empty extract warns", {
  dir <- withr::local_tempdir()
  fn <- function(poly, extract_dir) { expect_equal(extract_dir, dir); extract_result()[0, ] }
  expect_warning(out <- suppressMessages(with_mock_extract(fn, cl_fetch_osm(box, backend = "extract", extract_dir = dir))),
                 "no bicycle-tagged ways")
  expect_equal(nrow(out), 0L)
})

test_that("the boundary polygon, not the bbox, is what gets matched to an extract", {
  sq <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(rbind(
    c(-105.02, 39.69), c(-104.98, 39.69), c(-104.98, 39.73), c(-105.02, 39.73), c(-105.02, 39.69)
  ))), crs = 4326))
  matched <- NULL
  testthat::local_mocked_bindings(
    .extract_match = function(geom) { matched <<- geom; list(url = "https://x/y/small-latest.osm.pbf", file_size = 1e6) },
    .extract_query = function(url, poly, extract_dir) extract_result(),
    .package = "cyclelanes"
  )
  withr::local_envvar(CYCLELANES_CACHE_DIR = withr::local_tempdir())
  expect_message(out <- cl_fetch_osm(box, backend = "extract", clip = sq), "small-latest")
  expect_equal(as.numeric(sf::st_bbox(matched)), as.numeric(sf::st_bbox(sq)))
  # with no boundary the bbox polygon is matched
  suppressMessages(cl_fetch_osm(box, backend = "extract", clip = FALSE))
  expect_equal(as.numeric(sf::st_bbox(matched)), unname(cl_bbox(box)))
})

test_that("an oversized extract is refused with the size in the message", {
  withr::local_envvar(CYCLELANES_CACHE_DIR = withr::local_tempdir())
  fn <- function(poly, extract_dir) extract_result()
  expect_error(
    suppressMessages(with_mock_extract(fn, cl_fetch_osm(box, backend = "extract", clip = FALSE),
                                       match = list(url = "https://x/us-south-latest.osm.pbf", file_size = 3.2e9))),
    "3200 MB"
  )
  expect_no_error(
    suppressMessages(with_mock_extract(fn, cl_fetch_osm(box, backend = "extract", clip = FALSE, max_extract_mb = 5000),
                                       match = list(url = "https://x/us-south-latest.osm.pbf", file_size = 3.2e9)))
  )
})

test_that("the extract backend never calls Overpass and caches under its own key", {
  withr::local_envvar(CYCLELANES_CACHE_DIR = withr::local_tempdir())
  dir <- withr::local_tempdir()
  n_over <- 0L
  testthat::local_mocked_bindings(.overpass_query = function(q) { n_over <<- n_over + 1L; stop("should not be called") },
                                  .package = "cyclelanes")
  n_ext <- 0L
  fn <- function(poly, extract_dir) { n_ext <<- n_ext + 1L; extract_result() }
  out1 <- suppressMessages(with_mock_extract(fn, cl_fetch_osm(box, backend = "extract", cache = TRUE, cache_dir = dir)))
  expect_message(out2 <- with_mock_extract(fn, cl_fetch_osm(box, backend = "extract", cache = TRUE, cache_dir = dir)),
                 "cached extract result")
  expect_equal(n_ext, 1L)
  expect_equal(n_over, 0L)
  expect_equal(nrow(out1), nrow(out2))
  # the Overpass key for the same box is different, so no cross-talk
  expect_false(cyclelanes:::.overpass_cache_key(cl_bbox(box), NULL, "overpass") ==
                 cyclelanes:::.overpass_cache_key(cl_bbox(box), NULL, "extract"))
})

test_that("backend is validated and cl_bike_lanes passes it through", {
  withr::local_envvar(CYCLELANES_CACHE_DIR = withr::local_tempdir())
  expect_error(cl_fetch_osm(box, backend = "carrier pigeon"), "arg")
  fn <- function(poly, extract_dir) extract_result()
  lanes <- suppressMessages(with_mock_extract(fn, cl_bike_lanes(box, backend = "extract", clip = FALSE)))
  expect_gt(nrow(lanes), 0)
  expect_equal(attr(lanes, "cl_backend"), "extract")
})

test_that("underscored tag columns from GDAL are restored to their OSM names", {
  withr::local_envvar(CYCLELANES_CACHE_DIR = withr::local_tempdir())
  mk <- function(i) sf::st_linestring(rbind(c(-105 + i * 0.001, 39.71), c(-105 + i * 0.001 + 0.0005, 39.71)))
  raw <- sf::st_sf(
    osm_id = 1:3,
    highway = c("residential", "primary", "residential"),
    cycleway_right = c("lane", NA, NA),
    cycleway_left = c(NA, "track", NA),
    cycleway_both_buffer = c("yes", NA, NA),
    geometry = sf::st_sfc(lapply(1:3, mk), crs = 4326)
  )
  fn <- function(poly, extract_dir) raw
  out <- suppressMessages(with_mock_extract(fn, cl_fetch_osm(box, backend = "extract", clip = FALSE)))
  expect_true(all(c("cycleway:right", "cycleway:left", "cycleway:both:buffer") %in% names(out)))
  expect_false(any(c("cycleway_right", "cycleway_left") %in% names(out)))
  # the plain residential road with no bike tag is dropped; the two lanes survive
  expect_equal(sort(out$osm_id), c("1", "2"))
  lanes <- cl_classify(out)
  expect_equal(as.character(lanes$facility_type[lanes$osm_id == "1"]), "buffered_lane")
  expect_equal(as.character(lanes$facility_type[lanes$osm_id == "2"]), "protected_lane")
})
