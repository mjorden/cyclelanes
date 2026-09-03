# cl_inspect_source() against a fake ArcGIS layer (mocked .arcgis_get) and a
# local GeoJSON.

fake_layer <- function(n = 5, extent = c(3125000, 1690000, 3130000, 1700000), wkid = 2877) {
  calls <- character()
  get <- function(url) {
    calls <<- c(calls, url)
    tmp <- tempfile(fileext = ".json")
    if (grepl("[?]f=json$", url)) {
      writeLines(jsonlite::toJSON(list(
        name = "FAKE_BIKE_L", geometryType = "esriGeometryPolyline", maxRecordCount = 1000,
        advancedQueryCapabilities = list(supportsPagination = TRUE),
        supportedQueryFormats = "JSON, geoJSON",
        extent = list(xmin = extent[1], ymin = extent[2], xmax = extent[3], ymax = extent[4],
                      spatialReference = list(wkid = wkid, latestWkid = wkid)),
        fields = list(
          list(name = "OBJECTID", type = "esriFieldTypeOID", alias = "OBJECTID"),
          list(name = "FACILITY", type = "esriFieldTypeString", alias = "Facility Type"),
          list(name = "STREET", type = "esriFieldTypeString", alias = "Street"),
          list(name = "MILES", type = "esriFieldTypeDouble", alias = "Miles")
        )
      ), auto_unbox = TRUE), tmp)
    } else if (grepl("returnCountOnly=true", url)) {
      writeLines(sprintf('{"count":%d}', n), tmp)
    } else {
      feats <- lapply(seq_len(n), function(i) list(attributes = list(
        FACILITY = c("Bike Lane", "Protected Bike Lane", "Bike Lane", "Trail", "Bike Lane")[i],
        STREET = paste("Street", i)
      )))
      writeLines(jsonlite::toJSON(list(features = feats), auto_unbox = TRUE), tmp)
    }
    tmp
  }
  list(get = get, calls = function() calls)
}

test_that("an ArcGIS layer is inspected: fields, values, extent in WGS84", {
  fk <- fake_layer()
  testthat::local_mocked_bindings(.arcgis_get = fk$get, .package = "cyclelanes")
  x <- cl_inspect_source("https://example.org/arcgis/rest/services/X/FeatureServer/0")
  expect_s3_class(x, "cl_source_inspection")
  expect_equal(x$type, "arcgis")
  expect_equal(x$name, "FAKE_BIKE_L")
  expect_equal(x$n, 5L)
  expect_equal(x$geometry_type, "Polyline")
  expect_equal(x$crs, 2877L)
  expect_equal(x$max_record_count, 1000L)
  expect_equal(x$fields$name, c("OBJECTID", "FACILITY", "STREET", "MILES"))
  expect_equal(x$fields$type, c("OID", "String", "String", "Double"))
  expect_equal(x$values$FACILITY, c("Bike Lane" = 3L, "Protected Bike Lane" = 1L, "Trail" = 1L))
  # Colorado Central ftUS extent lands near Denver
  expect_gt(x$centre[["lat"]], 39); expect_lt(x$centre[["lat"]], 40.5)
  expect_gt(x$centre[["lon"]], -105.5); expect_lt(x$centre[["lon"]], -104)
  # only string fields were requested for tabulation
  q <- grep("returnGeometry=false", fk$calls(), value = TRUE)
  expect_match(q, "outFields=FACILITY%2CSTREET", fixed = TRUE)
  expect_output(print(x), "check this is the city you expect")
  expect_output(print(x), "Protected Bike Lane")
})

test_that("long string fields report a distinct count instead of a table", {
  fk <- fake_layer(n = 5)
  testthat::local_mocked_bindings(.arcgis_get = fk$get, .package = "cyclelanes")
  x <- cl_inspect_source("https://example.org/arcgis/rest/services/X/FeatureServer/0", max_values = 2)
  expect_s3_class(x$values$STREET, "cl_distinct_count")
  expect_equal(as.integer(x$values$STREET), 5L)
  expect_s3_class(x$values$FACILITY, "cl_distinct_count")
  expect_output(print(x), "5 distinct values")
})

test_that("type is guessed from the URL and can be forced", {
  fk <- fake_layer()
  testthat::local_mocked_bindings(.arcgis_get = fk$get, .package = "cyclelanes")
  expect_equal(cl_inspect_source("https://h/arcgis/rest/services/X/MapServer/3")$type, "arcgis")
  expect_equal(cl_inspect_source("https://h/arcgis/rest/services/X/MapServer/3/", type = "arcgis")$type, "arcgis")
  expect_error(cl_inspect_source(c("a", "b")), "single string")
})

test_that("a local file is inspected the same way", {
  raw <- sf::st_sf(
    CLS = c("Lane", "Lane", "Track", NA),
    NOTE = c("a", "b", "c", "d"),
    N = 1:4,
    geometry = sf::st_sfc(
      sf::st_linestring(rbind(c(-105.00, 39.71), c(-104.999, 39.71))),
      sf::st_linestring(rbind(c(-105.00, 39.72), c(-104.999, 39.72))),
      sf::st_linestring(rbind(c(-105.00, 39.73), c(-104.999, 39.73))),
      sf::st_linestring(rbind(c(-105.00, 39.74), c(-104.999, 39.74))),
      crs = 4326
    )
  )
  path <- withr::local_tempfile(fileext = ".geojson")
  sf::st_write(raw, path, quiet = TRUE)
  x <- cl_inspect_source(path)
  expect_equal(x$type, "file")
  expect_equal(x$n, 4L)
  expect_equal(x$crs, 4326L)
  expect_true(all(c("CLS", "NOTE", "N") %in% x$fields$name))
  expect_equal(x$values$CLS[c("Lane", "Track")], c(Lane = 2L, Track = 1L))
  expect_true("<NA>" %in% names(x$values$CLS))
  expect_false("N" %in% names(x$values))
  expect_equal(round(x$centre[["lat"]], 3), 39.725)
  expect_output(print(x), "CLS")
})
