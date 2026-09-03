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
