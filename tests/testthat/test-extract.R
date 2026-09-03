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

with_mock_extract <- function(fn, code) {
  testthat::local_mocked_bindings(.extract_query = fn, .package = "cyclelanes")
  force(code)
}

test_that("the extract backend keeps bicycle-relevant ways and drops the rest", {
  seen <- list()
  fn <- function(poly, extract_dir) { seen$poly <<- poly; seen$dir <<- extract_dir; extract_result() }
  out <- with_mock_extract(fn, cl_fetch_osm(box, backend = "extract", clip = FALSE))
  expect_s3_class(out, "sf")
  # cycleway, lane, track, designated footway, bicycle road; not the plain
  # road, not the waterway (no highway)
  expect_equal(sort(out$osm_id), c("1", "2", "3", "4", "5"))
  expect_false(any(c("z_order", "other_tags") %in% names(out)))
  expect_equal(attr(out, "cl_backend"), "extract")
  expect_equal(attr(out, "cl_bbox"), cl_bbox(box))
  expect_s3_class(seen$poly, "sfc")
  expect_equal(as.numeric(sf::st_bbox(seen$poly)), unname(cl_bbox(box)))
  expect_null(seen$dir)

  lanes <- cl_classify(out, drop_none = TRUE)
  expect_setequal(as.character(lanes$facility_type),
                  c("separated_path", "painted_lane", "protected_lane", "shared_use_path", "neighborhood_bikeway"))
})

test_that("extract_dir is passed through and an empty extract warns", {
  fn <- function(poly, extract_dir) { expect_equal(extract_dir, "D:/osm"); extract_result()[0, ] }
  expect_warning(out <- with_mock_extract(fn, cl_fetch_osm(box, backend = "extract", extract_dir = "D:/osm")),
                 "no bicycle-tagged ways")
  expect_equal(nrow(out), 0L)
})

test_that("the extract backend never calls Overpass and caches under its own key", {
  dir <- withr::local_tempdir()
  n_over <- 0L
  testthat::local_mocked_bindings(.overpass_query = function(q) { n_over <<- n_over + 1L; stop("should not be called") },
                                  .package = "cyclelanes")
  n_ext <- 0L
  fn <- function(poly, extract_dir) { n_ext <<- n_ext + 1L; extract_result() }
  out1 <- with_mock_extract(fn, cl_fetch_osm(box, backend = "extract", cache = TRUE, cache_dir = dir))
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
  expect_error(cl_fetch_osm(box, backend = "carrier pigeon"), "arg")
  fn <- function(poly, extract_dir) extract_result()
  lanes <- with_mock_extract(fn, cl_bike_lanes(box, backend = "extract", clip = FALSE))
  expect_gt(nrow(lanes), 0)
  expect_equal(attr(lanes, "cl_backend"), "extract")
})
