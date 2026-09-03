# A fake ArcGIS layer served through a mocked .arcgis_get(). `n` features,
# `cap` = maxRecordCount, `flag` = whether the server emits
# exceededTransferLimit, `paging` = advertised supportsPagination.
fake_arcgis <- function(n = 7, cap = 3, flag = TRUE, paging = TRUE, error = NULL) {
  calls <- character()
  feature <- function(i) {
    list(type = "Feature",
         properties = list(id = i, CLS = if (i %% 2 == 0) "Lane" else "Protected"),
         geometry = list(type = "LineString",
                         coordinates = list(c(-105 + i * 0.001, 39.7),
                                            c(-105 + i * 0.001 + 0.0005, 39.7))))
  }
  get <- function(url) {
    calls <<- c(calls, url)
    tmp <- tempfile(fileext = ".json")
    if (!is.null(error)) {
      writeLines(sprintf('{"error":{"code":%d,"message":"%s"}}', error$code, error$message), tmp)
      return(tmp)
    }
    if (grepl("[?]f=json$", url)) {
      writeLines(jsonlite::toJSON(list(
        name = "FAKE_L", maxRecordCount = cap,
        advancedQueryCapabilities = list(supportsPagination = paging),
        supportedQueryFormats = "JSON, geoJSON"
      ), auto_unbox = TRUE), tmp)
      return(tmp)
    }
    q <- sub("^.*[?]", "", url)
    kv <- strsplit(strsplit(q, "&", fixed = TRUE)[[1]], "=", fixed = TRUE)
    p <- stats::setNames(vapply(kv, `[`, "", 2), vapply(kv, `[`, "", 1))
    offset <- as.integer(p[["resultOffset"]])
    size <- as.integer(p[["resultRecordCount"]])
    idx <- seq_len(n)
    idx <- idx[idx > offset & idx <= offset + size]
    fc <- list(type = "FeatureCollection",
               crs = list(type = "name", properties = list(name = "EPSG:4326")))
    if (flag && length(idx) && max(idx) < n) fc$properties <- list(exceededTransferLimit = TRUE)
    fc$features <- lapply(idx, feature)
    writeLines(jsonlite::toJSON(fc, auto_unbox = TRUE), tmp)
    tmp
  }
  list(get = get, calls = function() calls)
}

read_fake <- function(fake, ...) {
  testthat::local_mocked_bindings(.arcgis_get = fake$get, .package = "cyclelanes")
  cyclelanes:::.arcgis_read("https://example.org/arcgis/rest/services/X/FeatureServer/0", ...)
}

test_that("all features are read when the server caps below page_size", {
  fake <- fake_arcgis(n = 7, cap = 3)
  out <- read_fake(fake, page_size = 2000)
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 7L)
  expect_equal(sort(out$id), 1:7)
  q <- grep("/query[?]", fake$calls(), value = TRUE)
  expect_length(q, 3L)
  expect_true(all(grepl("resultRecordCount=3", q)))
})

test_that("paging continues on a full page even without exceededTransferLimit", {
  fake <- fake_arcgis(n = 6, cap = 3, flag = FALSE)
  out <- read_fake(fake)
  expect_equal(nrow(out), 6L)
  # the final, empty page is what stops it
  expect_length(grep("/query[?]", fake$calls(), value = TRUE), 3L)
})

test_that("a single short page stops immediately", {
  fake <- fake_arcgis(n = 2, cap = 1000)
  out <- read_fake(fake)
  expect_equal(nrow(out), 2L)
  expect_length(grep("/query[?]", fake$calls(), value = TRUE), 1L)
})

test_that("a server that cannot page errors instead of truncating", {
  fake <- fake_arcgis(n = 7, cap = 3, paging = FALSE)
  expect_error(read_fake(fake), "does not support paging")
})

test_that("an ArcGIS error object is surfaced", {
  fake <- fake_arcgis(error = list(code = 499, message = "Token Required"))
  expect_error(read_fake(fake), "Token Required")
})

test_that("an empty result is a zero-row sf", {
  fake <- fake_arcgis(n = 0)
  out <- read_fake(fake)
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 0L)
})

test_that("where and bbox reach the query string", {
  fake <- fake_arcgis(n = 1)
  read_fake(fake, where = "CLS = 'Lane'", bbox = c(-105.1, 39.6, -104.9, 39.8))
  q <- grep("/query[?]", fake$calls(), value = TRUE)[1]
  expect_match(q, "where=CLS%20%3D%20%27Lane%27", fixed = TRUE)
  expect_match(q, "geometry=-105.1%2C39.6%2C-104.9%2C39.8", fixed = TRUE)
  expect_match(q, "geometryType=esriGeometryEnvelope", fixed = TRUE)
})

test_that("a page_size larger than the cap is reduced, smaller is kept", {
  fake <- fake_arcgis(n = 5, cap = 1000)
  read_fake(fake, page_size = 2)
  q <- grep("/query[?]", fake$calls(), value = TRUE)
  expect_true(all(grepl("resultRecordCount=2", q)))
  expect_length(q, 3L)
})

# --- servers without GeoJSON, native-CRS answers, MapServer paths ------------

fake_esri <- function(n = 3, formats = "JSON", answer_wkid = 4326, geojson_crs = NULL) {
  calls <- character()
  get <- function(url) {
    calls <<- c(calls, url)
    tmp <- tempfile(fileext = ".json")
    if (grepl("[?]f=json$", url)) {
      writeLines(jsonlite::toJSON(list(
        name = "OLD_L", maxRecordCount = 1000, geometryType = "esriGeometryPolyline",
        advancedQueryCapabilities = list(supportsPagination = TRUE),
        supportedQueryFormats = formats,
        extent = list(xmin = 3125000, ymin = 1690000, xmax = 3130000, ymax = 1700000,
                      spatialReference = list(wkid = 2877, latestWkid = 2877)),
        fields = list(list(name = "id", type = "esriFieldTypeInteger", alias = "id"))
      ), auto_unbox = TRUE), tmp)
      return(tmp)
    }
    q <- strsplit(sub("^.*[?]", "", url), "&", fixed = TRUE)[[1]]
    kv <- strsplit(q, "=", fixed = TRUE)
    p <- stats::setNames(vapply(kv, `[`, "", 2), vapply(kv, `[`, "", 1))
    offset <- as.integer(p[["resultOffset"]])
    idx <- seq_len(n); idx <- idx[idx > offset]
    if (grepl("f=json", url)) {
      # Esri JSON feature set, coordinates in the answer's CRS
      feats <- lapply(idx, function(i) list(
        attributes = list(code = paste0("w", i)),
        geometry = list(paths = list(list(c(-105 + i * 0.001, 39.7), c(-105 + i * 0.001 + 0.0005, 39.7))))
      ))
      fs <- list(geometryType = "esriGeometryPolyline",
                 spatialReference = list(wkid = answer_wkid),
                 fields = list(list(name = "code", type = "esriFieldTypeString", alias = "code")),
                 features = feats)
      writeLines(jsonlite::toJSON(fs, auto_unbox = TRUE, digits = NA), tmp)
    } else {
      # GeoJSON in Colorado Central ftUS (EPSG:2877) despite outSR=4326
      feats <- lapply(idx, function(i) list(
        type = "Feature", properties = list(id = i),
        geometry = list(type = "LineString",
                        coordinates = list(c(3127000 + i * 100, 1695000), c(3127000 + i * 100 + 50, 1695000)))
      ))
      fc <- list(type = "FeatureCollection", features = feats)
      if (!is.null(geojson_crs)) fc$crs <- list(type = "name", properties = list(name = geojson_crs))
      writeLines(jsonlite::toJSON(fc, auto_unbox = TRUE, digits = NA), tmp)
    }
    tmp
  }
  list(get = get, calls = function() calls)
}

test_that("a server without GeoJSON output is read as Esri JSON", {
  fk <- fake_esri(n = 3, formats = "JSON, AMF")
  testthat::local_mocked_bindings(.arcgis_get = fk$get, .package = "cyclelanes")
  out <- cyclelanes:::.arcgis_read("https://old.example/arcgis/rest/services/X/MapServer/2")
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 3L)
  expect_equal(sort(out$code), c("w1", "w2", "w3"))
  q <- grep("/query[?]", fk$calls(), value = TRUE)
  expect_true(all(grepl("f=json", q)))
  expect_false(any(grepl("f=geojson", q)))
  expect_true(isTRUE(sf::st_crs(out) == sf::st_crs(4326)))
})

test_that("an answer in the layer's native CRS is transformed to WGS84", {
  fk <- fake_esri(n = 2, formats = "JSON, geoJSON", geojson_crs = "EPSG:2877")
  testthat::local_mocked_bindings(.arcgis_get = fk$get, .package = "cyclelanes")
  out <- cyclelanes:::.arcgis_read("https://h/arcgis/rest/services/X/FeatureServer/0")
  expect_true(isTRUE(sf::st_crs(out) == sf::st_crs(4326)))
  bb <- sf::st_bbox(out)
  expect_gt(bb[["xmin"]], -105.2); expect_lt(bb[["xmax"]], -104.6)
  expect_gt(bb[["ymin"]], 39.5); expect_lt(bb[["ymax"]], 40)
})

test_that("GeoJSON with no CRS member is assumed to be the layer's CRS when outSR was ignored", {
  # coordinates are clearly state-plane feet, no crs member: assume wkid 2877 from metadata
  fk <- fake_esri(n = 2, formats = "JSON, geoJSON", geojson_crs = NULL)
  testthat::local_mocked_bindings(.arcgis_get = fk$get, .package = "cyclelanes")
  out <- cyclelanes:::.arcgis_read("https://h/arcgis/rest/services/X/FeatureServer/0")
  # GDAL labels CRS-less GeoJSON as WGS84; coordinates far outside lon/lat
  # range are relabelled with the layer's wkid and transformed
  expect_true(isTRUE(sf::st_crs(out) == sf::st_crs(4326)))
  bb <- sf::st_bbox(out)
  expect_gt(bb[["xmin"]], -105.2); expect_lt(bb[["xmax"]], -104.6)
  expect_gt(bb[["ymin"]], 39.5); expect_lt(bb[["ymax"]], 40)
})
