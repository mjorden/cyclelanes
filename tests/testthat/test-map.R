skip_if_not_installed("leaflet")

test_that("cl_map builds a leaflet widget with escaped popups and an OSM link", {
  lanes <- cl_classify(denver_lodo$osm, drop_none = TRUE)
  lanes$name[1] <- "<script>alert(1)</script> Street"
  m <- cl_map(lanes)
  expect_s3_class(m, "leaflet")
  html <- paste(unlist(lapply(m$x$calls, function(cl) unlist(cl$args))), collapse = "\n")
  expect_false(grepl("<script>alert(1)</script>", html, fixed = TRUE))
  expect_true(grepl("&lt;script&gt;", html, fixed = TRUE))
  expect_true(grepl("openstreetmap.org/way/", html, fixed = TRUE))
})

test_that("cl_map colours by lts and maps a comparison with gap groups", {
  lanes <- cl_lts(cl_classify(denver_lodo$osm, drop_none = TRUE))
  m <- cl_map(lanes, colour = "lts")
  expect_s3_class(m, "leaflet")
  expect_error(cl_map(cl_classify(denver_lodo$osm), colour = "lts"), "cl_lts")

  cmp <- cl_compare(cl_classify(denver_lodo$osm, drop_none = TRUE), denver_lodo$official)
  m2 <- cl_map(cmp)
  expect_s3_class(m2, "leaflet")
  groups <- unlist(lapply(m2$x$calls, function(cl) if (cl$method == "addLayersControl") cl$args[[2]]))
  expect_true(all(c("OpenStreetMap", "Official") %in% groups))
  html <- paste(unlist(lapply(m2$x$calls, function(cl) unlist(cl$args))), collapse = "\n")
  expect_true(grepl("City class:", html, fixed = TRUE))
  expect_true(grepl("Matched:", html, fixed = TRUE))
})

test_that("cl_map rejects non-sf input", {
  expect_error(cl_map(data.frame()), "must be an sf")
})
