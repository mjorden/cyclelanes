# Overpass fetching with the network call, the sleep, and the boundary
# lookup mocked out.

osm_result <- function(ids = "1", y = 39.71) {
  lines <- sf::st_sf(
    osm_id = as.character(ids),
    highway = rep("residential", length(ids)),
    cycleway = rep("lane", length(ids)),
    geometry = sf::st_sfc(lapply(seq_along(ids), function(i) {
      sf::st_linestring(rbind(c(-105 + i * 0.001, y), c(-105 + i * 0.001 + 0.0005, y)))
    }), crs = 4326)
  )
  list(osm_lines = lines)
}

http_error <- function(code) {
  structure(class = c(paste0("httr2_http_", code), "httr2_http", "httr2_error",
                      "rlang_error", "error", "condition"),
            list(message = sprintf("HTTP %d Too Many Requests.", code), call = NULL))
}

# A mock Overpass: `responses` is a list of either functions returning a
# result, or conditions to signal. Records the option in force at call time.
mock_overpass <- function(responses) {
  n <- 0L
  urls <- character()
  sleeps <- numeric()
  query <- function(q) {
    n <<- n + 1L
    urls <<- c(urls, getOption("osmdata.base_url", ""))
    r <- responses[[min(n, length(responses))]]
    if (inherits(r, "condition")) stop(r)
    if (is.function(r)) r(q) else r
  }
  list(
    query = query,
    sleep = function(s) sleeps <<- c(sleeps, s),
    calls = function() n,
    urls = function() urls,
    sleeps = function() sleeps
  )
}

with_mock_overpass <- function(m, code) {
  testthat::local_mocked_bindings(
    .overpass_query = m$query,
    .backoff_sleep = m$sleep,
    .package = "cyclelanes"
  )
  force(code)
}

box <- c(-105.01, 39.70, -104.99, 39.72)

test_that("a plain fetch calls Overpass once and returns the lines", {
  m <- mock_overpass(list(osm_result("1")))
  out <- with_mock_overpass(m, cl_fetch_osm(box))
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 1L)
  expect_equal(m$calls(), 1L)
  expect_equal(attr(out, "cl_bbox"), cl_bbox(box))
})

test_that("transient errors are retried with growing waits, then succeed", {
  m <- mock_overpass(list(http_error(429), http_error(504), osm_result("1")))
  expect_message(
    out <- with_mock_overpass(m, cl_fetch_osm(box, retries = 3)),
    "retry 1 of 3"
  )
  expect_equal(nrow(out), 1L)
  expect_equal(m$calls(), 3L)
  s <- m$sleeps()
  expect_length(s, 2L)
  expect_gt(s[2], s[1])
  expect_true(all(s >= 24 & s <= 300))
})

test_that("a non-transient error is not retried", {
  m <- mock_overpass(list(simpleError("boom")))
  expect_error(with_mock_overpass(m, cl_fetch_osm(box, retries = 3)), "boom")
  expect_equal(m$calls(), 1L)
  expect_length(m$sleeps(), 0L)
})

test_that("exhausting the retries gives a plain-language error", {
  m <- mock_overpass(list(http_error(504)))
  expect_error(
    suppressMessages(with_mock_overpass(m, cl_fetch_osm(box, retries = 2))),
    "after 3 attempts"
  )
  expect_equal(m$calls(), 3L)
  expect_length(m$sleeps(), 2L)
})

test_that("overpass_url applies for the call only and must be an interpreter", {
  old <- getOption("osmdata.base_url")
  m <- mock_overpass(list(osm_result("1")))
  with_mock_overpass(m, cl_fetch_osm(box, overpass_url = "https://mirror.example/api/interpreter"))
  expect_equal(m$urls(), "https://mirror.example/api/interpreter")
  expect_identical(getOption("osmdata.base_url"), old)
  expect_error(cl_fetch_osm(box, overpass_url = "https://mirror.example/api/status"), "interpreter")
})

test_that("tiling splits the box, queries each tile, and de-duplicates by osm_id", {
  tiles <- cyclelanes:::.tile_bbox(c(xmin = 0, ymin = 0, xmax = 1, ymax = 0.5), tile = 0.4)
  expect_length(tiles, 3L * 2L)
  expect_true(all(vapply(tiles, function(b) b[["xmax"]] - b[["xmin"]] <= 0.4 + 1e-9, logical(1))))
  expect_equal(cyclelanes:::.tile_bbox(c(xmin = 0, ymin = 0, xmax = 1, ymax = 1), NULL)[[1]],
               c(xmin = 0, ymin = 0, xmax = 1, ymax = 1))

  # every tile returns ways 1 and 2; way 3 only from the first tile
  m <- mock_overpass(list(osm_result(c("1", "2", "3")), osm_result(c("1", "2"))))
  out <- with_mock_overpass(m, cl_fetch_osm(c(-105.05, 39.70, -104.95, 39.72), tile = 0.06))
  expect_equal(m$calls(), 2L)
  expect_equal(sort(out$osm_id), c("1", "2", "3"))
  expect_error(cl_fetch_osm(box, tile = -1), "tile")
})

test_that("an empty Overpass answer warns and returns a zero-row sf", {
  m <- mock_overpass(list(list(osm_lines = NULL)))
  expect_warning(out <- with_mock_overpass(m, cl_fetch_osm(box)), "no bicycle-tagged ways")
  expect_equal(nrow(out), 0L)
  expect_s3_class(out, "sf")
})

test_that("the cache is written on a miss and read on a hit", {
  dir <- withr::local_tempdir()
  m <- mock_overpass(list(osm_result("1")))
  out1 <- with_mock_overpass(m, cl_fetch_osm(box, cache = TRUE, cache_dir = dir))
  expect_equal(m$calls(), 1L)
  expect_length(list.files(dir, pattern = "^overpass-.*rds$"), 1L)

  expect_message(
    out2 <- with_mock_overpass(m, cl_fetch_osm(box, cache = TRUE, cache_dir = dir)),
    "cached Overpass result"
  )
  expect_equal(m$calls(), 1L)
  expect_equal(out2$osm_id, out1$osm_id)
  expect_equal(attr(out2, "cl_fetched"), attr(out1, "cl_fetched"))

  # a stale entry is refetched; a different box is a different key
  with_mock_overpass(m, cl_fetch_osm(box, cache = TRUE, cache_dir = dir, cache_max_age = 0))
  expect_equal(m$calls(), 2L)
  with_mock_overpass(m, cl_fetch_osm(box + c(0, 0, 0.01, 0.01), cache = TRUE, cache_dir = dir))
  expect_equal(m$calls(), 3L)
  expect_length(list.files(dir, pattern = "^overpass-.*rds$"), 2L)

  expect_equal(cl_cache_clear(dir), 2L)
  expect_length(list.files(dir, pattern = "^overpass-.*rds$"), 0L)
})

test_that("cl_cache_dir honours the environment variable", {
  withr::local_envvar(CYCLELANES_CACHE_DIR = "C:/somewhere/else")
  expect_equal(cl_cache_dir(), "C:/somewhere/else")
  withr::local_envvar(CYCLELANES_CACHE_DIR = "")
  expect_match(cl_cache_dir(), "cyclelanes")
})

test_that("cl_bike_lanes passes fetch options through", {
  m <- mock_overpass(list(http_error(429), osm_result("1")))
  out <- suppressMessages(with_mock_overpass(
    m, cl_bike_lanes(box, retries = 2, overpass_url = "https://m.example/api/interpreter")))
  expect_equal(nrow(out), 1L)
  expect_equal(as.character(out$facility_type), "painted_lane")
  expect_equal(m$calls(), 2L)
  expect_equal(unique(m$urls()), "https://m.example/api/interpreter")
})
