# cl_check_source() against a fake ArcGIS layer and a local file.

fake_distinct <- function(values, counts = NULL, distinct_ok = TRUE) {
  calls <- character()
  get <- function(url) {
    calls <<- c(calls, url)
    tmp <- tempfile(fileext = ".json")
    if (grepl("returnDistinctValues=true", url)) {
      feats <- if (distinct_ok) lapply(values, function(v) list(attributes = list(CLS = v))) else list()
      writeLines(jsonlite::toJSON(list(features = feats), auto_unbox = TRUE), tmp)
    } else if (grepl("returnCountOnly=true", url)) {
      w <- utils::URLdecode(sub("^.*where=([^&]*).*$", "\\1", url))
      v <- sub("^CLS = '(.*)'$", "\\1", w)
      v <- gsub("''", "'", v)
      n <- if (is.null(counts)) 1L else counts[[v]]
      writeLines(sprintf('{"count":%d}', n), tmp)
    } else {
      # sample fallback
      feats <- lapply(values, function(v) list(attributes = list(CLS = v)))
      writeLines(jsonlite::toJSON(list(features = c(feats, feats)), auto_unbox = TRUE), tmp)
    }
    tmp
  }
  list(get = get, calls = function() calls)
}

register_fake <- function() {
  cl_register_source("faketown", url = "https://example.org/arcgis/rest/services/X/FeatureServer/0",
                     type = "arcgis", class_field = "CLS",
                     crosswalk = c("Bike Lane" = "painted_lane", "Trail" = "separated_path",
                                   "Old Class" = "shared_lane"))
}

test_that("mapped, unmapped and stale classes are reported with counts", {
  withr::defer(rm(list = ls(cyclelanes:::.cl_registry), envir = cyclelanes:::.cl_registry))
  register_fake()
  fk <- fake_distinct(c("Bike Lane", "Trail", "Protected Bike Lane"),
                      counts = list("Bike Lane" = 40L, "Trail" = 10L, "Protected Bike Lane" = 5L))
  testthat::local_mocked_bindings(.arcgis_get = fk$get, .package = "cyclelanes")

  x <- cl_check_source("faketown")
  expect_s3_class(x, "cl_source_check")
  expect_false(attr(x, "ok"))
  expect_equal(attr(x, "city"), "faketown")
  expect_equal(x$value[x$status == "unmapped"], "Protected Bike Lane")
  expect_equal(x$value[x$status == "stale"], "Old Class")
  expect_equal(x$target[x$value == "Trail"], "separated_path")
  expect_equal(x$n[x$value == "Bike Lane"], 40L)
  expect_equal(x$n[x$value == "Old Class"], 0L)
  # unmapped rows come first
  expect_equal(x$status[1], "unmapped")
  expect_output(print(x), "1 unmapped class value")
  expect_output(print(x), "no longer occur")
})

test_that("a fully covered source is ok", {
  withr::defer(rm(list = ls(cyclelanes:::.cl_registry), envir = cyclelanes:::.cl_registry))
  register_fake()
  fk <- fake_distinct(c("Bike Lane", "Trail", "Old Class"))
  testthat::local_mocked_bindings(.arcgis_get = fk$get, .package = "cyclelanes")
  x <- cl_check_source("faketown")
  expect_true(attr(x, "ok"))
  expect_true(all(x$status == "mapped"))
  expect_output(print(x), "covers every live class")
})

test_that("a server that ignores returnDistinctValues is tabulated from a sample", {
  withr::defer(rm(list = ls(cyclelanes:::.cl_registry), envir = cyclelanes:::.cl_registry))
  register_fake()
  fk <- fake_distinct(c("Bike Lane", "New Thing"), distinct_ok = FALSE)
  testthat::local_mocked_bindings(.arcgis_get = fk$get, .package = "cyclelanes")
  x <- cl_check_source("faketown")
  expect_equal(x$value[x$status == "unmapped"], "New Thing")
  expect_equal(x$n[x$value == "Bike Lane"], 2L)
  expect_true(any(grepl("resultRecordCount", fk$calls())))
})

test_that("a file source is checked the same way", {
  withr::defer(rm(list = ls(cyclelanes:::.cl_registry), envir = cyclelanes:::.cl_registry))
  raw <- sf::st_sf(
    CLS = c("Lane", "Lane", "Mystery", NA, " "),
    geometry = sf::st_sfc(lapply(1:5, function(i) {
      sf::st_linestring(rbind(c(-105, 39.7 + i * 0.01), c(-104.999, 39.7 + i * 0.01)))
    }), crs = 4326)
  )
  path <- withr::local_tempfile(fileext = ".geojson")
  sf::st_write(raw, path, quiet = TRUE)
  cl_register_source("filetown", url = path, type = "file", class_field = "CLS",
                     crosswalk = c(Lane = "painted_lane", Gone = "shoulder"))
  x <- cl_check_source("filetown")
  expect_equal(x$value[x$status == "unmapped"], "Mystery")
  expect_equal(x$value[x$status == "stale"], "Gone")
  expect_equal(x$n[x$value == "Lane"], 2L)
  expect_false(attr(x, "ok"))
})

test_that("the unmapped warning from cl_fetch_official reports segments and km", {
  withr::defer(rm(list = ls(cyclelanes:::.cl_registry), envir = cyclelanes:::.cl_registry))
  raw <- sf::st_sf(
    CLS = c("Lane", "Mystery", "Mystery"),
    geometry = sf::st_sfc(lapply(1:3, function(i) {
      sf::st_linestring(rbind(c(-105, 39.7 + i * 0.01), c(-104.999, 39.7 + i * 0.01)))
    }), crs = 4326)
  )
  path <- withr::local_tempfile(fileext = ".geojson")
  sf::st_write(raw, path, quiet = TRUE)
  cl_register_source("filetown", url = path, type = "file", class_field = "CLS",
                     crosswalk = c(Lane = "painted_lane"))
  expect_warning(cl_fetch_official("filetown"), "2 segments, 0.2 km")
  expect_warning(cl_fetch_official("filetown"), "cl_check_source")
})

test_that("unknown cities and bad types error", {
  expect_error(cl_check_source("atlantis"), "No official source")
})
