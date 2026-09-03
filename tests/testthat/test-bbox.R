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

test_that("Nominatim responses are parsed and the best candidate is chosen", {
  json <- '[
    {"class":"highway","type":"residential","boundingbox":["39.70","39.71","-105.01","-105.00"]},
    {"class":"boundary","type":"administrative","boundingbox":["39.6144","39.9142","-105.1099","-104.5997"]},
    {"class":"place","type":"city","boundingbox":["39.5","40.0","-105.2","-104.5"]}
  ]'
  bb <- cyclelanes:::.parse_nominatim(json)
  expect_equal(bb, c(xmin = -105.1099, ymin = 39.6144, xmax = -104.5997, ymax = 39.9142))

  # a place beats a street
  json2 <- '[{"class":"highway","type":"residential","boundingbox":["1","2","3","4"]},
             {"class":"place","type":"town","boundingbox":["10","20","30","40"]}]'
  expect_equal(unname(cyclelanes:::.parse_nominatim(json2)), c(30, 10, 40, 20))

  expect_null(cyclelanes:::.parse_nominatim("[]"))
  expect_null(cyclelanes:::.parse_nominatim("not json"))
  expect_null(cyclelanes:::.parse_nominatim('[{"class":"place","boundingbox":["a","b","c","d"]}]'))
})

test_that("the Nominatim URL is percent-encoded and asks for JSON", {
  u <- cyclelanes:::.nominatim_url("Denver, Colorado")
  expect_match(u, "^https://nominatim.openstreetmap.org/search[?]")
  expect_match(u, "q=Denver%2C%20Colorado", fixed = TRUE)
  expect_match(u, "format=json", fixed = TRUE)
})
