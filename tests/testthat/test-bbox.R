test_that("cl_bbox accepts numeric, matrix, sf and bbox inputs", {
  ref <- c(xmin = -105.02, ymin = 39.73, xmax = -104.97, ymax = 39.76)
  expect_equal(cl_bbox(c(-105.02, 39.73, -104.97, 39.76)), ref)

  m <- matrix(c(-105.02, 39.73, -104.97, 39.76), nrow = 2,
              dimnames = list(c("x", "y"), c("min", "max")))
  expect_equal(cl_bbox(m), ref)

  pts <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_point(c(-105.02, 39.73)), sf::st_point(c(-104.97, 39.76)), crs = 4326))
  expect_equal(cl_bbox(pts), ref)
  expect_equal(cl_bbox(sf::st_bbox(pts)), ref)

  # projected input is transformed back to WGS84
  utm <- sf::st_transform(pts, 32613)
  expect_equal(cl_bbox(utm), ref, tolerance = 1e-6)
})

test_that("cl_bbox rejects malformed boxes", {
  expect_error(cl_bbox(c(-104.97, 39.73, -105.02, 39.76)), "xmin < xmax")
  expect_error(cl_bbox(c(-105, 39, -104, NA)), "finite")
  expect_error(cl_bbox(c(-200, 39, -104, 40)), "WGS84")
  expect_error(cl_bbox(1:3), "place")
  expect_error(cl_bbox(list()), "place")
})
